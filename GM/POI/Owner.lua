--[[ GM/POI/Owner.lua — владелец POI (display helpers) ]]
local Types = require("GM.POI.Types")
local DB = require("Core.DB")

local Owner = {}

function Owner.ResolveDisplayLabel(ownerType, ownerGuid, ownerName, fallbackPlayerName)
    ownerType = tonumber(ownerType) or Types.Owner.Player
    ownerName = ownerName or ""

    if ownerType == Types.Owner.Organization then
        return ownerName ~= "" and ownerName or "Организация"
    end
    if ownerType == Types.Owner.System then
        return ownerName ~= "" and ownerName or "Система"
    end
    if ownerType == Types.Owner.Npc then
        return ownerName ~= "" and ownerName or "NPC"
    end

    if ownerName ~= "" then return ownerName end

    ownerGuid = DB.ToNumber(ownerGuid)
    if ownerGuid > 0 then
        local q = CharDBQuery(string.format(
            "SELECT name FROM characters WHERE guid = %d LIMIT 1", ownerGuid))
        if q then
            return q:GetString(0) or "?"
        end
    end

    return fallbackPlayerName or "?"
end

return Owner
