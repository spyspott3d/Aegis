-- Aegis/Modules/ResourceBar.lua
-- Player secondary resource bar, class- and form-aware. Sits below the
-- health bar in the current (horizontal) layout. Phase 2.5 will add
-- vertical layout; the bar fill direction will follow via SetOrientation.

-- 3.3.5a has no UNIT_POWER / UNIT_MAXPOWER (those landed in 4.0). We register
-- the per-type events instead and refresh() reads UnitPowerType fresh, so a
-- druid form switch lands the right values regardless of which event fired.

local _, ns = ...
ns.ResourceBar = ns.ResourceBar or {}
local ResourceBar = ns.ResourceBar

local BAR_HEIGHT = 14
local INSET = 2
local GAP = 4

-- WoW 3.3.5a power type indices (UnitPowerType return value).
local POWER_MANA   = 0
local POWER_RAGE   = 1
local POWER_FOCUS  = 2
local POWER_ENERGY = 3
local POWER_RUNIC  = 6

local frame
local text

local function colorForPower(powerType)
    local c = ns.Theme.colors
    if powerType == POWER_RAGE   then return c.rage   end
    if powerType == POWER_ENERGY then return c.energy end
    if powerType == POWER_FOCUS  then return c.energy end
    if powerType == POWER_RUNIC  then return c.runic  end
    return c.mana
end

local function refresh()
    if not frame then return end
    local powerType = UnitPowerType("player") or POWER_MANA
    local cur = UnitPower("player") or 0
    local max = UnitPowerMax("player") or 0
    local color = colorForPower(powerType)
    frame:SetStatusBarColor(color[1], color[2], color[3], color[4])
    frame:SetMinMaxValues(0, math.max(1, max))
    frame:SetValue(cur)
    if text then
        if max <= 0 then
            text:SetText("0")
        else
            text:SetText(cur .. " / " .. max)
        end
    end
end

function ResourceBar.Refresh()  refresh() end
function ResourceBar.GetFrame() return frame end

local function onEvent(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD"
        or event == "UPDATE_SHAPESHIFT_FORM" then
        refresh()
        return
    end
    if unit and unit ~= "player" then return end
    refresh()
end

local function makePixel(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(ns.Theme.backgroundTexture)
    return t
end

function ResourceBar.Build()
    if frame then return frame end
    local anchor = ns.Anchor and ns.Anchor.GetFrame()
    local healthBar = ns.HealthBar and ns.HealthBar.GetFrame()
    if not anchor then return end

    local Theme = ns.Theme
    frame = CreateFrame("StatusBar", "AegisResourceBar", anchor)
    if healthBar then
        frame:SetPoint("TOPLEFT",  healthBar, "BOTTOMLEFT",  0, -GAP)
        frame:SetPoint("TOPRIGHT", healthBar, "BOTTOMRIGHT", 0, -GAP)
    else
        frame:SetPoint("TOPLEFT",  anchor, "TOPLEFT",   INSET, -INSET - 26)
        frame:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -INSET, -INSET - 26)
    end
    frame:SetHeight(BAR_HEIGHT)
    frame:SetStatusBarTexture(Theme.statusBarTexture)
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(1)

    local bg = makePixel(frame, "BACKGROUND")
    bg:SetAllPoints(frame)
    local bgC = Theme.colors.bgDark
    bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])

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
    text:SetFont(Theme.font, Theme.fontSize - 2, Theme.fontFlags)
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local tw = Theme.colors.textWhite
    text:SetTextColor(tw[1], tw[2], tw[3], tw[4])

    -- Per-type events (3.3.5a). UNIT_DISPLAYPOWER fires when the displayed
    -- power type changes (druid forms). UPDATE_SHAPESHIFT_FORM is the
    -- belt-and-suspenders for druids.
    frame:RegisterEvent("UNIT_MANA")
    frame:RegisterEvent("UNIT_RAGE")
    frame:RegisterEvent("UNIT_ENERGY")
    frame:RegisterEvent("UNIT_FOCUS")
    frame:RegisterEvent("UNIT_RUNIC_POWER")
    frame:RegisterEvent("UNIT_MAXMANA")
    frame:RegisterEvent("UNIT_MAXRAGE")
    frame:RegisterEvent("UNIT_MAXENERGY")
    frame:RegisterEvent("UNIT_MAXFOCUS")
    frame:RegisterEvent("UNIT_MAXRUNIC_POWER")
    frame:RegisterEvent("UNIT_DISPLAYPOWER")
    frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", onEvent)

    refresh()
    return frame
end
