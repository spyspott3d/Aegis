-- Aegis/Blocks/Block.lua
-- The Block primitive. A frame parented to UIParent that holds an ordered
-- list of widgets, packed along an orientation axis. Drag/lock toggles via
-- the BlockManager. Position saved per block on the per-character DB.

local _, ns = ...
ns.Block = ns.Block or {}
local Block = {}
Block.__index = Block
ns.Block.__class = Block

local DEFAULT_WIDGET_GAP = 4  -- fallback when config.gap is missing (pre-v8 data)

local function makePixel(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(ns.Theme.backgroundTexture)
    return t
end

local function buildEdgeMarker(frame)
    local edge = CreateFrame("Frame", nil, frame)
    edge:SetAllPoints(frame)

    local color = (ns.Theme and ns.Theme.colors and ns.Theme.colors.pressureWarn)
        or { 1, 0.6, 0, 1 }
    local function line()
        local t = makePixel(edge, "OVERLAY")
        t:SetVertexColor(color[1], color[2], color[3], 0.9)
        return t
    end
    local top = line()
    top:SetPoint("TOPLEFT", edge, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", edge, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    local bot = line()
    bot:SetPoint("BOTTOMLEFT", edge, "BOTTOMLEFT", 0, 0)
    bot:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, 0)
    bot:SetHeight(1)
    local lft = line()
    lft:SetPoint("TOPLEFT", edge, "TOPLEFT", 0, 0)
    lft:SetPoint("BOTTOMLEFT", edge, "BOTTOMLEFT", 0, 0)
    lft:SetWidth(1)
    local rgt = line()
    rgt:SetPoint("TOPRIGHT", edge, "TOPRIGHT", 0, 0)
    rgt:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, 0)
    rgt:SetWidth(1)

    edge:Hide()
    return edge
end

function ns.Block.New(config)
    local self = setmetatable({}, Block)
    self.config = config       -- direct reference into AegisDBChar.blocks
    self.widgets = {}          -- { { id=string, frame=Frame, widget=WidgetTable }, ... }
    self.frame = nil
    self.edge = nil
    self:Build()
    return self
end

function Block:applyPosition()
    local p = self.config.position or {}
    self.frame:ClearAllPoints()
    self.frame:SetPoint(
        p.point or "CENTER",
        UIParent,
        p.relativePoint or "CENTER",
        p.xOffset or 0,
        p.yOffset or 0)
end

function Block:savePosition()
    if not self.frame then return end
    local point, _, relativePoint, xOffset, yOffset = self.frame:GetPoint(1)
    self.config.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        xOffset = xOffset or 0,
        yOffset = yOffset or 0,
    }
end

function Block:teardownWidgets()
    for _, w in ipairs(self.widgets) do
        if w.widget.Destroy then w.widget.Destroy(w.frame) end
    end
    wipe(self.widgets)
end

