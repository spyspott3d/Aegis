-- Aegis/Widgets/IncomingDPS.lua
-- Numeric readout of incoming DPS (damage taken per second).
-- Reads the session-based metric from the pressure module.

local _, ns = ...

local widget = ns.TextValueBase.MakeWidget({
    label  = "DPS taken: ",
    getter = function()
        return ns.Pressure and ns.Pressure.GetIncomingDPS() or 0
    end,
    colorKey = "haloCritical",
})

ns.Widgets.Register("dps_in", widget)
