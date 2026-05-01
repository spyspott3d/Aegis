-- Aegis/UI/Anchor.lua
-- The single movable parent frame. Every visible widget in later phases is
-- parented (directly or indirectly) here so that movement, scaling, and
-- visibility are atomic.

local _, ns = ...
ns.Anchor = ns.Anchor or {}
local Anchor = ns.Anchor

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 220, 80

local frame

local function applyPosition()
    if not frame or not AegisDBChar or not AegisDBChar.position then return end
    local p = AegisDBChar.position
    frame:ClearAllPoints()
    frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER",
        p.xOffset or 0, p.yOffset or 0)
end

local function savePosition()
    if not frame then return end
    local point, _, relativePoint, xOffset, yOffset = frame:GetPoint(1)
    AegisDBChar.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        xOffset = xOffset or 0,
        yOffset = yOffset or 0,
    }
end

local function showEdge(show)
    if not frame or not frame.edge then return end
    if show then frame.edge:Show() else frame.edge:Hide() end
end

local function setLocked(locked)
    AegisDBChar.locked = locked and true or false
    if not frame then return end
    local unlocked = not AegisDBChar.locked
    frame:EnableMouse(unlocked)
    frame:SetMovable(unlocked)
    showEdge(unlocked)
end

function Anchor.IsLocked()
    return AegisDBChar and AegisDBChar.locked and true or false
end

function Anchor.Lock()   setLocked(true)  end
function Anchor.Unlock() setLocked(false) end

function Anchor.Reset()
    if ns.Config and ns.Config.ResetPosition then
        ns.Config.ResetPosition()
    end
    applyPosition()
end

function Anchor.GetFrame()
    return frame
end

local function buildEdge(parent, theme)
    local edge = CreateFrame("Frame", nil, parent)
    edge:SetAllPoints(parent)

    local color = (theme and theme.colors and theme.colors.pressureWarn)
        or { 1, 0.6, 0, 1 }
    local tex = (theme and theme.backgroundTexture)
        or "Interface\\Buttons\\WHITE8x8"

    local function line()
        local t = edge:CreateTexture(nil, "OVERLAY")
        t:SetTexture(tex)
        t:SetVertexColor(color[1], color[2], color[3], 0.9)
        return t
    end
    local top = line(); top:SetPoint("TOPLEFT");    top:SetPoint("TOPRIGHT");    top:SetHeight(1)
    local bot = line(); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    local lft = line(); lft:SetPoint("TOPLEFT");    lft:SetPoint("BOTTOMLEFT");  lft:SetWidth(1)
    local rgt = line(); rgt:SetPoint("TOPRIGHT");   rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(1)

    local label = edge:CreateFontString(nil, "OVERLAY")
    local font = (theme and theme.font) or "Fonts\\FRIZQT__.TTF"
    local size = (theme and theme.fontSize) or 12
    local flags = (theme and theme.fontFlags) or "OUTLINE"
    label:SetFont(font, size, flags)
    label:SetPoint("BOTTOM", edge, "TOP", 0, 2)
    label:SetText("Aegis - drag to move, /ae lock when done")

    edge:Hide()
    return edge
end

-- Build the anchor frame. Called once from PLAYER_LOGIN.
function Anchor.Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "AegisAnchor", UIParent)
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")

    frame.edge = buildEdge(frame, ns.Theme)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not AegisDBChar.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    applyPosition()
    setLocked(AegisDBChar.locked ~= false)
    return frame
end
