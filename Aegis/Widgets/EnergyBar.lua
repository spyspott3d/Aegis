-- Aegis/Widgets/EnergyBar.lua
-- Energy resource widget. Power type 3.
--
-- Energy regenerates every 0.1s server-side, but UNIT_ENERGY can fire less
-- often on Ascension, producing visibly chunky bar updates. The widget adds
-- a 0.1s OnUpdate poll alongside the event handlers (carve-out from
-- CLAUDE.md hard rule #3 — see _ResourceBarBase.lua for the full rationale).
-- Cost: ~10 UnitPower polls/sec = negligible.

local _, ns = ...

local widget = ns.ResourceBarBase.MakeWidget({
    powerType = 3,
    colorKey  = "energy",
    pollInterval = 0.1,
    events    = {
        "UNIT_ENERGY",
        "UNIT_MAXENERGY",
        "UNIT_DISPLAYPOWER",
        "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD",
    },
})

ns.Widgets.Register("energy", widget)
