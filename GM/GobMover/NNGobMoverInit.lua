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
local MAX_STEP_ABS = 1000000

local AIO = NobleNext.AIO
local function HasPermission(player)
    return NobleNext.HasStaffPermission(player)
end

-- Only coordinates/angles need Eluna. The native command owns RBAC, saving and group sync.
local function FindGoByGuid(player, guid)
    local id = tostring(guid)
    if type(guid) == "number" and guid == math.floor(guid) and guid > 0 and guid < 2^53 then
        id = string.format("%.0f", guid)
    end
    local map = player:GetMap()
    if map and #id <= 20 and id:match("^[1-9]%d*$") then
        local go = map:GetGameObjectBySpawnId(CreateUint64(id))
        if go and tostring(go:GetDBTableGUIDLow()) == id then return go end
    end
    player:SendBroadcastMessage(NobleNext.Color("error", "[GobMover]|r Объект не загружен на вашей карте. Выберите объект поблизости."))
end

--- Finite step: allow tiny values (e.g. 0.000001); reject nan/inf/huge.
local function ValidateStep(step)
    local n = tonumber(step)
    if n == nil then
        return nil, "step must be a number"
    end
    if n ~= n then
        return nil, "step is nan"
    end
    if n == math.huge or n == -math.huge then
        return nil, "step is inf"
    end
    if math.abs(n) > MAX_STEP_ABS then
        return nil, "step too large"
    end
    return n
end

local function Transform(player, verb, go, x, y, z)
    player:RunCommand(string.format("gobject %s %s %.9g %.9g %.9g", verb,
        tostring(go:GetDBTableGUIDLow()), x, y, z))
end

-- Player-relative unit vectors (TC: forward = cos(o), sin(o)).
local DIR_XY = {
    F  = { 1,  0 },
    FR = { 1, -1 },
    R  = { 0, -1 },
    BR = {-1, -1 },
    B  = {-1,  0 },
    BL = {-1,  1 },
    L  = { 0,  1 },
    FL = { 1,  1 },
}

local GobMoverHandlers = AIO.AddHandlers(HANDLER_NAME, {})

--- Relative nudge from player facing. dir: F/FR/R/BR/B/BL/L/FL/UP/DOWN
function GobMoverHandlers.Nudge(player, guid, dir, step)
    if not HasPermission(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end

    local vstep, err = ValidateStep(step)
    if not vstep then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r " .. tostring(err or "bad step")))
        return
    end
    dir = tostring(dir or ""):upper()
    local dx, dy, dz = 0, 0, 0
    if dir == "UP" then
        dz = vstep
    elseif dir == "DOWN" then
        dz = -vstep
    else
        local vec = DIR_XY[dir]
        if not vec then
            player:SendBroadcastMessage(NobleNext.Color("error",
                "[GobMover]|r Неизвестное направление: " .. tostring(dir)))
            return
        end
        local fx, fy = vec[1], vec[2]
        local len = math.sqrt(fx * fx + fy * fy)
        if len > 0 then
            fx, fy = fx / len, fy / len
        end
        local o = player:GetO()
        local cosO = math.cos(o)
        local sinO = math.sin(o)
        -- forward=(cos,sin), left=(-sin,cos), right=(sin,-cos); DIR_XY y=+1 = left
        dx = (fx * cosO - fy * sinO) * vstep
        dy = (fx * sinO + fy * cosO) * vstep
    end
    Transform(player, "move", go, go:GetX() + dx, go:GetY() + dy, go:GetZ() + dz)
end

local function Rotate(player, guid, yaw, pitch, roll)
    if not HasPermission(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    yaw, pitch, roll = ValidateStep(yaw), ValidateStep(pitch), ValidateStep(roll)
    if not yaw or not pitch or not roll then
        player:SendBroadcastMessage(NobleNext.Color("error", "[GobMover]|r Некорректный угол поворота."))
        return
    end
    local oz, oy, ox = go:GetLocalRotationAngles()
    Transform(player, "turn", go, oz + math.rad(yaw), oy + math.rad(pitch), ox + math.rad(roll))
end

function GobMoverHandlers.RotateYaw(player, guid, deltaDeg)
    Rotate(player, guid, deltaDeg, 0, 0)
end

function GobMoverHandlers.Tilt(player, guid, dPitchDeg, dRollDeg)
    Rotate(player, guid, 0, dPitchDeg or 0, dRollDeg or 0)
end

function GobMoverHandlers.GetMineList(player, allPhases, offset, limit)
    if not HasPermission(player) then return end
    allPhases = allPhases and true or false
    offset = tonumber(offset) or 0
    limit = tonumber(limit) or 100
    if limit < 1 then limit = 100 end
    if limit > 500 then limit = 500 end
    if offset < 0 then offset = 0 end

    local rows = {}
    if type(player.GetOwnedGameObjectList) == "function" then
        local ok, result = pcall(player.GetOwnedGameObjectList, player, allPhases, offset, limit)
        if ok and type(result) == "table" then
            rows = result
        else
            NobleNext.LogError("GobMover", "GetOwnedGameObjectList failed: " .. tostring(result))
            player:SendBroadcastMessage(NobleNext.Color("error",
                "[GobMover]|r Список личных GO недоступен (нужен обновлённый core)."))
            return
        end
    else
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r Список личных GO недоступен (нужен обновлённый core)."))
        return
    end

    -- Eluna uint64 is userdata, which the AIO serializer cannot encode.
    for _, row in ipairs(rows) do
        row.guid = tostring(row.guid)
        row.phaseId = tostring(row.phaseId or 0)
    end
    AIO.Handle(player, HANDLER_NAME, "MineList", rows)
end

NobleNext.RegisterModule("GobMover", { layer = "GM", aio = "NN_GobMover", core = "Custom/NobleNext/GobMover" })
NobleNext.Log("GobMover", "registered (C++ .movego + AIO Nudge/Tilt)")
