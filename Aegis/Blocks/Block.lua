-- Aegis/Blocks/Block.lua
-- The Block primitive. A frame parented to UIParent that holds an ordered
-- list of widgets, packed along an orientation axis. Drag/lock toggles via
-- the BlockManager. Position saved per block on the per-character DB.

local _, ns = ...
ns.Block = ns.Block or {}
local Block = {}
Block.__index = Block
ns.Block.__class = Block

local WIDGET_GAP = 4

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
function Block:Layout()
    self:teardownWidgets()

    local orientation = self.config.orientation or "horizontal"
    local style = self.config.style or "standard"

    local xCursor, yCursor = 0, 0
    local maxW, maxH = 0, 0

    for _, widgetId in ipairs(self.config.widgets or {}) do
        local widget = ns.WidgetCatalog and ns.WidgetCatalog[widgetId]
        if widget and widget.IsAvailable() then
            local frame, w, h = widget.Build(self.frame, orientation, style)
            frame:ClearAllPoints()
            if orientation == "vertical" then
                frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", xCursor, 0)
                xCursor = xCursor + w + WIDGET_GAP
                if h > maxH then maxH = h end
            else
                frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -yCursor)
                yCursor = yCursor + h + WIDGET_GAP
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
        local width = math.max(1, xCursor - WIDGET_GAP)
        self.frame:SetSize(width, math.max(1, maxH))
    else
        local height = math.max(1, yCursor - WIDGET_GAP)
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
