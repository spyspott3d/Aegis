-- Aegis/Core/Config.lua
-- SavedVariables defaults, schema migrations, and config helpers. Schema
-- version 2: replaces the v1 single-anchor model with a list of blocks.
-- See SPEC.md and ARCHITECTURE.md.

local _, ns = ...
ns.Config = ns.Config or {}
local Config = ns.Config

Config.SCHEMA_VERSION = 9

local accountDefaults = {
    version = 9,
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
        -- value | percent | value_and_percent | none
        showHealthText = "value_and_percent",
        -- Per-bar text format. Each resource bar reads its own key so the
        -- user can hide text on, say, the rage bar while keeping a percent
        -- readout on the mana bar. Values mirror showHealthText:
        --   value | percent | value_and_percent | none
        -- v4 stored these as booleans (true/false); v5 migrated them to
        -- strings — true -> "value_and_percent", false -> "none".
        showManaText   = "value_and_percent",
        showRageText   = "value_and_percent",
        showEnergyText = "value_and_percent",
        showRunicText  = "value_and_percent",
        -- Combo points: render the integer count as a small label next to
        -- the filled pips, in addition to the pips themselves.
        showComboCount = false,
        font = "Friz Quadrata TT",
        defaultBlockStyle = "standard", -- standard | glossy
        -- Pressure halo around the health widget shows only while in
        -- combat by default. Set to false to keep the halo visible
        -- out of combat too (rarely useful in practice — sliding-window
        -- data ages out and the halo just lingers post-fight).
        haloInCombatOnly = true,
        -- Where to anchor the TTD readout when the HP bar is in vertical
        -- orientation: "above" puts it on top of the bar, "below" beneath.
        -- Horizontal bars always read TTD to the right (no setting).
        ttdPositionVertical = "below",
        -- Master toggle for the TTD readout. Off hides it entirely
        -- regardless of pressure state.
        showTTD = true,
    },
}

-- Default blocks installed on a fresh character (or after /ae reset). Per
-- SPEC.md "Default install": two blocks symmetric around screen center,
-- mirroring the player character.
-- Default install: two blocks symmetric around screen center, mirroring the
-- player character. Each block uses orientation = "horizontal" — meaning the
-- BARS are horizontal (wide, 150x22) and the block packs them top-to-bottom.
-- (v6 briefly inverted this convention; v7 reverts it to the original.)
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
        gap = 4,
        curve = "none",
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
        gap = 4,
        curve = "none",
        widgets = { "rage", "energy", "runic" },
    },
}

local charDefaults = {
    version = 4,
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
    [4] = function(db)
        -- v3 -> v4: replace the global showResourceText with per-bar toggles.
        if db.visual then
            local v = db.visual.showResourceText
            if v ~= nil then
                local on = (v ~= false)
                db.visual.showManaText   = on
                db.visual.showRageText   = on
                db.visual.showEnergyText = on
                db.visual.showRunicText  = on
                db.visual.showResourceText = nil
            end
        end
        db.version = 4
    end,
    [5] = function(db)
        -- v4 -> v5: per-bar text toggles upgrade from boolean to format string,
        -- matching showHealthText. Old true => "value_and_percent" (the v4
        -- behaviour was always "current / max"), old false => "none". Strings
        -- already in place pass through.
        if db.visual then
            local keys = { "showManaText", "showRageText", "showEnergyText", "showRunicText" }
            for _, k in ipairs(keys) do
                local cur = db.visual[k]
                if cur == true then
                    db.visual[k] = "value_and_percent"
                elseif cur == false then
                    db.visual[k] = "none"
                end
            end
        end
        db.version = 5
    end,
    [6] = function(db)
        -- v5 -> v6: no account-side changes (block orientation lives on the
        -- per-character DB; see charMigrations[6]). Bump only.
        db.version = 6
    end,
    [7] = function(db)
        -- v6 -> v7: no account-side changes; the v7 work is on the
        -- per-character DB (orientation labels reverted). Bump only.
        db.version = 7
    end,
    [8] = function(db)
        -- v7 -> v8: per-block `gap` field added to AegisDBChar.blocks. The
        -- defaults pass writes the missing field on existing blocks via the
        -- new `gap = 4` in defaultBlocks (matches the old hardcoded
        -- WIDGET_GAP, so visuals are unchanged for users who don't touch it).
        -- No account-side change here.
        db.version = 8
    end,
    [9] = function(db)
        -- v8 -> v9: per-block `curve` field added (none/left/right). No
        -- account-side change here.
        db.version = 9
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
    [4] = function(db)
        -- v3 -> v4: no per-character changes; bump only.
        db.version = 4
    end,
    [5] = function(db)
        -- v4 -> v5: no per-character changes; bump only.
        db.version = 5
    end,
    [6] = function(db)
        -- v5 -> v6: orientation labels were inverted vs the user's mental
        -- model (old "horizontal" = horizontal bars stacked vertically;
        -- old "vertical" = vertical bars side-by-side). v6 swaps the labels
        -- so "vertical" means widgets stack top-to-bottom and "horizontal"
        -- means widgets sit side-by-side. Existing blocks have their
        -- orientation flipped so the on-screen layout is unchanged.
        if db.blocks then
            for _, b in ipairs(db.blocks) do
                if b.orientation == "horizontal" then
                    b.orientation = "vertical"
                elseif b.orientation == "vertical" then
                    b.orientation = "horizontal"
                end
            end
        end
        db.version = 6
    end,
    [7] = function(db)
        -- v6 -> v7: REVERT the v6 swap. The v6 convention turned out to
        -- conflict with the user's mental model where "horizontal" describes
        -- the BAR shape (horizontal = wide bars stacked vertically;
        -- vertical = tall bars side-by-side). For data that was migrated
        -- through v6, this flip restores the pre-v6 value. For data that
        -- skipped v6 (e.g. fresh install at v7 reading an older saved
        -- variable that never went through v6), the flip is the identity
        -- they came in with. Either way the on-screen layout is preserved
        -- because Block:Layout was reverted in lockstep with this migration.
        if db.blocks then
            for _, b in ipairs(db.blocks) do
                if b.orientation == "horizontal" then
                    b.orientation = "vertical"
                elseif b.orientation == "vertical" then
                    b.orientation = "horizontal"
                end
            end
        end
        db.version = 7
    end,
    [8] = function(db)
        -- v7 -> v8: per-block `gap` (px between widgets in the layout). The
        -- defaults pass adds gap=4 on each existing block so the on-screen
        -- spacing is unchanged for blocks the user never touches.
        if db.blocks then
            for _, b in ipairs(db.blocks) do
                if b.gap == nil then b.gap = 4 end
            end
        end
        db.version = 8
    end,
    [9] = function(db)
        -- v8 -> v9: per-block `curve` (none/left/right) added. Existing
        -- blocks get "none" so visuals stay rectangular until the user
        -- explicitly picks a curve in the Blocks tab.
        if db.blocks then
            for _, b in ipairs(db.blocks) do
                if b.curve == nil then b.curve = "none" end
            end
        end
        db.version = 9
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
