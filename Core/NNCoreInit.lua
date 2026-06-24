--[[ Core/NNCoreInit.lua ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
if NobleNext.ScheduleBatch then
    return { bootstrapped = true }
end

local Batch = require("Core.Batch")
local DB = require("Core.DB")
local CoreAIO = require("Core.NNCoreAIO")

NobleNext.ScheduleBatch = Batch.ScheduleBatch
NobleNext.Db = DB

function NobleNext.SafeCall(label, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        NobleNext.LogError(label or "SafeCall", tostring(result))
        return false, result
    end
    return true, result
end

function NobleNext.RequireStaff(player, module)
    if NobleNext.HasStaffPermission(player) then return true end
    NobleNext.LogWarn(module or "Core", "denied: " .. NobleNext.FormatPlayer(player))
    return false
end

function NobleNext.SendClient(player, handler, method, ...)
    return CoreAIO.SendClient(player, handler, method, ...)
end

NobleNext.Log("Core", "services loaded (Batch, DB, AIO)")

return { bootstrapped = true }
