--[[ GM/Pet/NNPetInit ]]

if not _G.NN_BOOTSTRAP_ACTIVE then return end

local AIO = AIO or require("AIO")
if not AIO.IsMainState() then
    return
end

local NobleNext = require("NobleNext")

if _G.NN_GM_PET_BOOTSTRAPPED then
    return package.loaded["GM.Pet.NNPetInit"] or {}
end
_G.NN_GM_PET_BOOTSTRAPPED = true

local HANDLER_NAME = "NN_PetControl"
local BLOCK_AURA = 91072
local MAX_TEXT_LEN = 254

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function GetTargetCreature(player)
    if not player then return nil end
    local selection = player:GetSelectedUnit()
    if not selection then return nil end
    return selection:ToCreature()
end

local function IsCompanionOwner(player, creature)
    if not player or not creature then return false end
    if creature:HasAura(BLOCK_AURA) then return false end
    local controller = creature:GetControllerGUID()
    if not controller then return false end
    return controller == player:GetGUID()
end

local function NotifyNoControl(player)
    if not player then return end
    player:SendNotification("Вы не можете управлять этим существом.")
end

-- ---------------------------------------------------------------------------
-- AIO handlers
-- ---------------------------------------------------------------------------
local PetControlHandlers = AIO.AddHandlers(HANDLER_NAME, {})

function PetControlHandlers.CheckOwner(player)
    local creature = GetTargetCreature(player)
    local allowed = IsCompanionOwner(player, creature)
    AIO.Handle(player, HANDLER_NAME, "ShowButton", allowed)
end

function PetControlHandlers.Say(player, text)
    local creature = GetTargetCreature(player)
    if not IsCompanionOwner(player, creature) then
        NotifyNoControl(player)
        return
    end
    text = tostring(text or "")
    if #text == 0 or #text > MAX_TEXT_LEN then return end
    creature:SendUnitSay(text, 0)
end

function PetControlHandlers.Emote(player, text)
    local creature = GetTargetCreature(player)
    if not IsCompanionOwner(player, creature) then
        NotifyNoControl(player)
        return
    end
    text = tostring(text or "")
    if #text == 0 or #text > MAX_TEXT_LEN then return end
    creature:SendUnitEmote(creature:GetName() .. " " .. text)
end

function PetControlHandlers.Byte1(player, state)
    local creature = GetTargetCreature(player)
    if not IsCompanionOwner(player, creature) then
        NotifyNoControl(player)
        return
    end
    state = tonumber(state) or 0
    if state == 0 or state == 1 or state == 3 then
        creature:SetStandState(state)
    end
end

function PetControlHandlers.Follow(player, follow, distance, angle)
    local creature = GetTargetCreature(player)
    if not IsCompanionOwner(player, creature) then
        NotifyNoControl(player)
        return
    end

    if follow == 1 or follow == true then
        distance = tonumber(distance)
        if distance then
            distance = distance - 2
            if distance > 3 or distance < -2 then
                player:SendNotification("Укажите дистанцию следования от 0 до 5.")
                return
            end
        else
            distance = 0
        end

        angle = tonumber(angle)
        if angle then
            angle = angle * math.pi / 180
        else
            angle = 0.78
        end

        creature:MoveFollow(player, distance, angle)
    else
        creature:MoveExpire()
    end
end

function PetControlHandlers.Play(player, emoteId, repeatFlag)
    local creature = GetTargetCreature(player)
    if not IsCompanionOwner(player, creature) then
        NotifyNoControl(player)
        return
    end
    emoteId = tonumber(emoteId)
    if not emoteId then return end

    if repeatFlag then
        creature:EmoteState(emoteId)
    else
        creature:Emote(emoteId)
    end
end

function PetControlHandlers.Teleport(player)
    local creature = GetTargetCreature(player)
    if not IsCompanionOwner(player, creature) then
        NotifyNoControl(player)
        return
    end
    local x, y, z, o = player:GetLocation()
    creature:NearTeleport(x, y, z, o)
end

NobleNext.RegisterModule("PetControl", { layer = "GM", aio = "NN_PetControl", core = "Custom/NobleNext/Pet" })
NobleNext.Log("PetControl", "registered (C++ commands + AIO)")
