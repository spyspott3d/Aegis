-- Aegis/Widgets/_ResourceBarBase.lua
-- Shared factory for the four resource widgets (mana, rage, energy, runic).
-- They differ by power type, color, and event list — everything else is
-- common (StatusBar build, background, border, text, refresh, destroy).
--
-- Usage in each Widgets/<resource>.lua:
--
--   local ns = select(2, ...)
--   local widget = ns.ResourceBarBase.MakeWidget({
--       powerType = 0,                              -- WoW power index
--       colorKey  = "mana",                         -- key into Theme.colors
--       events    = { "UNIT_MANA", "UNIT_MAXMANA",  -- events to register
--                     "UNIT_DISPLAYPOWER",
--                     "PLAYER_ENTERING_WORLD" },
--   })
--   ns.Widgets.Register("mana", widget)

local _, ns = ...
ns.ResourceBarBase = ns.ResourceBarBase or {}
local Base = ns.ResourceBarBase

local function makePixel(parent, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture(ns.Theme.backgroundTexture)
    return t
end

-- Build the four 1px borders around `frame`. Caller passes the border color.
local function buildBorder(frame, borderC)
    local function edge()
        local t = makePixel(frame, "OVERLAY")
        t:SetVertexColor(borderC[1], borderC[2], borderC[3], borderC[4])
        return t
    end
    local top = edge()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
    top:SetHeight(1)
    local bot = edge()
    bot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
    bot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    bot:SetHeight(1)
    local lft = edge()
    lft:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    lft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
    lft:SetWidth(1)
    local rgt = edge()
    rgt:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
    rgt:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    rgt:SetWidth(1)
end

function Base.MakeWidget(config)
    local Widget = {}

    function Widget.IsAvailable()
        return (UnitPowerMax("player", config.powerType) or 0) > 0
    end

    function Widget.GetPreferredSize(orientation)
        if orientation == "vertical" then
            return 16, 80
        end
        return 150, 14
    end

    local function refresh(frame)
        if not frame then return end
        local cur = UnitPower("player", config.powerType) or 0
        local max = UnitPowerMax("player", config.powerType) or 0
        frame:SetMinMaxValues(0, math.max(1, max))
        frame:SetValue(cur)
        if frame.text then
            if max <= 0 then
                frame.text:SetText("0")
            else
                frame.text:SetText(cur .. " / " .. max)
            end
        end
    end

    Widget.Refresh = refresh

    local function onEvent(self, event, unit)
        if event == "PLAYER_ENTERING_WORLD"
            or event == "UPDATE_SHAPESHIFT_FORM" then
            refresh(self)
            return
        end
        if unit and unit ~= "player" then return end
        refresh(self)
    end

    function Widget.Build(parent, orientation, style)
        local Theme = ns.Theme
        local w, h = Widget.GetPreferredSize(orientation)
        local frame = CreateFrame("StatusBar", nil, parent)
        frame:SetSize(w, h)
        frame:SetStatusBarTexture(Theme.statusBarTexture)
        if orientation == "vertical" then
            frame:SetOrientation("VERTICAL")
        end

        local fill = Theme.colors[config.colorKey] or Theme.colors.mana
        frame:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4])
        frame:SetMinMaxValues(0, 1)
        frame:SetValue(1)

        local bg = makePixel(frame, "BACKGROUND")
        bg:SetAllPoints(frame)
        local bgC = Theme.colors.bgDark
        bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])

        buildBorder(frame, Theme.colors.border)

        frame.text = frame:CreateFontString(nil, "OVERLAY")
        frame.text:SetFont(Theme.font, Theme.fontSize - 2, Theme.fontFlags)
        frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
        local tw = Theme.colors.textWhite
        frame.text:SetTextColor(tw[1], tw[2], tw[3], tw[4])

        for _, ev in ipairs(config.events) do
            frame:RegisterEvent(ev)
        end
        frame:SetScript("OnEvent", onEvent)

        refresh(frame)
        return frame, w, h
    end

    function Widget.Destroy(frame)
        if not frame then return end
        frame:UnregisterAllEvents()
        frame:SetScript("OnEvent", nil)
        frame:Hide()
        frame:SetParent(nil)
    end

    return Widget
end
