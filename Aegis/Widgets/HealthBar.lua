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

local TEX_BASE = "Interface\\AddOns\\Aegis\\Textures\\"

-- Two halo flavours under the hood, sharing the same OnUpdate pulse + color
-- state. Picked by buildHalo based on whether the bar is rectangular
-- (StatusBar) or curved (TextureBar):
--
--   "rect"   — backdrop frame with edgeFile draws a 4-edge rectangular
--              outline outside the bar. Original behaviour for HP bars in
--              standard / glossy mode.
--   "curved" — texture posed BEHIND the bar (BACKGROUND, sublevel -1) at
--              parent + HALO_OUTSET overhang, using the same shape file as
--              the bar so the silhouette is identical but slightly larger.
--              Tinted via SetVertexColor → reads as a curved fringe of the
--              halo state colour around the bar.
--
-- Both flavours expose the same `_applyAlpha(color, alpha)` callback used by
-- the OnUpdate ticker, so the pulse logic is shared.
local function buildHalo(parent, curve, shape)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT",     parent, "TOPLEFT",     -HALO_OUTSET,  HALO_OUTSET)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT",  HALO_OUTSET, -HALO_OUTSET)

    if curve == "left" or curve == "right" then
        -- Halo uses the dedicated <Shape>Halo.tga texture: same spine arc
        -- as the bar but with thickness expanded by 2*HALO_GROW (encoded
        -- in the texture itself by the Python generator). Rendered at the
        -- SAME frame size as the bar (no overhang), so the wider silhouette
        -- inside the texture provides a uniform fringe at every height.
        --
        -- Why not scale the bar texture? Scaling around canvas center
        -- pushes off-center silhouette features (curve cusps at top/bottom)
        -- asymmetrically — overhang reads balanced at midpoint but uneven
        -- at the ends. Encoding the outset inside the texture geometry
        -- preserves it uniformly along the spine.
        -- BACKGROUND/0 (with TextureBar's bg moved to BACKGROUND/1) keeps
        -- the halo strictly behind the bar bg in the same layer. Negative
        -- sublevels are unreliable on 3.3.5a (silently clamped to 0), which
        -- previously put the halo ON TOP of the bg and produced the
        -- "halo over empty bar" bleed-through.
        local tex = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
        tex:SetTexture(TEX_BASE .. "Wide\\" .. shape .. "Halo")
        tex:SetAllPoints(parent)
        tex:SetVertexColor(0, 0, 0, 0)
        f._tex = tex
        f._applyAlpha = function(c, a) tex:SetVertexColor(c[1], c[2], c[3], a) end
    else
        f:SetBackdrop({
            edgeFile = ns.Theme.backgroundTexture,
            edgeSize = HALO_OUTSET,
        })
        f:SetBackdropBorderColor(0, 0, 0, 0)
        f._applyAlpha = function(c, a) f:SetBackdropBorderColor(c[1], c[2], c[3], a) end
    end

    f._color       = nil
    f._baseAlpha   = 0
    f._pulsePeriod = nil
    f._pulseAccum  = 0
    -- Pulse: OnUpdate modulates alpha via sine wave when pulsePeriod is set.
    -- Documented carve-out from CLAUDE.md hard rule #3 alongside the energy
    -- widget poll. ~30 Hz on at most a few halo frames is effectively free
    -- (~0.01% CPU).
    f:SetScript("OnUpdate", function(self, elapsed)
        -- Steady (non-pulsing) states are painted once by applyHaloState
        -- and never need a per-frame update — only pulsing states (warning,
        -- critical) animate alpha here.
        if not self._pulsePeriod or not self._color then return end
        self._pulseAccum = (self._pulseAccum or 0) + elapsed
        local p = self._pulseAccum % self._pulsePeriod
        local progress = p / self._pulsePeriod
        local pulse = 0.5 + 0.5 * math.sin(progress * 2 * math.pi)
        local alpha = self._baseAlpha * (0.5 + 0.5 * pulse)
        self._applyAlpha(self._color, alpha)
    end)
    return f
end

local function applyHaloState(halo, state)
    local cfg = STATE_HALO[state]
    if not cfg then
        halo._color       = nil
        halo._baseAlpha   = 0
        halo._pulsePeriod = nil
        halo._applyAlpha({ 0, 0, 0 }, 0)
        return
    end
    local color = ns.Theme.colors[cfg.colorKey] or { 1, 1, 1, 1 }
    halo._color       = color
    halo._baseAlpha   = cfg.alpha
    halo._pulsePeriod = cfg.pulsePeriod
    halo._pulseAccum  = 0
    halo._applyAlpha(color, cfg.alpha)
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
    -- Master kill switch: hide the TTD entirely when the user opts out.
    if AegisDB and AegisDB.visual and AegisDB.visual.showTTD == false then
        txt:Hide()
        return
    end
    if state == "warning" or state == "critical" then
        -- Re-anchor every tick so a Visual.ttdPositionVertical setting change
        -- takes effect within 0.25s without forcing a block rebuild. Costs
        -- ~3 SetPoint calls / pressure tick / HP widget — negligible.
        txt:ClearAllPoints()
        if frame._orientation == "vertical" then
            local pos = (AegisDB and AegisDB.visual
                and AegisDB.visual.ttdPositionVertical) or "below"
            if pos == "above" then
                txt:SetPoint("BOTTOM", frame, "TOP", 0, 4)
            else
                txt:SetPoint("TOP", frame, "BOTTOM", 0, -4)
            end
            txt:SetJustifyH("CENTER")
        else
            txt:SetPoint("LEFT", frame, "RIGHT", 6, 0)
            txt:SetJustifyH("LEFT")
        end
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

function HealthBar.Build(parent, orientation, style, curve)
    curve = curve or "none"
    local Theme = ns.Theme
    local w, h = HealthBar.GetPreferredSize(orientation)

    local frame
    if curve == "left" or curve == "right" then
        -- Curved bar: ship-shape texture with TexCoord-based fill. The bg
        -- and border are baked into the texture art so we skip the manual
        -- pixel bg + buildBorder calls used by the StatusBar branch. Glossy
        -- and the incoming-heal segment are skipped too (TODO heal-segment
        -- on curved bars: would need a 2nd texture overlay clipped to the
        -- predicted-heal sub-range; deferred until requested).
        local shape = (curve == "left") and "ArcLeft" or "ArcRight"
        frame = ns.TextureBar.New(parent, w, h, shape, { set = "Wide" })
        local fill = Theme.colors.health
        frame:SetStatusBarColor(fill[1], fill[2], fill[3], fill[4])
        frame:SetMinMaxValues(0, 1)
        frame:SetValue(1)
    else
        frame = CreateFrame("StatusBar", nil, parent)
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
    end

    -- Stored on the frame so applyTTDText can re-anchor the readout based on
    -- orientation without re-querying the block config (the widget isn't
    -- aware of its block parent).
    frame._orientation = orientation

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

    local haloShape = (curve == "left" and "ArcLeft")
        or (curve == "right" and "ArcRight") or nil
    frame.halo = buildHalo(frame, curve, haloShape)

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
