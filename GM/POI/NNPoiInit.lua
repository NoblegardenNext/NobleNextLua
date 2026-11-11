--[[ GM/POI/NNPoiInit.lua — bootstrap POI ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")

if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_POI_BOOTSTRAPPED then
    return package.loaded["GM.POI.NNPoiInit"] or {}
end
_G.NN_POI_BOOTSTRAPPED = true

local function OnLuaStateOpen()
    for _, player in ipairs(GetPlayersInWorld()) do
        if NobleNext.HasStaffPermission(player) then
            player:RunCommand("poi sync")
        end
    end
end

NobleNext.RegisterModule("POI", {
    layer = "GM",
    prefix = "RPC_POI_INFO",
    transport = "C++ Custom/Poi",
})
NobleNext.OnReload("POI", OnLuaStateOpen)
NobleNext.Log("POI", "module loaded")
