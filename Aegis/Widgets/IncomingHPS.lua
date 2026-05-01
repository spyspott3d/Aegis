-- Aegis/Widgets/IncomingHPS.lua
-- Numeric readout of incoming HPS (healing received per second).
-- Reads the session-based metric from the pressure module.

local _, ns = ...

local widget = ns.TextValueBase.MakeWidget({
    label  = "HPS in: ",
    getter = function()
        return ns.Pressure and ns.Pressure.GetIncomingHPS() or 0
    end,
    colorKey = "haloHealing",
})

ns.Widgets.Register("hps_in", widget)
