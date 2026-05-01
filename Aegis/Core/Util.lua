-- Aegis/Core/Util.lua
-- Small shared helpers. Phase 0 only needs color/print helpers; this module
-- will grow as later phases land formatting and math utilities.

local _, ns = ...
ns.Util = ns.Util or {}
local Util = ns.Util

-- Wrap text in a WoW chat color escape. hex is "rrggbb" (no leading #).
function Util.Colorize(text, hex)
    return "|cff" .. (hex or "ffffff") .. tostring(text or "") .. "|r"
end

-- Print a chat message prefixed with the addon name in accent color.
function Util.Print(msg)
    print(Util.Colorize("Aegis", "1ED760") .. ": " .. tostring(msg or ""))
end
