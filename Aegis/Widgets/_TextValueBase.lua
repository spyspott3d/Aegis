-- Aegis/Widgets/_TextValueBase.lua
-- Shared factory for text widgets that display a numeric value with a
-- leading label, polled at the pressure tick rate (0.25s). Used by the
-- four Pressure-fed widgets (dps_in / hps_in / dps_out / hps_out).
--
-- Each consumer module:
--
--   local widget = ns.TextValueBase.MakeWidget({
--       label  = "DPS taken: ",
--       getter = function() return ns.Pressure and ns.Pressure.GetIncomingDPS() or 0 end,
--   })
--   ns.Widgets.Register("dps_in", widget)
--
-- The 0.25s OnUpdate poll is a documented carve-out from CLAUDE.md hard
-- rule #3 (alongside the energy bar and the halo pulse). The values come
-- from Pressure.* getters that already update at 0.25s; polling at the
-- same cadence keeps the displayed number in sync without overdriving the
-- handler. Cost on four widgets: ~16 SetText calls/sec total, negligible.

local _, ns = ...
ns.TextValueBase = ns.TextValueBase or {}
local Base = ns.TextValueBase

local TICK = 0.25

function Base.MakeWidget(config)
    local Widget = {}

    -- Marker read by Block:Layout() to stack consecutive text widgets in the
    -- minor axis instead of placing them along the block's main flow. See the
    -- comment in Blocks/Block.lua for the layout rule.
    Widget.kind = "text"

    function Widget.IsAvailable() return true end

    function Widget.GetPreferredSize(orientation)
        return config.preferredWidth or 130, 16
    end

    local function refresh(frame)
        if not frame or not frame.text or not config.getter then return end
        local v = config.getter() or 0
        frame.text:SetText(config.label .. math.floor(v + 0.5))
    end

    Widget.Refresh = refresh

    function Widget.Build(parent, orientation, style)
        local Theme = ns.Theme
        local w, h = Widget.GetPreferredSize(orientation)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(w, h)

        frame.text = frame:CreateFontString(nil, "OVERLAY")
        frame.text:SetFont(Theme.font, Theme.fontSize, Theme.fontFlags)
        frame.text:SetPoint("LEFT", frame, "LEFT", 0, 0)
        local tc = config.colorKey and Theme.colors[config.colorKey]
            or Theme.colors.textWhite
        frame.text:SetTextColor(tc[1], tc[2], tc[3], tc[4] or 1)

        local accum = 0
        frame:SetScript("OnUpdate", function(self, elapsed)
            accum = accum + elapsed
            if accum >= TICK then
                accum = 0
                refresh(self)
            end
        end)

        refresh(frame)
        return frame, w, h
    end

    function Widget.Destroy(frame)
        if not frame then return end
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        frame:SetParent(nil)
    end

    return Widget
end
