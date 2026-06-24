--[[ GM/Army/NNArmyInit.lua — Army Controller (выделение и команды NPC) ]]

if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_GM_ARMY_BOOTSTRAPPED then
    return package.loaded["GM.Army.NNArmyInit"] or {}
end
_G.NN_GM_ARMY_BOOTSTRAPPED = true

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local AURA_CONTROL       = 540626
local SPELL_UNSELECT     = 540632
local SPELL_DELETE       = 540633
local SPELL_EMOTE        = 540628
local SPELL_TOGGLE_OFF   = 540631
local SPELL_SELECT_TARGET = 540636

local NPC_RUN     = 1001170
local NPC_WALK    = 1001171
local NPC_ROTATE  = 1001172
local NPC_SEL_2   = 1001173
local NPC_SEL_5   = 1001174

local HANDLER_NAME = "ArmyHandlers"
local MAX_SELECTION = 50

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------
-- playerGuidLow -> { [creatureGuidLow] = { guid = low, entry = entry, name = name } }
local SelectedNPCs = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function HasPermission(player, creature)
    return NobleNext.CanControlCreature(player, creature)
end

local function SafeGetCreature(info, map)
    if not info or not info.guid or not info.entry then return nil end
    local creatureGUID = GetUnitGUID(info.guid, info.entry, map:GetId())
    if not creatureGUID then return nil end
    return map:GetWorldObject(creatureGUID)
end

local function GetPlayerSelectionTable(player)
    local guidLow = player:GetGUIDLow()
    if not SelectedNPCs[guidLow] then
        SelectedNPCs[guidLow] = {}
    end
    return SelectedNPCs[guidLow]
end

local function BuildNpcList(player)
    local list = {}
    for _, info in pairs(GetPlayerSelectionTable(player)) do
        table.insert(list, info)
    end
    return list
end

local function SendSelection(player)
    AIO.Handle(player, HANDLER_NAME, "SelectNewNPCs", BuildNpcList(player))
end

local function ClearSelection(player)
    SelectedNPCs[player:GetGUIDLow()] = nil
    AIO.Handle(player, HANDLER_NAME, "UnselectAll")
end

local function AddCreatureToSelection(player, creature)
    if not creature then return false end
    if not HasPermission(player, creature) then return false end

    local lowGuid = creature:GetGUIDLow()
    local sel = GetPlayerSelectionTable(player)

    if sel[lowGuid] then
        return true
    end

    if #BuildNpcList(player) >= MAX_SELECTION then
        player:SendBroadcastMessage(NobleNext.Color("warning", "[Army]|r Достигнут лимит выделения (" .. MAX_SELECTION .. ")."))
        return false
    end

    sel[lowGuid] = {
        guid  = lowGuid,
        entry = creature:GetEntry(),
        name  = creature:GetName(),
    }
    return true
end

local AIO = NobleNext.AIO
local ArmyHandlers = AIO.AddHandlers(HANDLER_NAME, {})

