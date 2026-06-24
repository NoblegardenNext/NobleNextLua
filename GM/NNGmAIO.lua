--[[ GM/NNGmAIO.lua — fallback AIO → RunCommand (клиент использует whisper) ]]
local NobleNext = require("NobleNext")

local GmAIO = {}

function GmAIO.Register()
    if GmAIO._registered then return end
    if not NobleNext.AIO or not NobleNext.AIO.IsMainState or not NobleNext.AIO.IsMainState() then
        return
    end

    GmAIO._registered = true
    local CoreHandlers = NobleNext.AIO.AddHandlers("NN_Core", {})

    function CoreHandlers.RunGmCommand(player, command)
        if not NobleNext.HasStaffPermission(player) then
            NobleNext.LogWarn("GM", "denied: " .. NobleNext.FormatPlayer(player))
            return
        end

        command = NobleNext.Trim(command):gsub("^[%./]+", "")
        if command == "" or #command > 512 then return end
        command = "." .. command

        local ok, err = pcall(function()
            player:RunCommand(command)
        end)

        if not ok then
            NobleNext.LogError("GM", "RunCommand failed: " .. tostring(err) .. " cmd=" .. command)
            player:SendBroadcastMessage(NobleNext.Color("error", "[NobleNext]|r Команда не выполнена."))
        else
            NobleNext.LogAudit("GM", "run", player, command)
        end
    end
end

return GmAIO
