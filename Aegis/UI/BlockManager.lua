-- Aegis/UI/BlockManager.lua
-- Owns the live list of Block instances. Builds them at PLAYER_LOGIN from
-- AegisDBChar.blocks. Provides global lock/unlock and reset operations and
-- a cross-block widget query (used by the pressure module to find every
-- `health` widget regardless of which block hosts it).

local _, ns = ...
ns.BlockManager = ns.BlockManager or {}
local BM = ns.BlockManager

local blocks = {}

local function clearBlocks()
    for _, b in ipairs(blocks) do
        b:Destroy()
    end
    wipe(blocks)
end

function BM.Build()
    clearBlocks()
    if not AegisDBChar or not AegisDBChar.blocks then return end
    for _, blockConfig in ipairs(AegisDBChar.blocks) do
        local b = ns.Block.New(blockConfig)
        table.insert(blocks, b)
    end
    BM.SetLocked(AegisDBChar.locked ~= false)
end

function BM.Rebuild()
    BM.Build()
end

function BM.SetLocked(locked)
    AegisDBChar.locked = locked and true or false
    for _, b in ipairs(blocks) do
        b:SetLocked(AegisDBChar.locked)
    end
end

function BM.IsLocked()
    return AegisDBChar and AegisDBChar.locked and true or false
end

function BM.Lock()   BM.SetLocked(true)  end
function BM.Unlock() BM.SetLocked(false) end

-- Reset: discard the user's blocks, reinstall the default seed list, rebuild.
function BM.Reset()
    clearBlocks()
    if AegisDBChar then AegisDBChar.blocks = nil end
    if ns.Config and ns.Config.Initialize then ns.Config.Initialize() end
    BM.Build()
end

-- Returns a flat list of all widget frames matching `typeId` across every
-- block. Used by the pressure module to push state to every `health`
-- widget. The list is a fresh table on each call; callers should not retain
-- references between block edits.
function BM.GetWidgetsByType(typeId)
    local list = {}
    for _, b in ipairs(blocks) do
        local frames = b:GetWidgetsByType(typeId)
        for _, f in ipairs(frames) do
            table.insert(list, f)
        end
    end
    return list
end

function BM.GetBlocks() return blocks end

-- Find the live Block instance whose config.id matches `id`. Returns nil if
-- the user just removed it from AegisDBChar.blocks but Build() has not run yet.
function BM.GetBlockByConfigId(id)
    if not id then return nil end
    for _, b in ipairs(blocks) do
        if b.config and b.config.id == id then return b end
    end
    return nil
end

-- Push a Refresh() call to every live widget. Used by the settings dialog
-- after the user changes a visual toggle so the change is visible without
-- waiting for the next event tick (text format dropdowns, combo count, etc).
function BM.RefreshAllWidgets()
    for _, b in ipairs(blocks) do
        if b.widgets then
            for _, w in ipairs(b.widgets) do
                if w.widget and w.widget.Refresh and w.frame then
                    w.widget.Refresh(w.frame)
                end
            end
        end
    end
end

-- Rebuild a single block in place after its config (orientation, style,
-- widget list, scale) was edited. Cheaper than BM.Build() when only one
-- block changed; avoids flickering the others. Falls back to full Build()
-- if the block is not yet alive.
function BM.RebuildBlock(id)
    local b = BM.GetBlockByConfigId(id)
    if not b then
        BM.Build()
        return
    end
    b:Layout()
    b:applyPosition()
end
