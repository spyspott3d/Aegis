-- Aegis/Core/Init.lua
-- Addon namespace, lifecycle, slash command dispatch. Loads last so all
-- modules (Util, Config, Theme, Anchor) have already attached themselves to
-- the namespace.

local addonName, ns = ...

-- Public namespace exposed as a global so /run and other modules can reach it.
Aegis = ns
ns.name = addonName
ns.version = GetAddOnMetadata(addonName, "Version") or "?"

-- SavedVariables stubs in case ADDON_LOADED has not yet fired by the time
-- something reads them (defensive; Config.Initialize is the real path).
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
-- Slash command dispatch
----------------------------------------------------------------

local sub = {}

sub.help = function()
    print(colorize("Aegis", "1ED760") .. " commands:")
    print("  /ae lock      - lock the HUD position")
    print("  /ae unlock    - unlock the HUD for dragging")
    print("  /ae reset     - reset HUD position to default")
    print("  /ae about     - show version info")
    print("  /ae help      - show this list")
    print("  /ae pressure  - (not yet implemented)")
    print("  /ae debug     - (not yet implemented)")
end

sub.lock = function()
    if ns.Anchor and ns.Anchor.Lock then ns.Anchor.Lock() end
    aprint("HUD locked.")
end

sub.unlock = function()
    if ns.Anchor and ns.Anchor.Unlock then ns.Anchor.Unlock() end
    aprint("HUD unlocked. Drag to move, /ae lock when done.")
end

sub.reset = function()
    if ns.Anchor and ns.Anchor.Reset then ns.Anchor.Reset() end
    aprint("position reset to default.")
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
        -- Cache class once. Per CLAUDE.md, repeated UnitClass calls in hot
        -- paths are wasteful; class never changes for a character.
        ns.playerClass = select(2, UnitClass("player"))
        if ns.Anchor and ns.Anchor.Build then
            ns.Anchor.Build()
        end
        if ns.HealthBar and ns.HealthBar.Build then
            ns.HealthBar.Build()
        end
        if ns.ResourceBar and ns.ResourceBar.Build then
            ns.ResourceBar.Build()
        end
        if ns.ComboPoints and ns.ComboPoints.Build then
            ns.ComboPoints.Build()
        end
        print(("%s v%s loaded. Type /ae for commands."):format(
            colorize(addonName, "1ED760"), ns.version))
    end
end)
