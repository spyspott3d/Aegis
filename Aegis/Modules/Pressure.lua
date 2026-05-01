-- Aegis/Modules/Pressure.lua
-- The pressure module: combat log parser, ring buffer, sliding-window
-- recompute, state machine with hysteresis, public getters for the four
-- DPS/HPS readouts. Phase 3 ships the data layer; Phase 4 will hook it to
-- the visual overlays on the health widget and to the four text widgets.
--
-- Hot path: COMBAT_LOG_EVENT_UNFILTERED fires hundreds of times per second
-- in a 25-man fight. Per CLAUDE.md hard rule #4, the first thing the
-- handler does is filter for events relevant to the player. Anything that
-- is neither incoming (destGUID == playerGUID) nor outgoing
-- (sourceFlags has the AFFILIATION_MINE bit) returns immediately, no
-- string parsing, no allocation.
--
-- The ring buffer is pre-allocated once at module load (CLAUDE.md hard
-- rule #5). push() mutates the entry at the current head index; no
-- tinsert/tremove, no allocation. Recompute walks the buffer linearly,
-- producing four sums in a single pass.

local _, ns = ...
ns.Pressure = ns.Pressure or {}
local Pressure = ns.Pressure

----------------------------------------------------------------
-- Constants
----------------------------------------------------------------

local BUFFER_SIZE      = 256
local TICK_INTERVAL    = 0.25
local DEBUG_INTERVAL   = 1.0
local AFFILIATION_MINE = 0x00000001 -- bit-test against sourceFlags

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

local STATE_RANK = {
    none     = 0,
    light    = 1,
    warning  = 2,
    critical = 3,
}

----------------------------------------------------------------
-- Public state
----------------------------------------------------------------

Pressure.state   = "none"
Pressure.ttd     = nil
Pressure.dps_in  = 0
Pressure.hps_in  = 0
Pressure.dps_out = 0
Pressure.hps_out = 0
Pressure.debug   = false

function Pressure.GetIncomingDPS()  return Pressure.dps_in  end
function Pressure.GetIncomingHPS()  return Pressure.hps_in  end
function Pressure.GetOutgoingDPS()  return Pressure.dps_out end
function Pressure.GetOutgoingHPS()  return Pressure.hps_out end

----------------------------------------------------------------
-- Ring buffer
----------------------------------------------------------------

-- Each entry is a fixed 3-slot array: { timestamp, category, amount }.
-- Allocated once, mutated forever.
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
    -- SPELL_DAMAGE, SPELL_PERIODIC_DAMAGE, RANGE_DAMAGE
    return a4 or 0, a9 or 0
end

local function parseHeal(_subevent, _a1, _a2, _a3, a4, a5)
    -- SPELL_HEAL, SPELL_PERIODIC_HEAL: amount=a4, overhealing=a5.
    return a4 or 0, a5 or 0
end

----------------------------------------------------------------
-- Combat log handler
----------------------------------------------------------------

local function onCombatLog(self, event,
    _timestamp, subevent,
    sourceGUID, _sourceName, sourceFlags,
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

    if DAMAGE_SUBEVENTS[subevent] then
        local amount, absorbed = parseDamage(subevent, a1, a2, a3, a4, a5, a6, a7, a8, a9)
        if isIncoming then
            -- Effective: subtract the absorbed portion (CLAUDE.md / SPEC).
            local eff = amount - absorbed
            if eff > 0 then push(now, "damage_in", eff) end
        end
        if isOutgoing then
            -- Outgoing uses the raw amount (matches how damage meters
            -- report DPS dealt; overkill stays counted).
            if amount > 0 then push(now, "damage_out", amount) end
        end
    elseif HEAL_SUBEVENTS[subevent] then
        local amount, overhealing = parseHeal(subevent, a1, a2, a3, a4, a5)
        local eff = amount - overhealing
        if eff > 0 then
            if isIncoming then push(now, "heal_in", eff) end
            if isOutgoing then push(now, "heal_out", eff) end
        end
    end
end

----------------------------------------------------------------
-- State transition with hysteresis
----------------------------------------------------------------
--
-- "lastValidTime" is the most recent moment when the raw-computed state was
-- at least as severe as the current state. If raw stays below current for
-- hysteresisSeconds without any spike back up, we accept the downgrade.
-- Worse states are adopted immediately.

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
-- Recompute (called every TICK_INTERVAL)
----------------------------------------------------------------

local function recompute()
    local now = GetTime()
    local window = (AegisDB and AegisDB.pressure
        and AegisDB.pressure.windowSeconds) or 4
    local cutoff = now - window

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

    Pressure.dps_in  = d_in  / window
    Pressure.hps_in  = h_in  / window
    Pressure.dps_out = d_out / window
    Pressure.hps_out = h_out / window

    local netLoss = Pressure.dps_in - Pressure.hps_in
    local rawState = "none"
    if netLoss > 0 then
        local cur = UnitHealth("player") or 0
        local ttd = cur / netLoss
        Pressure.ttd = ttd
        local thresholds = (AegisDB and AegisDB.pressure
            and AegisDB.pressure.thresholds) or {}
        local critT = thresholds.critical or 5
        local warnT = thresholds.warning or 10
        if ttd <= critT then
            rawState = "critical"
        elseif ttd <= warnT then
            rawState = "warning"
        else
            rawState = "light"
        end
    else
        Pressure.ttd = nil
    end

    transition(rawState)
end

----------------------------------------------------------------
-- Debug print (toggled by /ae debug pressure on|off)
----------------------------------------------------------------

local function printDebug()
    print(("|cff1ED760Aegis|r pressure: state=%s ttd=%s | "
        .. "DPS_in=%.0f HPS_in=%.0f DPS_out=%.0f HPS_out=%.0f"):format(
        Pressure.state,
        Pressure.ttd and ("%.1fs"):format(Pressure.ttd) or "nil",
        Pressure.dps_in, Pressure.hps_in,
        Pressure.dps_out, Pressure.hps_out))
end

----------------------------------------------------------------
-- Tickers and event hookup
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
