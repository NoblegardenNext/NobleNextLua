--[[ GM/POI/Client.lua — AIO уведомления клиенту (опционально) ]]
local Types = require("GM.POI.Types")

local Client = {}

function Client.PushList(player, rows)
    if not player then return end
    AIO.Handle(player, Types.AIO_CLIENT, "SetList", rows or {})
end

function Client.Notice(player, level, message)
    if not player then return end
    AIO.Handle(player, Types.AIO_CLIENT, "Notice", level or "info", message or "")
end

return Client
