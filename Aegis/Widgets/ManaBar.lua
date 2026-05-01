-- Aegis/Widgets/ManaBar.lua
-- Mana resource widget. Power type 0.

local _, ns = ...

local widget = ns.ResourceBarBase.MakeWidget({
    powerType = 0,
    colorKey  = "mana",
    events    = {
        "UNIT_MANA",
        "UNIT_MAXMANA",
        "UNIT_DISPLAYPOWER",
        "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD",
    },
})

ns.Widgets.Register("mana", widget)
