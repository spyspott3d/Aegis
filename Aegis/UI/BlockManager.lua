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
