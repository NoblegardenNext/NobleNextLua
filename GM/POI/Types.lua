--[[ GM/POI/Types.lua — константы POI (C++ authoritative) ]]
local Types = {}

Types.ADDON_PREFIX = "RPC_POI_INFO"
Types.AIO_HANDLER = "NN_POI"
Types.AIO_CLIENT = "NN_POI_Client"

Types.Owner = {
    Player = 1,
    Organization = 2,
    System = 3,
    Npc = 4,
}

Types.OwnerLabels = {
    [1] = "Игрок",
    [2] = "Организация",
    [3] = "Система",
    [4] = "NPC",
}

Types.TypeHelp = {
    "1 — Информация",
    "2 — Сюжетная точка",
    "3 — Лагерь / здание",
    "4 — Башня / опасная зона",
}

function Types.IsValidPoiType(t)
    t = tonumber(t)
    return t and t >= 1 and t <= 4
end

function Types.DefaultIconForType(poiType)
    local t = tonumber(poiType) or 1
    if t == 2 then return "Story" end
    if t == 3 then return "Camp" end
    if t == 4 then return "Tower" end
    return "Misc"
end

return Types
