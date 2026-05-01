-- Aegis/Widgets/Widget.lua
-- The widget catalog. Each Widgets/<id>.lua module registers itself here at
-- load time. The catalog is closed-set: users do not add widgets at runtime.
--
-- Widget interface (each entry implements):
--
--   IsAvailable() -> bool
--       Whether this widget should render on this character. Resource bars
--       return false when UnitPowerMax(player, type) <= 0. health and combo
--       always return true.
--
--   GetPreferredSize(orientation) -> w, h
--       Dimensions the widget would like, given the parent block's
--       orientation ("horizontal" or "vertical").
--
--   Build(parent, orientation, style) -> frame, w, h
--       Create the frame parented to `parent`, register events, return the
--       frame plus its actual size. State lives on the frame itself
--       (frame.text, frame.bg, etc.) so the module stays stateless.
--
--   Refresh(frame)
--       Pull current values from the WoW API and redraw. Called by event
--       handlers and after settings changes.
--
--   Destroy(frame)
--       Tear down: unregister events, drop scripts, hide, unparent. Called
--       when the user removes the widget from a block, or when the block
--       rebuilds its widget list (orientation/style change).

local _, ns = ...
ns.WidgetCatalog = ns.WidgetCatalog or {}

ns.Widgets = ns.Widgets or {}
local Widgets = ns.Widgets

function Widgets.Register(id, widget)
    ns.WidgetCatalog[id] = widget
end

function Widgets.Get(id)
    return ns.WidgetCatalog[id]
end
