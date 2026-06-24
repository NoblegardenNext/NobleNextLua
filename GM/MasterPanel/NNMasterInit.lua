--[[ GM/MasterPanel/NNMasterInit ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

-- AIO handlers must be registered in the main (WORLD) Lua state only.
local AIO = AIO or require("AIO")
if not AIO.IsMainState() then
    return
end

local NobleNext = require("NobleNext")

if _G.NN_GM_MASTER_BOOTSTRAPPED then
    return package.loaded["GM.MasterPanel.NNMasterInit"] or {}
end
_G.NN_GM_MASTER_BOOTSTRAPPED = true

local HANDLER_NAME = "AIOAddonMasterPanel"
local AddonNDMHandlers = AIO.AddHandlers(HANDLER_NAME, {})

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local MAX_CHAT_LEN = 355
local MAX_RADIUS = 90
local MAX_COLOR = 7
local MAX_UNDO_RADIUS = 15
local MIN_NAME_LEN = 5

local COLOR_TABLE = {
    "|cffbbbbbb",
    "|cffff0000",
    "|cff00ccff",
    "|cff93c57f",
    "|cffFF6EB4",
    "|cffec9c22",
    "|cffc169d2",
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function IsForbiddenChat(text)
    return tostring(text):len() > MAX_CHAT_LEN
end

local function FormatText(text)
    return (tostring(text):gsub("%s+", " "))
end

local function IsForbiddenRadius(radius)
    local r = tonumber(radius)
    return not r or r > MAX_RADIUS
end

local function IsForbiddenColor(color)
    local c = tonumber(color)
    return not c or c > MAX_COLOR or c < 1
end

local function IsGmOrDm(player)
    return NobleNext.HasStaffPermission(player)
end

-- ---------------------------------------------------------------------------
-- Chat: NPC
-- ---------------------------------------------------------------------------
local function NPCSayFunc(player, line)
    local unit = player:GetSelectedUnit()
    if not unit then return end
    local lastChar = line:sub(-1)
    if lastChar == "!" then
        unit:Emote(5)
    elseif lastChar == "?" then
        unit:Emote(6)
    else
        unit:Emote(1)
    end
    unit:SendUnitSay(line, 0)
end

local function NPCSayByEmoteFunc(player, line)
    local unit = player:GetSelectedUnit()
    if not unit then return end
    unit:SendUnitEmote("|cffFFFF9F" .. line)
end

local function NPCEmoteFunc(player, line)
    local unit = player:GetSelectedUnit()
    if not unit then return end
    unit:SendUnitEmote(line)
end

local function NPCYellFunc(player, line)
    local unit = player:GetSelectedUnit()
    if not unit then return end
    unit:Emote(22)
    unit:SendUnitYell(line, 0)
end

-- ---------------------------------------------------------------------------
-- Chat: Color (radius / party)
-- ---------------------------------------------------------------------------
local function ChatColorRadius(player, text, radius, colorIdx)
    if IsForbiddenRadius(radius) or IsForbiddenColor(colorIdx) then return end

    local r = tonumber(radius)
    local color = COLOR_TABLE[tonumber(colorIdx)] or COLOR_TABLE[1]
    local msg = color .. text

    local players = player:GetPlayersInRange(r)
    player:SendBroadcastMessage(msg)
    for i = 1, #players do
        players[i]:SendBroadcastMessage(msg)
    end
end

local function ChatColorParty(player, text, colorIdx)
    if IsForbiddenColor(colorIdx) then return end

    local group = player:GetGroup()
    if not group then return end

    local members = group:GetMembers()
    local color = COLOR_TABLE[tonumber(colorIdx)] or COLOR_TABLE[1]
    local msg = color .. text

    for i = 1, #members do
        members[i]:SendBroadcastMessage(msg)
    end
end

-- ---------------------------------------------------------------------------
-- TalkingHead
-- ---------------------------------------------------------------------------
local function SendTalkingHead(player, text, unitName, creator)
    AIO.Handle(player, HANDLER_NAME, "ElunaGetTalkingHead", text, unitName, creator)
end

local function TalkingHeadRadius(player, text, unitName, creator, radius)
    if IsForbiddenRadius(radius) then return end
    local r = tonumber(radius)

    local unit = player:GetSelectedUnit()
    if not unit then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Master]|r Не выбрана цель для TalkingHead."))
        return
    end

    local players = player:GetPlayersInRange(r)

    player:GossipComplete()
    player:GossipClearMenu()
    player:GossipMenuAddItem(0, "TalkingHead", 1, 1)
    player:GossipSendMenu(100, unit)
    SendTalkingHead(player, text, unitName, creator)

    for i = 1, #players do
        local p = players[i]
        p:GossipComplete()
        p:GossipClearMenu()
        p:GossipMenuAddItem(0, "TalkingHead", 1, 1)
        p:GossipSendMenu(100, unit)
        SendTalkingHead(p, text, unitName, creator)
    end
end

local function TalkingHeadParty(player, text, unitName, creator)
    local group = player:GetGroup()
    if not group then return end

    local members = group:GetMembers()
    local unit = player:GetSelectedUnit()
    if not unit then
        player:SendBroadcastMessage(NobleNext.Color("error", "[Master]|r Не выбрана цель для TalkingHead."))
        return
    end

    for i = 1, #members do
        local p = members[i]
        p:GossipComplete()
        p:GossipClearMenu()
        p:GossipMenuAddItem(0, "TalkingHead", 1, 1)
        p:GossipSendMenu(100, unit)
        SendTalkingHead(p, text, unitName, creator)
    end
end

-- ---------------------------------------------------------------------------
-- AIO Handlers
-- ---------------------------------------------------------------------------
function AddonNDMHandlers.NPCChatRetranslator(player, text, state, radius, color)
    if IsForbiddenChat(text) then return end
    if not IsGmOrDm(player) then return end

    local s = tonumber(state)
    if not s then return end

    local fmt = FormatText(text)

    if s == 1 then
        NPCSayFunc(player, fmt)
        NobleNext.LogAudit("Master", "npc_say", player, fmt:sub(1, 80))
    elseif s == 2 then
        NPCSayByEmoteFunc(player, fmt)
    elseif s == 3 then
        NPCEmoteFunc(player, fmt)
    elseif s == 4 then
        NPCYellFunc(player, fmt)
    elseif s == 5 then
        local r = tonumber(radius) or 0
        if r == 0 then
            ChatColorParty(player, fmt, color)
        else
            ChatColorRadius(player, fmt, r, color)
        end
    end
end

function AddonNDMHandlers.TalkingHeadRetranslator(player, text, unitName, creator, radius)
    if not IsGmOrDm(player) then return end

    local r = tonumber(radius)
    if r and r > MAX_RADIUS then return end

    if r == 0 or r == nil then
        TalkingHeadParty(player, text, unitName, creator)
    else
        TalkingHeadRadius(player, text, unitName, creator, r)
    end
end

-- ---------------------------------------------------------------------------
-- GameObject: Undo
-- ---------------------------------------------------------------------------
local function LogDeletion(player, gobGuid, gobName)
    NobleNext.LogGobDeleteGuid(gobGuid)
    NobleNext.LogAudit("Master", "gob_delete", player, string.format(
        "guid=%s name=%s", tostring(gobGuid or "-"), tostring(gobName or "-")))
end

local function DeleteGobject(go)
    if not go then return false end
    local ok, err = pcall(function() go:RemoveFromWorld(true) end)
    if not ok then
        NobleNext.LogError("GobDelete", "RemoveFromWorld failed: " .. tostring(err))
        return false
    end
    return true
end

function AddonNDMHandlers.UndoPhaseGobjects(player, undoRadius)
    if not IsGmOrDm(player) then return end

    local r = tonumber(undoRadius)
    if type(r) ~= "number" or r > MAX_UNDO_RADIUS or r <= 0 then return end

    local playerPhase = player:GetPhaseMask()
    player:SendBroadcastMessage("Удаляются GO из фазы [" .. playerPhase .. "]. Радиус " .. r .. " ярдов.")

    NobleNext.LogGobDeleteSession(player)

    local gobs = player:GetGameObjectsInRange(r)
    if not gobs or #gobs == 0 then
        player:SendBroadcastMessage("Объекты не найдены.")
        return
    end

    local deleted = 0

    for i = 1, #gobs do
        local go = gobs[i]
        if go:GetPhaseMask() == playerPhase then
            LogDeletion(player, go:GetDBTableGUIDLow(), go:GetName())
            if DeleteGobject(go) then
                deleted = deleted + 1
            end
        end
    end

    player:SendBroadcastMessage("Удалено объектов: " .. deleted)
end

function AddonNDMHandlers.UndoPhaseNameGobjects(player, gobName, undoRadius)
    if not IsGmOrDm(player) then return end

    local r = tonumber(undoRadius)
    if type(r) ~= "number" or r > MAX_UNDO_RADIUS or r <= 0 then return end

    local name = NobleNext.Trim(gobName)
    if name:len() < MIN_NAME_LEN then return end

    local playerPhase = player:GetPhaseMask()
    player:SendBroadcastMessage("Удаляются GO (\"" .. name .. "\") из фазы [" .. playerPhase .. "]. Радиус " .. r .. " ярдов.")

    NobleNext.LogGobDeleteSession(player)

    local gobs = player:GetGameObjectsInRange(r)
    if not gobs or #gobs == 0 then
        player:SendBroadcastMessage("Объекты не найдены.")
        return
    end

    local deleted = 0
    local lowerName = name:lower()

    for i = 1, #gobs do
        local go = gobs[i]
        if go:GetPhaseMask() == playerPhase then
            local goName = go:GetName()
            if goName and goName:lower():find(lowerName, 1, true) then
                LogDeletion(player, go:GetDBTableGUIDLow(), goName)
                if DeleteGobject(go) then
                    deleted = deleted + 1
                end
            end
        end
    end

    player:SendBroadcastMessage("Удалено объектов: " .. deleted)
end

NobleNext.RegisterModule("MasterPanel", { layer = "GM", aio = "NN_Master", core = "Custom/NobleNext/Master" })
NobleNext.Log("MasterPanel", "registered (C++ chat fallback)")
