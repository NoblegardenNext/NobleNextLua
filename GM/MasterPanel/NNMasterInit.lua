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
    -- NPC speech uses native commands. Only party/radius announcements need this AIO route.
    if tonumber(state) ~= 5 or IsForbiddenChat(text) or not IsGmOrDm(player) then return end
    local fmt = FormatText(text)
    local r = tonumber(radius) or 0
    if r == 0 then
        ChatColorParty(player, fmt, color)
    else
        ChatColorRadius(player, fmt, r, color)
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

local function DeleteNearbyObjects(player, radius, name)
    if not IsGmOrDm(player) then return end
    local r = tonumber(radius)
    if not (r and r > 0 and r <= MAX_UNDO_RADIUS) then return end

    -- The grid search filters native visibility. The command checks logical RP
    -- context, RBAC and delete protection for each spawn independently.
    local targets = {}
    for _, go in ipairs(player:GetGameObjectsInRange(r) or {}) do
        local guid = tostring(go:GetDBTableGUIDLow())
        local goName = go:GetName() or ""
        if guid:match("^[1-9]%d*$") and (not name or goName:lower():find(name, 1, true)) then
            targets[#targets + 1] = { guid, goName }
        end
    end
    if #targets == 0 then
        player:SendBroadcastMessage("Постоянные объекты не найдены.")
        return
    end

    NobleNext.LogGobDeleteSession(player)
    local accepted = 0
    for _, target in ipairs(targets) do
        if player:RunCommand("gobject delete " .. target[1]) then
            accepted = accepted + 1
            LogDeletion(player, target[1], target[2])
        end
    end
    player:SendBroadcastMessage("Команд удаления принято: " .. accepted .. " из " .. #targets .. ".")
end

function AddonNDMHandlers.UndoPhaseGobjects(player, radius)
    DeleteNearbyObjects(player, radius)
end

function AddonNDMHandlers.UndoPhaseNameGobjects(player, gobName, radius)
    local name = NobleNext.Trim(gobName)
    if #name >= MIN_NAME_LEN then DeleteNearbyObjects(player, radius, name:lower()) end
end

NobleNext.RegisterModule("MasterPanel", { layer = "GM", aio = "NN_Master", core = "Custom/NobleNext/Master" })
NobleNext.Log("MasterPanel", "registered (C++ chat fallback)")
