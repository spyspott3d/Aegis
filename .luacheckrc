-- .luacheckrc
-- Luacheck configuration for the Aegis addon.
--
-- Tuned to silence noise from the WoW global namespace while still catching
-- real issues (unused vars, redefined locals, undefined locals).

std = "lua51"
max_line_length = false
max_cyclomatic_complexity = 30

-- Globals defined by Aegis itself (the addon writes to these).
globals = {
    "Aegis",
    "AegisDB",
    "AegisDBChar",
    "SLASH_AE1",
    "SLASH_AE2",
    -- Blizzard slash command registry: addons add their own "KEY" entry to it.
    "SlashCmdList",
    -- StaticPopupDialogs: addons add their own dialog entries to this table
    -- (e.g. AEGIS_RESET_CONFIRM).
    "StaticPopupDialogs",
}

-- Read-only globals: WoW client API and Lua stdlib that the addon reads but
-- does not assign to. Trim or extend as needed.
read_globals = {
    -- Lua stdlib that 3.3.5a exposes
    "bit", "string", "table", "math", "type", "select", "pairs", "ipairs",
    "tostring", "tonumber", "unpack", "next", "rawget", "rawset", "setmetatable",
    "getmetatable", "pcall", "xpcall", "error", "assert", "print", "format",
    "wipe", "strsplit", "strjoin", "strtrim", "strsub", "strlen", "strlower",
    "strupper", "strfind", "strmatch", "gmatch", "gsub", "tinsert", "tremove",
    "tContains", "max", "min", "abs", "floor", "ceil", "mod", "random",
    "date", "time", "GetTime", "debugstack",

    -- Frame and UI API (StaticPopupDialogs is in `globals` because we write
    -- our own dialog entries to it).
    "CreateFrame", "UIParent", "WorldFrame", "GameTooltip", "DEFAULT_CHAT_FRAME",
    "ChatFrame1", "StaticPopup_Show", "StaticPopup_Hide",
    "PlaySound", "PlaySoundFile", "GetCursorPosition", "GetScreenWidth",
    "GetScreenHeight", "InCombatLockdown", "IsAddOnLoaded", "LoadAddOn",
    "GetAddOnMetadata", "EnableAddOn", "DisableAddOn",

    -- Slash commands (SlashCmdList is in `globals` because we write to it)
    "ChatEdit_FocusActiveWindow", "ChatFrame_OpenChat",

    -- Unit info (player and others)
    "UnitHealth", "UnitHealthMax", "UnitGUID", "UnitName", "UnitClass",
    "UnitPower", "UnitPowerMax", "UnitPowerType", "UnitExists",
    "GetComboPoints", "GetShapeshiftForm",
    -- Cataclysm-style heal prediction (backported on Project Ascension)
    "UnitGetIncomingHeals",

    -- Items, bags
    "GetItemInfo", "GetItemQualityColor", "GetItemIcon", "GetContainerItemInfo",
    "GetContainerItemLink", "GetContainerNumSlots", "GetContainerNumFreeSlots",
    "PickupContainerItem", "UseContainerItem", "SplitContainerItem",
    "GetItemCount", "GetItemFamily", "ContainerIDToInventoryID",
    "GetInventoryItemLink", "GetInventoryItemID", "GetInventoryItemCount",

    -- Money
    "GetMoney", "GetCoinTextureString", "MoneyFrame_Update",

    -- Localization
    "GetLocale",

    -- Events / errors
    "geterrorhandler", "seterrorhandler",

    -- Common constants
    "BOOKTYPE_SPELL", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "BACKPACK_CONTAINER",
    "BANK_CONTAINER", "KEYRING_CONTAINER",

    -- Ace3 (loaded as an embedded lib if used)
    "LibStub",
}

-- Globally ignored warnings.
-- 212: unused argument (event handlers often take args they ignore)
-- 213: unused loop variable
-- 631: line too long (already disabled via max_line_length)
ignore = {
    "212",
    "213",
    "631",
}
