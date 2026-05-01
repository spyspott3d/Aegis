-- Aegis/Widgets/OutgoingHPS.lua
-- Numeric readout of outgoing HPS (healing dealt per second), including
-- healing totems and any owned summons via the AFFILIATION_MINE filter
-- in the pressure module.

local _, ns = ...

local widget = ns.TextValueBase.MakeWidget({
    label  = "HPS out: ",
    getter = function()
        return ns.Pressure and ns.Pressure.GetOutgoingHPS() or 0
    end,
    colorKey = "haloHealing",
})

ns.Widgets.Register("hps_out", widget)
