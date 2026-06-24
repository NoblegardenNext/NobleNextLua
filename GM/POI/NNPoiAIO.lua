--[[ GM/POI/NNPoiAIO.lua — read-only AIO (мутации через C++ .poi) ]]
local NobleNext = require("NobleNext")
local Types = require("GM.POI.Types")
local Store = require("GM.POI.Store")
local Client = require("GM.POI.Client")

local AIO = AIO or require("AIO")
local PoiAIO = {}

function PoiAIO.Register()
    if PoiAIO._handlers then
        return PoiAIO._handlers
    end

    local handlers = AIO.AddHandlers(Types.AIO_HANDLER, {})
    PoiAIO._handlers = handlers

    function handlers.GetList(player)
        if not NobleNext.RequireStaff(player, "POI") then return end
        Client.PushList(player, Store.FetchListRows())
    end

    function handlers.SearchList(player, filter)
        if not NobleNext.RequireStaff(player, "POI") then return end
        Client.PushList(player, Store.SearchListRows(filter))
    end

    function handlers.List(player)
        if not NobleNext.RequireStaff(player, "POI") then return end
        local rows = Store.FetchListRows()
        if #rows == 0 then
            player:SendBroadcastMessage(NobleNext.Color("info", "[POI]|r Нет точек."))
            return
        end
        player:SendBroadcastMessage(NobleNext.Color("gold", "[POI]|r Список:"))
        for _, row in ipairs(rows) do
            local typeLabel = Types.TypeHelp[row.type] or ("тип " .. tostring(row.type))
            player:SendBroadcastMessage(string.format("  #%d — %s (map %d, %s, владелец: %s)",
                row.id, row.name, row.map, typeLabel, row.owner or "?"))
        end
    end

    return handlers
end

return PoiAIO
