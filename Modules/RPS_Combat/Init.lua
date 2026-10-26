-- WORLD owner for AIO, profiles and reaction queues.
if not _G.NN_BOOTSTRAP_ACTIVE then return end
local N = require("NobleNext")
if not N.IsMainState() then return end
if N.RPS then return N.RPS end
local C = require("Modules.RPS_Combat.00_RPS_Config")
local S = require("Modules.RPS_Combat.01_RPS_Storage")
local M = require("Modules.RPS_Combat.02_RPS_Combat")
local R = {Config=C,Storage=S,Combat=M,PendingAttacks={},Locks={},Seen={}}
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
-- lookup: optional per-request {players=map, creatures=map} built once so a batch of
-- nameplate GUIDs does not rescan the world for every entry.
local function BuildUnitLookup(player)
    local lookup={players={},creatures={}}
    for _,plr in ipairs(GetPlayersInWorld and GetPlayersInWorld() or {}) do
        lookup.players[tostring(plr:GetGUID())]=plr
    end
    if player.GetCreaturesInRange then
        for _,cre in ipairs(player:GetCreaturesInRange(100) or {}) do
            lookup.creatures[tostring(cre:GetGUID())]=cre
        end
    end
    return lookup
end
local function ResolveUnitForPlayerByGuid(player, guidStr, lookup)
    if not player or type(guidStr)~="string" or guidStr=="" or #guidStr>128 then return nil end
    if tostring(player:GetGUID())==guidStr then return player end
    if lookup then
        local unit=lookup.players[guidStr] or lookup.creatures[guidStr]
        if unit and RpsTargetContext(player,unit,false) then return unit end
    end
    local wantLow=ExtractLowGuid(guidStr)
    local isCreatureQuery=guidStr:find("^Creature")~=nil or guidStr:find("^Vehicle")~=nil or guidStr:find("^Pet")~=nil
    local isPlayerQuery=guidStr:find("^Player")~=nil
    local function Matches(unit)
        if not unit then return false end
        if tostring(unit:GetGUID())==guidStr then return true end
        if wantLow and C.IdString(unit:GetGUIDLow())==wantLow then
            local up=unit:ToPlayer()~=nil
            if isPlayerQuery then return up end
            if isCreatureQuery then return not up end
            return true
        end
        return false
    end
    local sel=player:GetSelection()
    if sel and Matches(sel) and RpsTargetContext(player,sel,false) then return sel end
    if lookup then return nil end
    if not isCreatureQuery then
        for _,plr in ipairs(GetPlayersInWorld and GetPlayersInWorld() or {}) do
            if Matches(plr) and (plr==player or RpsTargetContext(player,plr,false)) then return plr end
        end
    end
    if not isPlayerQuery and player.GetCreaturesInRange then
        for _,cre in ipairs(player:GetCreaturesInRange(100) or {}) do
            if Matches(cre) and RpsTargetContext(player,cre,false) then return cre end
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
    if p then AIO.Handle(player,prefix,"SyncProfile",{protocol=1,registry=C.StatOrder,profile=Public(p),pendingAttackIds=pending}) end
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
local function Refresh(player)
    for _,def in ipairs(C.StatOrder) do
        if def.spellId>0 and RpsIsDiceSpell(def.spellId) and not player:HasSpell(def.spellId) then player:LearnSpell(def.spellId) end
    end
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
        if player and result.kind=="roll" then
            local def=C.StatDefs[result.statKey]
            local text=player:GetName()..": "..(def and def.name or result.statKey).." = "..result.total
                ..(result.damage and (", урон: "..result.damage) or "")
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

