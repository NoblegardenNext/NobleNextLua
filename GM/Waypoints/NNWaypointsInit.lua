--[[ GM/Waypoints/NNWaypointsInit ]]

if not _G.NN_BOOTSTRAP_ACTIVE then return end

local AIO = AIO or require("AIO")
if not AIO.IsMainState() then
    return
end

local NobleNext = require("NobleNext")

if _G.NN_GM_WAYPOINTS_BOOTSTRAPPED then
    return package.loaded["GM.Waypoints.NNWaypointsInit"] or {}
end
_G.NN_GM_WAYPOINTS_BOOTSTRAPPED = true

local HANDLER_NAME = "NN_Waypoints"

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local WALK_AURA       = 88032   -- legacy aura, optional
local MIN_DISTANCE    = 3
local MIN_WAIT_TIME   = 0.5
local MAX_WAYPOINTS   = 50

local POINT_MOVE = 1
local POINT_WAIT = 2
local POINT_WALK = 3

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------
local NPCWaypoints = {}   -- creatureGuidLow -> { points = {...} }
local ActiveTimers = {}   -- timerId -> { guid, entry, map, nextOrder }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function Distance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

local function CanControl(player, creature)
    return NobleNext.CanControlCreature(player, creature)
end

local function GetTargetCreature(player)
    local selection = player:GetSelectedUnit()
    if not selection then return nil end
    return selection:ToCreature()
end

local function StopCycle(creature)
    if not creature then return end
    local lowGuid = creature:GetGUIDLow()

    -- remove all timers associated with this creature
    local toRemove = {}
    for timerId, data in pairs(ActiveTimers) do
        if data.guid == lowGuid then
            table.insert(toRemove, timerId)
        end
    end
    for _, timerId in ipairs(toRemove) do
        RemoveEventById(timerId)
        ActiveTimers[timerId] = nil
    end

    creature:EmoteState(0)
end

-- ---------------------------------------------------------------------------
-- Cycle logic
-- ---------------------------------------------------------------------------
local function GoToNextWaypoint(eventId, delay, repeats)
    local data = ActiveTimers[eventId]
    if not data then return end

    -- clear current timer entry
    ActiveTimers[eventId] = nil

    local map = GetMapById(data.map)
    if not map then return end

    local creature = NobleNext.SafeGetCreature({ guid = data.guid, entry = data.entry }, map)
    if not creature or not creature:IsAlive() or not creature:IsInWorld() then
        return
    end

    creature:SetWalk(true)
    if creature:HasAura(WALK_AURA) then
        creature:RemoveAura(WALK_AURA)
    end

    local waypoints = NPCWaypoints[data.guid]
    if not waypoints or #waypoints == 0 then
        return
    end

    local point = waypoints[data.nextOrder]
    if not point then
        return
    end

    local nextOrder = data.nextOrder + 1
    if nextOrder > #waypoints then
        nextOrder = 1
    end

    local nextDelay = 100

    if point.c_type == POINT_MOVE or point.c_type == POINT_WALK then
        local speed = (point.c_type == POINT_WALK) and 0.5 or 1.0
        creature:SetSpeed(0, speed)
        creature:EmoteState(0)
        local dist = Distance2D(creature:GetX(), creature:GetY(), point.x, point.y)
        nextDelay = math.max((dist / creature:GetSpeed(0)) * 1000, 100)
        creature:MoveTo(1000, point.x, point.y, point.z)
    elseif point.c_type == POINT_WAIT then
        creature:EmoteState(point.emoteId or 0)
        nextDelay = math.max(point.waitTime * 1000, 100)
    end

    local nextTimerId = CreateLuaEvent(GoToNextWaypoint, nextDelay, 1)
    ActiveTimers[nextTimerId] = {
        guid = data.guid,
        entry = data.entry,
        map = data.map,
        nextOrder = nextOrder,
    }
end

