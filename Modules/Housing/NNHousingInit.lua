--[[
    Housing Unlock — минимальный анлок интерфейса жилья для просмотра
    
    Что делает:
      • При логине отправляет mirror var `housingServiceEnabled = 1`, чтобы
        HousingMicroButton стала видна и C_Housing.IsHousingServiceEnabled() вернул true.
      • Завершает tutorial-квесты, чтобы не было сплэш-скрина «Начать обучение».
      • Отправляет addon message `SKIP_HOUSING_TUTORIALS` клиентскому аддону NobleNext.
      • Команда `.housing` открывает Housing Dashboard через addon message.
    
    Что НЕ делает (убрано по сравнению с полной версией):
      • Не отправляет housingEnableBuyHouse / Move / Delete / Create*Neighborhood —
        покупка, перемещение, удаление и создание районов остаются недоступными.
      • Не прелоадит Blizzard_HousingDashboard — клиентский аддон NobleNext делает это сам.
      • Не создаёт виртуальные дома / neighborhood — только разблокировка UI.
    
    Требует клиентский аддон: Addons/NobleNext/ (или Interface/AddOns/NobleNext/)
]]

if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")

if _G.NN_MOD_HOUSING_BOOTSTRAPPED then
    return package.loaded["Modules.Housing.NNHousingInit"] or {}
end
_G.NN_MOD_HOUSING_BOOTSTRAPPED = true

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local PLAYER_EVENT_ON_LOGIN   = 3
local PLAYER_EVENT_ON_COMMAND = 42
local SERVER_EVENT_ON_LUA_STATE_OPEN = 33

local SMSG_MIRROR_VARS = 0x42036D
local CHAT_MSG_WHISPER = 7

local ADDON_PREFIX           = "NobleNext"
local ADDON_OPEN_DASHBOARD   = "OPEN_HOUSING_DASHBOARD"
local ADDON_SKIP_TUTORIALS   = "SKIP_HOUSING_TUTORIALS"

local QUEST_STATUS_REWARDED = 6
local HOUSING_TUTORIAL_QUESTS = { 91863, 91968, 91969 }

-- Достаточно housingServiceEnabled для видимости кнопки HousingMicroButton.
-- housingMarketEnabled добавлен на случай, если клиент проверяет его для Dashboard.
local HOUSING_MIRROR_VARS = {
    { name = "housingServiceEnabled", value = "1" },
    { name = "housingMarketEnabled",  value = "1" },
}

-- ---------------------------------------------------------------------------
-- SMSG_MIRROR_VARS: bit-packed SizedCString
-- ---------------------------------------------------------------------------
local MirrorVars = {}

