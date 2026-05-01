-- Aegis/Widgets/RageBar.lua
-- Rage resource widget. Power type 1.

local _, ns = ...

local widget = ns.ResourceBarBase.MakeWidget({
    powerType   = 1,
    colorKey    = "rage",
    showTextKey = "showRageText",
    events      = {
        "UNIT_RAGE",
        "UNIT_MAXRAGE",
        "UNIT_DISPLAYPOWER",
        "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD",
    },
})

ns.Widgets.Register("rage", widget)
