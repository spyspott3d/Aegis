-- Aegis/Modules/Pressure.lua
-- The pressure module: combat log parser, ring buffer, sliding-window
-- recompute (for TTD/state), session-since-combat-start accumulators (for
-- the displayed dps_in/hps_in/dps_out/hps_out values), state machine with
-- hysteresis. Phase 3 ships the data layer; Phase 4 will hook it to the
-- visual overlay on the health widget and to the four text widgets.
--
-- Two parallel metrics serve different needs:
--
--  * Sliding window (default 4s, configurable) drives the pressure state
--    and TTD. It must be responsive to bursts: a sudden DPS spike should
--    push the bar to warning/critical immediately, not lag behind a
--    growing average.
--
--  * Session-since-combat-start drives the displayed text widgets. It is
--    stable mid-fight even against slow attackers: a mob that hits once
--    every 5s will produce a steady "session DPS" instead of a 4s
--    sliding window that oscillates between a real value and 0 between
--    hits. It freezes when leaving combat (so the post-fight readout is
--    "the average for that fight") and resets at the next combat entry.
--
-- Hot path: COMBAT_LOG_EVENT_UNFILTERED fires hundreds of times per second
-- in a 25-man fight. Per CLAUDE.md hard rule #4, the first thing the
-- handler does is filter for events relevant to the player. Anything that
-- is neither incoming (destGUID == playerGUID) nor outgoing (sourceFlags
-- has the AFFILIATION_MINE bit) returns immediately.
--
-- The ring buffer is pre-allocated once at module load (CLAUDE.md hard
-- rule #5). push() mutates the entry at the current head index. Recompute
-- walks the buffer linearly, producing four sliding sums in a single pass.

local _, ns = ...
ns.Pressure = ns.Pressure or {}
local Pressure = ns.Pressure

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local BUFFER_SIZE          = 256
local TICK_INTERVAL        = 0.25
local DEBUG_INTERVAL       = 1.0
local AFFILIATION_MINE     = 0x00000001 -- bit-test against sourceFlags
local SESSION_PRIME_WINDOW = 1.0        -- prime session from buffer events
                                         -- in this many seconds before
                                         -- PLAYER_REGEN_DISABLED fires
local SESSION_MIN_ELAPSED  = 0.5        -- below this, session DPS would
                                         -- be a noisy spike; emit 0

local DAMAGE_SUBEVENTS = {
    SWING_DAMAGE          = true,
    RANGE_DAMAGE          = true,
    SPELL_DAMAGE          = true,
    SPELL_PERIODIC_DAMAGE = true,
    ENVIRONMENTAL_DAMAGE  = true,
}

local HEAL_SUBEVENTS = {
    SPELL_HEAL          = true,
    SPELL_PERIODIC_HEAL = true,
}

-- States, ordered by severity. `healing` is "less severe" than `none` (it is
-- the most positive state — heals dominate damage). Hysteresis keys off
-- this ordering: transition to a less severe state requires sustaining.
local STATE_RANK = {
    healing  = -1,
    none     = 0,
    light    = 1,
    warning  = 2,
    critical = 3,
}

----------------------------------------------------------------
-- Public state (session-based for display widgets)
----------------------------------------------------------------

Pressure.state   = "none"
Pressure.ttd     = nil
Pressure.dps_in  = 0  -- session: total damage taken / combat elapsed
Pressure.hps_in  = 0
Pressure.dps_out = 0
Pressure.hps_out = 0
Pressure.debug   = false

function Pressure.GetIncomingDPS()  return Pressure.dps_in  end
function Pressure.GetIncomingHPS()  return Pressure.hps_in  end
function Pressure.GetOutgoingDPS()  return Pressure.dps_out end
function Pressure.GetOutgoingHPS()  return Pressure.hps_out end

----------------------------------------------------------------
-- Internal sliding-window values (for TTD / state)
----------------------------------------------------------------

local sliding_dps_in  = 0
local sliding_hps_in  = 0
local sliding_dps_out = 0
local sliding_hps_out = 0

function Pressure.GetSlidingIncomingDPS()  return sliding_dps_in  end
function Pressure.GetSlidingIncomingHPS()  return sliding_hps_in  end
function Pressure.GetSlidingOutgoingDPS()  return sliding_dps_out end
function Pressure.GetSlidingOutgoingHPS()  return sliding_hps_out end

----------------------------------------------------------------
-- Session accumulators (reset per combat)
----------------------------------------------------------------

local sessionDamageIn  = 0
local sessionHealIn    = 0
local sessionDamageOut = 0
local sessionHealOut   = 0
local combatStartTime  = nil  -- nil before first combat
local combatEndTime    = nil  -- non-nil while frozen out-of-combat

local function inCombat()
    return combatStartTime ~= nil and combatEndTime == nil
end

----------------------------------------------------------------
-- Ring buffer
----------------------------------------------------------------

local buffer = {}
for i = 1, BUFFER_SIZE do buffer[i] = { 0, "", 0 } end
local head = 0

local function push(now, category, amount)
    head = (head % BUFFER_SIZE) + 1
    local e = buffer[head]
    e[1] = now
    e[2] = category
    e[3] = amount
end

----------------------------------------------------------------
-- Per-subevent argument parsers
----------------------------------------------------------------
--
-- 3.3.5a COMBAT_LOG_EVENT_UNFILTERED payload after destFlags, by subevent:
--
--   SWING_DAMAGE:
--     amount, overkill, school, resisted, blocked, absorbed, critical,
--     glancing, crushing
--
--   ENVIRONMENTAL_DAMAGE:
--     environmentalType, amount, overkill, school, resisted, blocked,
--     absorbed, critical, glancing, crushing
--
--   SPELL_DAMAGE / SPELL_PERIODIC_DAMAGE / RANGE_DAMAGE:
--     spellId, spellName, spellSchool, amount, overkill, school,
--     resisted, blocked, absorbed, critical, glancing, crushing
--
--   SPELL_HEAL / SPELL_PERIODIC_HEAL:
--     spellId, spellName, spellSchool, amount, overhealing, absorbed,
--     critical
--

local function parseDamage(subevent, a1, a2, a3, a4, a5, a6, a7, a8, a9)
    if subevent == "SWING_DAMAGE" then
        return a1 or 0, a6 or 0
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        return a2 or 0, a7 or 0
    end
    return a4 or 0, a9 or 0
end

local function parseHeal(_subevent, _a1, _a2, _a3, a4, a5)
    return a4 or 0, a5 or 0
end

----------------------------------------------------------------
-- Combat log handler
----------------------------------------------------------------

local function onCombatLog(self, event,
    _timestamp, subevent,
    _sourceGUID, _sourceName, sourceFlags,
    destGUID, _destName, _destFlags,
    a1, a2, a3, a4, a5, a6, a7, a8, a9)

    local pGUID = ns.playerGUID
    if not pGUID then return end

    local isIncoming = (destGUID == pGUID)
    local isOutgoing = sourceFlags
        and bit.band(sourceFlags, AFFILIATION_MINE) ~= 0
        or false
    if not isIncoming and not isOutgoing then return end

    local now = GetTime()
    local accumulate = inCombat()

    if DAMAGE_SUBEVENTS[subevent] then
        local amount, absorbed = parseDamage(subevent, a1, a2, a3, a4, a5, a6, a7, a8, a9)
        if isIncoming then
            local eff = amount - absorbed
            if eff > 0 then
                push(now, "damage_in", eff)
                if accumulate then sessionDamageIn = sessionDamageIn + eff end
            end
        end
        if isOutgoing then
            if amount > 0 then
                push(now, "damage_out", amount)
                if accumulate then sessionDamageOut = sessionDamageOut + amount end
            end
        end
    elseif HEAL_SUBEVENTS[subevent] then
        local amount, overhealing = parseHeal(subevent, a1, a2, a3, a4, a5)
        local eff = amount - overhealing
        if eff > 0 then
            if isIncoming then
                push(now, "heal_in", eff)
                if accumulate then sessionHealIn = sessionHealIn + eff end
            end
            if isOutgoing then
                push(now, "heal_out", eff)
                if accumulate then sessionHealOut = sessionHealOut + eff end
            end
        end
    end
end

----------------------------------------------------------------
-- Combat state handler (REGEN events drive session reset/freeze)
----------------------------------------------------------------

local function primeSessionFromBuffer(now)
    -- The first hit of a fight typically fires *before* PLAYER_REGEN_DISABLED.
    -- Scan recent buffer entries and fold them into the session totals so
    -- the very first hit is not lost. Also walk back combatStartTime to
    -- the earliest event in this prime window so elapsed time matches the
    -- earliest data.
    local cutoff = now - SESSION_PRIME_WINDOW
    local earliest = combatStartTime or now
    for i = 1, BUFFER_SIZE do
        local e = buffer[i]
        local ts = e[1]
        if ts >= cutoff and ts <= now then
            local cat, amt = e[2], e[3]
            if     cat == "damage_in"  then sessionDamageIn  = sessionDamageIn  + amt
            elseif cat == "heal_in"    then sessionHealIn    = sessionHealIn    + amt
            elseif cat == "damage_out" then sessionDamageOut = sessionDamageOut + amt
            elseif cat == "heal_out"   then sessionHealOut   = sessionHealOut   + amt
            end
            if ts < earliest then earliest = ts end
        end
    end
    combatStartTime = earliest
end

local function onCombatState(self, event)
    local now = GetTime()
    if event == "PLAYER_REGEN_DISABLED" then
        sessionDamageIn  = 0
        sessionHealIn    = 0
        sessionDamageOut = 0
        sessionHealOut   = 0
        combatStartTime  = now
        combatEndTime    = nil
        primeSessionFromBuffer(now)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Freeze: keep totals as-is; recompute will divide by the frozen
        -- elapsed (combatEndTime - combatStartTime) so the displayed
        -- average stops drifting.
        combatEndTime = now
    end
end

local combatStateFrame = CreateFrame("Frame")
combatStateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatStateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatStateFrame:SetScript("OnEvent", onCombatState)

----------------------------------------------------------------
-- State transition with hysteresis
----------------------------------------------------------------

local lastValidTime = 0

local function transition(rawState)
    local current = Pressure.state or "none"
    local now = GetTime()
    if STATE_RANK[rawState] >= STATE_RANK[current] then
        Pressure.state = rawState
        lastValidTime = now
    else
        local hyst = (AegisDB and AegisDB.pressure
            and AegisDB.pressure.hysteresisSeconds) or 0.5
        if now - lastValidTime >= hyst then
            Pressure.state = rawState
            lastValidTime = now
        end
    end
end

----------------------------------------------------------------
-- Raw state derivation from current sliding values
----------------------------------------------------------------

local function rawStateFromTTD(ttd, warnTTD, critTTD)
    if ttd <= critTTD then return "critical" end
    if ttd <= warnTTD then return "warning"  end
    return "light"
end

local function rawStateFromDrain(drain, warnDrain, critDrain)
    if drain >= critDrain then return "critical" end
    if drain >= warnDrain then return "warning"  end
    return "light"
end

-- Returns the raw state string for the current sliding-window numbers.
-- Side effect: assigns Pressure.ttd (number for net-loss states, nil
-- otherwise). Kept separate so recompute stays under the cyclomatic
-- complexity ceiling.
local function deriveRawState()
    local netLoss = sliding_dps_in - sliding_hps_in
    if sliding_hps_in > sliding_dps_in and sliding_hps_in > 0 then
        Pressure.ttd = nil
        return "healing"
    end
    if netLoss <= 0 then
        Pressure.ttd = nil
        return "none"
    end
    local cur = UnitHealth("player") or 0
    local mx  = UnitHealthMax("player") or 1
    if mx < 1 then mx = 1 end
    local ttd = cur / netLoss
    Pressure.ttd = ttd
    local drain = netLoss / mx

    local thresholds = (AegisDB and AegisDB.pressure
        and AegisDB.pressure.thresholds) or {}
    local fromTTD   = rawStateFromTTD(ttd,
        thresholds.warningTTD or 10, thresholds.criticalTTD or 5)
    local fromDrain = rawStateFromDrain(drain,
        thresholds.warningDrain or 0.01, thresholds.criticalDrain or 0.03)
    if STATE_RANK[fromDrain] > STATE_RANK[fromTTD] then
        return fromDrain
    end
    return fromTTD
end

----------------------------------------------------------------
-- Recompute (called every TICK_INTERVAL)
----------------------------------------------------------------

local function recompute()
    local now = GetTime()
    local window = (AegisDB and AegisDB.pressure
        and AegisDB.pressure.windowSeconds) or 4
    local cutoff = now - window

    -- Sliding window pass (used for TTD/state).
    local d_in, h_in, d_out, h_out = 0, 0, 0, 0
    for i = 1, BUFFER_SIZE do
        local e = buffer[i]
        if e[1] >= cutoff then
            local cat = e[2]
            local amt = e[3]
            if     cat == "damage_in"  then d_in  = d_in  + amt
            elseif cat == "heal_in"    then h_in  = h_in  + amt
            elseif cat == "damage_out" then d_out = d_out + amt
            elseif cat == "heal_out"   then h_out = h_out + amt
            end
        end
    end
    sliding_dps_in  = d_in  / window
    sliding_hps_in  = h_in  / window
    sliding_dps_out = d_out / window
    sliding_hps_out = h_out / window

    -- Session pass (used for displayed widgets).
    if combatStartTime then
        local elapsed
        if combatEndTime then
            elapsed = combatEndTime - combatStartTime
        else
            elapsed = now - combatStartTime
        end
        if elapsed >= SESSION_MIN_ELAPSED then
            Pressure.dps_in  = sessionDamageIn  / elapsed
            Pressure.hps_in  = sessionHealIn    / elapsed
            Pressure.dps_out = sessionDamageOut / elapsed
            Pressure.hps_out = sessionHealOut   / elapsed
        else
            Pressure.dps_in  = 0
            Pressure.hps_in  = 0
            Pressure.dps_out = 0
            Pressure.hps_out = 0
        end
    else
        -- Never been in combat this session.
        Pressure.dps_in  = 0
        Pressure.hps_in  = 0
        Pressure.dps_out = 0
        Pressure.hps_out = 0
    end

    -- State from sliding (responsive). See deriveRawState above for the
    -- five-tier hybrid drain+TTD logic.
    transition(deriveRawState())
end

----------------------------------------------------------------
-- Debug print (toggled by /ae debug pressure on|off)
----------------------------------------------------------------

local function combatStatusLabel()
    if not combatStartTime then return "no-combat" end
    if combatEndTime then return "frozen" end
    return "in-combat"
end

local function printDebug()
    local netLoss = sliding_dps_in - sliding_hps_in
    local drain = 0
    if netLoss > 0 then
        local mx = UnitHealthMax("player") or 1
        if mx >= 1 then drain = (netLoss / mx) * 100 end
    end
    print(("|cff1ED760Aegis|r pressure: state=%s ttd=%s drain=%.2f%%/s [%s]"):format(
        Pressure.state,
        Pressure.ttd and ("%.1fs"):format(Pressure.ttd) or "nil",
        drain,
        combatStatusLabel()))
    print(("  session: DPS_in=%.0f HPS_in=%.0f DPS_out=%.0f HPS_out=%.0f"):format(
        Pressure.dps_in, Pressure.hps_in,
        Pressure.dps_out, Pressure.hps_out))
    print(("  window:  DPS_in=%.0f HPS_in=%.0f DPS_out=%.0f HPS_out=%.0f"):format(
        sliding_dps_in, sliding_hps_in,
        sliding_dps_out, sliding_hps_out))
end

----------------------------------------------------------------
-- Tickers and combat log hookup
----------------------------------------------------------------

local tickAccum  = 0
local debugAccum = 0

local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(self, elapsed)
    tickAccum = tickAccum + elapsed
    if tickAccum >= TICK_INTERVAL then
        tickAccum = 0
        recompute()
    end
    if Pressure.debug then
        debugAccum = debugAccum + elapsed
        if debugAccum >= DEBUG_INTERVAL then
            debugAccum = 0
            printDebug()
        end
    end
end)

local handler = CreateFrame("Frame")
handler:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
handler:SetScript("OnEvent", onCombatLog)
