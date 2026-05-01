-- Aegis/Widgets/ComboPoints.lua
-- Combo point pips on the player's current target. Renders only filled
-- pips: 0 cp = nothing visible at all (no empty placeholder slots, so
-- characters who never use combo abilities see nothing).
--
-- Visibility is universal on Ascension (any character can build combo
-- points), so IsAvailable always returns true.

local _, ns = ...
local ComboPoints = {}

local NUM_PIPS = 5
local PIP_SIZE = 10
local PIP_GAP  = 3

function ComboPoints.IsAvailable()
    return true
end

function ComboPoints.GetPreferredSize(orientation)
    -- Combo pips look weird as a vertical column. Even in vertical-orientation
    -- blocks, the row stays horizontal — the widget reports a wider-than-tall
    -- footprint and the block packs it as one row.
    local w = NUM_PIPS * PIP_SIZE + (NUM_PIPS - 1) * PIP_GAP
    return w, PIP_SIZE
end

local function makePixel(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(ns.Theme.backgroundTexture)
    return t
end

local function buildPip(parent, theme, index, prevPip)
    local pip = CreateFrame("Frame", nil, parent)
    pip:SetSize(PIP_SIZE, PIP_SIZE)
    if index == 1 then
        pip:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    else
        pip:SetPoint("TOPLEFT", prevPip, "TOPRIGHT", PIP_GAP, 0)
    end

    local bg = pip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(pip)
    bg:SetTexture(theme.backgroundTexture)
    local bgC = theme.colors.bgDark
    bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])

    local fill = pip:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints(pip)
    fill:SetTexture(theme.statusBarTexture)
    -- Color is set per-refresh based on count (yellow normally, red at max),
    -- so we leave it default-white here; refresh paints it before any pip
    -- becomes visible.
    pip.fill = fill

    local borderC = theme.colors.border
    local function edge()
        local t = makePixel(pip, "OVERLAY")
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

local function refresh(frame)
    if not frame or not frame.pips then return end
    local count = 0
    if UnitExists("target") then
        count = GetComboPoints("player", "target") or 0
    end
    -- At-max gets the alert red; otherwise the default yellow.
    local Theme = ns.Theme
    local atMax = (count >= NUM_PIPS)
    local color = atMax and Theme.colors.comboMaxFill or Theme.colors.comboFill
    -- Show only filled pips. Hide the rest entirely (no dim placeholders).
    for i = 1, NUM_PIPS do
        local pip = frame.pips[i]
        if pip then
            if i <= count then
                if pip.fill then
                    pip.fill:SetVertexColor(color[1], color[2], color[3], color[4])
                end
                pip:Show()
            else
                pip:Hide()
            end
        end
    end
end

ComboPoints.Refresh = refresh

local function onEvent(self)
    refresh(self)
end

function ComboPoints.Build(parent, orientation, style)
    local Theme = ns.Theme
    local w, h = ComboPoints.GetPreferredSize(orientation)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(w, h)

    frame.pips = {}
    local prev = nil
    for i = 1, NUM_PIPS do
        local pip = buildPip(frame, Theme, i, prev)
        pip:Hide() -- hidden until refresh raises them
        frame.pips[i] = pip
        prev = pip
    end

    frame:RegisterEvent("PLAYER_COMBO_POINTS")
    frame:RegisterEvent("UNIT_COMBO_POINTS")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", onEvent)

    refresh(frame)
    return frame, w, h
end

function ComboPoints.Destroy(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    frame:Hide()
    frame:SetParent(nil)
end

ns.Widgets.Register("combo", ComboPoints)
