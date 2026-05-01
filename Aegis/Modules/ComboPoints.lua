-- Aegis/Modules/ComboPoints.lua
-- A row of pip frames showing combo points generated on the player's
-- current target. Visible only for rogue (always) and druid in cat form;
-- hidden for every other class and for druids out of cat form.
--
-- 3.3.5a fires PLAYER_COMBO_POINTS (no unit arg). UNIT_COMBO_POINTS came
-- later. We register both for forward compat with private servers that
-- may have backported it; either one routes to the same refresh.

local _, ns = ...
ns.ComboPoints = ns.ComboPoints or {}
local ComboPoints = ns.ComboPoints

local NUM_PIPS = 5
local PIP_SIZE = 10
local PIP_GAP  = 3
local ROW_GAP  = 4

local POWER_ENERGY = 3 -- druid in cat form has energy as primary power

local frame
local pips = {}

local function shouldShow()
    local class = ns.playerClass
    if class == "ROGUE" then return true end
    if class == "DRUID" then
        return UnitPowerType("player") == POWER_ENERGY
    end
    return false
end

local function refresh()
    if not frame then return end
    if not shouldShow() then
        frame:Hide()
        return
    end
    frame:Show()
    local count = 0
    if UnitExists("target") then
        count = GetComboPoints("player", "target") or 0
    end
    for i = 1, NUM_PIPS do
        local pip = pips[i]
        if pip and pip.fill then
            if i <= count then
                pip.fill:SetAlpha(1)
            else
                pip.fill:SetAlpha(0.2)
            end
        end
    end
end

function ComboPoints.Refresh()  refresh() end
function ComboPoints.GetFrame() return frame end

local function onEvent(self, event)
    refresh()
end

local function buildPip(parent, theme, index)
    local pip = CreateFrame("Frame", nil, parent)
    pip:SetSize(PIP_SIZE, PIP_SIZE)
    if index == 1 then
        pip:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    else
        pip:SetPoint("TOPLEFT", pips[index - 1], "TOPRIGHT", PIP_GAP, 0)
    end

    local bg = pip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(pip)
    bg:SetTexture(theme.backgroundTexture)
    local bgC = theme.colors.bgDark
    bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])

    local fill = pip:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints(pip)
    fill:SetTexture(theme.statusBarTexture)
    local fc = theme.colors.energy
    fill:SetVertexColor(fc[1], fc[2], fc[3], fc[4])
    fill:SetAlpha(0.2)
    pip.fill = fill

    local borderC = theme.colors.border
    local function edge()
        local t = pip:CreateTexture(nil, "OVERLAY")
        t:SetTexture(theme.backgroundTexture)
        t:SetVertexColor(borderC[1], borderC[2], borderC[3], borderC[4])
        return t
    end
    local top = edge()
    top:SetPoint("TOPLEFT", pip, "TOPLEFT", -1, 1)
    top:SetPoint("TOPRIGHT", pip, "TOPRIGHT", 1, 1)
    top:SetHeight(1)
    local bot = edge()
    bot:SetPoint("BOTTOMLEFT", pip, "BOTTOMLEFT", -1, -1)
    bot:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", 1, -1)
    bot:SetHeight(1)
    local lft = edge()
    lft:SetPoint("TOPLEFT", pip, "TOPLEFT", -1, 1)
    lft:SetPoint("BOTTOMLEFT", pip, "BOTTOMLEFT", -1, -1)
    lft:SetWidth(1)
    local rgt = edge()
    rgt:SetPoint("TOPRIGHT", pip, "TOPRIGHT", 1, 1)
    rgt:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", 1, -1)
    rgt:SetWidth(1)

    return pip
end

function ComboPoints.Build()
    if frame then return frame end
    local anchor = ns.Anchor and ns.Anchor.GetFrame()
    local resourceBar = ns.ResourceBar and ns.ResourceBar.GetFrame()
    if not anchor then return end

    local rowWidth = NUM_PIPS * PIP_SIZE + (NUM_PIPS - 1) * PIP_GAP

    frame = CreateFrame("Frame", "AegisComboPoints", anchor)
    frame:SetSize(rowWidth, PIP_SIZE)
    if resourceBar then
        frame:SetPoint("TOPLEFT", resourceBar, "BOTTOMLEFT", 0, -ROW_GAP)
    else
        frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 2, -50)
    end

    for i = 1, NUM_PIPS do
        pips[i] = buildPip(frame, ns.Theme, i)
    end

    frame:RegisterEvent("PLAYER_COMBO_POINTS")
    frame:RegisterEvent("UNIT_COMBO_POINTS")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", onEvent)

    refresh()
    return frame
end
