--[[
    NobleNext — shared core для серверных скриптов NobleNextLua.

    Предоставляет:
      • единую проверку прав (GM/DM)
      • безопасный поиск creature
      • утилиты расстояния, логирования, цвета
      • хелперы для регистрации событий с учётом WORLD/MAP state

    Использование:
        local NobleNext = require("NobleNext")

    Точка входа Eluna: 00_NobleNext.lua (не регистрируйте модули отсюда).
]]

if package.loaded["NobleNext"] then
    return package.loaded["NobleNext"]
end

local NobleNext = {}
package.loaded["NobleNext"] = NobleNext

-- Подпапки NobleNextLua (Core/, GM/, Modules/, …)
local scriptPath = debug.getinfo(1, "S").source:match("^@(.+)[/\\][^/\\]+$") or "."
package.path = scriptPath .. "/?.lua;"
    .. scriptPath .. "/?/?.lua;"
    .. scriptPath .. "/?/?/?.lua;"
    .. package.path

NobleNext.VERSION = "1.3.0"
NobleNext.DM_PHASE = 1024

-- Уровни: DEBUG=1, INFO=2, WARN=3, ERROR=4
-- Переопределение: _G.NOBLENEXT_LOG_LEVEL = 1 в lua_scripts/extensions или worldserver env
NobleNext.LOG = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
NobleNext.logLevel = tonumber(_G.NOBLENEXT_LOG_LEVEL) or NobleNext.LOG.INFO

-- Eluna event ids (см. Eluna RegisterPlayerEvent / RegisterServerEvent)
NobleNext.Events = {
    PLAYER_LOGOUT          = 4,
    PLAYER_SPELL_CAST      = 5,
    PLAYER_UPDATE_ZONE     = 27,
    PLAYER_COMMAND         = 42,
    SERVER_WEATHER         = 25,
    SERVER_LUA_STATE_OPEN  = 33,
    CREATURE_JUST_SUMMONED = 22,
}

-- ---------------------------------------------------------------------------
-- AIO
-- ---------------------------------------------------------------------------
NobleNext.AIO = AIO or require("AIO")

-- C++ .movego → AIO (Custom/NobleNext/GobMover)
function NobleNext.GobMoverSetTarget(player, guid, name)
    if not player or not NobleNext.AIO then return end
    NobleNext.AIO.Handle(player, "NN_GobMover", "SetTarget", guid or 0, name or "")
end

-- ---------------------------------------------------------------------------
-- State helpers
-- ---------------------------------------------------------------------------
function NobleNext.IsMainState()
    return GetStateMapId() == -1
end

function NobleNext.IsMapState()
    return GetStateMapId() > 0
end

-- ---------------------------------------------------------------------------
-- Permission helpers
-- ---------------------------------------------------------------------------
-- DM в creative-фазе: GM rank >= 1 и phase 1024 (замена GetDmLevel из legacy).
function NobleNext.IsCreativeDm(player)
    if not player then return false end
    return player:GetGMRank() >= 1 and player:GetPhaseMask() == NobleNext.DM_PHASE
end

function NobleNext.HasStaffPermission(player)
    if not player then return false end
    if player:GetGMRank() > 0 then return true end
    return NobleNext.IsCreativeDm(player)
end

function NobleNext.CanControlCreature(player, creature)
    if not player or not creature then return false end
    if creature:GetOwner() == player then return true end
    if player:GetGMRank() > 0 then return true end
    if NobleNext.IsCreativeDm(player) then return true end
    return false
end

function NobleNext.HasPermission(player, requireDm)
    if not player then return false end
    if player:GetGMRank() > 0 then return true end
    if requireDm ~= false and NobleNext.IsCreativeDm(player) then return true end
    return false
end

function NobleNext.IsDmOrBetter(player)
    return NobleNext.HasStaffPermission(player)
end

-- ---------------------------------------------------------------------------
-- Creature / object helpers
-- ---------------------------------------------------------------------------
function NobleNext.GetTargetCreature(player)
    if not player then return nil end
    local selection = player:GetSelectedUnit()
    if not selection then return nil end
    return selection:ToCreature()
end

function NobleNext.SafeGetCreature(guid, entry, map)
    if not guid or not entry then return nil end

    -- Если передан map-объект, ищем через него (3-arg GetUnitGUID)
    local mapObj = map
    if type(map) == "number" then
        mapObj = GetMapById(map)
    end
    if not mapObj then return nil end

    local creatureGUID = GetUnitGUID(guid, entry, mapObj:GetId())
    if not creatureGUID then return nil end
    return mapObj:GetWorldObject(creatureGUID)
end

