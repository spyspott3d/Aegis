-- Aegis/Widgets/RunicBar.lua
-- Runic power widget. Power type 6. On Ascension this is unlockable; if the
-- character has not unlocked it, UnitPowerMax(player, 6) returns 0 and the
-- widget hides itself.

local _, ns = ...

local widget = ns.ResourceBarBase.MakeWidget({
    powerType   = 6,
    colorKey    = "runic",
    showTextKey = "showRunicText",
    events      = {
        "UNIT_RUNIC_POWER",
        "UNIT_MAXRUNIC_POWER",
        "UNIT_DISPLAYPOWER",
        "PLAYER_ENTERING_WORLD",
    },
})

ns.Widgets.Register("runic", widget)
