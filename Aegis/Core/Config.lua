-- Aegis/Core/Config.lua
-- SavedVariables defaults, schema migrations, and config helpers. The config
-- panel itself is built later (Phase 5); this module is just the data layer.

local _, ns = ...
ns.Config = ns.Config or {}
local Config = ns.Config

Config.SCHEMA_VERSION = 1

local accountDefaults = {
    version = 1,
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
    },
}

local charDefaults = {
    version = 1,
    position = {
        point = "CENTER",
        relativePoint = "CENTER",
        xOffset = -200,
        yOffset = 0,
    },
    locked = true,
}

-- Recursively fill missing keys from src into target. Values already present
-- in target are preserved (so user customizations survive default updates).
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

-- Migration registry. migrations[N] upgrades a DB at version N-1 to N. Phase 0
-- only ships v1, so the entry is a no-op stamp; future schema changes append
-- new entries here.
local accountMigrations = {
    [1] = function(db)
        db.version = 1
    end,
}

local charMigrations = {
    [1] = function(db)
        db.version = 1
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

-- Called from ADDON_LOADED once SavedVariables are populated.
function Config.Initialize()
    AegisDB = AegisDB or {}
    AegisDBChar = AegisDBChar or {}
    runMigrations(AegisDB, accountMigrations, Config.SCHEMA_VERSION)
    runMigrations(AegisDBChar, charMigrations, Config.SCHEMA_VERSION)
    applyDefaults(AegisDB, accountDefaults)
    applyDefaults(AegisDBChar, charDefaults)
end

-- Reset the per-character HUD position to the shipped default. Returns the
-- position table so callers can immediately re-apply.
function Config.ResetPosition()
    AegisDBChar.position = {}
    applyDefaults(AegisDBChar.position, charDefaults.position)
    return AegisDBChar.position
end

Config.accountDefaults = accountDefaults
Config.charDefaults = charDefaults
