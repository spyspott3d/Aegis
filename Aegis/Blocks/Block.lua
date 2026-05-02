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

-- Frame center expressed as offset from UIParent's center, in UIParent's
-- coordinate space. Stable regardless of which anchor StartMoving rewrote
-- the frame to (WoW's StartMoving converts the anchor to TOPLEFT-relative
-- internally, which makes GetPoint return weird coordinates mid-drag).
local function liveCenterOffset(frame)
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and px) then return 0, 0 end
    return fx - px, fy - py
end

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

    -- Position read-out: shown at the block's top-left while unlocked, so
    -- the user can see the live anchor + offset of each block as they drag.
    -- Anchored just OUTSIDE the edge (BOTTOMLEFT-of-label = TOPLEFT-of-edge)
    -- so it does not overlap the bar contents inside the block.
    local pos = edge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pos:SetPoint("BOTTOMLEFT", edge, "TOPLEFT", 0, 2)
    pos:SetJustifyH("LEFT")
    pos:SetTextColor(color[1], color[2], color[3], 1)
    edge.posLabel = pos

    edge:Hide()
    return edge
end

-- Read the block's current screen position and write it to the edge
-- marker's read-out. Always reads as "offset from UIParent CENTER" so the
-- value is stable regardless of which anchor StartMoving has set internally.
-- Called on lock/unlock, on drag start/stop, and via OnUpdate while a drag
-- is active so the number is live as you move.
local function updatePosLabel(block)
    if not (block and block.edge and block.edge.posLabel and block.frame) then
        return
    end
    local x, y = liveCenterOffset(block.frame)
    block.edge.posLabel:SetText(("CENTER %+d, %+d"):format(
        math.floor(x + 0.5), math.floor(y + 0.5)))
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
    -- Re-anchor to CENTER/CENTER with the live screen offset. This undoes
    -- the TOPLEFT anchor that StartMoving wrote during drag, so the saved
    -- position reads as the natural "offset from screen center" — useful
    -- for mirroring blocks left/right around the player.
    local x, y = liveCenterOffset(self.frame)
    self.config.position = {
        point         = "CENTER",
        relativePoint = "CENTER",
        xOffset       = math.floor(x + 0.5),
        yOffset       = math.floor(y + 0.5),
    }
    self:applyPosition()
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
    -- `curve` is meaningful only for vertical blocks (tall bars side-by-side).
    -- Values: "none" (rectangular, default), "left" (silhouette `(`), "right"
    -- (silhouette `)`). Horizontal blocks ignore it — the textures we ship
    -- are designed for vertical bars and rotating them would require a
    -- second texture set + a perpendicular fill direction.
    local curve = self.config.curve or "none"
    if orientation ~= "vertical" then curve = "none" end

    local xCursor, yCursor = 0, 0
    local maxW, maxH = 0, 0

    -- For vertical blocks: track the column origin of the most recently
    -- placed text widget so the next consecutive text widget can stack
    -- under it instead of taking a fresh column.
    local prevTextX, prevTextBottom, prevTextWidth

    for _, widgetId in ipairs(self.config.widgets or {}) do
        local widget = ns.WidgetCatalog and ns.WidgetCatalog[widgetId]
        if widget and widget.IsAvailable() then
            local frame, w, h = widget.Build(self.frame, orientation, style, curve)
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
        -- Live-update the position label every frame while the user drags.
        -- StartMoving repositions the frame on each render tick; we just
        -- read the current anchor with GetPoint and rewrite the text.
        self_:SetScript("OnUpdate", function() updatePosLabel(block) end)
    end)
    self.frame:SetScript("OnDragStop", function(self_)
        self_:StopMovingOrSizing()
        self_:SetScript("OnUpdate", nil)
        block:savePosition()
        updatePosLabel(block)  -- final value after StopMovingOrSizing
    end)

    self:Layout()
    self:applyPosition()
    updatePosLabel(self)
end

function Block:SetLocked(locked)
    if not self.frame then return end
    local unlocked = not locked
    self.frame:EnableMouse(unlocked)
    self.frame:SetMovable(unlocked)
    if self.edge then
        if unlocked then
            updatePosLabel(self)  -- refresh before showing
            self.edge:Show()
        else
            self.edge:Hide()
        end
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
