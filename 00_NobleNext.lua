--[[
    00_NobleNext.lua — единственная точка входа NobleNextLua для Eluna.

    Eluna auto-require'ит каждый *.lua по имени файла; shim'ы и Init в подпапках
    дублировали загрузку и ломали reload. Модули подключаются только отсюда.
]]

local rootPath = debug.getinfo(1, "S").source:match("^@(.+)[/\\][^/\\]+$") or "."
package.path = rootPath .. "/?.lua;"
    .. rootPath .. "/?/?.lua;"
    .. rootPath .. "/?/?/?.lua;"
    .. package.path

if _G.NN_ENTRY_LOADED then
    return
end
_G.NN_ENTRY_LOADED = true

local AIO = AIO or require("AIO")
if not AIO.IsMainState() then
    return
end

if GetStateMapId() ~= -1 then
    return
end

local NobleNext = require("NobleNext")

local MODULES = {
    "Core.NNCoreInit",
    "GM.NNGmInit",
    "Modules.NNModulesInit",
    "GM.Status.NNStatusInit",
    "GM.Army.NNArmyInit",
    "GM.Army.NNArmyClient",
    "GM.MasterPanel.NNMasterInit",
    "GM.MasterPanel.NNMasterClient",
    "GM.Waypoints.NNWaypointsInit",
    "GM.GobMover.NNGobMoverInit",
    "GM.GobMover.NNGobMoverClient",
    "GM.Pet.NNPetInit",
    "GM.Weather.NNWeatherInit",
    "GM.Time.NNTimeInit",
    "GM.GobTele.NNGobTeleInit",
    "GM.POI.NNPoiInit",
    "GM.POI.NNPoiClient",
    "Modules.Housing.NNHousingInit",
    "Modules.AutoMount.NNAutoMountInit",
}

_G.NN_BOOTSTRAP_ACTIVE = true
for i = 1, #MODULES do
    local mod = MODULES[i]
    package.loaded[mod] = nil
    local ok, err = pcall(require, mod)
    if not ok then
        NobleNext.LogError("Bootstrap", mod .. ": " .. tostring(err))
    end
end
_G.NN_BOOTSTRAP_ACTIVE = false

NobleNext.Log("Bootstrap", string.format("NobleNextLua ready (%d modules)", #MODULES))
