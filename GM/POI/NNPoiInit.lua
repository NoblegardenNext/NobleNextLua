--[[ GM/POI/NNPoiInit.lua — bootstrap POI ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
local Types = require("GM.POI.Types")
local PoiAIO = require("GM.POI.NNPoiAIO")

if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_POI_BOOTSTRAPPED then
    return package.loaded["GM.POI.NNPoiInit"] or {}
end
_G.NN_POI_BOOTSTRAPPED = true

PoiAIO.Register()

local function OnLuaStateOpen()
    local players = GetPlayersInWorld()
    for i = 1, #players do
        players[i]:RunCommand(".poi sync")
    end
    NobleNext.Log("POI", string.format("reload — .poi sync для %d игроков (C++ RPC_POI_INFO)", #players))
end

NobleNext.RegisterModule("POI", {
    layer = "GM",
    aio = Types.AIO_HANDLER,
    prefix = Types.ADDON_PREFIX,
    transport = "C++ Custom/Poi",
})
NobleNext.OnReload("POI", OnLuaStateOpen)
NobleNext.Log("POI", "module loaded")

return { Types = Types }
