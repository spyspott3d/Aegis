-- Aegis/UI/Theme.lua
-- Single source of truth for visual constants. Modules MUST reference these
-- rather than hardcoding hex values (per CLAUDE.md visual conventions).

local _, ns = ...
ns.Theme = ns.Theme or {}
local Theme = ns.Theme

local function rgb(r, g, b, a)
    return { r / 255, g / 255, b / 255, a or 1 }
end

Theme.colors = {
    -- Bar fills
    health         = rgb(0x1E, 0xD7, 0x60),     -- #1ED760
    healthIncoming = rgb(0xA0, 0xFF, 0xC8, 0.7),-- bright mint, the predicted-heal segment
    mana         = rgb(0x3F, 0x8E, 0xFF),       -- #3F8EFF
    rage         = rgb(0xE8, 0x41, 0x41),       -- #E84141
    energy       = rgb(0xFF, 0xD9, 0x3B),       -- #FFD93B
    runic        = rgb(0x1E, 0xD2, 0xDA),       -- #1ED2DA
    -- Pressure overlay (legacy aliases retained for Phase 4 wiring)
    pressureWarn = rgb(0xFF, 0xAA, 0x00),       -- #FFAA00
    pressureCrit = rgb(0xFF, 0x20, 0x20),       -- #FF2020
    -- Halo around the health widget per pressure state. The HealthBar
    -- widget (Phase 4) renders a colored glow around its frame whose
    -- color and alpha track the current state.
    haloHealing  = rgb(0x3F, 0x8E, 0xFF),       -- #3F8EFF blue (heal > damage)
    haloLight    = rgb(0xFF, 0xD9, 0x3B),       -- #FFD93B yellow (slow drain)
    haloWarning  = rgb(0xFF, 0xAA, 0x00),       -- #FFAA00 orange (sustained drain)
    haloCritical = rgb(0xFF, 0x20, 0x20),       -- #FF2020 red (imminent / heavy)
    -- Combo point fills (yellow by default, red at max)
    comboFill    = rgb(0xFF, 0xD9, 0x3B),       -- #FFD93B (same as energy)
    comboMaxFill = rgb(0xFF, 0x20, 0x20),       -- #FF2020 (alert red)
    -- Chrome
    bgDark       = rgb(0x0E, 0x0E, 0x10, 0.85), -- #0E0E10
    border       = rgb(0x00, 0x00, 0x00),       -- #000000
    textWhite    = { 1, 1, 1, 1 },
}

-- White1x1 ships with the Blizzard client and stretches cleanly. Avoids any
-- texture asset packaging in v1.
Theme.statusBarTexture  = "Interface\\Buttons\\WHITE8x8"
Theme.backgroundTexture = "Interface\\Buttons\\WHITE8x8"
Theme.font              = "Fonts\\FRIZQT__.TTF"
Theme.fontSize          = 12
Theme.fontFlags         = "OUTLINE"

-- Hex strings (no #) for use inside chat color escapes |cffRRGGBB...|r.
Theme.chatHex = {
    accent       = "1ED760",
    pressureWarn = "FFAA00",
    pressureCrit = "FF2020",
}

-- Apply a "glossy" overlay to a StatusBar frame: a top-half white
-- gradient (highlight) and a bottom-half black gradient (shadow), both
-- at low alpha. Stock WoW StatusBars do not support real curvature; this
-- gradient pair is the conventional approximation. Called by widgets
-- whose hosting block has style == "glossy".
function Theme.ApplyGlossy(frame)
    if not frame or not frame.GetWidth then return end
    local tex = Theme.statusBarTexture

    -- Top half: transparent at the middle, white at the top. Vertical
    -- gradient in 3.3.5a goes (min = bottom, max = top), so min is
    -- middle (alpha 0) and max is top (alpha 0.30).
    local hi = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    hi:SetTexture(tex)
    hi:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    hi:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    hi:SetPoint("BOTTOM",   frame, "CENTER",   0, 0)
    hi:SetGradientAlpha("VERTICAL",
        1, 1, 1, 0.00,   -- bottom of upper half: transparent
        1, 1, 1, 0.30)   -- top:                 white tint

    -- Bottom half: black at the bottom, transparent at the middle.
    local sh = frame:CreateTexture(nil, "ARTWORK", nil, 7)
    sh:SetTexture(tex)
    sh:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  0, 0)
    sh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    sh:SetPoint("TOP",         frame, "CENTER",      0, 0)
    sh:SetGradientAlpha("VERTICAL",
        0, 0, 0, 0.30,   -- bottom: black shadow
        0, 0, 0, 0.00)   -- middle: transparent
end
