-- Aegis/Core/Init.lua
-- Addon namespace, lifecycle, slash command dispatch. Loads after every
-- widget registers itself in ns.WidgetCatalog and after Block / BlockManager
-- are defined, so PLAYER_LOGIN can build all blocks immediately.

local addonName, ns = ...

Aegis = ns
ns.name = addonName
ns.version = GetAddOnMetadata(addonName, "Version") or "?"

AegisDB = AegisDB or {}
AegisDBChar = AegisDBChar or {}

local Util = ns.Util

local function aprint(msg)
    if Util and Util.Print then
        Util.Print(msg)
    else
        print("Aegis: " .. tostring(msg))
    end
end

local function colorize(text, hex)
    if Util and Util.Colorize then return Util.Colorize(text, hex) end
    return tostring(text)
end

----------------------------------------------------------------
-- Reset confirm dialog
----------------------------------------------------------------

StaticPopupDialogs["AEGIS_RESET_CONFIRM"] = {
    text = "Reset all Aegis blocks to the default layout? Your current "
        .. "block list will be discarded.",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function()
        if ns.BlockManager and ns.BlockManager.Reset then
            ns.BlockManager.Reset()
            aprint("blocks reset to default.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

----------------------------------------------------------------
-- Block subcommand helpers
----------------------------------------------------------------

local function catalogIds()
    local ids = {}
    if ns.WidgetCatalog then
        for k in pairs(ns.WidgetCatalog) do
            tinsert(ids, k)
        end
        table.sort(ids)
    end
    return ids
end

local function generateBlockId()
    local used = {}
    if AegisDBChar.blocks then
        for _, b in ipairs(AegisDBChar.blocks) do
            if b.id then used[b.id] = true end
        end
    end
    local i = 1
    while used["block" .. i] do i = i + 1 end
    return "block" .. i
end

local function listBlocks()
    local blocks = AegisDBChar and AegisDBChar.blocks
    if not blocks or #blocks == 0 then
        aprint("no blocks. Try /ae reset to install defaults.")
        return
    end
    print(colorize("Aegis", "1ED760") .. " blocks:")
    for i, b in ipairs(blocks) do
        local p = b.position or {}
        local pos = ("%s%+d,%+d"):format(
            p.point or "?", p.xOffset or 0, p.yOffset or 0)
        local wlist = (b.widgets and #b.widgets > 0)
            and table.concat(b.widgets, ",") or "(empty)"
        print(("  [%d] id=%s pos=%s orient=%s style=%s widgets=%s"):format(
            i,
            b.id or "?",
            pos,
            b.orientation or "horizontal",
            b.style or "standard",
            wlist))
    end
end

local function addBlock(args)
    args = args or ""
    local orientation, rest = args:match("^(%S+)%s*(.*)$")
    if not orientation then
        aprint("usage: /ae block add <horizontal|vertical> <widget1> [widget2] ...")
        return
    end
    if orientation == "h" then orientation = "horizontal" end
    if orientation == "v" then orientation = "vertical" end
    if orientation ~= "horizontal" and orientation ~= "vertical" then
        aprint("orientation must be horizontal or vertical (h | v).")
        return
    end
    local widgets = {}
    for w in (rest or ""):gmatch("(%S+)") do
        if not (ns.WidgetCatalog and ns.WidgetCatalog[w]) then
            aprint(("unknown widget '%s'. /ae block help for the catalog."):format(w))
            return
        end
        tinsert(widgets, w)
    end
    if #widgets == 0 then
        aprint("at least one widget id is required.")
        return
    end
    local newBlock = {
        id          = generateBlockId(),
        position    = {
            point         = "CENTER",
            relativePoint = "CENTER",
            xOffset       = 0,
            yOffset       = 0,
        },
        orientation = orientation,
        style       = (AegisDB.visual and AegisDB.visual.defaultBlockStyle) or "standard",
        scale       = 1.0,
        gap         = 4,
        widgets     = widgets,
    }
    AegisDBChar.blocks = AegisDBChar.blocks or {}
    tinsert(AegisDBChar.blocks, newBlock)
    if ns.BlockManager and ns.BlockManager.Build then
        ns.BlockManager.Build()
    end
    aprint(("block '%s' added (%s, %d widgets) at screen center."):format(
        newBlock.id, orientation, #widgets))
end

local function removeBlock(id)
    id = strtrim(id or "")
    if id == "" then
        aprint("usage: /ae block remove <id> (see /ae block list)")
        return
    end
    local blocks = AegisDBChar and AegisDBChar.blocks
    if not blocks then
        aprint("no blocks.")
        return
    end
    for i, b in ipairs(blocks) do
        if b.id == id then
            tremove(blocks, i)
            if ns.BlockManager and ns.BlockManager.Build then
                ns.BlockManager.Build()
            end
            aprint(("block '%s' removed."):format(id))
            return
        end
    end
    aprint(("block '%s' not found. /ae block list."):format(id))
end

local function blockHelp()
    print(colorize("Aegis", "1ED760") .. " block commands:")
    print("  /ae block list                                 - list all blocks")
    print("  /ae block add <h|v> <widget1> [widget2] ...    - create a block at screen center")
    print("    h = horizontal bars (wide, 150x22) stacked top-to-bottom")
    print("    v = vertical bars   (tall, 22x100) side-by-side")
    print("  /ae block remove <id>                          - delete a block by id")
    print("  Available widgets: " .. table.concat(catalogIds(), ", "))
end

----------------------------------------------------------------
-- Slash command dispatch
----------------------------------------------------------------

local sub = {}

sub.help = function()
    print(colorize("Aegis", "1ED760") .. " commands:")
    print("  /ae                          - toggle the settings window")
    print("  /ae lock                     - lock all blocks in place")
    print("  /ae unlock                   - unlock all blocks for dragging")
    print("  /ae reset                    - reset blocks to default layout (asks to confirm)")
    print("  /ae block ...                - manage blocks (see /ae block help)")
    print("  /ae pressure                 - show pressure config")
    print("  /ae debug pressure [on|off]  - toggle pressure debug print")
    print("  /ae about                    - show version info")
    print("  /ae help                     - show this list")
end

sub.lock = function()
    if ns.BlockManager then ns.BlockManager.Lock() end
    aprint("all blocks locked.")
end

sub.unlock = function()
    if ns.BlockManager then ns.BlockManager.Unlock() end
    aprint("blocks unlocked. Drag to move, /ae lock when done.")
end

sub.reset = function()
    StaticPopup_Show("AEGIS_RESET_CONFIRM")
end

sub.about = function()
    local author = GetAddOnMetadata(addonName, "Author") or "?"
    print(("%s v%s by %s"):format(colorize(addonName, "1ED760"), ns.version, author))
end

sub.pressure = function()
    local p = (AegisDB and AegisDB.pressure) or {}
    local th = p.thresholds or {}
    print(colorize("Aegis", "1ED760") .. " pressure config:")
    print(("  window: %ss"):format(p.windowSeconds or 4))
    print(("  TTD thresholds: warning=%ss, critical=%ss"):format(
        th.warningTTD or 10, th.criticalTTD or 5))
    print(("  drain thresholds: warning=%.2f%%/s, critical=%.2f%%/s"):format(
        (th.warningDrain or 0.01) * 100, (th.criticalDrain or 0.03) * 100))
    print(("  hysteresis: %ss (healing sustain: %ss)"):format(
        p.hysteresisSeconds or 0.5, p.healingSustainTime or 1.5))
    print(("  sound on critical: %s"):format(tostring(p.soundOnCritical or false)))
    print("  (use the config panel to tune; /ae)")
end

sub.block = function(rest)
    rest = rest or ""
    local action, args = rest:match("^(%S+)%s*(.*)$")
    action = action or ""
    if action == "" or action == "help" then
        blockHelp()
    elseif action == "list" then
        listBlocks()
    elseif action == "add" then
        addBlock(args)
    elseif action == "remove" or action == "rm" or action == "delete" then
        removeBlock(args)
    else
        aprint(("unknown /ae block subcommand '%s'. /ae block help."):format(action))
    end
end

sub.debug = function(rest)
    rest = rest or ""
    -- /ae debug pressure on|off|toggle
    local target, arg = rest:match("^(%S+)%s*(.*)$")
    if target == "pressure" then
        if not ns.Pressure then
            aprint("pressure module not loaded.")
            return
        end
        if arg == "on" then
            ns.Pressure.debug = true
            aprint("pressure debug on (printing every 1s).")
        elseif arg == "off" then
            ns.Pressure.debug = false
            aprint("pressure debug off.")
        else
            ns.Pressure.debug = not ns.Pressure.debug
            aprint("pressure debug " .. (ns.Pressure.debug and "on" or "off") .. ".")
        end
    else
        aprint("usage: /ae debug pressure [on|off]")
    end
end

local function dispatch(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "" then
        -- /ae alone opens the settings panel. Falls back to text help if
        -- the settings module is somehow not loaded.
        if ns.Settings and ns.Settings.Toggle then
            ns.Settings.Toggle()
        else
            sub.help()
        end
        return
    end
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd or ""
    local handler = sub[cmd]
    if handler then
        handler(rest)
    else
        aprint(("unknown command '%s'. Try /ae help."):format(cmd))
    end
end

SLASH_AE1 = "/ae"
SLASH_AE2 = "/aegis"
SlashCmdList["AE"] = dispatch

----------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------

local lifecycle = CreateFrame("Frame")
lifecycle:RegisterEvent("ADDON_LOADED")
lifecycle:RegisterEvent("PLAYER_LOGIN")

lifecycle:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if ns.Config and ns.Config.Initialize then
            ns.Config.Initialize()
        end
    elseif event == "PLAYER_LOGIN" then
        -- Cache stable identifiers per CLAUDE.md (class never changes; the
        -- player GUID is needed by Phase 3's combat log filter).
        ns.playerClass = select(2, UnitClass("player"))
        ns.playerGUID  = UnitGUID("player")
        if ns.BlockManager and ns.BlockManager.Build then
            ns.BlockManager.Build()
        end
        print(("%s v%s loaded. Type /ae for commands."):format(
            colorize(addonName, "1ED760"), ns.version))
    end
end)
