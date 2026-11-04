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
-- Short per-player debounce (ms). 0 = no shared cooldown (sequential AIO ops must not drop).
local COOLDOWN_MS = 0
local SEARCH_RADIUS = 50
local FIND_BY_GUID_RADIUS = 100
local MAX_STEP_ABS = 1000000

local AIO = NobleNext.AIO
local playersCooldowns = {}

local function IsReady(player)
    if COOLDOWN_MS <= 0 then
        return true
    end
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

local function GuidEquals(a, b)
    local na = tonumber(a)
    local nb = tonumber(b)
    if na and nb then
        return na == nb
    end
    return tostring(a) == tostring(b)
end

local function GetDistance3(player, go)
    local dx = player:GetX() - go:GetX()
    local dy = player:GetY() - go:GetY()
    local dz = player:GetZ() - go:GetZ()
    return math.sqrt(dx * dx + dy * dy + dz * dz)
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

local function GetGoEuler(go)
    if go.GetLocalRotationAngles then
        local oz, oy, ox = go:GetLocalRotationAngles()
        return tonumber(oz) or go:GetO() or 0, tonumber(oy) or 0, tonumber(ox) or 0
    end
    return go:GetO() or 0, 0, 0
end

--- Spawn-store lookup (no phase filter). Requires Map:GetGameObjectBySpawnId (Eluna).
local function FindGoBySpawnId(player, guid)
    local want = tonumber(guid)
    if not want or want <= 0 then
        return nil
    end
    local map = player:GetMap()
    if map and map.GetGameObjectBySpawnId then
        local go = map:GetGameObjectBySpawnId(want)
        if go then
            return go
        end
    end
    return nil
end

--- Nearest live GO in range (Eluna grid; phase-filtered). Prefer .movego / spawn-store Select.
local function FindNearestGo(player, radius)
    radius = radius or SEARCH_RADIUS
    local gos = player:GetGameObjectsInRange(radius)
    if not gos then
        return nil
    end
    local nearest, nearestDist
    for _, go in ipairs(gos) do
        if go then
            local dist = GetDistance3(player, go)
            if dist <= radius and (not nearestDist or dist < nearestDist) then
                nearest = go
                nearestDist = dist
            end
        end
    end
    return nearest
end

local function FindGoByGuid(player, guid)
    local want = tonumber(guid) or guid
    if want == nil or want == 0 or want == "" then
        return nil
    end
    local bySpawn = FindGoBySpawnId(player, want)
    if bySpawn then
        return bySpawn
    end
    local gos = player:GetGameObjectsInRange(FIND_BY_GUID_RADIUS)
    if not gos then
        return nil
    end
    for _, go in ipairs(gos) do
        if go and GuidEquals(go:GetDBTableGUIDLow(), want) then
            return go
        end
    end
    return nil
end

local function CanMutateGo(player, go)
    if go and go.CanEditForRoleplay and go:CanEditForRoleplay(player) then
        return true
    end
    player:SendBroadcastMessage(NobleNext.Color("error",
        "[GobMover]|r Мутация запрещена: требуется текущая logical RP phase и роль editor/manager/owner."))
    return false
end

local function HintSelectMessage()
    return "[GobMover]|r Live GO не найден (радиус "
        .. tostring(SEARCH_RADIUS)
        .. "). Housing/phase: .gob near → клик [Sel]/[Move] или .movego <guid>."
end

-- Silent relative-pose sync for soft groups (errors ignored).
-- Player:RunCommand → ChatHandler::_ParseCommands (без ведущей точки).
local function CaptureGroupSilent(player, guid)
    pcall(function()
        player:RunCommand("gobject group capture " .. tostring(guid) .. " silent")
    end)
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

function GobMoverHandlers.Open(player)
    if not HasPermission(player) then return end
    -- C++ .movego: IgnorePhases + радиус 50 (надёжнее Eluna grid на housing).
    local ran = pcall(function()
        player:RunCommand("movego")
    end)
    if ran then
        return
    end
    -- Fallback без C++ команды
    local go = FindNearestGo(player, SEARCH_RADIUS)
    if not go then
        player:SendBroadcastMessage(NobleNext.Color("error", HintSelectMessage()))
        return
    end
    NobleNext.GobMoverSetTarget(player, go:GetDBTableGUIDLow(), go:GetName() or "")
end

function GobMoverHandlers.Select(player, guid)
    if not HasPermission(player) then return end
    local want = tonumber(guid)
    if not want or want <= 0 then
        player:SendBroadcastMessage(NobleNext.Color("error", "[GobMover]|r Укажите DB GUID (spawnId)."))
        return
    end
    local ran = pcall(function()
        player:RunCommand("movego " .. tostring(want))
    end)
    if ran then
        return
    end
    local go = FindGoByGuid(player, want)
    if not go then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r GO GUID " .. tostring(want)
            .. " не загружен на карте. Подойдите ближе (грид) или проверьте .gob near."))
        return
    end
    NobleNext.GobMoverSetTarget(player, go:GetDBTableGUIDLow(), go:GetName() or "")
