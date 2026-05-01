-- Aegis/Core/Aegis.lua

local addonName, ns = ...

-- Public namespace exposed as a global so other parts of the addon (and
-- /run for debugging) can reach it.
Aegis = ns
ns.name = addonName
ns.version = GetAddOnMetadata(addonName, "Version") or "?"

-- Saved variables. Initialized in ADDON_LOADED.
AegisDB = AegisDB or {}
AegisDBChar = AegisDBChar or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- One-time init when SavedVariables are available.
    elseif event == "PLAYER_LOGIN" then
        print(("|cff00ff00%s|r v%s loaded. Type /%s for commands."):format(
            addonName, ns.version, "ae"))
    end
end)

-- Slash command.
SLASH_AE1 = "/ae"
SlashCmdList["AE"] = function(msg)
    msg = msg and msg:lower() or ""
    if msg == "" or msg == "help" then
        print(("|cff00ff00%s|r commands:"):format(addonName))
        print("  /ae about - show version info")
        print("  /ae help  - show this list")
    elseif msg == "about" then
        print(("|cff00ff00%s|r v%s by %s"):format(
            addonName, ns.version, GetAddOnMetadata(addonName, "Author") or "?"))
    else
        print(("|cff00ff00%s|r: unknown command '%s'. Try /%s help."):format(
            addonName, msg, "ae"))
    end
end
