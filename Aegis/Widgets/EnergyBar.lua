-- Aegis/Widgets/EnergyBar.lua
-- Energy resource widget. Power type 3.

local _, ns = ...

local widget = ns.ResourceBarBase.MakeWidget({
    powerType = 3,
    colorKey  = "energy",
    events    = {
        "UNIT_ENERGY",
        "UNIT_MAXENERGY",
        "UNIT_DISPLAYPOWER",
        "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD",
    },
})

ns.Widgets.Register("energy", widget)
