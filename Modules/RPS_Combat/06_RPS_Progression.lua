-- Native levels and XP. RP level = server level - 9, server 10..19 = RP 1..10.
-- Level-up is native and automatic; XP comes only from the DM grant below.
-- No hooks on require. InstallMap runs in every MAP state (ON_GIVE_XP / ON_LEVEL_CHANGE fire there,
-- player->GetEluna() is the map state); InstallWorld runs in the WORLD writer.
local C = require("Modules.RPS_Combat.00_RPS_Config")
local K = require("Modules.RPS_Combat.03_RPS_Catalog")
local V = require("Modules.RPS_Combat.04_RPS_Resolver")

local P = {
    MAX_RP_LEVEL = #K.Xp,
    MIN_SERVER_LEVEL = K.Xp[1].serverLevel,
    MAX_GRANT = K.Xp[#K.Xp].xpStart,
    -- Shared through the C++ WorldObject:Data() cache: the WORLD grant and the MAP hook are different Lua states.
    GRANT_KEY = "rps_dm_xp",
    LEVEL_KEY = "rps_level_changed",
    LocalGuard = {},
}
P.COMBAT_STATS = {"accuracy", "healing", "evasion", "resistance"}
local GIFTED_TRAIT = "odarennost"

local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end

local function DataOf(obj)
    if not obj or not obj.Data then return nil end
    local ok, data = pcall(obj.Data, obj)
    return ok and data or nil
end

local function LowKey(player)
    return C.IdString(player:GetGUIDLow()) or tostring(player:GetGUIDLow())
end

function P.RpLevel(serverLevel)
    return K.RpLevelFromServerLevel(serverLevel) or 1
end

-- ON_GIVE_XP: nil keeps the amount, 0 blocks it. Only a DM grant (no victim, exact guarded amount) passes.
function P.FilterXp(player, amount, victim)
    if type(amount) ~= "number" or amount <= 0 then return nil end
    if victim == nil and player then
        local data = DataOf(player)
        local allowed = data and data:Get(P.GRANT_KEY)
        if allowed == nil then allowed = P.LocalGuard[LowKey(player)] end
        if allowed ~= nil and allowed == amount then return nil end
    end
    return 0
end

function P.MarkLevelChanged(player)
    local data = DataOf(player)
    if data then data:Set(P.LEVEL_KEY, true) end
end

function P.TakeLevelFlag(player)
    local data = DataOf(player)
    if not data or data:Get(P.LEVEL_KEY) == nil then return false end
    data:Set(P.LEVEL_KEY, nil)
    return true
end

-- Calls the native GiveXP with the guard raised only for this exact amount.
function P.GiveGuardedXp(player, amount)
    local key, data = LowKey(player), DataOf(player)
    if data then data:Set(P.GRANT_KEY, amount) end
    P.LocalGuard[key] = amount
    local ok, err = pcall(player.GiveXP, player, amount)
    if data then data:Set(P.GRANT_KEY, nil) end
    P.LocalGuard[key] = nil
    return ok, err
end

function P.InstallMap()
    if P.mapInstalled then return end
    P.mapInstalled = true
    RegisterPlayerEvent(12, function(_, player, amount, victim) return P.FilterXp(player, amount, victim) end)
    RegisterPlayerEvent(13, function(_, player) P.MarkLevelChanged(player) end)
end

local function HasTrait(profile, creation, key)
    if creation and creation.state == "complete" then
        for _, trait in ipairs(creation.traits or {}) do if trait == key then return true end end
        return false
    end
    return profile ~= nil and profile.commonTrait == key
end

-- Confirmed creation choices as a resolver input; nil means "use the archetype table".
function P.SheetInput(creation, rpLevel)
    if type(creation) ~= "table" or creation.state ~= "complete" then return nil end
    return {archetype = creation.archetype, rpLevel = rpLevel, race = creation.race,
        racialFeature = creation.racialFeature, traits = creation.traits,
        traitChoice = creation.traitChoice ~= "" and creation.traitChoice or nil, mastery = creation.mastery}
end

-- Sheet maxima and combat bonuses at one RP level.
function P.Maxima(profile, creation, rpLevel)
    local input = P.SheetInput(creation, rpLevel)
    local sheet = input and V.Resolve(input)
    if sheet then
        local out = {source = "resolver", maxHealth = sheet.maxHealth, maxEnergy = sheet.maxEnergy}
        for _, key in ipairs(P.COMBAT_STATS) do out[key] = sheet[key] end
        return out
    end
    local arch = C.Archetypes[profile.archetype] or C.Archetypes.fighter
    local out = {source = "archetype", maxHealth = arch.health[rpLevel], maxEnergy = arch.energy[rpLevel]}
    for _, key in ipairs(P.COMBAT_STATS) do out[key] = arch.stats[key][rpLevel] end
    return out
end

-- One step per crossed level: maxima and current resources move by the sheet difference.
-- profile.level is the last applied RP level, so a repeat never adds the same step twice.
-- Wounds, the round budget and surplus resources are kept as they are.
function P.ApplyLevels(profile, creation, toRp, copy)
    local from = profile.level
    if not C.Integer(from, 1, P.MAX_RP_LEVEL) or not C.Integer(toRp, 1, P.MAX_RP_LEVEL) or from == toRp then
        return nil
    end
    local draft = copy(profile)
    local dir = toRp > from and 1 or -1
    local steps, prev = {}, P.Maxima(profile, creation, from)
    for level = from + dir, toRp, dir do
        local cur = P.Maxima(profile, creation, level)
        local dh, de = cur.maxHealth - prev.maxHealth, cur.maxEnergy - prev.maxEnergy
        draft.maxHealth = Clamp(draft.maxHealth + dh, 1, C.MAX_RESOURCE)
        draft.curHealth = Clamp(draft.curHealth + dh, 0, C.MAX_RESOURCE)
        draft.maxEnergy = Clamp(draft.maxEnergy + de, 0, C.MAX_RESOURCE)
        draft.curEnergy = Clamp(draft.curEnergy + de, 0, C.MAX_RESOURCE)
        for _, key in ipairs(P.COMBAT_STATS) do
            if draft.stats[key] ~= nil then
                draft.stats[key] = Clamp(draft.stats[key] + cur[key] - prev[key], -1000, 1000)
            end
        end
        steps[#steps + 1] = {rpLevel = level, maxHealth = dh, maxEnergy = de, source = cur.source}
        prev = cur
    end
    draft.level = toRp
    return draft, steps
end

function P.Slots(profile, creation, rpLevel)
    local gifted = HasTrait(profile, creation, GIFTED_TRAIT)
    local list, open, nextUnlock = {}, 0, nil
    for i, slot in ipairs(K.PersonalAbilitySlots) do
        local level = gifted and K.GiftedUnlockLevels[i] or slot.unlockLevel
        local isOpen = rpLevel >= level
        if isOpen then open = open + 1
        elseif not nextUnlock then
            nextUnlock = {rpLevel = level, slot = slot.slot, cost = slot.cost,
                text = string.format("Слот персональной способности %d (%d ОЭ)", slot.slot, slot.cost)}
        end
        list[i] = {slot = slot.slot, cost = slot.cost, unlockLevel = level, open = isOpen}
    end
    return list, open, nextUnlock, gifted
end

function P.Snapshot(player, profile, creation)
    local serverLevel = player:GetLevel()
    local rpLevel = P.RpLevel(serverLevel)
    local atCap = rpLevel >= P.MAX_RP_LEVEL
    local xp = player:GetXP() or 0
    local needed = 0
    if not atCap then
        needed = player:GetXPForNextLevel() or 0
        if needed <= 0 then needed = K.Xp[rpLevel].xpToNext end
    end
    local slots, open, nextUnlock, gifted = P.Slots(profile, creation, rpLevel)
    return {serverLevel = serverLevel, rpLevel = rpLevel, xp = xp, xpNeeded = needed,
        xpTotal = atCap and P.MAX_GRANT or math.min(P.MAX_GRANT, K.Xp[rpLevel].xpStart + xp),
        maxRpLevel = P.MAX_RP_LEVEL, abilitySlots = open, slots = slots, gifted = gifted,
        nextUnlock = nextUnlock, atCap = atCap, sheetLevel = profile and profile.level or nil}
end

-- R = N.RPS (Init), H = the single RPS_Combat handler table.
function P.InstallWorld(R, H)
    if P.world then return P.world end
    local N = require("NobleNext")
    local S, M, AIO, prefix = R.Storage, R.Combat, N.AIO, C.AIO_PREFIX
    local Escape = require("Core.DB").EscapeSqlString
    local W = {Grants = {}, RetryAt = {}}
    P.world = W
    local readTicks = {}
    local function Id(player) return C.IdString(player:GetGUIDLow()) end
    local function Q(value) return "'" .. Escape(value or "") .. "'" end
    local function Creation(guid)
        local rec = S.Creation and S.Creation[guid]
        if rec == nil and S.GetOrLoadCreation then rec = S.GetOrLoadCreation(guid) end
        return rec
    end

    function W.Push(player, extra)
        local guid = Id(player)
        local profile = S.PlayerProfiles[guid]
        local payload = P.Snapshot(player, profile, profile and Creation(guid) or nil)
        for key, value in pairs(extra or {}) do payload[key] = value end
        AIO.Handle(player, prefix, "Progression", payload)
        return payload
    end

    -- Applies native level changes to the cached RP sheet once. Returns true when a commit started.
    function W.Reconcile(player)
        local guid = Id(player)
        local p = guid and S.PlayerProfiles[guid]
        local rp = P.RpLevel(player:GetLevel())
        if not p or p.level == rp or R.Locks["p:" .. guid] then return false end
        if W.RetryAt[guid] and os.time() < W.RetryAt[guid] then return false end
        local draft, steps = P.ApplyLevels(p, Creation(guid), rp, S.CopyProfile)
        if not draft then return false end
        R.Locks["p:" .. guid] = true
        local locator, from = player:GetGUID(), p.level
        S.SaveProfiles({draft}, function(saved, why)
            R.Locks["p:" .. guid] = nil
            if not saved then
                W.RetryAt[guid] = os.time() + 30
                N.Log("RPS_Progression", "level_sync_failed guid=" .. guid .. " rp=" .. from .. "->" .. rp .. " reason=" .. tostring(why))
                return
            end
            W.RetryAt[guid] = nil
            N.Log("RPS_Progression", string.format("level_sync guid=%s rp=%d->%d steps=%d maxHealth=%d maxEnergy=%d source=%s",
                guid, from, rp, #steps, draft.maxHealth, draft.maxEnergy, steps[#steps].source))
            local current = GetPlayerByGUID(locator)
            if not current then return end
            R.SyncPlayerState(current)
            if M and M.BroadcastUnitUpdate then M.BroadcastUnitUpdate(current, AIO) end
            W.Push(current, {levelUp = {from = from, to = rp}})
        end)
        return true
    end

    function W.RequestProgression(player)
        local key = Id(player)
        local now = GetCurrTime()
        if readTicks[key] and now >= readTicks[key] and now - readTicks[key] < 300 then return end
        readTicks[key] = now
        if R.ready then W.Reconcile(player) end
        W.Push(player)
    end

    local function FindPlayer(wanted)
        for _, other in ipairs(GetPlayersInWorld() or {}) do
            if R.NormalizeWireGuid(other:GetGUID()) == wanted then return other end
        end
    end

    local function Remember(seen, requestId, record)
        local count, oldestId, oldest = 0, nil, nil
        for id, prior in pairs(seen) do
            count = count + 1
            if prior.result and (not oldest or prior.created < oldest) then oldestId, oldest = id, prior.created end
        end
        if count >= 64 and oldestId then seen[oldestId] = nil end
        record.created = os.time()
        seen[requestId] = record
    end

    -- DmGrantXp(targetGuid, amount, reason, requestId) -> DmGrantXpResult({ok, code?, requestId, newLevel, newXp}).
    function W.DmGrantXp(player, targetGuid, amount, reason, requestId)
        local valid = type(requestId) == "string" and #requestId >= 1 and #requestId <= 80
            and requestId:match("^[%w_-]+$") ~= nil
        local function Reply(result)
            result.requestId = valid and requestId or nil
            AIO.Handle(player, prefix, "DmGrantXpResult", result)
        end
        if not valid then return Reply({ok = false, code = "invalid_request_id"}) end
        if not R.ready then return Reply({ok = false, code = "system_unavailable"}) end
        local issuer = Id(player)
        if not N.HasStaffPermission(player) then
            N.Log("RPS_Progression", "xp_grant_denied issuer=" .. tostring(issuer) .. " request=" .. requestId)
            return Reply({ok = false, code = "permission_denied"})
        end
        if not C.Integer(amount, 1, P.MAX_GRANT) then return Reply({ok = false, code = "invalid_amount"}) end
        reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
        if #reason < 3 or #reason > 200 or reason:find("%c") then return Reply({ok = false, code = "invalid_reason"}) end
        local wanted = R.NormalizeWireGuid(targetGuid)
        if not wanted then return Reply({ok = false, code = "invalid_target"}) end

        local signature = "xp:" .. wanted .. ":" .. amount .. ":" .. reason
        local seen = W.Grants[issuer] or {}
        W.Grants[issuer] = seen
        local prior = seen[requestId]
        if prior then
            if prior.signature ~= signature then return Reply({ok = false, code = "request_conflict"}) end
            if not prior.result then return Reply({ok = false, code = "request_pending"}) end
            local copy = {}
            for key, value in pairs(prior.result) do copy[key] = value end
            copy.duplicate = true
            return Reply(copy)
        end
        local where = " WHERE issuer_guid=" .. issuer .. " AND request_id=" .. Q(requestId)
        local count = CharDBQuery("SELECT COUNT(*) FROM rps_action_receipts" .. where)
        if not count then return Reply({ok = false, code = "receipt_unavailable"}) end
        if count:GetUInt32(0) > 0 then
            local q = CharDBQuery("SELECT signature,state,total,damage FROM rps_action_receipts" .. where)
            if not q then return Reply({ok = false, code = "receipt_unavailable"}) end
            if q:GetString(0) ~= signature then return Reply({ok = false, code = "request_conflict"}) end
            local result = {ok = true, newLevel = q:GetInt32(3), targetGuid = wanted}
            Remember(seen, requestId, {signature = signature, result = result})
            local copy = {duplicate = true}
            for key, value in pairs(result) do copy[key] = value end
            return Reply(copy)
        end

        local target = FindPlayer(wanted)
        if not target then return Reply({ok = false, code = "target_unavailable"}) end
        local beforeLevel, beforeXp = target:GetLevel(), target:GetXP()
        if P.RpLevel(beforeLevel) >= P.MAX_RP_LEVEL then
            return Reply({ok = false, code = "at_cap", newLevel = beforeLevel, newXp = beforeXp})
        end
        if target.IsAlive and not target:IsAlive() then return Reply({ok = false, code = "target_dead"}) end

        local record = {signature = signature}
        Remember(seen, requestId, record)
        local given, err = P.GiveGuardedXp(target, amount)
        local afterLevel, afterXp = target:GetLevel(), target:GetXP()
        if not given or (afterLevel == beforeLevel and afterXp == beforeXp) then
            seen[requestId] = nil
            N.Log("RPS_Progression", "xp_grant_not_applied issuer=" .. issuer .. " target=" .. wanted
                .. " amount=" .. amount .. " error=" .. tostring(err))
            return Reply({ok = false, code = "xp_not_applied"})
        end
        if target.SaveToDB then target:SaveToDB() end
        local result = {ok = true, newLevel = afterLevel, newXp = afterXp, rpLevel = P.RpLevel(afterLevel),
            levelsGained = afterLevel - beforeLevel, targetGuid = wanted, amount = amount}
        N.Log("RPS_Progression", string.format("xp_grant issuer=%s target=%s amount=%d level=%d->%d xp=%d->%d request=%s reason=%s",
            issuer, wanted, amount, beforeLevel, afterLevel, beforeXp, afterXp, requestId, reason))
        if target.SendBroadcastMessage then
            target:SendBroadcastMessage("Ведущий начислил опыт: +" .. amount .. " (" .. reason .. ")")
        end
        if not W.Reconcile(target) then W.Push(target) end

        local sql = string.format([[INSERT INTO rps_action_receipts
            (issuer_guid,request_id,signature,state,result_kind,stat_key,total,damage,attack_id)
            VALUES (%s,%s,%s,'done','xp_grant','',%d,%d,%s)]], issuer, Q(requestId), Q(signature), amount, afterLevel,
            Q(C.IdString(target:GetGUIDLow()) or ""))
        local locator, entered = player:GetGUID(), false
        local function Done(saved)
            entered = true
            if not saved then
                result.code = "receipt_failed"
                N.Log("RPS_Progression", "xp_grant_receipt_failed issuer=" .. issuer .. " request=" .. requestId)
            end
            record.result = result
            local current = GetPlayerByGUID(locator)
            if current then
                local copy = {requestId = requestId}
                for key, value in pairs(result) do copy[key] = value end
                AIO.Handle(current, prefix, "DmGrantXpResult", copy)
            end
        end
        local called = pcall(RpsCommitAsync, "characters", {sql}, Done)
        if not called and not entered then Done(false) end
    end

    H.RequestProgression = W.RequestProgression
    H.DmGrantXp = W.DmGrantXp

    -- Picks up native level changes from any source (DM grant, GM .levelup, MAP hook flag, login).
    CreateLuaEvent(function()
        if not R.ready then return end
        for _, player in ipairs(GetPlayersInWorld() or {}) do
            if player.GetLevel then
                local flagged = P.TakeLevelFlag(player)
                if not W.Reconcile(player) and flagged then W.Push(player) end
            end
        end
    end, 1000, 0)
    return W
end

return P
