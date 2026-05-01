-- Aegis/Widgets/HealthBar.lua
-- Health widget. Always available. Hosts the pressure overlay (added in
-- Phase 4 via SetPressure(state, ttd) — for now the frame is just a HP bar).

local _, ns = ...
local HealthBar = {}

function HealthBar.IsAvailable()
    return true
end

function HealthBar.GetPreferredSize(orientation)
    if orientation == "vertical" then
        return 22, 100
    end
    return 150, 22
end

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

local function refresh(frame)
    if not frame then return end
    local cur = UnitHealth("player") or 0
    local max = UnitHealthMax("player") or 0
    frame:SetMinMaxValues(0, math.max(1, max))
    frame:SetValue(cur)
    if frame.text then frame.text:SetText(formatHP(cur, max)) end
end

HealthBar.Refresh = refresh

local function onEvent(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        refresh(self)
        return
    end
    if unit ~= "player" then return end
    refresh(self)
end

local function makePixel(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(ns.Theme.backgroundTexture)
    return t
end

local function buildBorder(frame, borderC)
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
end

function HealthBar.Build(parent, orientation, style)
    local Theme = ns.Theme
    local w, h = HealthBar.GetPreferredSize(orientation)
    local frame = CreateFrame("StatusBar", nil, parent)
    frame:SetSize(w, h)
    frame:SetStatusBarTexture(Theme.statusBarTexture)
    if orientation == "vertical" then
        frame:SetOrientation("VERTICAL")
    end

    local fill = Theme.colors.health
    frame:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4])
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(1)

    local bg = makePixel(frame, "BACKGROUND")
    bg:SetAllPoints(frame)
    local bgC = Theme.colors.bgDark
    bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])

    buildBorder(frame, Theme.colors.border)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(Theme.font, Theme.fontSize, Theme.fontFlags)
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local tw = Theme.colors.textWhite
    frame.text:SetTextColor(tw[1], tw[2], tw[3], tw[4])

    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", onEvent)

    refresh(frame)
    return frame, w, h
end

function HealthBar.Destroy(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    frame:Hide()
    frame:SetParent(nil)
end

ns.Widgets.Register("health", HealthBar)
