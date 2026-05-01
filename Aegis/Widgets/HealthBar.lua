-- Aegis/Widgets/HealthBar.lua
-- Health widget. Always available. Hosts the pressure halo (a colored
-- border drawn outside the bar that signals incoming pressure state) and
-- the incoming-heal segment (a light-green texture inside the bar that
-- previews predicted post-heal HP, fed by Ascension's backported
-- UnitGetIncomingHeals API).
--
-- Public extensions added by Build:
--   frame.SetPressure(self, state, ttd) — called by the pressure module
--                                          on each tick. Updates halo,
--                                          TTD readout, and triggers a
--                                          critical-entry sound when
--                                          the state transitions into
--                                          critical.

local _, ns = ...
local HealthBar = {}

----------------------------------------------------------------
-- Halo state map
----------------------------------------------------------------
--
-- Each pressure state maps to a halo color, a base alpha, and an
-- optional pulse period (seconds). State `none` means "no halo at all";
-- `healing` is the only state that does NOT pulse despite being highly
-- visible — it is good news, not a warning.

local STATE_HALO = {
    healing  = { colorKey = "haloHealing",  alpha = 0.45 },
    none     = nil,
    light    = { colorKey = "haloLight",    alpha = 0.25 },
    warning  = { colorKey = "haloWarning",  alpha = 0.55, pulsePeriod = 1.5 },
    critical = { colorKey = "haloCritical", alpha = 0.75, pulsePeriod = 0.5 },
}

----------------------------------------------------------------
-- Widget interface
----------------------------------------------------------------

function HealthBar.IsAvailable()
    return true
end

function HealthBar.GetPreferredSize(orientation)
    if orientation == "vertical" then
        return 22, 100
    end
    return 150, 22
end

local function readFormat()
    local v = AegisDB and AegisDB.visual
    return (v and v.showHealthText) or "value_and_percent"
end

local function formatHP(cur, max)
    local fmt = readFormat()
    if fmt == "none" then return "" end
    if not cur or cur < 0 then cur = 0 end
    if not max or max < 1 then max = 1 end
    local pct = math.floor((cur / max) * 100 + 0.5)
    if fmt == "value" then
        return tostring(cur)
    elseif fmt == "percent" then
        return pct .. "%"
    end
    return cur .. " / " .. max .. "  " .. pct .. "%"
end

----------------------------------------------------------------
-- Incoming heal segment (Ascension backported UnitGetIncomingHeals)
----------------------------------------------------------------

local function refreshIncomingHeal(frame)
    local seg = frame and frame.healSegment
    if not seg then return end
    if not UnitGetIncomingHeals then
        seg:Hide()
        return
    end
    local incoming = UnitGetIncomingHeals("player") or 0
    if incoming <= 0 then
        seg:Hide()
        return
    end
    local cur = UnitHealth("player") or 0
    local mx  = UnitHealthMax("player") or 1
    if mx < 1 then mx = 1 end
    local barWidth  = frame:GetWidth() or 0
    local barHeight = frame:GetHeight() or 0
    if barWidth < 1 or barHeight < 1 then
        seg:Hide()
        return
    end
    local fillFrac = cur / mx
    if fillFrac > 1 then fillFrac = 1 end
    local healFrac = incoming / mx
    if healFrac + fillFrac > 1 then healFrac = 1 - fillFrac end
    if healFrac <= 0 then
        seg:Hide()
        return
    end
    seg:ClearAllPoints()
    seg:SetPoint("TOPLEFT",    frame, "TOPLEFT",    fillFrac * barWidth, 0)
    seg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", fillFrac * barWidth, 0)
    seg:SetWidth(healFrac * barWidth)
    seg:Show()
end

----------------------------------------------------------------
-- Refresh
----------------------------------------------------------------

local function refresh(frame)
    if not frame then return end
    local cur = UnitHealth("player") or 0
    local max = UnitHealthMax("player") or 0
    frame:SetMinMaxValues(0, math.max(1, max))
    frame:SetValue(cur)
    if frame.text then frame.text:SetText(formatHP(cur, max)) end
    refreshIncomingHeal(frame)
end

HealthBar.Refresh = refresh

----------------------------------------------------------------
-- Event handler
----------------------------------------------------------------

