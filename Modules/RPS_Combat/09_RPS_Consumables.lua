local C = require("Modules.RPS_Combat.00_RPS_Config")
local Definitions = require("Modules.RPS_Combat.08_RPS_ConsumableCatalog")
local I = {}

-- A full resource is a rejected use, so a potion is never wasted by a retry.
function I.Plan(profile, definition)
    if type(profile) ~= "table" or not profile.isPlayer then return nil, "Допустима только цель-игрок" end
    if profile.deathOutcome == "death" or profile.curHealth <= 0
        or (profile.curWounds or 0) >= (profile.maxWounds or 3) then return nil, "Цель не может использовать зелье" end
    if not definition or (definition.resource ~= "curHealth" and definition.resource ~= "curEnergy")
        or definition.maximum ~= (definition.resource == "curHealth" and "maxHealth" or "maxEnergy")
        or not C.Integer(definition.amount, 1, C.MAX_RESOURCE) then return nil, "Неизвестное зелье" end
    local current, maximum = profile[definition.resource], profile[definition.maximum]
    if not C.Integer(current, 0, C.MAX_RESOURCE) or not C.Integer(maximum, 0, C.MAX_RESOURCE) then
        return nil, "Некорректный ресурс"
    end
    if current >= maximum then return nil, "Ресурс уже заполнен" end
    return math.min(maximum, current + definition.amount)
end

function I.InstallMap()
    for entry in pairs(Definitions) do
        RegisterItemEvent(entry, 2, function(_, player, item, target)
            target = target or player:GetSelection() or player
            target = target.ToPlayer and target:ToPlayer()
            if not target then
                player:SendBroadcastMessage("Зелья пока можно применять только на себя и игроков, не на НИП")
            elseif not RpsQueueConsumableUse then
                player:SendBroadcastMessage("Зелья недоступны: серверный обработчик не загружен")
            elseif not RpsQueueConsumableUse(player, item, target) then
                player:SendBroadcastMessage("Зелье недоступно: проверьте бой, расстояние и дождитесь предыдущего действия")
            end
            return false
        end)
    end
end

