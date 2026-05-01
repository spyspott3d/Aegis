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
-- Slash command dispatch
----------------------------------------------------------------

local sub = {}

sub.help = function()
    print(colorize("Aegis", "1ED760") .. " commands:")
    print("  /ae lock      - lock all blocks in place")
    print("  /ae unlock    - unlock all blocks for dragging")
    print("  /ae reset     - reset blocks to default layout (asks to confirm)")
    print("  /ae about     - show version info")
    print("  /ae help      - show this list")
    print("  /ae pressure  - (not yet implemented)")
    print("  /ae debug     - (not yet implemented)")
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
    aprint("pressure settings not yet implemented.")
end

sub.debug = function()
    aprint("debug not yet implemented.")
end

local function dispatch(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "" then
        sub.help()
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
