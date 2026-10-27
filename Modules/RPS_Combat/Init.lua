-- WORLD owner for AIO, profiles and reaction queues.
if not _G.NN_BOOTSTRAP_ACTIVE then return end
local N = require("NobleNext")
if not N.IsMainState() then return end
if N.RPS then return N.RPS end
local C = require("Modules.RPS_Combat.00_RPS_Config")
local S = require("Modules.RPS_Combat.01_RPS_Storage")
local M = require("Modules.RPS_Combat.02_RPS_Combat")
local R = {Config=C,Storage=S,Combat=M,PendingAttacks={},Locks={},Seen={},SpellStatuses={},LearnFailed={},
    ActionSpellStatuses={},LastReaction={}}
N.RPS = R
local AIO, prefix = N.AIO, C.AIO_PREFIX
local function Id(player) return C.IdString(player:GetGUIDLow()) end
local function Actor(p) return p.isPlayer and "p:"..p.guid or "n:"..p.runtimeKey end
local function Player(guid) return GetPlayerByGUID(guid) end
local function Error(player, code, requestId)
    if type(requestId)~="string" or #requestId>80 then requestId=nil end
    if player then AIO.Handle(player,prefix,"Error",{code=code,requestId=requestId,reason=code=="system_unavailable" and R.unavailableReason or nil}) end
end
local function Target(player)
    local target = player:GetSelection()
    if target and RpsTargetContext(player,target,false) then return target end
end
local function ExtractLowGuid(guidStr)
    if type(guidStr)~="string" or guidStr=="" then return nil end
    if guidStr:match("^%d+$") then return C.IdString(guidStr) end
    local hex=guidStr:match("^%a+%-.*%-(%x+)$")
    if hex and #hex<=13 then
        local n=tonumber(hex,16)
        if n and n<=9007199254740991 then return C.IdString(n) end
    end
    local tail=guidStr:match("-(%d+)$")
    if tail then return C.IdString(tail) end
    return nil
end
-- Wire GUID contract: the server's tostring(ObjectGuid) and the client's UnitGUID share
-- one text format; this block must stay byte-identical to Addons/NobleNext/Core/RPSClient.lua.
local WIRE_GUID_KINDS = {
    player = "Player", creature = "Creature", pet = "Pet", vehicle = "Vehicle", gameobject = "GameObject",
}
local function NormalizeWireGuid(value)
    if type(value) ~= "string" then
        if type(value) ~= "userdata" then return nil end
        value = tostring(value)
    end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or #value > 128 then return nil end
    local kind, rest = value:match("^(%a+)%-([%w%-]+)$")
    if not kind or rest:find("%-%-") or rest:find("^%-") or rest:sub(-1) == "-" then return nil end
    return (WIRE_GUID_KINDS[kind:lower()] or kind) .. "-" .. rest:upper()
end
R.NormalizeWireGuid=NormalizeWireGuid
-- lookup: optional per-request {players=map, creatures=map} keyed by canonical wire GUID,
-- built once so a batch of nameplate GUIDs does not rescan the world for every entry.
local function BuildUnitLookup(player)
    local lookup={players={},creatures={}}
    for _,plr in ipairs(GetPlayersInWorld and GetPlayersInWorld() or {}) do
        local key=NormalizeWireGuid(plr:GetGUID())
        if key then lookup.players[key]=plr end
    end
    if player.GetCreaturesInRange then
        for _,cre in ipairs(player:GetCreaturesInRange(100) or {}) do
            local key=NormalizeWireGuid(cre:GetGUID())
            if key then lookup.creatures[key]=cre end
        end
    end
    return lookup
end
-- Full-GUID match only: low counters repeat across types, maps and instances.
-- A bare decimal low GUID (legacy clients) is accepted for the current selection only.
local function ResolveUnitForPlayerByGuid(player, guidStr, lookup)
    if not player or type(guidStr)~="string" or guidStr=="" or #guidStr>128 then return nil end
    local sel=player:GetSelection()
    local wanted=NormalizeWireGuid(guidStr)
    if not wanted then
        local low=guidStr:match("^%d+$") and ExtractLowGuid(guidStr)
        if low and sel and C.IdString(sel:GetGUIDLow())==low and RpsTargetContext(player,sel,false) then return sel end
        return nil
    end
    if NormalizeWireGuid(player:GetGUID())==wanted then return player end
    if lookup then
        local unit=lookup.players[wanted] or lookup.creatures[wanted]
        if unit and RpsTargetContext(player,unit,false) then return unit end
    end
    if sel and NormalizeWireGuid(sel:GetGUID())==wanted and RpsTargetContext(player,sel,false) then return sel end
    if lookup then return nil end
    for _,plr in ipairs(GetPlayersInWorld and GetPlayersInWorld() or {}) do
        if NormalizeWireGuid(plr:GetGUID())==wanted and RpsTargetContext(player,plr,false) then return plr end
    end
    if player.GetCreaturesInRange then
        for _,cre in ipairs(player:GetCreaturesInRange(100) or {}) do
            if NormalizeWireGuid(cre:GetGUID())==wanted and RpsTargetContext(player,cre,false) then return cre end
        end
    end
    return nil
end
local function Public(p)
    local out = {}
    for _, k in ipairs({"guid","runtimeGuid","isPlayer","name","roleType","isStaticThreshold","curHealth","maxHealth",
        "curEnergy","maxEnergy","energySpentRound","curWounds","maxWounds","armor","speed","weaponDice","blockDice",
        "revision","deathOutcome","archetype","raceId","level"}) do out[k]=p[k] end
    out.stats={}; for k, v in pairs(p.stats) do if C.StatDefs[k] then out.stats[k]=v end end
    if p.isPlayer then
        for _,def in ipairs(C.StatOrder) do
            if (def.category=="combat" or def.category=="mastery") and out.stats[def.key]==nil then out.stats[def.key]=def.defaultValue end
        end
    end
    return out