-- ---------------------------------------------------------------------------
-- Distance helpers
-- ---------------------------------------------------------------------------
function NobleNext.Distance2D(x1, y1, x2, y2)
    local dx = x1 - x2
    local dy = y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function NobleNext.Distance3D(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------
local function ShouldLog(level)
    return level >= NobleNext.logLevel
end

local function EmitLog(tag, module, details)
    print(string.format("[NobleNext%s] %s | %s", tag, module or "?", details or ""))
end

function NobleNext.Log(module, details)
    if ShouldLog(NobleNext.LOG.INFO) then
        EmitLog("", module, details)
    end
end

function NobleNext.LogDebug(module, details)
    if ShouldLog(NobleNext.LOG.DEBUG) then
        EmitLog("|DEBUG", module, details)
    end
end

function NobleNext.LogWarn(module, details)
    if ShouldLog(NobleNext.LOG.WARN) then
        EmitLog("|WARN", module, details)
    end
end

function NobleNext.LogError(module, details)
    if ShouldLog(NobleNext.LOG.ERROR) then
        EmitLog("|ERROR", module, details)
    end
end

function NobleNext.AppendFile(filename, text)
    local function tryOpen(path)
        local file = io.open(path, "a")
        if file then
            file:write(text)
            file:close()
            return true
        end
        return false
    end

    -- cwd worldserver (как DeletedGobLog.txt)
    if tryOpen(filename) then
        return true
    end

    -- попытка создать logs/ (Linux docker / Windows)
    pcall(function() os.execute('mkdir -p logs 2>/dev/null') end)
    pcall(function() os.execute('mkdir logs 2>nul') end)

    if filename:find("/") or filename:find("\\") then
        if tryOpen(filename) then
            return true
        end
    end

    local base = filename:match("([^/\\]+)$") or filename
    if base ~= filename and tryOpen(base) then
        return true
    end

    EmitLog("|ERROR", "FileLog", "cannot open " .. tostring(filename))
    return false
end

function NobleNext.FormatPlayer(player)
    if not player then return "?" end
    local account = player.GetAccountName and player:GetAccountName() or "?"
    return string.format("%s (account=%s)", player:GetName(), account)
end

function NobleNext.FormatLocation(player)
    if not player then return "map=?" end
    local x, y, z = player:GetLocation()
    return string.format("map=%d pos=%.1f,%.1f,%.1f phase=%s",
        player:GetMapId(), x, y, z, tostring(player:GetPhaseMask()))
end

-- Структурированный аудит → NobleNext_audit.log (cwd worldserver)
function NobleNext.LogAudit(module, action, player, details)
    local ts = os.date("%Y-%m-%d %H:%M:%S")
    local who = NobleNext.FormatPlayer(player)
    local where = player and NobleNext.FormatLocation(player) or ""
    local line = string.format("[%s] module=%s action=%s player=%s %s details=%s\n",
        ts, module or "?", action or "?", who, where, details or "")
    NobleNext.AppendFile("NobleNext_audit.log", line)
    NobleNext.Log(module, string.format("%s | %s | %s", action or "?", who, details or ""))
end

-- Совместимость с legacy MasterPanel: DeletedGobLog.txt в cwd worldserver
function NobleNext.LogGobDeleteSession(player)
    if not player then return end
    local x, y, z = player:GetLocation()
    NobleNext.AppendFile("DeletedGobLog.txt", string.format(
        "Player: %s Account: %s Time: [%s] MapID: %d GPS: [%.1f %.1f %.1f]\n",
        player:GetName(),
        player.GetAccountName and player:GetAccountName() or "?",
        os.date("%d.%m %H:%M:%S"),
        player:GetMapId(),
        x, y, z
    ))
end

function NobleNext.LogGobDeleteGuid(gobGuid)
    if not gobGuid then return end
    NobleNext.AppendFile("DeletedGobLog.txt", "GUID: " .. tostring(gobGuid) .. "\n")
end

-- ---------------------------------------------------------------------------
-- Event registration helpers (state-safe)
-- ---------------------------------------------------------------------------
function NobleNext.RegisterWorldEvent(eventId, handler)
    if NobleNext.IsMainState() then
        RegisterPlayerEvent(eventId, handler)
        return true
    end
    return false
end

function NobleNext.RegisterMapEvent(eventId, handler)
    if NobleNext.IsMapState() then
        RegisterPlayerEvent(eventId, handler)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- String / table helpers
-- ---------------------------------------------------------------------------
function NobleNext.Trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function NobleNext.EscapeSqlLike(s)
    return tostring(s or ""):gsub("([%%%_%[%]])", "\\%1")
end

-- ---------------------------------------------------------------------------
-- Color helpers for broadcast messages
-- ---------------------------------------------------------------------------
NobleNext.COLOR = {
    primary = "|cff00ccff",
    success = "|cff629404",
    warning = "|cffff9900",
    error   = "|cffff0000",
    info    = "|cff8bad4c",
    white   = "|cffffffff",
    gray    = "|cffbbbbbb",
    gold    = "|cffec9c22",
    pink    = "|cffFF6EB4",
    purple  = "|cffc169d2",
}

function NobleNext.Color(name, text)
    return (NobleNext.COLOR[name] or "") .. text .. "|r"
end

-- ---------------------------------------------------------------------------
-- Module registry & reload hooks (единый процесс после .reload eluna)
-- ---------------------------------------------------------------------------
NobleNext._modules = NobleNext._modules or {}
NobleNext._reloadHooks = NobleNext._reloadHooks or {}

function NobleNext.RegisterModule(name, meta)
    NobleNext._modules[name] = meta or true
    NobleNext.LogDebug("Core", "module registered: " .. tostring(name))
end

function NobleNext.OnReload(label, handler)
    if type(handler) ~= "function" then return end
    table.insert(NobleNext._reloadHooks, { label = label or "?", fn = handler })
end

local function RunReloadHooks()
    NobleNext.Log("Core", string.format("reload hooks: %d", #NobleNext._reloadHooks))
    for i = 1, #NobleNext._reloadHooks do
        local hook = NobleNext._reloadHooks[i]
        local ok, err = pcall(hook.fn)
        if not ok then
            NobleNext.LogError("Core", string.format("reload hook '%s' failed: %s", hook.label, tostring(err)))
        end
    end
end

if NobleNext.IsMainState() and not NobleNext._reloadEventRegistered then
    NobleNext._reloadEventRegistered = true
    RegisterServerEvent(NobleNext.Events.SERVER_LUA_STATE_OPEN, RunReloadHooks)
end

if NobleNext.IsMainState() and not NobleNext._coreLogged then
    NobleNext._coreLogged = true
    NobleNext.Log("Core", string.format("loaded v%s (log level=%d)", NobleNext.VERSION, NobleNext.logLevel))
end

return NobleNext
