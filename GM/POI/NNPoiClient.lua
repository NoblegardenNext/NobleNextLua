--[[ GM/POI/NNPoiClient.lua — AIO client stub ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end
if package.loaded["GM.POI.NNPoiClient"] then return end

local AIO = AIO or require("AIO")
if AIO.AddAddon() then
    return
end

local PoiClientHandlers = AIO.AddHandlers("NN_POI_Client", {})
_G.NobleNextPoi = _G.NobleNextPoi or {}

function PoiClientHandlers.SetList(player, rows)
    if _G.NobleNextPoi.OnSetList then
        _G.NobleNextPoi.OnSetList(rows)
    end
end

function PoiClientHandlers.Notice(player, level, message)
    if _G.NobleNextPoi.OnNotice then
        _G.NobleNextPoi.OnNotice(level, message)
    end
end
