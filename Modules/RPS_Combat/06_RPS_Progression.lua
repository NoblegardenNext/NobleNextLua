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
local GIFTED_TRAIT = "gifted"

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
    local W = {Grants = {}, RetryAt = {}, PendingTargets = {}, Checked = {}}
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
        if W.PendingTargets[guid] then return end
        local profile = S.PlayerProfiles[guid]
        local payload = P.Snapshot(player, profile, profile and Creation(guid) or nil)
        for key, value in pairs(extra or {}) do payload[key] = value end
        AIO.Handle(player, prefix, "Progression", payload)
        return payload
    end

    -- Applies native level changes to the cached RP sheet once. Returns true when a commit started.
    function W.Reconcile(player)
        local guid = Id(player)
        if not W.Checked[guid] then W.Recover(player) end
        if not W.Checked[guid] or W.PendingTargets[guid] then return false end
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

    local function Where(issuer, requestId)
        return " WHERE issuer_guid=" .. issuer .. " AND request_id=" .. Q(requestId)
    end

    local function Reply(issuer, requestId, result)
        local current = FindPlayer(issuer)
        if not current then return end
        local copy = {requestId = requestId}
        for key, value in pairs(result) do copy[key] = value end
        AIO.Handle(current, prefix, "DmGrantXpResult", copy)
    end

    local function NativeXpCurve(target)
        if type(RpsXpGrantContext) ~= "function" then return nil, "xp_commit_unavailable" end
        local maxLevel = P.MIN_SERVER_LEVEL + P.MAX_RP_LEVEL - 1
        local cap, blocked, curve = RpsXpGrantContext(target, P.MIN_SERVER_LEVEL, maxLevel)
        if cap ~= maxLevel then return nil, "xp_level_cap_mismatch" end
        if blocked then return nil, "xp_gain_blocked" end
        for _, step in ipairs(K.Xp) do
            if step.serverLevel < maxLevel and curve[step.serverLevel] ~= step.xpToNext then return nil, "xp_curve_mismatch" end
        end
        return curve
    end

    -- The persisted intent fixes both endpoints before native state can change.
    local function Plan(target, amount, reason, wanted)
        local level, xp = target:GetLevel(), target:GetXP()
        local index = level - P.MIN_SERVER_LEVEL + 1
        if not K.Xp[index] or index >= P.MAX_RP_LEVEL then return nil, "invalid_native_level" end
        local curve, why = NativeXpCurve(target)
        if not curve then return nil, why end
        if target:GetXPForNextLevel() ~= K.Xp[index].xpToNext then return nil, "xp_curve_mismatch" end
        local nextLevel, nextXp = level, xp + amount
        while index < P.MAX_RP_LEVEL and nextXp >= K.Xp[index].xpToNext do
            nextXp = nextXp - K.Xp[index].xpToNext
            nextLevel, index = nextLevel + 1, index + 1
        end
        return {version = 1, beforeLevel = level, beforeXp = xp, amount = amount, reason = reason,
            targetGuid = wanted, targetLow = Id(target), result = {ok = true, newLevel = nextLevel,
                newXp = nextXp, rpLevel = P.RpLevel(nextLevel), levelsGained = nextLevel - level,
                targetGuid = wanted, amount = amount}}
    end

    local function ValidPlan(plan)
        return type(plan) == "table" and plan.version == 1 and type(plan.result) == "table"
            and C.Integer(plan.beforeLevel, P.MIN_SERVER_LEVEL, P.MIN_SERVER_LEVEL + P.MAX_RP_LEVEL - 2)
            and C.Integer(plan.beforeXp, 0, P.MAX_GRANT) and C.Integer(plan.amount, 1, P.MAX_GRANT)
            and C.Integer(plan.result.newLevel, plan.beforeLevel, P.MIN_SERVER_LEVEL + P.MAX_RP_LEVEL - 1)
            and C.Integer(plan.result.newXp, 0, P.MAX_GRANT * 2)
            and type(plan.targetGuid) == "string" and C.IdString(plan.targetLow) ~= nil
            and type(plan.reason) == "string"
    end

    local function Release(record)
        local guid = record.plan.targetLow
        if W.PendingTargets[guid] == record then W.PendingTargets[guid] = nil end
        if R.Locks["p:" .. guid] == record then R.Locks["p:" .. guid] = nil end
        W.RetryAt[guid] = nil
    end

    local function Resume(record)
        if record.busy then return end
        local plan, issuer, requestId = record.plan, record.issuer, record.requestId
        local target = FindPlayer(plan.targetGuid)
        local function Pending(why)
            record.busy = false
            W.RetryAt[plan.targetLow] = os.time() + 30
            N.Log("RPS_Progression", "xp_pending request=" .. requestId .. " reason=" .. tostring(why))
            Reply(issuer, requestId, {ok = false, code = "pending_recovery"})
        end
        if not record.intentConfirmed then
            local count = CharDBQuery("SELECT COUNT(*) FROM rps_action_receipts" .. Where(record.issuerLow, requestId))
            if not count then return Pending("intent_unknown") end
            if count:GetUInt32(0) == 0 then
                Release(record)
                W.Checked[plan.targetLow] = nil
                local seen = W.Grants[record.issuerLow]
                if seen and seen[requestId] == record then seen[requestId] = nil end
                return Reply(issuer, requestId, {ok = false, code = "save_failed"})
            end
            local q = CharDBQuery("SELECT signature,state FROM rps_action_receipts" .. Where(record.issuerLow, requestId))
            if not q or q:GetString(0) ~= record.signature or q:GetString(1) ~= "pending" then return Pending("intent_unknown") end
            record.intentConfirmed = true
        end
        if not target then return Pending("target_unavailable") end
        local level, xp = target:GetLevel(), target:GetXP()
        if level == plan.beforeLevel and xp == plan.beforeXp then
            local curve, why = NativeXpCurve(target)
            if not curve then return Pending(why) end
            local given = P.GiveGuardedXp(target, plan.amount)
            if not given then return Pending("xp_not_applied") end
        end
        -- A reload may find the native change already applied. Never add the amount twice.
        if target:GetLevel() ~= plan.result.newLevel or target:GetXP() ~= plan.result.newXp then
            return Pending("native_state_conflict")
        end
        local payload = assert(S.EncodeReceipt(plan))
        local sql = "UPDATE rps_action_receipts SET state='done',result_payload=" .. Q(payload)
            .. Where(record.issuerLow, requestId) .. " AND state='pending'"
        record.busy = true
        local entered = false
        local function Done(saved)
            entered = true
            if not saved then return Pending("save_failed") end
            record.busy, record.result = false, plan.result
            Release(record)
            W.Checked[plan.targetLow] = true
            N.Log("RPS_Progression", "xp_grant issuer=" .. record.issuerLow .. " target=" .. plan.targetGuid
                .. " amount=" .. plan.amount .. " request=" .. requestId .. " reason=" .. plan.reason)
            local current = FindPlayer(plan.targetGuid)
            if current then
                if current.SendBroadcastMessage then
                    current:SendBroadcastMessage("Ведущий начислил опыт: +" .. plan.amount .. " (" .. plan.reason .. ")")
                end
                if not W.Reconcile(current) then W.Push(current) end
            end
            Reply(issuer, requestId, plan.result)
        end
        local called = pcall(RpsSaveXpAsync, target, {sql}, Done)
        if not called and not entered then Done(false) end
    end

    local function Restore(issuerLow, issuer, requestId, signature, payload)
        local plan, why = S.DecodeReceipt(payload)
        if not ValidPlan(plan) then return nil, why or "receipt_incomplete" end
        local guid = plan.targetLow
        local record = W.PendingTargets[guid]
        if record and (record.issuerLow ~= issuerLow or record.requestId ~= requestId) then return nil, "pending_recovery" end
        if not record then
            if R.Locks["p:" .. guid] then return nil, "actor_busy" end
            record = {issuerLow = issuerLow, issuer = issuer, requestId = requestId, signature = signature, plan = plan}
            R.Locks["p:" .. guid], W.PendingTargets[guid] = record, record
        end
        record.intentConfirmed = true
        record.issuer = issuer or record.issuer
        return record
    end

    -- A committed intent survives logout, Lua reload and a server crash. Recovery
    -- accepts only its before/after endpoints; unrelated native changes need reconciliation.
    function W.Recover(target)
        local guid = Id(target)
        local active = W.PendingTargets[guid]
        if active then
            if not W.RetryAt[guid] or os.time() >= W.RetryAt[guid] then Resume(active) end
            return
        end
        local where = " WHERE result_kind='xp_grant' AND state='pending' AND attack_id=" .. Q(guid)
        local count = CharDBQuery("SELECT COUNT(*) FROM rps_action_receipts" .. where)
        if not count then return end
        if count:GetUInt32(0) == 0 then W.Checked[guid] = true; return end
        local q = CharDBQuery("SELECT issuer_guid,request_id,signature,result_payload FROM rps_action_receipts" .. where)
        if not q or count:GetUInt32(0) ~= 1 then return end
        local issuerLow = C.IdString(q:GetUInt64(0))
        local issuer = nil
        for _, player in ipairs(GetPlayersInWorld() or {}) do if Id(player) == issuerLow then issuer = R.NormalizeWireGuid(player:GetGUID()) end end
        local record = Restore(issuerLow, issuer, q:GetString(1), q:GetString(2), q:GetString(3))
        if record then Resume(record) end
    end

    function W.DmGrantXp(player, targetGuid, amount, reason, requestId)
        local valid = type(requestId) == "string" and #requestId >= 1 and #requestId <= 80
            and requestId:match("^[%w_-]+$") ~= nil
        local issuer, issuerWire = Id(player), R.NormalizeWireGuid(player:GetGUID())
        local function Fail(code) Reply(issuerWire, valid and requestId or nil, {ok = false, code = code}) end
        if not valid then return Fail("invalid_request_id") end
        if not R.ready then return Fail("system_unavailable") end
        if not N.HasStaffPermission(player) then return Fail("permission_denied") end
        if type(RpsSaveXpAsync) ~= "function" or type(RpsXpGrantContext) ~= "function" then return Fail("xp_commit_unavailable") end
        if not C.Integer(amount, 1, P.MAX_GRANT) then return Fail("invalid_amount") end
        reason = type(reason) == "string" and reason:match("^%s*(.-)%s*$") or ""
        if #reason < 3 or #reason > 200 or reason:find("%c") then return Fail("invalid_reason") end
        local wanted = R.NormalizeWireGuid(targetGuid)
        if not wanted then return Fail("invalid_target") end
        local signature = "xp:" .. wanted .. ":" .. amount .. ":" .. reason
        local seen = W.Grants[issuer] or {}; W.Grants[issuer] = seen
        local prior = seen[requestId]
        if prior then
            if prior.signature ~= signature then return Fail("request_conflict") end
            if prior.result then
                local result = {duplicate = true}
                for key, value in pairs(prior.result) do result[key] = value end
                return Reply(issuerWire, requestId, result)
            end
            if prior.busy then return Fail("request_pending") end
        end
        local where = Where(issuer, requestId)
        local count = CharDBQuery("SELECT COUNT(*) FROM rps_action_receipts" .. where)
        if not count then return Fail("receipt_unavailable") end
        if count:GetUInt32(0) > 0 then
            local q = CharDBQuery("SELECT signature,state,result_payload FROM rps_action_receipts" .. where)
            if not q then return Fail("receipt_unavailable") end
            if q:GetString(0) ~= signature then return Fail("request_conflict") end
            local plan = S.DecodeReceipt(q:GetString(2))
            if not ValidPlan(plan) then return Fail("receipt_incomplete") end
            if q:GetString(1) == "done" then
                local active = W.PendingTargets[plan.targetLow]
                if active and active.issuerLow == issuer and active.requestId == requestId then Release(active) end
                local record = {signature = signature, result = plan.result}
                Remember(seen, requestId, record)
                local result = {duplicate = true}
                for key, value in pairs(plan.result) do result[key] = value end
                return Reply(issuerWire, requestId, result)
            end
            local record, why = Restore(issuer, issuerWire, requestId, signature, q:GetString(2))
            if not record then return Fail(why) end
            Remember(seen, requestId, record)
            return Resume(record)
        end
        local target = FindPlayer(wanted)
        if not target then return Fail("target_unavailable") end
        if P.RpLevel(target:GetLevel()) >= P.MAX_RP_LEVEL then
            return Reply(issuerWire, requestId, {ok = false, code = "at_cap", newLevel = target:GetLevel(), newXp = target:GetXP()})
        end
        if target.IsAlive and not target:IsAlive() then return Fail("target_dead") end
        W.Recover(target)
        if not W.Checked[Id(target)] or W.PendingTargets[Id(target)] then return Fail("pending_recovery") end
        local plan, why = Plan(target, amount, reason, wanted)
        if not plan then return Fail(why) end
        local payload = assert(S.EncodeReceipt(plan))
        local record
        record, why = Restore(issuer, issuerWire, requestId, signature, payload)
        if not record then return Fail(why) end
        Remember(seen, requestId, record)
        record.busy, record.intentConfirmed = true, false
        local sql = string.format([[INSERT INTO rps_action_receipts
            (issuer_guid,request_id,signature,state,result_kind,stat_key,total,damage,attack_id,result_payload)
            VALUES (%s,%s,%s,'pending','xp_grant','',%d,%d,%s,%s)]], issuer, Q(requestId), Q(signature), amount,
            plan.result.newLevel, Q(plan.targetLow), Q(payload))
        local entered = false
        local function Intended(saved)
            entered = true
            record.busy = false
            record.intentConfirmed = saved == true
            Resume(record)
        end
        local called = pcall(RpsCommitAsync, "characters", {sql}, Intended)
        if not called and not entered then Intended(false) end
    end

    H.RequestProgression = W.RequestProgression
    H.DmGrantXp = W.DmGrantXp

    -- Picks up native level changes from any source (DM grant, GM .levelup, MAP hook flag, login).
    CreateLuaEvent(function()
        if not R.ready then return end
        for _, player in ipairs(GetPlayersInWorld() or {}) do
            if player.GetLevel then
                if not W.Checked[Id(player)] or W.PendingTargets[Id(player)] then W.Recover(player) end
                local flagged = P.TakeLevelFlag(player)
                if not W.Reconcile(player) and flagged then W.Push(player) end
            end
        end
    end, 1000, 0)
    return W
end

return P