function MirrorVars.writeBits(buf, bitpos, curbitval, value, bits)
    value = value % (2 ^ bits)
    if bits > bitpos then
        curbitval = curbitval + math.floor(value / (2 ^ (bits - bitpos)))
        bits = bits - bitpos
        bitpos = 8
        buf[#buf + 1] = curbitval % 256
        while bits >= 8 do
            bits = bits - 8
            buf[#buf + 1] = math.floor(value / (2 ^ bits)) % 256
        end
        bitpos = 8 - bits
        curbitval = bits > 0 and (value % (2 ^ bits)) * (2 ^ bitpos) or 0
    else
        bitpos = bitpos - bits
        curbitval = curbitval + (value % (2 ^ bits)) * (2 ^ bitpos)
    end
    return bitpos, curbitval
end

function MirrorVars.writeBit(buf, bitpos, curbitval, bit)
    bitpos = bitpos - 1
    if bit ~= 0 then
        curbitval = curbitval + (2 ^ bitpos)
    end
    if bitpos == 0 then
        bitpos = 8
        buf[#buf + 1] = curbitval % 256
        curbitval = 0
    end
    return bitpos, curbitval
end

function MirrorVars.flushBits(buf, bitpos, curbitval)
    if bitpos ~= 8 then
        buf[#buf + 1] = curbitval % 256
        bitpos = 8
        curbitval = 0
    end
    return bitpos, curbitval
end

function MirrorVars.buildPacket(vars)
    local buf = {}
    local count = #vars

    buf[1] = count % 256
    buf[2] = math.floor(count / 256) % 256
    buf[3] = math.floor(count / 65536) % 256
    buf[4] = math.floor(count / 16777216) % 256

    local bitpos, curbitval = 8, 0
    for i = 1, count do
        local entry = vars[i]
        bitpos, curbitval = MirrorVars.writeBit(buf, bitpos, curbitval, 0)
        bitpos, curbitval = MirrorVars.writeBits(buf, bitpos, curbitval, #entry.name + 1, 24)
        bitpos, curbitval = MirrorVars.writeBits(buf, bitpos, curbitval, #entry.value + 1, 24)
        bitpos, curbitval = MirrorVars.flushBits(buf, bitpos, curbitval)

        for j = 1, #entry.name do
            buf[#buf + 1] = string.byte(entry.name, j)
        end
        buf[#buf + 1] = 0

        for j = 1, #entry.value do
            buf[#buf + 1] = string.byte(entry.value, j)
        end
        buf[#buf + 1] = 0
    end

    return buf
end

function MirrorVars.send(player, vars)
    local payload = MirrorVars.buildPacket(vars)
    local packet = CreatePacket(SMSG_MIRROR_VARS, #payload + 16)
    for i = 1, #payload do
        packet:WriteUByte(payload[i])
    end
    player:SendPacket(packet)
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function scheduleForPlayer(player, delayMs, fn)
    local guid = player:GetGUID()
    CreateLuaEvent(function()
        local p = GetPlayerByGUID(guid)
        if p and p:IsInWorld() then
            fn(p)
        end
    end, delayMs, 1)
end

local function completeHousingTutorialQuests(player)
    for _, questId in ipairs(HOUSING_TUTORIAL_QUESTS) do
        if player:GetQuestStatus(questId) ~= QUEST_STATUS_REWARDED then
            player:SetQuestStatus(questId, QUEST_STATUS_REWARDED)
        end
    end
end

local function sendSkipHousingTutorials(player)
    player:SendAddonMessage(ADDON_PREFIX, ADDON_SKIP_TUTORIALS, CHAT_MSG_WHISPER, player)
end

local function enableHousingMirrorVars(player)
    MirrorVars.send(player, HOUSING_MIRROR_VARS)
end

-- ---------------------------------------------------------------------------
-- Core: unlock housing UI on login
-- ---------------------------------------------------------------------------
local function enableHousingWithRetry(player)
    completeHousingTutorialQuests(player)
    enableHousingMirrorVars(player)
    sendSkipHousingTutorials(player)
    -- Повторная отправка через 1 сек — клиент может инициализироваться с задержкой.
    scheduleForPlayer(player, 1000, function(p)
        enableHousingMirrorVars(p)
        sendSkipHousingTutorials(p)
    end)
end

-- ---------------------------------------------------------------------------
-- .housing command — open dashboard
-- ---------------------------------------------------------------------------
local function OnPlayerCommand(_, player, command)
    if not player then return true end

    local cmd = command:gsub("^%s+", ""):gsub("%s+$", ""):match("^%s*(%S+)")
    if cmd ~= "housing" then
        return true
    end

    -- Обновляем mirror vars (на случай, если сбросились) и открываем dashboard
    enableHousingWithRetry(player)
    scheduleForPlayer(player, 200, function(p)
        p:SendAddonMessage(ADDON_PREFIX, ADDON_OPEN_DASHBOARD, CHAT_MSG_WHISPER, p)
        p:SendBroadcastMessage("|cff629404[Housing]|r Dashboard opened.")
    end)

    return false
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function OnLogin(_, player)
    enableHousingWithRetry(player)
end

local function OnLuaStateOpen()
    local online = GetPlayersInWorld(2)
    for i = 1, #online do
        enableHousingWithRetry(online[i])
    end
end

NobleNext.OnReload("HousingUnlock", OnLuaStateOpen)

-- ---------------------------------------------------------------------------
-- Register (WORLD state only)
-- ---------------------------------------------------------------------------
if GetStateMapId() == -1 then
    RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnLogin)
    RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, OnPlayerCommand)
    NobleNext.RegisterModule("HousingUnlock", { layer = "Modules", mirrorVars = #HOUSING_MIRROR_VARS })
    NobleNext.Log("HousingUnlock", string.format(
        "ON_LOGIN (%d), ON_COMMAND (%d), OnReload registered; mirror vars=%d, tutorial quests=%d.",
        PLAYER_EVENT_ON_LOGIN,
        PLAYER_EVENT_ON_COMMAND,
        #HOUSING_MIRROR_VARS,
        #HOUSING_TUTORIAL_QUESTS
    ))
end
