-- Aegis/Widgets/OutgoingDPS.lua
-- Numeric readout of outgoing DPS (damage dealt per second), aggregating
-- player + pets + totems + summons via the AFFILIATION_MINE filter in
-- the pressure module.

local _, ns = ...

local widget = ns.TextValueBase.MakeWidget({
    label  = "DPS dealt: ",
    getter = function()
        return ns.Pressure and ns.Pressure.GetOutgoingDPS() or 0
    end,
    colorKey = "haloWarning",
})

ns.Widgets.Register("dps_out", widget)