-- Replacing a receipt is allowed only for a different entry reusing the GUID.
-- The exact previous payload prevents a stale replacement from overwriting a newer use.
function I.ReceiptStatements(requestId, signature, payload, previous)
    local DB = require("Core.DB")
    local function Q(value) return "'" .. DB.EscapeSqlString(value) .. "'" end
    local statements = {}
    if previous then
        statements[1] = "DELETE FROM rps_action_receipts WHERE issuer_guid=0 AND request_id=" .. Q(requestId)
            .. " AND signature=" .. Q(previous.signature) .. " AND result_payload=" .. Q(previous.payload)
            .. " AND state='done' AND result_kind='consumable'"
    end
    statements[#statements+1] = "INSERT INTO rps_action_receipts (issuer_guid, request_id, signature, state, result_kind, result_payload) VALUES (0,"
        .. Q(requestId) .. "," .. Q(signature) .. ",'done','consumable'," .. Q(payload) .. ")"
    return statements
end

function I.InstallWorld(R, H)
    local S = R.Storage
    local DB = require("Core.DB")
    local function Q(value) return "'" .. DB.EscapeSqlString(value) .. "'" end
    local function Id(player) return C.IdString(player:GetGUIDLow()) end
    local function Notice(player, message) if player then player:SendBroadcastMessage(message) end end
    local function Log(message) require("NobleNext").Log("RPS_Combat", message) end
    local function InBattle(guid)
        for _, attack in pairs(R.PendingAttacks or {}) do
            if attack.attackerGuid == guid or attack.defenderGuid == guid then return true end
        end
        return false
    end
    local function Reply(player, target, result)
        Notice(player, "Зелье использовано: +" .. result.amount .. (result.resource == "curHealth" and " ОЗ" or " ОЭ"))
        if target then
            if R.SyncPlayerState then R.SyncPlayerState(target) end
            if R.Combat.BroadcastUnitUpdate then R.Combat.BroadcastUnitUpdate(target, require("NobleNext").AIO) end
        end
    end
    local function Receipt(itemGuid)
        local prior = CharDBQuery("SELECT signature, state, result_payload, result_kind FROM rps_action_receipts WHERE issuer_guid=0 AND request_id="
            .. Q("consume_" .. itemGuid))
        if not prior then return end
        local payload = prior:GetString(2)
        local result = prior:GetString(1) == "done" and prior:GetString(3) == "consumable" and S.DecodeReceipt(payload)
        if type(result) ~= "table" or result.kind ~= "consumable" or result.itemGuid ~= itemGuid
            or not C.Integer(result.entry, 1, 2147483647) or type(result.ownerGuid) ~= "string" or type(result.targetGuid) ~= "string"
            or C.IdString(result.ownerGuid) ~= result.ownerGuid or C.IdString(result.targetGuid) ~= result.targetGuid
            or (result.resource ~= "curHealth" and result.resource ~= "curEnergy")
            or not C.Integer(result.amount, 1, C.MAX_RESOURCE) or not C.Integer(result.value, result.amount, C.MAX_RESOURCE)
            or prior:GetString(0) ~= result.ownerGuid .. ":" .. result.targetGuid .. ":" .. result.entry then
            return false
        end
        return {result=result, signature=prior:GetString(0), payload=payload}
    end
    local function RemoveConsumed(player, itemGuid, entry)
        local item = RpsFindOwnedItem(player, itemGuid)
        if not item or item:GetEntry() ~= entry then return end
        Log("consumed_item_recovered:" .. itemGuid .. ":" .. entry .. ":" .. Id(player))
        if item:IsInTrade() then return end
        player:RemoveItem(item, 1)
    end
    function I.Recover(player)
        -- Current client inventory: backpack/bank in bag 255, carried bags 30..34.
        -- Recovery runs on login, never as a periodic inventory scan.
        local function Check(item)
            if not item or not Definitions[item:GetEntry()] then return end
            local guid = tostring(item:GetGUID())
            local prior = Receipt(guid)
            if prior and prior.result.entry == item:GetEntry() then RemoveConsumed(player, guid, item:GetEntry()) end
        end
        for slot=0,254 do Check(player:GetItemByPos(255,slot)) end
        for bag=30,34 do
            local container = player:GetItemByPos(255,bag)
            if container then
                for slot=0,container:GetBagSize()-1 do Check(player:GetItemByPos(bag,slot)) end
            end
        end
    end
    function I.Use(player, target, itemGuid)
        if not R.ready then Notice(player, "Ролевая система недоступна"); return end
        target = target and target.ToPlayer and target:ToPlayer()
        if type(itemGuid) ~= "string" or #itemGuid > 72 or not itemGuid:match("^[%w%-]+$")
            or not target then Notice(player, "Неверный предмет или цель: допустимы только игроки"); return end
        local requestId = "consume_" .. itemGuid
        local issuer, receiver = Id(player), Id(target)
        local itemKey = "item:" .. itemGuid
        if R.Locks[itemKey] then Notice(player, "Предыдущее действие ещё обрабатывается"); return end
        local item = RpsFindOwnedItem(player, itemGuid)
        local prior = Receipt(itemGuid)
        if prior == false then Notice(player, "Не удалось проверить сохранённый результат зелья"); return end
        if prior and (not item or item:GetEntry() == prior.result.entry) then
            RemoveConsumed(player, itemGuid, prior.result.entry)
            if not item and prior.result.ownerGuid == issuer and prior.result.targetGuid == receiver then
                Reply(player, target, prior.result)
            else Notice(player, "Предмет уже использован") end
            return prior.result
        end
        if not player:IsAlive() or not target:IsAlive() or player:IsInCombat() or target:IsInCombat()
            or InBattle(issuer) or InBattle(receiver) or not RpsConsumableContext(player, target) then
            Notice(player, "Зелье можно применить только к живому игроку рядом вне боя"); return
        end
        if R.Locks["p:" .. issuer] or R.Locks["p:" .. receiver] then Notice(player, "Предыдущее действие ещё обрабатывается"); return end
        local entry = item and item:GetEntry()
        local definition = entry and Definitions[entry]
        local bag, slot = item and item:GetBagSlot(), item and item:GetSlot()
        local carried = bag and ((bag == 255 and slot >= 35 and slot < 63) or (bag >= 30 and bag <= 34))
        if not definition or not carried or item:GetCount() ~= 1 or item:GetMaxStackCount() ~= 1 or item:IsInTrade() then Notice(player, "Зелье не найдено в сумке"); return end
        local source = S.ResolveUnitStats(player)
        local profile = S.ResolveUnitStats(target)
        if not source or source.curHealth <= 0 or source.deathOutcome == "death"
            or (source.curWounds or 0) >= (source.maxWounds or 3) then Notice(player, "Персонаж не может использовать зелье"); return end
        local value, why = I.Plan(profile, definition)
        if not value then Notice(player, why); return end
        local draft = S.CopyProfile(profile)
        draft[definition.resource] = value
        local result = {kind="consumable", itemGuid=itemGuid, entry=entry, ownerGuid=issuer, targetGuid=receiver,
            resource=definition.resource, amount=value-profile[definition.resource], value=value}
        local payload = S.EncodeReceipt(result)
        if not payload then Notice(player, "Не удалось подготовить сохранение"); return end
        local signature = issuer .. ":" .. receiver .. ":" .. entry
        local actorGuid, targetGuid = player:GetGUID(), target:GetGUID()
        R.Locks["p:" .. issuer], R.Locks["p:" .. receiver], R.Locks[itemKey] = true, true, true
        S.SaveProfiles({draft}, function(ok)
            R.Locks["p:" .. issuer], R.Locks["p:" .. receiver], R.Locks[itemKey] = nil, nil, nil
            local actor, recipient = GetPlayerByGUID(actorGuid), GetPlayerByGUID(targetGuid)
            if ok then Reply(actor, recipient, result)
            else Notice(actor, "Зелье не израсходовано: запись не подтверждена") end
        end, function(pool, statements, callback)
            if pool ~= "characters" then callback(false); return end
            RpsCommitAsync(pool, statements, function(ok)
                if ok then
                    -- The item may have changed owners while the DB was working.
                    -- Offline owners recover on login; no live userdata crosses the commit.
                    for _, current in ipairs(GetPlayersInWorld()) do RemoveConsumed(current, itemGuid, entry) end
                end
                callback(ok)
            end)
        end, {characters=I.ReceiptStatements(requestId, signature, payload, prior)})
    end
    H.UseConsumable = function(player, itemGuid) I.Use(player, player:GetSelection() or player, itemGuid) end
    CreateLuaEvent(function()
        if not RpsPollConsumableUses then return end
        for _, use in ipairs(RpsPollConsumableUses()) do I.Use(use.player, use.target, use.itemGuid) end
    end, 100, 0)
    return I
end

return I
