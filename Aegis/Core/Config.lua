-- Aegis/Core/Config.lua
-- SavedVariables defaults, schema migrations, and config helpers. Schema
-- version 2: replaces the v1 single-anchor model with a list of blocks.
-- See SPEC.md and ARCHITECTURE.md.

local _, ns = ...
ns.Config = ns.Config or {}
local Config = ns.Config

Config.SCHEMA_VERSION = 3

local accountDefaults = {
    version = 3,
    pressure = {
        windowSeconds = 4,
        thresholds = {
            -- TTD-based (immediate danger from current rate, in seconds).
            warningTTD   = 10,
            criticalTTD  = 5,
            -- Drain-based (% of max HP per second, expressed as a fraction:
            -- 0.01 == 1%/s). Catches sustained attrition that TTD alone
            -- under-flags on long fights with high-HP characters.
            warningDrain  = 0.01,
            criticalDrain = 0.03,
        },
        soundOnCritical = false,
        hysteresisSeconds = 0.5,
        -- Entering "healing" requires this many seconds of sustained
        -- HPS_in > DPS_in. Longer than the general hysteresis so a brief
        -- heal tick mid-fight does not flip the halo from red to blue
        -- before the next mob attack lands.
        healingSustainTime = 1.5,
    },
    visual = {
        scale = 1.0,
        outOfCombatAlpha = 0.3,
        showHealthText = "value_and_percent",
        font = "Friz Quadrata TT",
        defaultBlockStyle = "standard", -- standard | glossy
        -- Pressure halo around the health widget shows only while in
        -- combat by default. Set to false to keep the halo visible
        -- out of combat too (rarely useful in practice — sliding-window
        -- data ages out and the halo just lingers post-fight).
        haloInCombatOnly = true,
    },
}

-- Default blocks installed on a fresh character (or after /ae reset). Per
-- SPEC.md "Default install": two blocks symmetric around screen center,
-- mirroring the player character.
local defaultBlocks = {
    {
        id = "left",
        position = {
            point = "RIGHT",
            relativePoint = "CENTER",
            xOffset = -120,
            yOffset = 0,
        },
        orientation = "horizontal",
        style = "standard",
        scale = 1.0,
        widgets = { "combo", "health", "mana" },
    },
    {
        id = "right",
        position = {
            point = "LEFT",
            relativePoint = "CENTER",
            xOffset = 120,
            yOffset = 0,
        },
        orientation = "horizontal",
        style = "standard",
        scale = 1.0,
        widgets = { "rage", "energy", "runic" },
    },
}

local charDefaults = {
    version = 3,
    locked = true,
    -- `blocks` is NOT applied via applyDefaults. It is seeded once if missing
    -- (see installBlocksIfMissing). applyDefaults is for key-value fills and
    -- would corrupt array sequences.
}

-- Recursively fill missing keys in target from src. Skips array-shaped tables
-- (sequences) — those are handled by callers explicitly.
local function applyDefaults(target, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = {}
            end
            applyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Deep copy used to seed AegisDBChar.blocks without aliasing the constants.
local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepCopy(v) end
    return copy
end

local accountMigrations = {
    [1] = function(db)
        db.version = 1
    end,
    [2] = function(db)
        -- v1 -> v2: orientation and glossy moved from global visual to
        -- per-block. Drop the global versions; defaults pass installs
        -- defaultBlockStyle.
        if db.visual then
            db.visual.orientation = nil
            db.visual.glossy = nil
        end
        db.version = 2
    end,
    [3] = function(db)
        -- v2 -> v3: pressure thresholds split into TTD-based and drain-based
        -- pairs. Old `warning` and `critical` were TTD seconds; rename them
        -- to warningTTD / criticalTTD. Drain thresholds are added by the
        -- defaults pass.
        if db.pressure and db.pressure.thresholds then
            local th = db.pressure.thresholds
            if th.warning  ~= nil then th.warningTTD  = th.warning  end
            if th.critical ~= nil then th.criticalTTD = th.critical end
            th.warning  = nil
            th.critical = nil
        end
        db.version = 3
    end,
}

local charMigrations = {
    [1] = function(db)
        db.version = 1
    end,
    [2] = function(db)
        -- v1 -> v2: replace the single anchor position with a block list.
        -- We discard the v1 position; installBlocksIfMissing reseeds.
        db.position = nil
        db.blocks = nil
        db.version = 2
    end,
    [3] = function(db)
        -- v2 -> v3: no per-character changes; bump only.
        db.version = 3
    end,
}

local function runMigrations(db, migrations, target)
    local from = db.version or 0
    for v = from + 1, target do
        local fn = migrations[v]
        if fn then fn(db) end
    end
    db.version = target
end

local function installBlocksIfMissing()
    if not AegisDBChar.blocks or #AegisDBChar.blocks == 0 then
        AegisDBChar.blocks = deepCopy(defaultBlocks)
    end
end

function Config.Initialize()
    AegisDB = AegisDB or {}
    AegisDBChar = AegisDBChar or {}
    runMigrations(AegisDB, accountMigrations, Config.SCHEMA_VERSION)
    runMigrations(AegisDBChar, charMigrations, Config.SCHEMA_VERSION)
    applyDefaults(AegisDB, accountDefaults)
    applyDefaults(AegisDBChar, charDefaults)
    installBlocksIfMissing()
end

-- Discard the user's blocks and reseed with the default list. Called by
-- BlockManager.Reset (and ultimately by /ae reset).
function Config.ResetBlocks()
    if not AegisDBChar then return end
    AegisDBChar.blocks = deepCopy(defaultBlocks)
end

Config.accountDefaults = accountDefaults
Config.charDefaults = charDefaults
Config.defaultBlocks = defaultBlocks