-- ---------------------------------------------------------------------------
-- Waypoint management
-- ---------------------------------------------------------------------------
local function AddWaypoint(player, c_type)
    local creature = GetTargetCreature(player)
    if not creature or not CanControl(player, creature) then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Waypoints]|r Не выбрано подходящее существо."))
        return false
    end

    local lowGuid = creature:GetGUIDLow()
    local px, py, pz = player:GetLocation()
    local points = NPCWaypoints[lowGuid]

    if points and #points >= MAX_WAYPOINTS then
        player:SendBroadcastMessage(NobleNext.Color("warning", "[Waypoints]|r Достигнут лимит точек (" .. MAX_WAYPOINTS .. ")."))
        return false
    end

    if points and #points > 0 then
        local last = points[#points]
        if last.c_type ~= POINT_WAIT and Distance2D(last.x, last.y, px, py) < MIN_DISTANCE then
            player:SendBroadcastMessage(NobleNext.Color("warning", "[Waypoints]|r Расстояние от предыдущей точки меньше " .. MIN_DISTANCE .. " ярдов."))
            return false
        end
    end

    if not points then
        points = {}
        NPCWaypoints[lowGuid] = points
    end

    table.insert(points, { c_type = c_type, x = px, y = py, z = pz })

    local typeName = (c_type == POINT_WALK) and "медленный шаг" or "передвижение"
    player:SendBroadcastMessage(NobleNext.Color("success", "[Waypoints]|r " .. creature:GetName() .. " — точка " .. #points .. " (" .. typeName .. ")."))
    return true
end

local function AddWaitPoint(player, waitTime, emoteId)
    local creature = GetTargetCreature(player)
    if not creature or not CanControl(player, creature) then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Waypoints]|r Не выбрано подходящее существо."))
        return false
    end

    waitTime = tonumber(waitTime) or 0
    if waitTime < MIN_WAIT_TIME then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Waypoints]|r Время ожидания не может быть меньше " .. MIN_WAIT_TIME .. " сек."))
        return false
    end

    local lowGuid = creature:GetGUIDLow()
    local points = NPCWaypoints[lowGuid]
    if not points then
        points = {}
        NPCWaypoints[lowGuid] = points
    end

    table.insert(points, { c_type = POINT_WAIT, waitTime = waitTime, emoteId = tonumber(emoteId) or 0 })
    player:SendBroadcastMessage(NobleNext.Color("success", "[Waypoints]|r " .. creature:GetName() .. " — точка ожидания " .. #points .. " (" .. waitTime .. " сек)."))
    return true
end

local function ClearWaypoints(player)
    local creature = GetTargetCreature(player)
    if not creature or not CanControl(player, creature) then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Waypoints]|r Не выбрано подходящее существо."))
        return false
    end

    local lowGuid = creature:GetGUIDLow()
    StopCycle(creature)
    NPCWaypoints[lowGuid] = nil
    player:SendBroadcastMessage(NobleNext.Color("info", "[Waypoints]|r Маршрут " .. creature:GetName() .. " очищен."))
    return true
end

local function StartCycle(player)
    local creature = GetTargetCreature(player)
    if not creature or not CanControl(player, creature) then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Waypoints]|r Не выбрано подходящее существо."))
        return false
    end

    local lowGuid = creature:GetGUIDLow()
    local points = NPCWaypoints[lowGuid]
    if not points or #points < 2 then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Waypoints]|r Нужно минимум 2 точки."))
        return false
    end

    StopCycle(creature)

    creature:RemoveAura(WALK_AURA)
    creature:SetWalk(true)

    local first = points[1]
    local timerDelay = 100

    if first.c_type == POINT_MOVE or first.c_type == POINT_WALK then
        local speed = (first.c_type == POINT_WALK) and 0.5 or 1.0
        creature:SetSpeed(0, speed)
        local dist = Distance2D(creature:GetX(), creature:GetY(), first.x, first.y)
        timerDelay = math.max((dist / creature:GetSpeed(0)) * 1000, 100)
        creature:MoveTo(1000, first.x, first.y, first.z)
    elseif first.c_type == POINT_WAIT then
        creature:EmoteState(first.emoteId or 0)
        timerDelay = math.max(first.waitTime * 1000, 100)
    end

    local timerId = CreateLuaEvent(GoToNextWaypoint, timerDelay, 1)
    ActiveTimers[timerId] = {
        guid = lowGuid,
        entry = creature:GetEntry(),
        map = player:GetMapId(),
        nextOrder = 2,
    }

    player:SendBroadcastMessage(NobleNext.Color("success", "[Waypoints]|r Маршрут для " .. creature:GetName() .. " запущен."))
    NobleNext.LogAudit("Waypoints", "start", player,
        string.format("npc=%s entry=%d points=%d", creature:GetName(), creature:GetEntry(), #points))
    return true
end

local function SetStandState(player, state)
    local creature = GetTargetCreature(player)
    if not creature or not CanControl(player, creature) then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Waypoints]|r Не выбрано подходящее существо."))
        return false
    end

    state = tonumber(state) or 0
    creature:SetStandState(state)
    player:SendBroadcastMessage(NobleNext.Color("info", "[Waypoints]|r Стойка " .. state .. " установлена."))
    return true
end

-- ---------------------------------------------------------------------------
-- AIO handlers
-- ---------------------------------------------------------------------------
local WaypointHandlers = AIO.AddHandlers(HANDLER_NAME, {})

function WaypointHandlers.AddMove(player)
    AddWaypoint(player, POINT_MOVE)
end

function WaypointHandlers.AddWalk(player)
    AddWaypoint(player, POINT_WALK)
end

function WaypointHandlers.AddWait(player, waitTime, emoteId)
    AddWaitPoint(player, waitTime, emoteId)
end

function WaypointHandlers.Clear(player)
    ClearWaypoints(player)
end

function WaypointHandlers.Go(player)
    StartCycle(player)
end

function WaypointHandlers.Stop(player)
    local creature = GetTargetCreature(player)
    if creature then
        StopCycle(creature)
        player:SendBroadcastMessage(NobleNext.Color("info", "[Waypoints]|r Цикл остановлен."))
    end
end

function WaypointHandlers.SetStandState(player, state)
    SetStandState(player, state)
end

NobleNext.RegisterModule("Waypoints", { layer = "GM", aio = "NN_Waypoints", core = "Custom/NobleNext/Waypoints" })
NobleNext.Log("Waypoints", "registered (C++ commands + AIO)")