end
function R.SyncPlayerState(player)
    local p = S.PlayerProfiles[Id(player)]
    local pending={}
    for id,a in pairs(R.PendingAttacks) do if a.defenderGuid==Id(player) then pending[#pending+1]=id end end
    if p then AIO.Handle(player,prefix,"SyncProfile",{protocol=1,registry=C.StatOrder,profile=Public(p),pendingAttackIds=pending,
        spells=R.SpellStatuses[Id(player)],actionSpells=R.ActionSpellStatuses[Id(player)],
        creation=R.CreationSummary and R.CreationSummary(player) or nil}) end
end
function R.SyncTargetState(player, targetUnit)
    local unit = targetUnit or Target(player)
    if unit and not RpsTargetContext(player,unit,false) then unit=nil end
    if not unit then
        AIO.Handle(player,prefix,"SyncTarget",{inSystem=false})
        return
    end
    local canEdit = RpsTargetContext(player,unit,true)
    local payload = M.BuildUnitSyncPayload(unit, canEdit)
    AIO.Handle(player,prefix,"SyncTarget",payload)
    AIO.Handle(player,prefix,"SyncUnit",payload)
end
local function Ensure(player, callback)
    local p, err = S.GetOrLoadPlayerProfile(player)
    if p then callback(p); return end
    if err~="profile_missing_or_query_failed" then callback(nil,err); return end
    local guid, locator=Id(player),player:GetGUID()
    local count=CharDBQuery("SELECT COUNT(*) FROM character_rps_stats WHERE guid="..guid)
    if not count or count:GetUInt32(0)~=0 then callback(nil,"profile_unavailable"); return end
    if R.Locks["p:"..guid] then callback(nil,"actor_busy"); return end
    R.Locks["p:"..guid]=true
    local draft=S.BuildDefaultPlayerProfile(player)
    S.SaveProfiles({draft},function(ok,why)
        R.Locks["p:"..guid]=nil
        local current=Player(locator)
        if not current then return end
        callback(ok and S.PlayerProfiles[guid] or nil,why)
    end)
end
local function NotifyPending(player)
    for _, a in pairs(R.PendingAttacks) do
        if a.defenderGuid==Id(player) then
            AIO.Handle(player,prefix,"PromptDefenseReaction",{attackId=a.id,attackerName=a.attackerName,
                attackTotal=a.attackTotal,weaponDice=a.weaponDice,timeoutSec=math.max(0,a.expiresAt-os.time())})
        end
    end
end
-- Learning is confirmed only by HasSpell. A failed spell gets one immediate retry, then waits
-- for login, `.rps reload` or `.rps diag spells` (force) instead of retrying on every sync.
local function LearnConfirmed(player,id)
    player:LearnSpell(id)
    if player:HasSpell(id) then return true end
    player:LearnSpell(id)
    return player:HasSpell(id)
end
function R.IssueSpells(player,force)
    local key=Id(player)
    if force then R.LearnFailed[key]=nil end
    local failed=R.LearnFailed[key] or {}
    local statuses={}
    for _,def in ipairs(C.StatOrder) do
        local configured=def.configuredSpellId or def.spellId
        if def.diceFormula~="none" or configured>0 then
            local entry={id=configured}
            if configured==0 then entry.status="unmapped"
            elseif def.spellUnavailable then
                entry.status=def.spellUnavailable=="no_spellinfo" and "no_spellinfo" or "unsafe"
                entry.reason=def.spellUnavailable
            elseif player:HasSpell(def.spellId) then entry.status="ok"; failed[def.spellId]=nil
            elseif failed[def.spellId] then entry.status="learn_failed"
            elseif LearnConfirmed(player,def.spellId) then entry.status="ok"
            else
                entry.status="learn_failed"; failed[def.spellId]=true
                N.Log("RPS_Combat","learn_failed: player="..key.." stat="..def.key.." spell="..def.spellId)
            end
            statuses[def.key]=entry
        end
    end
    R.ActionSpellStatuses[key]=R.IssueActionSpells(player,failed)
    R.LearnFailed[key]=next(failed) and failed or nil
    R.SpellStatuses[key]=statuses
    return statuses
end
-- Action spells are static; a missing SpellInfo only marks the action, never the dice.
function R.IssueActionSpells(player,failed)
    local statuses={}
    for _,actionKey in ipairs(C.ActionOrder) do
        local id=C.Actions[actionKey].spellId
        if id>0 then
            local reason=C.ActionSpellStatus[actionKey] or "unmapped"
            local entry={id=id}
            if reason~="ok" then
                entry.status=(reason=="no_spellinfo" or reason=="unmapped") and reason or "unsafe"
                if entry.status=="unsafe" then entry.reason=reason end
            elseif player:HasSpell(id) then entry.status="ok"; failed[id]=nil
            elseif failed[id] then entry.status="learn_failed"
            elseif LearnConfirmed(player,id) then entry.status="ok"
            else
                entry.status="learn_failed"; failed[id]=true
                N.Log("RPS_Combat","learn_failed: player="..Id(player).." action="..actionKey.." spell="..id)
            end
            statuses[actionKey]=entry
        end
    end
    return statuses
end
local function Refresh(player)
    R.IssueSpells(player)
    R.SyncPlayerState(player); R.SyncTargetState(player); NotifyPending(player)
end
local function Guard(player,requestId)
    if not R.ready then Error(player,"system_unavailable",requestId); return false end
    return true
end
local ticks={}
local Escape=require("Core.DB").EscapeSqlString
local function Q(value) return "'"..Escape(value or "").."'" end
local function ReceiptSql(playerId,requestId,record,result,state)
    return string.format([[INSERT INTO rps_action_receipts
        (issuer_guid,request_id,signature,state,result_kind,stat_key,total,damage,attack_id)
        VALUES (%s,%s,%s,%s,%s,%s,%d,%d,%s)]],playerId,Q(requestId),Q(record.signature),Q(state),
        Q(result.kind),Q(result.statKey),result.total or 0,result.damage or 0,Q(result.attackId))
end
local function Rate(player)
    local key=Id(player)
    local now=GetCurrTime()
    if ticks[key] and now>=ticks[key] and now-ticks[key]<400 then Error(player,"rate_limited"); return false end
    ticks[key]=now; return true
end
local function Begin(player, requestId, signature, profiles)
    if type(signature)~="string" or #signature>8192 then Error(player,"invalid_message"); return end
    if type(requestId)~="string" or #requestId<1 or #requestId>80 or not requestId:match("^[%w_-]+$") then
        Error(player,"invalid_request_id"); return
    end
    local key=Id(player)
    local seen=R.Seen[key] or {}; R.Seen[key]=seen
    if seen[requestId] then
        local prior=seen[requestId]
        if prior.signature~=signature then Error(player,"request_conflict",requestId)
        elseif prior.done then
            if prior.error then Error(player,prior.error,requestId) else
                Refresh(player); AIO.Handle(player,prefix,"Committed",{requestId=requestId,result=prior.result})
            end
        else Error(player,"request_pending",requestId) end
        return
    end
    local receiptPool="characters"
    if #profiles>0 then
        receiptPool="world"
        for _,p in ipairs(profiles) do if p.isPlayer then receiptPool="characters"; break end end
    end
    local query=receiptPool=="characters" and CharDBQuery or WorldDBQuery
    local where=" WHERE issuer_guid="..key.." AND request_id="..Q(requestId)
    local countQuery=query("SELECT COUNT(*) FROM rps_action_receipts"..where)
    if not countQuery then Error(player,"receipt_unavailable",requestId); return end
    if countQuery:GetUInt32(0)>0 then
        local q=query("SELECT signature,state,result_kind,stat_key,total,damage,attack_id FROM rps_action_receipts"..where)
        if not q then Error(player,"receipt_unavailable",requestId); return end
        if q:GetString(0)~=signature then Error(player,"request_conflict",requestId); return end
        if q:GetString(1)~="done" then Error(player,"pending_recovery",requestId); return end
        Refresh(player)
        AIO.Handle(player,prefix,"Committed",{requestId=requestId,result={kind=q:GetString(2),statKey=q:GetString(3),
            total=q:GetInt32(4),damage=q:GetInt32(5),attackId=q:GetString(6)}})
        return
    end
    local keys={}
    for _, p in ipairs(profiles) do keys[Actor(p)]=true end
    for k in pairs(keys) do if R.Locks[k] then Error(player,"actor_busy",requestId); return end end
    local count=0
    for id, record in pairs(seen) do
        if record.done and os.time()-record.created>300 then seen[id]=nil else count=count+1 end
    end
    if count>=64 then
        local oldestId,oldest
        for id,prior in pairs(seen) do
            if prior.done and (not oldest or prior.created<oldest) then oldestId,oldest=id,prior.created end
        end
        if not oldestId then Error(player,"request_window_full",requestId); return end
        seen[oldestId]=nil
    end
    for k in pairs(keys) do R.Locks[k]=true end
    local record={signature=signature,created=os.time(),keys=keys,pool=receiptPool,issuer=key}
    seen[requestId]=record
    return record
end
local function Finish(playerGuid,requestId,record,profiles,result,extras,after)
    extras=extras or {}
    local pools={}
    for _,p in ipairs(profiles) do pools[p.isPlayer and "characters" or "world"]=true end
    for pool,sql in pairs(extras) do if #sql>0 then pools[pool]=true end end
    local mixed=pools.characters and pools.world
    extras[record.pool]=extras[record.pool] or {}
    extras[record.pool][#extras[record.pool]+1]=ReceiptSql(record.issuer,requestId,record,result,mixed and "pending" or "done")
    local function Complete(ok,why)
        for key in pairs(record.keys) do R.Locks[key]=nil end
        record.done,record.error,record.result=true,not ok and why or nil,result
        local player=Player(playerGuid)
        if not ok then
            if player then Refresh(player); Error(player,why,requestId) end
            return
        end
        if after then after() end
        if player and (result.kind=="roll" or result.kind=="attack") then
            local def=C.StatDefs[result.statKey]
            local text=player:GetName()..": "..(result.kind=="attack" and "Атака ("..(def and def.name or result.statKey)..")"
                or (def and def.name or result.statKey)).." = "..result.total
                ..(result.hit==false and ", промах" or "")..(result.damage and (", урон: "..result.damage) or "")
            for _,other in ipairs(GetPlayersInWorld()) do
                if other:GetGUID()~=playerGuid and other.SendBroadcastMessage and RpsTargetContext(player,other,false) then
                    other:SendBroadcastMessage(text)
                end
            end
        end
        if player then Refresh(player); AIO.Handle(player,prefix,"Committed",{requestId=requestId,result=result}) end
    end
    S.SaveProfiles(profiles,function(ok,why)
        if not ok or not mixed then Complete(ok,why); return end
        local update="UPDATE rps_action_receipts SET state='done' WHERE issuer_guid="..record.issuer.." AND request_id="..Q(requestId)
        RpsCommitAsync(record.pool,{update},function(saved)
            if saved then Complete(true) else Complete(false,"receipt_failed") end
        end)
    end,nil,extras)
end
local function Abort(player,id,record,why)
    for key in pairs(record.keys) do R.Locks[key]=nil end
    record.done,record.error=true,why; Error(player,why,id)
end
local sequence=0
local function NewId()
    sequence=sequence+1
    return RpsRuntimeEpoch().."-"..GetCurrTime().."-"..sequence
end
local function PendingSql(a)
    local escape=require("Core.DB").EscapeSqlString
    return string.format([[INSERT INTO rps_pending_attacks
        (attack_id,attacker_guid,defender_guid,attacker_name,attack_total,weapon_dice,damage_type,expires_at)
        VALUES ('%s',%s,%s,'%s',%d,'%s','%s',%d)]],a.id,a.attackerGuid,a.defenderGuid,
        escape(a.attackerName),a.attackTotal,escape(a.weaponDice),a.damageType,a.expiresAt)
end
local function PendingDelete(a) return "DELETE FROM rps_pending_attacks WHERE attack_id='"..a.id.."'" end

-- A dice check is standalone even with a selected target; only R.Attack attacks.
function R.Roll(player,statKey,fate,requestId,revision)
    if not Guard(player,requestId) then return end
    if not C.ValidStatKey(statKey) or not C.StatDefs[statKey] or type(fate)~="boolean"
        or not C.Integer(revision,0,4294967295) then Error(player,"invalid_roll",requestId); return end
    if not Rate(player) then return end
    local p=S.PlayerProfiles[Id(player)]
    if not p then Error(player,"profile_unavailable",requestId); return end
    local signature="roll:"..statKey..":"..tostring(fate)..":"..tostring(revision)..":"
    local record=Begin(player,requestId,signature,{p}); if not record then return end
    if revision~=p.revision then Abort(player,requestId,record,"stale_profile"); return end
    local draft,roll=M.ExecuteStatRoll(p,statKey,fate,nil,p.stats.debuff_fatigue or 0)
    if not draft then Abort(player,requestId,record,roll); return end
    local result={kind="roll",statKey=statKey,total=roll.total,energyApplied=roll.energyApplied}
    local locator=player:GetGUID()
    Finish(locator,requestId,record,{draft},result,nil,function()
        local actor=Player(locator)
        if actor then M.BroadcastUnitUpdate(actor,AIO) end
    end)
end

-- Explicit attack: PvP creates one pending attack with a 30 s window; an NPC defends at once.
function R.Attack(player,fate,requestId,revision)
    if not Guard(player,requestId) then return end
    local statKey=C.Actions.attack.statKey
    if type(fate)~="boolean" or not C.Integer(revision,0,4294967295) or not C.StatDefs[statKey] then
        Error(player,"invalid_action",requestId); return
    end
    if not Rate(player) then return end
    local p=S.PlayerProfiles[Id(player)]
    if not p then Error(player,"profile_unavailable",requestId); return end
    local target=Target(player)
    if target and tostring(target:GetGUID())==tostring(player:GetGUID()) then target=nil end
    if not target then
        player:SendNotification("Атака: выберите цель")
        Error(player,"attack_no_target",requestId); return
    end
    local tp,err=S.ResolveUnitStats(target)
    if not tp then Error(player,err or "target_outside_system",requestId); return end
    if tp.isPlayer then
        for _,a in pairs(R.PendingAttacks) do
            if a.attackerGuid==p.guid and a.defenderGuid==tp.guid then Error(player,"attack_pending",requestId); return end
        end
    end
    local signature="attack:"..tostring(fate)..":"..tostring(revision)..":"..Actor(tp)
    local record=Begin(player,requestId,signature,{p,tp}); if not record then return end
    if revision~=p.revision then Abort(player,requestId,record,"stale_profile"); return end
    local draft,roll=M.ExecuteStatRoll(p,statKey,fate,nil,p.stats.debuff_fatigue or 0)
    if not draft then Abort(player,requestId,record,roll); return end
    local profiles={draft}
    local extras,after
    local locator=player:GetGUID()
    local result={kind="attack",actionKey="attack",statKey=statKey,total=roll.total,energyApplied=roll.energyApplied}
    if tp.isPlayer then
        local pendingCount,total=0,0
        for _, a in pairs(R.PendingAttacks) do
            total=total+1; if a.defenderGuid==tp.guid then pendingCount=pendingCount+1 end
        end
        if pendingCount>=8 or total>=2048 then Abort(player,requestId,record,"reaction_queue_full"); return end
        local a={id=NewId(),attackerGuid=p.guid,defenderGuid=tp.guid,attackerName=player:GetName(),
            attackTotal=roll.total,weaponDice=p.weaponDice,damageType="physical",expiresAt=os.time()+C.REACTION_TIMEOUT_SEC}
        result.attackId=a.id
        extras={characters={PendingSql(a)}}
        after=function()
            a.createdTick=GetCurrTime()
            R.PendingAttacks[a.id]=a
            for _, other in ipairs(GetPlayersInWorld()) do if Id(other)==a.defenderGuid then NotifyPending(other) end end
            local actor=Player(locator)
            if actor then M.BroadcastUnitUpdate(actor,AIO) end
        end
    else
        local threshold,why=M.GetNpcDefense(tp,M.DefenseStatFor({damageType="physical"}))
        if not threshold then Abort(player,requestId,record,why); return end
        result.defense=threshold
        result.hit=M.AttackHits(roll.total,threshold)
        if result.hit then
            local damage=C.RollDiceString(p.weaponDice,0)
            local damaged,outcome=M.ApplyDamageToUnit(tp,damage.total,"physical",0)
            if not damaged then Abort(player,requestId,record,outcome); return end
            profiles[#profiles+1]=damaged; result.damage=outcome.damage
        end
        after=function()
            local actor=Player(locator)
            if actor then M.BroadcastUnitUpdate(actor,AIO) end
            M.BroadcastUnitUpdate(target,AIO)
        end
    end
    Finish(locator,requestId,record,profiles,result,extras,after)
end

-- statKey nil lets the server pick the defense stat from the attack (action path).
function R.React(player,attackId,choice,statKey,fate,requestId)
    if not Guard(player,requestId) or type(attackId)~="string" then return end
    if #attackId>96 or (choice~="TAKE" and choice~="BLOCK" and choice~="AVOID")
        or (statKey~=nil and statKey~="evasion" and statKey~="resistance") or type(fate)~="boolean" then
        Error(player,"invalid_reaction",requestId); return
    end
    if not Rate(player) then return end
    local signature="react:"..attackId..":"..tostring(choice)..":"..tostring(statKey)..":"..tostring(fate)
    local a=R.PendingAttacks[attackId]
    if not a or a.defenderGuid~=Id(player) then
        -- A replayed request returns its stored receipt; any other answer to a closed attack is refused.
        local seen=R.Seen[Id(player)]
        if a==nil and type(requestId)=="string" and seen and seen[requestId] then Begin(player,requestId,signature,{}); return end
        Error(player,"reaction_unavailable",requestId); return
    end
    if a.busy then Error(player,"request_pending",requestId); return end
    statKey=statKey or M.DefenseStatFor(a)
    local p=S.GetOrLoadPlayerProfile(player)
    if not p then Error(player,"profile_unavailable",requestId); return end
    local record=Begin(player,requestId,signature,{p})
    if not record then return end
    local attacker
    for _,other in ipairs(GetPlayersInWorld()) do if Id(other)==a.attackerGuid then attacker=other; break end end
    if not attacker or not RpsTargetContext(player,attacker,false) then
        local locator=player:GetGUID()
        a.busy,a.record=true,record
        Finish(locator,requestId,record,{}, {kind="reaction",attackId=attackId,cancelled=true},
            {characters={PendingDelete(a)}},function()
                R.PendingAttacks[attackId]=nil
                local current=Player(locator)
                if current then AIO.Handle(current,prefix,"ReactionClosed",attackId) end
            end)
        return
    end
    -- Past the server deadline every answer becomes the default TAKE (only armor applies).
    local timedOut=os.time()>=a.expiresAt and choice~="TAKE"
    if os.time()>=a.expiresAt then choice,statKey,fate="TAKE","evasion",false end
    local draft,outcome=M.HandleDefenseReaction(p,a,choice,statKey,fate,nil,p.stats.debuff_fatigue or 0)
    if not draft then Abort(player,requestId,record,outcome); return end
    outcome.timedOut=timedOut or nil
    a.busy=true
    local locator=player:GetGUID()
    local attackerGuid=attacker:GetGUID()
    Finish(player:GetGUID(),requestId,record,{draft},{kind="reaction",attackId=attackId,outcome=outcome},
        {characters={PendingDelete(a)}},function()
            R.PendingAttacks[attackId]=nil
            R.LastReaction[a.defenderGuid]=GetCurrTime()
            local current=Player(locator)
            if current then
                AIO.Handle(current,prefix,"ReactionClosed",attackId)
                M.BroadcastUnitUpdate(current,AIO)
            end
            local source=Player(attackerGuid)
            if source then
                AIO.Handle(source,prefix,"AttackResolved",{attackId=attackId,choice=outcome.choice,avoided=outcome.avoided==true,
                    damage=outcome.damage and outcome.damage.damage or 0,timedOut=outcome.timedOut})
            end
        end)
    -- Failed commits leave the attack available for retry/timeout.
    a.record=record
end

-- Open incoming attacks of the defender, oldest first, and how many are being resolved now.
function R.IncomingAttacks(player)
    local free,busy,me,now={},0,Id(player),os.time()
    for _,a in pairs(R.PendingAttacks) do
        if a.defenderGuid==me and now<a.expiresAt then
            if a.busy then busy=busy+1 else free[#free+1]=a end
        end
    end
    table.sort(free,function(x,y)
        if x.expiresAt~=y.expiresAt then return x.expiresAt<y.expiresAt end
        return x.id<y.id
    end)
    return free,busy
end

-- One server path for CombatPrompt buttons and native action spells.
-- args: {attackId=, fate=, revision=}. A reaction without attackId picks the only open attack;
-- several (or one that arrived right after the previous answer) ask the client to choose.
function R.PerformAction(player,actionKey,args,requestId)
    if not Guard(player,requestId) then return end
    local action=type(actionKey)=="string" and C.Actions[actionKey]
    if args==nil then args={} end
    if not action or type(args)~="table" or (args.fate~=nil and type(args.fate)~="boolean")
        or (args.attackId~=nil and type(args.attackId)~="string") then
        Error(player,"invalid_action",requestId); return
    end
    if action.kind=="attack" then return R.Attack(player,args.fate==true,requestId,args.revision) end
    if args.fate and action.choice~="AVOID" then Error(player,"invalid_fate_choice",requestId); return end
    local attackId=args.attackId
    if attackId==nil then
        local free,busy=R.IncomingAttacks(player)
        -- While one answer is being committed a native cast never moves on to another attack.
        if busy>0 then Error(player,"request_pending",requestId); return end
        if #free==0 then
            player:SendNotification("Нет входящей атаки")
            Error(player,"no_incoming_attack",requestId); return
        end
        local last=R.LastReaction[Id(player)]
        local now=GetCurrTime()
        local fresh=last and free[1].createdTick and free[1].createdTick>=last and now>=last and now-last<1500
        if #free>1 or fresh then
            local ids={}
            for i,a in ipairs(free) do ids[i]=a.id end
            NotifyPending(player)
            AIO.Handle(player,prefix,"ChooseDefenseAttack",{actionKey=actionKey,attackIds=ids,requestId=requestId})
            return
        end
        attackId=free[1].id
    end
    R.React(player,attackId,action.choice,nil,action.choice=="AVOID" and args.fate==true,requestId)
end

local actionRejections={map_changed="Действие отменено: смена карты",target_changed="Действие отменено: цель изменилась",
    expired="Действие отменено: истекло время ожидания"}
function R.CastAction(player,actionKey,rejected)
    if rejected then player:SendNotification(actionRejections[rejected] or "Действие отменено"); return end
    local p=S.GetOrLoadPlayerProfile(player)
    if not p then player:SendNotification("Действие недоступно: нет RP-профиля"); return end
    R.PerformAction(player,actionKey,{revision=p.revision},NewId())
end

local numeric={maxHealth={1,C.MAX_RESOURCE},curHealth={0,C.MAX_RESOURCE},maxEnergy={0,C.MAX_RESOURCE},curEnergy={0,C.MAX_RESOURCE},
    armor={0,1000000},speed={0,1000}}
function R.DmSave(player,payload,requestId)
    if not Guard(player,requestId) or type(payload)~="table" then return end
    if not C.Integer(payload.revision,0,4294967295) then Error(player,"invalid_revision",requestId); return end
    if not Rate(player) then return end
    local target=Target(player)
    if not target and type(payload.targetGuid)=="string" then
        local resolved=ResolveUnitForPlayerByGuid(player,payload.targetGuid)
        if resolved then target=resolved end
    end
    if not target or not RpsTargetContext(player,target,true) then Error(player,"permission_denied",requestId); return end
    if payload.targetGuid~=tostring(target:GetGUID()) then Error(player,"target_changed",requestId); return end
    local p=S.ResolveUnitStats(target)
    if not p and target:ToCreature() then p=S.BuildCreatureProfile(target:ToCreature()) end
    if not p then Error(player,"profile_unavailable",requestId); return end
    local draft=S.CopyProfile(p)
    local parts={"dm",payload.targetGuid,tostring(payload.revision)}
    for k, bounds in pairs(numeric) do
        if payload[k]~=nil then
            if not C.Integer(payload[k],bounds[1],bounds[2]) then Error(player,"invalid_field",requestId); return end
            draft[k]=payload[k]; parts[#parts+1]=k.."="..payload[k]
        end
    end
    for _, k in ipairs({"weaponDice","blockDice"}) do
        if payload[k]~=nil then
            if not C.ParseDice(payload[k]) then Error(player,"invalid_dice",requestId); return end
            draft[k]=payload[k]; parts[#parts+1]=k.."="..payload[k]
        end
    end
    if payload.stats~=nil then
        if type(payload.stats)~="table" then Error(player,"invalid_stats",requestId); return end
        local count=0
        for k,v in pairs(payload.stats) do
            count=count+1
            local def=C.StatDefs[k]
            if count>128 or not def or (def.category~="combat" and def.category~="mastery") or not C.Integer(v,-1000,1000) then
                Error(player,"invalid_stats",requestId); return
            end
            draft.stats[k]=v; parts[#parts+1]=k.."="..v
        end
    end
    if payload.beginRound~=nil and type(payload.beginRound)~="boolean" then Error(player,"invalid_field",requestId); return end
    if payload.beginRound then
        if not p.isPlayer then Error(player,"invalid_round_target",requestId); return end
        draft.energySpentRound=0; parts[#parts+1]="round"
    end
    table.sort(parts)
    local record=Begin(player,requestId,table.concat(parts,"|"),{p}); if not record then return end
    if (p.revision or 0)~=payload.revision then Abort(player,requestId,record,"stale_profile"); return end
    draft.persistOverride=not p.isPlayer
    local targetPlayerGuid=target:ToPlayer() and target:GetGUID()
    Finish(player:GetGUID(),requestId,record,{draft},{kind="dm_save"},nil,function()
        local other=targetPlayerGuid and Player(targetPlayerGuid)
        if other then R.SyncPlayerState(other) end
        if target then M.BroadcastUnitUpdate(target,AIO) end
    end)
end

local H=AIO.AddHandlers(prefix,{})
local readTicks={}
local function ReadAllowed(player,kind,interval)
    local key=Id(player)..":"..kind
    local now=GetCurrTime()
    if readTicks[key] and now>=readTicks[key] and now-readTicks[key]<interval then return false end
    readTicks[key]=now
    return true
end
function H.RequestSync(player)
    if not Guard(player) or not ReadAllowed(player,"self",500) then return end
    local locator=player:GetGUID()
    Ensure(player,function(p,why)
        local current=Player(locator)
        if not current then return end
        if p then Refresh(current) else Error(current,why) end
    end)
end
function H.RequestTargetSync(player) if Guard(player) and ReadAllowed(player,"target",250) then R.SyncTargetState(player) end end
function H.RequestUnitsSync(player,guidList)
    if not Guard(player) or type(guidList)~="table" or not ReadAllowed(player,"units",200) then return end
    -- Every requested GUID gets an entry: state "ready" | "none" (no RP profile) |
    -- "unknown" (not resolved / outside context / invalid), so the client never keeps a stale snapshot.
    local batch={}
    local count=0
    local lookup=BuildUnitLookup(player)
    for i,guidStr in ipairs(guidList) do
        if count>=45 or i>64 then break end
        if type(guidStr)=="string" and guidStr~="" and #guidStr<=128 then
            local guid=NormalizeWireGuid(guidStr)
            local key=guid or guidStr
            if batch[key]==nil then
                local unit=guid and ResolveUnitForPlayerByGuid(player,guid,lookup)
                local data=unit and M.BuildUnitSyncPayload(unit,RpsTargetContext(player,unit,true))
                if data then
                    data.guid,data.targetGuid=key,key
                    data.state=data.inSystem and "ready" or "none"
                else
                    data={guid=key,targetGuid=key,inSystem=false,state="unknown",reason=guid and "unresolved" or "invalid_guid"}
                end
                batch[key]=data
                count=count+1
            end
        end
    end
    if next(batch) then
        AIO.Handle(player,prefix,"SyncUnitBatch",batch)
    end
end
H.RollStat=R.Roll
H.SendDefenseReaction=R.React
H.PerformAction=R.PerformAction
H.DmSaveTargetStats=R.DmSave
require("Modules.RPS_Combat.05_RPS_Creation").Register(R,H,Ensure)
require("Modules.RPS_Combat.06_RPS_Progression").InstallWorld(R,H)

local function Load()
    R.unavailableReason=nil
    local function Fail(reason)
        R.unavailableReason=reason
        N.Log("RPS_Combat","inactive: "..reason)
        return false
    end
    R.degradedReason=nil
    for _,name in ipairs({"RpsCommitAsync","RpsPollDiceCasts","RpsTargetContext","RpsIsDiceSpell","RpsRuntimeEpoch"}) do
        if type(_G[name])~="function" then return Fail("missing_binding:"..name) end
    end
    local ok,why=C.LoadStatDefinitions()
    if not ok then return Fail(why or "registry_unavailable") end
    if #C.SpellDiagnostics>0 then
        R.degradedReason="dice_spells_unavailable:"..C.SpellDiagnosticsText()
        N.Log("RPS_Combat",R.degradedReason)
    end
    local _,actionStatuses=C.RefreshActionSpells()
    for _,actionKey in ipairs(C.ActionOrder) do
        local reason=actionStatuses[actionKey]
        if reason and reason~="ok" then N.Log("RPS_Combat","action_spell_unavailable:"..actionKey..":"..C.Actions[actionKey].spellId..":"..reason) end
    end
    ok,why=S.LoadNpcCaches()
    if not ok then return Fail(why or "npc_cache_unavailable") end
    if not ok or not WorldDBQuery("SELECT COUNT(*) FROM rps_creature_runtime_stats")
        or not WorldDBQuery("SELECT COUNT(*) FROM rps_action_receipts")
        or not CharDBQuery("SELECT COUNT(*) FROM rps_action_receipts") then return Fail("runtime_or_receipts_schema_unavailable") end
    -- Empty SELECT cannot report success, so validate columns through COUNT.
    if not CharDBQuery("SELECT COUNT(revision),COUNT(death_outcome) FROM character_rps_stats") then return Fail("character_profile_schema_unavailable") end
    local count=CharDBQuery("SELECT COUNT(*) FROM rps_pending_attacks")
    if not count then return Fail("pending_schema_unavailable") end
    if count:GetUInt32(0)>2048 then return Fail("pending_limit_exceeded") end
    local pending={}
    if count:GetUInt32(0)>0 then
        local q=CharDBQuery([[SELECT attack_id,attacker_guid,defender_guid,attacker_name,attack_total,weapon_dice,damage_type,expires_at
            FROM rps_pending_attacks]])
        if not q then return Fail("pending_query_failed") end
        repeat
            local a={id=q:GetString(0),attackerGuid=C.IdString(q:GetUInt64(1)),defenderGuid=C.IdString(q:GetUInt64(2)),
                attackerName=q:GetString(3),attackTotal=q:GetInt32(4),weaponDice=q:GetString(5),damageType=q:GetString(6),expiresAt=q:GetUInt32(7)}
            if not a.id:match("^[%w_-]+$") or #a.id>96 or not C.ParseDice(a.weaponDice)
                or not a.attackerGuid or not a.defenderGuid then return Fail("invalid_pending_attack") end
            pending[a.id]=a
        until not q:NextRow()
    end
    R.PendingAttacks=pending; S.RuntimePersistence=true
    return true
end
R.ready=Load()
function R.DiagSpells(player)
    local sel=player:GetSelection()
    local target=sel and sel:ToPlayer() or player
    local lines={string.format("RPS spells: ready=%s reason=%s degraded=%s player=%s",tostring(R.ready==true),
        tostring(R.unavailableReason or "-"),tostring(R.degradedReason or "-"),target:GetName())}
    local before={}
    for _,def in ipairs(C.StatOrder) do
        local id=def.configuredSpellId or def.spellId
        if id>0 then before[def.key]=target:HasSpell(id) end
    end
    local actionBefore={}
    for _,actionKey in ipairs(C.ActionOrder) do
        local id=C.Actions[actionKey].spellId
        if id>0 then actionBefore[actionKey]=target:HasSpell(id) end
    end
    local statuses=R.ready and R.IssueSpells(target,true) or {}
    for _,def in ipairs(C.StatOrder) do
        local id=def.configuredSpellId or def.spellId
        if def.diceFormula~="none" or id>0 then
            local _,check=C.SpellStatus(id)
            local line=string.format("%s id=%d check=%s has=%s",def.key,id,check,
                before[def.key]==nil and "-" or tostring(before[def.key]))
            local entry=statuses[def.key]
            if entry and id>0 then
                line=line..string.format(" -> has=%s status=%s",tostring(target:HasSpell(id)),entry.status)
            elseif entry then line=line.." status="..entry.status end
            lines[#lines+1]=line
        end
    end
    local actions=R.ActionSpellStatuses[Id(target)] or {}
    for _,actionKey in ipairs(C.ActionOrder) do
        local id=C.Actions[actionKey].spellId
        if id>0 then
            lines[#lines+1]=string.format("action %s id=%d check=%s has=%s -> has=%s status=%s",actionKey,id,
                tostring(C.ActionSpellStatus[actionKey] or "-"),tostring(actionBefore[actionKey]),
                tostring(target:HasSpell(id)),actions[actionKey] and actions[actionKey].status or "-")
        end
    end
    if R.ready then R.SyncPlayerState(target) end
    for _,line in ipairs(lines) do player:SendBroadcastMessage(line) end
    return lines
end
RegisterPlayerEvent(3,function(_,player)
    if not R.ready then return end
    R.IssueSpells(player,true)
    H.RequestSync(player)
end)
RegisterPlayerEvent(4,function(_,player)
    local key=Id(player)
    if not R.Locks["p:"..key] then S.ReleasePlayer(player) end
    R.SpellStatuses[key],R.LearnFailed[key]=nil,nil
    R.ActionSpellStatuses[key],R.LastReaction[key]=nil,nil
    ticks[key]=nil
    readTicks[key..":self"],readTicks[key..":target"],readTicks[key..":units"]=nil,nil,nil
end)
RegisterPlayerEvent(42,function(_,player,command)
    -- Never swallow the existing .rps character / npc command trees.
    local key,value=command:match("^rps setstat ([a-z][a-z0-9_]*) (%-?%d+)$")
    if key then
        if not player then return false end
        local target=Target(player)
        local p=target and S.ResolveUnitStats(target)
        if not p and target and target:ToCreature() then p=S.BuildCreatureProfile(target:ToCreature()) end
        if not p then Error(player,"target_unavailable"); return false end
        R.DmSave(player,{targetGuid=tostring(target:GetGUID()),revision=p.revision or 0,stats={[key]=tonumber(value)}},NewId())
        return false
    end
    if command=="rps diag spells" then
        if not player or not N.HasStaffPermission(player) then return false end
        R.DiagSpells(player)
        return false
    end
    -- `.rps race reset [playerName] [reason]`; no C++ `rps race` subcommand exists to intercept it.
    local raceArgs=command:match("^rps race reset(.*)$")
    if raceArgs and (raceArgs=="" or raceArgs:match("^%s")) then
        if not player then return false end
        local name,reason=raceArgs:match("^%s*(%S*)%s*(.-)%s*$")
        R.Creation.StaffResetRace(player,name,reason)
        return false
    end
    if command~="rps reload" then return end
    if not player or not N.HasStaffPermission(player) then return false end
    if next(R.Locks) then Error(player,"actor_busy"); return false end
    R.ready=Load()
    if R.ready then
        for _,p in ipairs(GetPlayersInWorld()) do R.IssueSpells(p,true); H.RequestSync(p) end
    else Error(player,"system_unavailable") end
    return false
end)
local castRejections={map_changed="Бросок отменён: смена карты",target_changed="Бросок отменён: цель изменилась",
    expired="Бросок отменён: истекло время ожидания"}
CreateLuaEvent(function()
    if not R.ready then return end
    for _, cast in ipairs(RpsPollDiceCasts()) do
        local actionKey=C.SpellToActionKey[cast.spellId]
        if actionKey then R.CastAction(cast.player,actionKey,cast.rejected)
        else
            local key=C.SpellToStatKey[cast.spellId]
            local p=not cast.rejected and key and S.GetOrLoadPlayerProfile(cast.player)
            if p then R.Roll(cast.player,key,false,NewId(),p.revision)
            else
                cast.player:SendNotification(castRejections[cast.rejected]
                    or (not key and "Бросок недоступен: спелл отключён") or "Бросок недоступен: нет RP-профиля")
            end
        end
    end
    for _,p in ipairs(GetPlayersInWorld()) do
        for _,a in pairs(R.PendingAttacks) do
            if a.record and a.record.done and a.record.error then a.busy,a.record=nil,nil end
            if a.defenderGuid==Id(p) and os.time()>=a.expiresAt and not a.busy and not R.Locks["p:"..Id(p)] then
                local now=GetCurrTime()
                if not ticks[Id(p)] or now<ticks[Id(p)] or now-ticks[Id(p)]>=400 then
                    R.React(p,a.id,"TAKE","evasion",false,NewId())
                end
                break
            end
        end
    end
end,250,0)
N.Log("RPS_Combat",R.ready and "ready" or "inactive: schema or native bindings unavailable")
return R