local function onEvent(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        refresh(self)
        return
    end
    if event == "UNIT_HEAL_PREDICTION" then
        if unit == "player" then refreshIncomingHeal(self) end
        return
    end
    if unit ~= "player" then return end
    refresh(self)
end

----------------------------------------------------------------
-- Border / chrome helpers
----------------------------------------------------------------

local function makePixel(parent, layer, sublevel)
    local t = parent:CreateTexture(nil, layer or "OVERLAY", nil, sublevel)
    t:SetTexture(ns.Theme.backgroundTexture)
    return t
end

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

----------------------------------------------------------------
-- Halo (pressure state visual)
----------------------------------------------------------------

local HALO_OUTSET = 4

local function buildHalo(parent)
    local halo = CreateFrame("Frame", nil, parent)
    halo:SetPoint("TOPLEFT",     parent, "TOPLEFT",     -HALO_OUTSET,  HALO_OUTSET)
    halo:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",  HALO_OUTSET, -HALO_OUTSET)
    halo:SetBackdrop({
        edgeFile = ns.Theme.backgroundTexture,
        edgeSize = HALO_OUTSET,
    })
    halo:SetBackdropBorderColor(0, 0, 0, 0)
    halo._color       = nil
    halo._baseAlpha   = 0
    halo._pulsePeriod = nil
    halo._pulseAccum  = 0
    -- Pulse: OnUpdate modulates alpha via sine wave when pulsePeriod is
    -- set. Documented carve-out from CLAUDE.md hard rule #3 alongside the
    -- energy widget poll. ~30 Hz on at most a few halo frames is
    -- effectively free (~0.01% CPU).
    halo:SetScript("OnUpdate", function(self, elapsed)
        if not self._pulsePeriod or not self._color then return end
        self._pulseAccum = (self._pulseAccum or 0) + elapsed
        local p = self._pulseAccum % self._pulsePeriod
        local progress = p / self._pulsePeriod
        local pulse = 0.5 + 0.5 * math.sin(progress * 2 * math.pi)
        local alpha = self._baseAlpha * (0.5 + 0.5 * pulse)
        local c = self._color
        self:SetBackdropBorderColor(c[1], c[2], c[3], alpha)
    end)
    return halo
end

local function applyHaloState(halo, state)
    local cfg = STATE_HALO[state]
    if not cfg then
        halo._color       = nil
        halo._baseAlpha   = 0
        halo._pulsePeriod = nil
        halo:SetBackdropBorderColor(0, 0, 0, 0)
        return
    end
    local color = ns.Theme.colors[cfg.colorKey] or { 1, 1, 1, 1 }
    halo._color       = color
    halo._baseAlpha   = cfg.alpha
    halo._pulsePeriod = cfg.pulsePeriod
    halo._pulseAccum  = 0
    halo:SetBackdropBorderColor(color[1], color[2], color[3], cfg.alpha)
end

----------------------------------------------------------------
-- TTD readout + critical sound
----------------------------------------------------------------

local function formatTTD(ttd)
    if not ttd then return "TTD ?" end
    if ttd < 10 then
        return ("TTD %.1fs"):format(ttd)
    end
    return ("TTD %ds"):format(math.floor(ttd + 0.5))
end

local function applyTTDText(frame, state, ttd)
    local txt = frame.ttdText
    if not txt then return end
    if state == "warning" or state == "critical" then
        txt:SetText(formatTTD(ttd))
        if state == "critical" then
            local c = ns.Theme.colors.haloCritical
            txt:SetTextColor(c[1], c[2], c[3], 1)
        else
            local c = ns.Theme.colors.haloWarning
            txt:SetTextColor(c[1], c[2], c[3], 1)
        end
        txt:Show()
    else
        txt:Hide()
    end
end

local function maybePlayCriticalSound(frame, state)
    if state ~= "critical" then return end
    if frame._lastState == "critical" then return end
    if not (AegisDB and AegisDB.pressure and AegisDB.pressure.soundOnCritical) then
        return
    end
    -- "RaidWarning" is a built-in Blizzard sound name; falls back silently
    -- if missing on a private server build.
    PlaySound("RaidWarning")
end

----------------------------------------------------------------
-- Build
----------------------------------------------------------------

function HealthBar.Build(parent, orientation, style)
    local Theme = ns.Theme
    local w, h = HealthBar.GetPreferredSize(orientation)
    local frame = CreateFrame("StatusBar", nil, parent)
    frame:SetSize(w, h)
    frame:SetStatusBarTexture(Theme.statusBarTexture)
    if orientation == "vertical" then
        frame:SetOrientation("VERTICAL")
    end

    local fill = Theme.colors.health
    frame:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4])
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(1)

    local bg = makePixel(frame, "BACKGROUND")
    bg:SetAllPoints(frame)
    local bgC = Theme.colors.bgDark
    bg:SetVertexColor(bgC[1], bgC[2], bgC[3], bgC[4])

    -- Incoming-heal preview segment. Sits on ARTWORK above the bar fill
    -- (which the StatusBar draws on ARTWORK at sublevel 0).
    local seg = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    seg:SetTexture(Theme.statusBarTexture)
    local hi = Theme.colors.healthIncoming
    seg:SetVertexColor(hi[1], hi[2], hi[3], hi[4])
    seg:Hide()
    frame.healSegment = seg

    if style == "glossy" and Theme.ApplyGlossy then
        Theme.ApplyGlossy(frame)
    end

    buildBorder(frame, Theme.colors.border)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(Theme.font, Theme.fontSize, Theme.fontFlags)
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local tw = Theme.colors.textWhite
    frame.text:SetTextColor(tw[1], tw[2], tw[3], tw[4])

    -- TTD readout: shown only in warning/critical. Anchored INSIDE the
    -- bar's right edge so it stays visible regardless of how the block
    -- is laid out (an earlier draft anchored it just outside the bar's
    -- right edge, which made it disappear off the edge of left-side
    -- blocks). Right-justified so the seconds digit stays put as TTD
    -- changes magnitude.
    -- TTD readout sits OUTSIDE the bar, hugged against the right edge.
    -- Inside the bar overlaps the centered HP text. Outside-right places
    -- it in the natural gap between the left block and the player
    -- character at screen center, where the eye already rests.
    local ttdText = frame:CreateFontString(nil, "OVERLAY")
    ttdText:SetFont(Theme.font, Theme.fontSize + 2, Theme.fontFlags)
    ttdText:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    ttdText:SetJustifyH("LEFT")
    ttdText:Hide()
    frame.ttdText = ttdText

    frame.halo = buildHalo(frame)

    -- Public method: pressure module pushes state every 0.25s.
    frame.SetPressure = function(self, state, ttd)
        if not state then state = "none" end
        -- Halo is in-combat only by default. Out of combat the player has
        -- no actionable use for a colored halo (the residual sliding-
        -- window data still ages out for a few seconds after combat
        -- ends; without this gate the halo would briefly remain colored
        -- post-combat).
        local v = (AegisDB and AegisDB.visual) or {}
        local hideForOOC = (v.haloInCombatOnly ~= false) and not InCombatLockdown()
        if hideForOOC then
            applyHaloState(self.halo, "none")
            if self.ttdText then self.ttdText:Hide() end
            -- Keep _lastState updated so the in-combat re-entry knows
            -- the prior state for sound triggering.
            self._lastState = state
            return
        end
        applyHaloState(self.halo, state)
        applyTTDText(self, state, ttd)
        maybePlayCriticalSound(self, state)
        -- Belt-and-suspenders: re-poll UnitGetIncomingHeals on every
        -- pressure tick. UNIT_HEAL_PREDICTION is the primary trigger but
        -- on Ascension it does not always fire on heal start/end, so the
        -- segment can go stale. 0.25s max staleness from this poll.
        refreshIncomingHeal(self)
        self._lastState = state
    end

    frame:RegisterEvent("UNIT_HEALTH")
    frame:RegisterEvent("UNIT_MAXHEALTH")
    frame:RegisterEvent("UNIT_HEAL_PREDICTION")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", onEvent)

    refresh(frame)
    return frame, w, h
end

function HealthBar.Destroy(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame:SetScript("OnEvent", nil)
    if frame.halo then
        frame.halo:SetScript("OnUpdate", nil)
        frame.halo:Hide()
        frame.halo:SetParent(nil)
        frame.halo = nil
    end
    frame:Hide()
    frame:SetParent(nil)
end

ns.Widgets.Register("health", HealthBar)