-- Lay out widgets according to config.widgets, config.orientation. Skips
-- widgets whose IsAvailable() returns false.
--
-- Convention (orientation describes the BAR shape, not the block growth
-- direction):
--   "horizontal" block = widgets render in their wide form (HP bar 150x22,
--                        combo pips as a horizontal row); the block packs
--                        them top-to-bottom.
--   "vertical"   block = widgets render in their tall form (HP bar 22x100,
--                        combo pips as a bottom-to-top column); the block
--                        packs them left-to-right.
--
-- Special-case for `kind = "text"` widgets (the four Pressure readouts:
-- dps_in / hps_in / dps_out / hps_out): in vertical blocks, two consecutive
-- text widgets stack in the MINOR axis (Y) instead of taking their own
-- column. This avoids the "two text widgets side-by-side at the right of
-- the bars" outcome — the natural reading order is top-to-bottom for stacked
-- text. A single text widget after a bar still gets its own column. In
-- horizontal blocks the rule is a no-op: the main flow is already top-to-
-- bottom, so consecutive text widgets stack naturally.
function Block:Layout()
    self:teardownWidgets()

    local orientation = self.config.orientation or "horizontal"
    local style = self.config.style or "standard"
    local gap = self.config.gap or DEFAULT_WIDGET_GAP

    local xCursor, yCursor = 0, 0
    local maxW, maxH = 0, 0

    -- For vertical blocks: track the column origin of the most recently
    -- placed text widget so the next consecutive text widget can stack
    -- under it instead of taking a fresh column.
    local prevTextX, prevTextBottom, prevTextWidth

    for _, widgetId in ipairs(self.config.widgets or {}) do
        local widget = ns.WidgetCatalog and ns.WidgetCatalog[widgetId]
        if widget and widget.IsAvailable() then
            local frame, w, h = widget.Build(self.frame, orientation, style)
            frame:ClearAllPoints()
            if orientation == "vertical" then
                local isText = (widget.kind == "text")
                if isText and prevTextX then
                    -- Stack under the previous text widget in the same column.
                    frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                        prevTextX, -prevTextBottom)
                    local newBottom = prevTextBottom + h + gap
                    prevTextBottom = newBottom
                    if w > prevTextWidth then prevTextWidth = w end
                    -- Track the rightmost extent of the column so the block
                    -- width grows if the wider text widget overhangs.
                    local colRight = prevTextX + prevTextWidth + gap
                    if colRight > xCursor then xCursor = colRight end
                    if newBottom - gap > maxH then
                        maxH = newBottom - gap
                    end
                else
                    frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", xCursor, 0)
                    if isText then
                        prevTextX      = xCursor
                        prevTextBottom = h + gap
                        prevTextWidth  = w
                    else
                        -- Bars reset the text-stacking state.
                        prevTextX = nil
                    end
                    xCursor = xCursor + w + gap
                    if h > maxH then maxH = h end
                end
            else
                frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -yCursor)
                yCursor = yCursor + h + gap
                if w > maxW then maxW = w end
            end
            table.insert(self.widgets, {
                id = widgetId,
                frame = frame,
                widget = widget,
            })
        end
    end

    if orientation == "vertical" then
        local width = math.max(1, xCursor - gap)
        self.frame:SetSize(width, math.max(1, maxH))
    else
        local height = math.max(1, yCursor - gap)
        self.frame:SetSize(math.max(1, maxW), height)
    end
end

function Block:Build()
    local name = "AegisBlock_" .. tostring(self.config.id or "anon")
    self.frame = CreateFrame("Frame", name, UIParent)
    self.frame:SetClampedToScreen(true)
    self.frame:SetFrameStrata("MEDIUM")

    -- Per-block scale.
    local scale = self.config.scale or 1.0
    self.frame:SetScale(scale)

    self.edge = buildEdgeMarker(self.frame)

    self.frame:RegisterForDrag("LeftButton")
    local block = self
    self.frame:SetScript("OnDragStart", function(self_)
        if AegisDBChar and AegisDBChar.locked then return end
        self_:StartMoving()
    end)
    self.frame:SetScript("OnDragStop", function(self_)
        self_:StopMovingOrSizing()
        block:savePosition()
    end)

    self:Layout()
    self:applyPosition()
end

function Block:SetLocked(locked)
    if not self.frame then return end
    local unlocked = not locked
    self.frame:EnableMouse(unlocked)
    self.frame:SetMovable(unlocked)
    if self.edge then
        if unlocked then self.edge:Show() else self.edge:Hide() end
    end
end

function Block:Destroy()
    self:teardownWidgets()
    if self.frame then
        self.frame:Hide()
        self.frame:SetParent(nil)
        self.frame = nil
    end
    self.edge = nil
end

-- Return all widget frames in this block matching the given catalog id.
function Block:GetWidgetsByType(typeId)
    local list = {}
    for _, w in ipairs(self.widgets) do
        if w.id == typeId then table.insert(list, w.frame) end
    end
    return list
end

function Block:GetFrame() return self.frame end
function Block:GetConfig() return self.config end
