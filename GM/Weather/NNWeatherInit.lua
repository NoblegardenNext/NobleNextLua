--[[ GM/Weather/NNWeatherInit.lua — AIO → C++ .weather ]]

if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_GM_WEATHER_BOOTSTRAPPED then
    return package.loaded["GM.Weather.NNWeatherInit"] or {}
end
_G.NN_GM_WEATHER_BOOTSTRAPPED = true

local AIO = NobleNext.AIO
local HANDLER_NAME = "NN_Weather"

local WeatherHandlers = AIO.AddHandlers(HANDLER_NAME, {})

local function IsGmOrDm(player)
    return NobleNext.HasStaffPermission(player)
end

function WeatherHandlers.SetWeather(player, index, strength, targetMode)
    if not IsGmOrDm(player) then return end
    index = tonumber(index) or 1
    strength = tonumber(strength) or 5
    targetMode = tonumber(targetMode) or 0

    if targetMode == 1 then
        local selection = player:GetSelectedUnit()
        local target = selection and selection:ToPlayer()
        if not target then
            player:SendBroadcastMessage(NobleNext.Color("error", "[Weather]|r Не выбран игрок."))
            return
        end
        target:RunCommand(string.format(".weather %d %d %s", index, strength, target:GetName()))
    else
        player:RunCommand(string.format(".weather %d %d", index, strength))
    end
end

function WeatherHandlers.Cancel(player)
    if not player then return end
    player:RunCommand(".weather cancel")
end

NobleNext.RegisterModule("Weather", { layer = "GM", aio = "NN_Weather", core = "Custom/NobleNext/Weather" })
NobleNext.Log("Weather", "registered (C++ authoritative)")
