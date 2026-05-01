-- Aegis/Core/Config.lua
-- SavedVariables defaults, schema migrations, and config helpers. Schema
-- version 2: replaces the v1 single-anchor model with a list of blocks.
-- See SPEC.md and ARCHITECTURE.md.

local _, ns = ...
ns.Config = ns.Config or {}
local Config = ns.Config

Config.SCHEMA_VERSION = 2

local accountDefaults = {
    version = 2,
    pressure = {
        windowSeconds = 4,
        thresholds = {
            warning = 10,
            critical = 5,
        },
        soundOnCritical = false,
        hysteresisSeconds = 0.5,
    },
    visual = {
        scale = 1.0,
        outOfCombatAlpha = 0.3,
        showHealthText = "value_and_percent",
        font = "Friz Quadrata TT",
        defaultBlockStyle = "standard", -- standard | glossy
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
    version = 2,
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