end

function GobMoverHandlers.Move(player, guid, dx, dy, dz)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r GO не найден в радиусе " .. tostring(FIND_BY_GUID_RADIUS)
            .. ". Подойдите ближе к объекту."))
        return
    end
    local vdx, errDx = ValidateStep(dx)
    local vdy, errDy = ValidateStep(dy)
    local vdz, errDz = ValidateStep(dz)
    if not vdx or not vdy or not vdz then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r Некорректный delta: " .. tostring(errDx or errDy or errDz)))
        return
    end
    if not CanMutateGo(player, go) then return end
    go:ChangePosition(go:GetX() + vdx, go:GetY() + vdy, go:GetZ() + vdz, go:GetO())
    CaptureGroupSilent(player, guid)
    NobleNext.LogAudit("GobMover", "move", player,
        string.format("guid=%s delta=%.6f,%.6f,%.6f", tostring(guid), vdx, vdy, vdz))
end

--- Relative nudge from player facing. dir: F/FR/R/BR/B/BL/L/FL/UP/DOWN
function GobMoverHandlers.Nudge(player, guid, dir, step)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r GO не найден в радиусе " .. tostring(FIND_BY_GUID_RADIUS)
            .. ". Подойдите ближе к объекту."))
        return
    end
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
    if not CanMutateGo(player, go) then return end
    go:ChangePosition(go:GetX() + dx, go:GetY() + dy, go:GetZ() + dz, go:GetO())
    CaptureGroupSilent(player, guid)
    NobleNext.LogAudit("GobMover", "nudge", player,
        string.format("guid=%s dir=%s step=%.6f", tostring(guid), dir, vstep))
end

function GobMoverHandlers.RotateYaw(player, guid, deltaDeg)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    local deltaDegN, err = ValidateStep(deltaDeg)
    if not deltaDegN then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r " .. tostring(err or "bad yaw")))
        return
    end
    local delta = math.rad(deltaDegN)
    if not CanMutateGo(player, go) then return end
    -- Prefer full Euler via GetLocalRotationAngles; fallback GetGoEuler → Turn(newO,0,0).
    local oz, oy, ox = GetGoEuler(go)
    go:Turn(oz + delta, oy, ox)
    CaptureGroupSilent(player, guid)
    NobleNext.LogAudit("GobMover", "rotate", player,
        string.format("guid=%s deltaDeg=%s", tostring(guid), tostring(deltaDegN)))
end

function GobMoverHandlers.Tilt(player, guid, dPitchDeg, dRollDeg)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    local dPitch, errP = ValidateStep(dPitchDeg or 0)
    local dRoll, errR = ValidateStep(dRollDeg or 0)
    if not dPitch or not dRoll then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r " .. tostring(errP or errR or "bad tilt")))
        return
    end
    if not CanMutateGo(player, go) then return end
    local oz, oy, ox = GetGoEuler(go)
    go:Turn(oz, oy + math.rad(dPitch), ox + math.rad(dRoll))
    CaptureGroupSilent(player, guid)
    NobleNext.LogAudit("GobMover", "tilt", player,
        string.format("guid=%s dPitch=%.6f dRoll=%.6f", tostring(guid), dPitch, dRoll))
end

function GobMoverHandlers.ResetRotation(player, guid)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    if not CanMutateGo(player, go) then return end
    go:Turn(0, 0, 0)
    CaptureGroupSilent(player, guid)
end

function GobMoverHandlers.Scale(player, guid, scale)
    if not HasPermission(player) or not IsReady(player) then return end
    local go = FindGoByGuid(player, guid)
    if not go then return end
    local vscale, err = ValidateStep(scale)
    if not vscale then
        player:SendBroadcastMessage(NobleNext.Color("error",
            "[GobMover]|r " .. tostring(err or "bad scale")))
        return
    end
    if vscale <= 0 then vscale = 0.001 end
    if not CanMutateGo(player, go) then return end
    -- SetScale only changes runtime fields; the native command also saves spawn size.
    local spawnId = go:GetDBTableGUIDLow()
    if spawnId and spawnId > 0 then
        if not player:RunCommand(string.format("gobject set scale %d %.9g", spawnId, vscale)) then
            return
        end
    else
        go:SetScale(vscale)
    end
    NobleNext.LogAudit("GobMover", "scale", player,
        string.format("guid=%s scale=%.6f", tostring(guid), vscale))
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

    AIO.Handle(player, HANDLER_NAME, "MineList", rows)
end

NobleNext.RegisterModule("GobMover", { layer = "GM", aio = "NN_GobMover", core = "Custom/NobleNext/GobMover" })
NobleNext.Log("GobMover", "registered (C++ .movego + AIO Nudge/Tilt)")
