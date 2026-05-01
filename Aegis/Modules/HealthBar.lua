-- Aegis/Modules/HealthBar.lua
-- Player health bar parented to the Anchor frame. Event-driven only (no
-- OnUpdate). 3.3.5a does not have RegisterUnitEvent, so UNIT_HEALTH /
-- UNIT_MAXHEALTH are filtered by hand.

local _, ns = ...
ns.HealthBar = ns.HealthBar or {}
local HealthBar = ns.HealthBar

local BAR_HEIGHT = 22
local INSET = 2

local frame
local text

local function readFormat()
    local v = AegisDB and AegisDB.visual
    return (v and v.showHealthText) or "value_and_percent"
end

local function formatHP(cur, max)
    if not cur or cur < 0 then cur = 0 end
    if not max or max < 1 then max = 1 end
    local pct = math.floor((cur / max) * 100 + 0.5)
    local fmt = readFormat()
    if fmt == "value" then
        return tostring(cur)
    elseif fmt == "percent" then
        return pct .. "%"
    end
    return cur .. " / " .. max .. "  " .. pct .. "%"
end

local function refresh()
    if not frame then return end
    local cur = UnitHealth("player") or 0
    local max = UnitHealthMax("player") or 0
    frame:SetMinMaxValues(0, math.max(1, max))
    frame:SetValue(cur)
    if text then text:SetText(formatHP(cur, max)) end
end

function HealthBar.Refresh() refresh() end
function HealthBar.GetFrame() return frame end

local function onEvent(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        refresh()
        return
    end
    if unit ~= "player" then return end
    refresh()
end

local function makePixel(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(ns.Theme and ns.Theme.backgroundTexture
        or "Interface\\Buttons\\WHITE8x8")
    return t
end

function HealthBar.Build()
    if frame then return frame end
    local anchor = ns.Anchor and ns.Anchor.GetFrame()
    if not anchor then return end

    local Theme = ns.Theme

    frame = CreateFrame("StatusBar", "AegisHealthBar", anchor)
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", INSET, -INSET)
    frame:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -INSET, -INSET)
    frame:SetHeight(BAR_HEIGHT)
    frame:SetStatusBarTexture(Theme.statusBarTexture)

    local fill = Theme.colors.health
    frame:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4])
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(1)

    local bg = makePixel(frame, "BACKGROUND")
    bg:SetAllPoints(frame)
    local bgC = Theme.colors.bgDark
    bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])
    frame.bg = bg

    local borderC = Theme.colors.border
    local function edge()
        local t = makePixel(frame, "OVERLAY")
        t:SetVertexColor(borderC[1], borderC[2], borderC[3], borderC[4])
        return t
    end
    local top = edge()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
    top:SetHeight(1)
    local bot = edge()
    bot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
    bot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    bot:SetHeight(1)
    local lft = edge()
    lft:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    lft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
    lft:SetWidth(1)
    local rgt = edge()
    rgt:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
    rgt:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    rgt:SetWidth(1)

    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont(Theme.font, Theme.fontSize, Theme.fontFlags)
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local tw = Theme.colors.textWhite
    text:SetTextColor(tw[1], tw[2], tw[3], tw[4])
    frame.text = text

    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", onEvent)

    refresh()
    return frame
end
