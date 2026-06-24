--[[ GM/GobMover/NNGobMoverInit.lua — редактирование GameObject (C++: .movego) ]]

if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_GM_GOBMOVER_BOOTSTRAPPED then
    return package.loaded["GM.GobMover.NNGobMoverInit"] or {}
end
_G.NN_GM_GOBMOVER_BOOTSTRAPPED = true

local HANDLER_NAME = "NN_GobMover"
local COOLDOWN_MS = 300
local SEARCH_RADIUS = 20

local AIO = NobleNext.AIO
local playersCooldowns = {}

local function IsReady(player)
    local name = player:GetName()
    local now = GetCurrTime()
    if not playersCooldowns[name] or (now - playersCooldowns[name]) >= COOLDOWN_MS then
        playersCooldowns[name] = now
        return true
    end
    return false
end

local function HasPermission(player)
    return NobleNext.HasStaffPermission(player)
end

local function FindGoByGuid(player, guid)
    local gos = player:GetGameObjectsInRange(SEARCH_RADIUS)
    if not gos then return nil end
    for _, go in ipairs(gos) do
        if go:GetDBTableGUIDLow() == guid then
            return go
        end
    end
    return nil
end

local GobMoverHandlers = AIO.AddHandlers(HANDLER_NAME, {})

function GobMoverHandlers.Open(player)
    if not HasPermission(player) then return end
    local go = player:GetNearestGameObject(SEARCH_RADIUS)
    if not go then
        player:SendBroadcastMessage(NobleNext.Color("error", "[GobMover]|r GO не найден рядом."))
        return
    end
    NobleNext.GobMoverSetTarget(player, go:GetDBTableGUIDLow(), go:GetName() or "")
end

function GobMoverHandlers.Move(player, guid, dx, dy, dz)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then
        player:SendBroadcastMessage(NobleNext.Color("error", "[GobMover]|r GO не найден."))
        return
    end
    dx = tonumber(dx) or 0
    dy = tonumber(dy) or 0
    dz = tonumber(dz) or 0
    go:ChangePosition(go:GetX() + dx, go:GetY() + dy, go:GetZ() + dz, go:GetO())
    NobleNext.LogAudit("GobMover", "move", player,
        string.format("guid=%s delta=%.3f,%.3f,%.3f", tostring(guid), dx, dy, dz))
end

function GobMoverHandlers.RotateYaw(player, guid, deltaDeg)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    local delta = math.rad(tonumber(deltaDeg) or 0)
    go:ChangePosition(go:GetX(), go:GetY(), go:GetZ(), go:GetO() + delta)
    NobleNext.LogAudit("GobMover", "rotate", player,
        string.format("guid=%s deltaDeg=%s", tostring(guid), tostring(deltaDeg)))
end

function GobMoverHandlers.ResetRotation(player, guid)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    go:Turn(0, 0, 0)
end

function GobMoverHandlers.Scale(player, guid, scale)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    scale = tonumber(scale) or 1
    if scale <= 0 then scale = 0.001 end
    go:SetScale(scale)
    NobleNext.LogAudit("GobMover", "scale", player,
        string.format("guid=%s scale=%.3f", tostring(guid), scale))
end

NobleNext.RegisterModule("GobMover", { layer = "GM", aio = "NN_GobMover", core = "Custom/NobleNext/GobMover" })
NobleNext.Log("GobMover", "registered (C++ .movego + AIO)")