-- ---------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------
local function OnNPCSelectSpawn(event, creature, summoner)
    local markerEntry = creature:GetEntry()
    local range = 0
    if markerEntry == NPC_SEL_2 then
        range = -1 -- GetCreaturesInRange(-1, 0, 0, 1) → 2 ярда
    elseif markerEntry == NPC_SEL_5 then
        range = 2.5
    else
        creature:DespawnOrUnsummon()
        return
    end

    creature:DespawnOrUnsummon()

    local inRange = creature:GetCreaturesInRange(range, 0, 0, 1)
    local added = 0

    for i = 1, #inRange do
        local c = inRange[i]
        if AddCreatureToSelection(summoner, c) then
            added = added + 1
        end
    end

    if added > 0 then
        NobleNext.LogAudit("Army", "select_area", summoner,
            string.format("entry=%d added=%d total=%d", markerEntry, added, #BuildNpcList(summoner)))
        SendSelection(summoner)
    end
end

local function OnSelectTargetSpell(player)
    local selection = player:GetSelection()
    if not selection then return end
    local creature = selection:ToCreature()
    if not creature then return end

    if AddCreatureToSelection(player, creature) then
        NobleNext.LogAudit("Army", "select_target", player,
            string.format("npc=%s entry=%d", creature:GetName(), creature:GetEntry()))
        SendSelection(player)
    end
end

function ArmyHandlers.AddTargetToSelection(player)
    OnSelectTargetSpell(player)
end

-- ---------------------------------------------------------------------------
-- Movement / Commands
-- ---------------------------------------------------------------------------
local function OnNPCCommandSpawn(event, creature, summoner)
    local entry = creature:GetEntry()
    local cmdType = 0
    if entry == NPC_RUN then
        cmdType = 1
    elseif entry == NPC_WALK then
        cmdType = 2
    elseif entry == NPC_ROTATE then
        cmdType = 3
    else
        creature:DespawnOrUnsummon()
        return
    end

    local x, y, z = creature:GetHomePosition()
    creature:DespawnOrUnsummon()
    AIO.Handle(summoner, HANDLER_NAME, "CallTableToCommand", cmdType, x, y, z)
end

function ArmyHandlers.CommandToNPC(player, npcList, cmdType, xPos, yPos, zPos)
    local list = npcList
    if not list or #list == 0 then
        list = BuildNpcList(player)
    end
    if #list == 0 then return end

    local map = player:GetMap()
    if not map then return end

    local totalX, totalY, totalZ = 0, 0, 0
    local validCount = 0
    local creatures = {}

    for i = 1, #list do
        local info = list[i]
        local c = SafeGetCreature(info, map)
        if c and HasPermission(player, c) then
            local cx, cy, cz, co = c:GetHomePosition()
            totalX = totalX + cx
            totalY = totalY + cy
            totalZ = totalZ + cz
            validCount = validCount + 1
            table.insert(creatures, { obj = c, ox = cx, oy = cy, oz = cz, oo = co })
        end
    end

    if validCount == 0 then return end

    NobleNext.LogAudit("Army", "command", player,
        string.format("type=%d targets=%d dest=%.1f,%.1f,%.1f", cmdType, validCount, xPos, yPos, zPos))

    local centerX = totalX / validCount
    local centerY = totalY / validCount
    local centerZ = totalZ / validCount

    local endVecX = xPos - centerX
    local endVecY = yPos - centerY
    local endVecZ = zPos - centerZ
    local endAngle = math.atan2(endVecY, endVecX)

    for i = 1, #creatures do
        local item = creatures[i]
        local c = item.obj
        local sx = item.ox - centerX
        local sy = item.oy - centerY
        local sz = item.oz - centerZ

        local startAngle = math.atan2(sy, sx)
        local rotAngle = endAngle - item.oo
        local ca = math.cos(rotAngle)
        local sa = math.sin(rotAngle)
        local rx = ca * sx - sa * sy
        local ry = sa * sx + ca * sy

        local destX = xPos + rx
        local destY = yPos + ry
        local destZ = zPos + sz

        if cmdType == 1 then -- бег
            c:SetWalk(false)
            c:SetHomePosition(destX, destY, destZ, endAngle)
            c:MoveHome()
        elseif cmdType == 2 then -- шаг
            c:SetWalk(true)
            c:MoveTo(i, destX, destY, destZ)
            c:SetHomePosition(destX, destY, destZ, endAngle)
        elseif cmdType == 3 then -- поворот
            c:SetHomePosition(centerX + rx, centerY + ry, centerZ + sz, endAngle)
            c:MoveHome()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Emote
-- ---------------------------------------------------------------------------
function ArmyHandlers.SetEmoteToNPC(player, npcList, emoteID)
    local emote = tonumber(emoteID)
    if not emote or emote < 0 then return end

    local list = npcList
    if not list or #list == 0 then
        list = BuildNpcList(player)
    end
    if #list == 0 then return end

    local map = player:GetMap()
    if not map then return end

    for i = 1, #list do
        local info = list[i]
        local c = SafeGetCreature(info, map)
        if c and HasPermission(player, c) then
            c:EmoteState(emote)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Delete / Despawn
-- ---------------------------------------------------------------------------
function ArmyHandlers.DeleteAllNpcInGroup(player, npcList)
    local list = npcList
    if not list or #list == 0 then
        list = BuildNpcList(player)
    end

    local map = player:GetMap()
    if not map then return end

    for i = 1, #list do
        local info = list[i]
        local c = SafeGetCreature(info, map)
        if c and HasPermission(player, c) then
            c:DespawnOrUnsummon(0)
        end
    end

    ClearSelection(player)
    NobleNext.LogAudit("Army", "delete", player, string.format("count=%d", #list))
end

function ArmyHandlers.DeleteAllNpcInGroupPerm(player, npcList)
    local list = npcList
    if not list or #list == 0 then
        list = BuildNpcList(player)
    end

    local map = player:GetMap()
    if not map then return end

    for i = 1, #list do
        local info = list[i]
        local c = SafeGetCreature(info, map)
        if c and HasPermission(player, c) then
            c:DespawnOrUnsummon(0)
        end
    end

    ClearSelection(player)
    NobleNext.LogAudit("Army", "delete_perm", player, string.format("count=%d", #list))
end

ArmyHandlers.CallTableToDel     = ArmyHandlers.DeleteAllNpcInGroup
ArmyHandlers.CallTableToDelPerm = ArmyHandlers.DeleteAllNpcInGroupPerm

function ArmyHandlers.UnselectAll(player)
    ClearSelection(player)
end

-- ---------------------------------------------------------------------------
-- Spell handlers
-- ---------------------------------------------------------------------------
local function OnSpellCast(event, player, spell, skipCheck)
    local entry = spell:GetEntry()

    if entry == SPELL_UNSELECT then
        ClearSelection(player)
    elseif entry == SPELL_DELETE then
        ArmyHandlers.DeleteAllNpcInGroup(player)
    elseif entry == SPELL_EMOTE then
        AIO.Handle(player, HANDLER_NAME, "CallEmoteFrame")
    elseif entry == SPELL_TOGGLE_OFF then
        player:RemoveAura(AURA_CONTROL)
    elseif entry == SPELL_SELECT_TARGET then
        OnSelectTargetSpell(player)
    end
end

-- ---------------------------------------------------------------------------
-- Register
-- ---------------------------------------------------------------------------
RegisterPlayerEvent(NobleNext.Events.PLAYER_SPELL_CAST, OnSpellCast)

local function SafeRegisterCreatureEvent(entry, eventId, handler)
    local ok, err = pcall(RegisterCreatureEvent, entry, eventId, handler)
    if not ok then
        NobleNext.LogError("ArmyController", string.format("Failed to register creature event for entry %d: %s", entry, tostring(err)))
    end
end

SafeRegisterCreatureEvent(NPC_RUN,    NobleNext.Events.CREATURE_JUST_SUMMONED, OnNPCCommandSpawn)
SafeRegisterCreatureEvent(NPC_WALK,   NobleNext.Events.CREATURE_JUST_SUMMONED, OnNPCCommandSpawn)
SafeRegisterCreatureEvent(NPC_ROTATE, NobleNext.Events.CREATURE_JUST_SUMMONED, OnNPCCommandSpawn)
SafeRegisterCreatureEvent(NPC_SEL_2,  NobleNext.Events.CREATURE_JUST_SUMMONED, OnNPCSelectSpawn)
SafeRegisterCreatureEvent(NPC_SEL_5,  NobleNext.Events.CREATURE_JUST_SUMMONED, OnNPCSelectSpawn)

NobleNext.RegisterModule("ArmyController", { layer = "GM", aio = "NN_Army", core = "Custom/NobleNext/Army" })
NobleNext.Log("ArmyController", "registered")