function R.Roll(player,statKey,fate,requestId,revision)
    if not Guard(player,requestId) then return end
    if not C.ValidStatKey(statKey) or not C.StatDefs[statKey] or type(fate)~="boolean"
        or not C.Integer(revision,0,4294967295) then Error(player,"invalid_roll",requestId); return end
    if not Rate(player) then return end
    local p=S.PlayerProfiles[Id(player)]
    if not p then Error(player,"profile_unavailable",requestId); return end
    local target=statKey=="accuracy" and Target(player) or nil
    if target and tostring(target:GetGUID())==tostring(player:GetGUID()) then target=nil end
    local tp,err
    if target then tp,err=S.ResolveUnitStats(target); if not tp then Error(player,err or "target_outside_system",requestId); return end end
    local involved={p}; if tp then involved[#involved+1]=tp end
    local signature="roll:"..tostring(statKey)..":"..tostring(fate)..":"..tostring(revision)..":"..(tp and Actor(tp) or "")
    local record=Begin(player,requestId,signature,involved); if not record then return end
    if revision~=p.revision then Abort(player,requestId,record,"stale_profile"); return end
    local draft,roll=M.ExecuteStatRoll(p,statKey,fate,nil,p.stats.debuff_fatigue or 0)
    if not draft then Abort(player,requestId,record,roll); return end
    local profiles={draft}
    local extras,after
    local result={kind="roll",statKey=statKey,total=roll.total,energyApplied=roll.energyApplied}
    if tp then
        if tp.isPlayer then
            local pendingCount,total=0,0
            for _, a in pairs(R.PendingAttacks) do
                total=total+1; if a.defenderGuid==tp.guid then pendingCount=pendingCount+1 end
            end
            if pendingCount>=8 or total>=2048 then Abort(player,requestId,record,"reaction_queue_full"); return end
            local a={id=NewId(),attackerGuid=p.guid,defenderGuid=tp.guid,attackerName=player:GetName(),
                attackTotal=roll.total,weaponDice=p.weaponDice,damageType="physical",expiresAt=os.time()+C.REACTION_TIMEOUT_SEC}
            extras={characters={PendingSql(a)}}
            after=function()
                R.PendingAttacks[a.id]=a
                for _, other in ipairs(GetPlayersInWorld()) do if Id(other)==a.defenderGuid then NotifyPending(other) end end
                local actor=Player(player:GetGUID())
                if actor then M.BroadcastUnitUpdate(actor,AIO) end
            end
        else
            local threshold,why=M.GetNpcDefense(tp,"evasion")
            if not threshold then Abort(player,requestId,record,why); return end
            result.hit=roll.total>threshold
            if result.hit then
                local damage=C.RollDiceString(p.weaponDice,0)
                local damaged,outcome=M.ApplyDamageToUnit(tp,damage.total,"physical",0)
                if not damaged then Abort(player,requestId,record,outcome); return end
                profiles[#profiles+1]=damaged; result.damage=outcome.damage
            end
            after=function()
                local actor=Player(player:GetGUID())
                if actor then M.BroadcastUnitUpdate(actor,AIO) end
                if target then M.BroadcastUnitUpdate(target,AIO) end
            end
        end
    else
        after=function()
            local actor=Player(player:GetGUID())
            if actor then M.BroadcastUnitUpdate(actor,AIO) end
        end
    end
    Finish(player:GetGUID(),requestId,record,profiles,result,extras,after)
end

function R.React(player,attackId,choice,statKey,fate,requestId)
    if not Guard(player,requestId) or type(attackId)~="string" then return end
    if #attackId>96 or (choice~="TAKE" and choice~="BLOCK" and choice~="AVOID")
        or (statKey~="evasion" and statKey~="resistance") or type(fate)~="boolean" then Error(player,"invalid_reaction",requestId); return end
    if not Rate(player) then return end
    local a=R.PendingAttacks[attackId]
    if not a or a.defenderGuid~=Id(player) then Error(player,"reaction_unavailable",requestId); return end
    if a.busy then Error(player,"request_pending",requestId); return end
    local p=S.GetOrLoadPlayerProfile(player)
    if not p then Error(player,"profile_unavailable",requestId); return end
    local record=Begin(player,requestId,"react:"..attackId..":"..tostring(choice)..":"..tostring(statKey)..":"..tostring(fate),{p})
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
    if os.time()>=a.expiresAt then choice,statKey,fate="TAKE","evasion",false end
    local draft,outcome=M.HandleDefenseReaction(p,a,choice,statKey,fate,nil,p.stats.debuff_fatigue or 0)
    if not draft then Abort(player,requestId,record,outcome); return end
    a.busy=true
    local locator=player:GetGUID()
    Finish(player:GetGUID(),requestId,record,{draft},{kind="reaction",attackId=attackId,outcome=outcome},
        {characters={PendingDelete(a)}},function()
            R.PendingAttacks[attackId]=nil
            local current=Player(locator)
            if current then
                AIO.Handle(current,prefix,"ReactionClosed",attackId)
                M.BroadcastUnitUpdate(current,AIO)
            end
        end)
    -- Failed commits leave the attack available for retry/timeout.
    a.record=record
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
    local batch={}
    local count=0
    local lookup=BuildUnitLookup(player)
    for i,guidStr in ipairs(guidList) do
        if count>=45 or i>64 then break end
        if type(guidStr)=="string" and guidStr~="" then
            local unit=ResolveUnitForPlayerByGuid(player,guidStr,lookup)
            if unit then
                local data=M.BuildUnitSyncPayload(unit,RpsTargetContext(player,unit,true))
                if data then
                    data.guid=guidStr
                    batch[guidStr]=data
                    count=count+1
                end
            end
        end
    end
    if next(batch) then
        AIO.Handle(player,prefix,"SyncUnitBatch",batch)
    end
end
H.RollStat=R.Roll
H.SendDefenseReaction=R.React
H.DmSaveTargetStats=R.DmSave

local function Load()
    R.unavailableReason=nil
    local function Fail(reason)
        R.unavailableReason=reason
        N.Log("RPS_Combat","inactive: "..reason)
        return false
    end
    for _,name in ipairs({"RpsCommitAsync","RpsPollDiceCasts","RpsTargetContext","RpsIsDiceSpell","RpsRuntimeEpoch"}) do
        if type(_G[name])~="function" then return Fail("missing_binding:"..name) end
    end
    local ok,why=C.LoadStatDefinitions()
    if not ok then return Fail(why or "registry_unavailable") end
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
RegisterPlayerEvent(3,function(_,player) if R.ready then H.RequestSync(player) end end)
RegisterPlayerEvent(4,function(_,player)
    local key=Id(player)
    if not R.Locks["p:"..key] then S.ReleasePlayer(player) end
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
    if command~="rps reload" then return end
    if not player or not N.HasStaffPermission(player) then return false end
    if next(R.Locks) then Error(player,"actor_busy"); return false end
    R.ready=Load()
    if R.ready then for _,p in ipairs(GetPlayersInWorld()) do H.RequestSync(p) end else Error(player,"system_unavailable") end
    return false
end)
CreateLuaEvent(function()
    if not R.ready then return end
    for _, cast in ipairs(RpsPollDiceCasts()) do
        local p=S.GetOrLoadPlayerProfile(cast.player)
        local key=C.SpellToStatKey[cast.spellId]
        if p and key then R.Roll(cast.player,key,false,NewId(),p.revision) end
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
