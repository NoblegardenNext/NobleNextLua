-- Work on copies; the runtime must persist a draft before
-- publishing its result. No live Unit mutations, timers, logs or registrations here.
local C = require("Modules.RPS_Combat.00_RPS_Config")
local S = require("Modules.RPS_Combat.01_RPS_Storage")
local M = {}

function M.SpendEnergy(profile, cost)
    if type(profile) ~= "table" or not C.Integer(cost, 0, C.MAX_ENERGY_PER_ROUND)
        or not C.Integer(profile.maxEnergy, 0, C.MAX_RESOURCE)
        or not C.Integer(profile.curEnergy, 0, C.MAX_RESOURCE)
        or not C.Integer(profile.energySpentRound, 0, C.MAX_ENERGY_PER_ROUND) then return nil, "invalid_budget" end
    if profile.curEnergy < cost then return nil, "insufficient_energy" end
    if profile.energySpentRound + cost > C.MAX_ENERGY_PER_ROUND then return nil, "round_budget_exhausted" end
    local draft = S.CopyProfile(profile)
    draft.curEnergy = draft.curEnergy - cost
    draft.energySpentRound = draft.energySpentRound + cost
    return draft
end

local function GainEnergy(draft, amount)
    if not C.Integer(draft.maxEnergy, 0, C.MAX_RESOURCE) or not C.Integer(draft.curEnergy, 0, C.MAX_RESOURCE) then
        return nil, "invalid_energy"
    end
    -- Natural regain stops at the maximum and never trims existing bonus energy.
    local gained = math.max(0, math.min(draft.maxEnergy - draft.curEnergy, amount))
    draft.curEnergy = draft.curEnergy + gained
    return gained
end

function M.ExecuteStatRoll(profile, statKey, useFateDie, rng, fatigueStacks)
    local def = type(statKey) == "string" and C.StatDefs[statKey]
    if not def or def.diceFormula == "none" then return nil, "stat_not_rollable" end
    if type(profile) ~= "table" or not C.Integer(profile.curHealth, 0, 1000000)
        or not C.Integer(profile.curWounds, 0, 255) then return nil, "invalid_profile" end
    if profile.curHealth == 0 and profile.curWounds > 0 then return nil, "incapacitated" end
    if type(useFateDie) ~= "boolean" then return nil, "invalid_fate_choice" end
    local draft, err = M.SpendEnergy(profile, useFateDie and C.FATE_DIE_COST or 0)
    if not draft then return nil, err end
    local fateBonus = useFateDie and C.RollDiceString("1d6", 0, rng).total or 0
    local roll
    if def.diceFormula == "3d6" then
        local modifier = draft.stats and draft.stats[statKey]
        if modifier==nil and draft.isPlayer then modifier=def.defaultValue; draft.stats[statKey]=modifier end
        if modifier == nil then return nil, "missing_stat" end
        roll, err = C.Roll3d6(modifier, fateBonus, fatigueStacks, rng)
        if not roll then return nil, err end
        local gained
        gained, err = GainEnergy(draft, roll.energyGained)
        if gained == nil then return nil, err end
        roll.energyApplied = gained
    else
        local formula = def.diceFormula
        if formula == "weapon" then formula = draft.weaponDice elseif formula == "shield" then formula = draft.blockDice end
        roll, err = C.RollDiceString(formula, fateBonus, rng)
        if not roll then return nil, err end
    end
    return draft, roll
end

-- Physical armor and an allowed block are applied once. A wound is a transition
-- from positive RP health to zero, not another wound for every hit at zero health.
function M.ApplyDamageToUnit(profile, rawDamage, damageType, blockMitigation, rng)
    if type(profile) ~= "table" or not C.Integer(profile.curHealth, 0, C.MAX_RESOURCE)
        or not C.Integer(profile.maxHealth, 1, C.MAX_RESOURCE)
        or not C.Integer(profile.armor, 0, 1000000) or not C.Integer(rawDamage, 0, 1000000)
        or not C.Integer(blockMitigation, 0, 1000000)
        or (damageType ~= "physical" and damageType ~= "magic") then return nil, "invalid_damage" end
    if profile.isPlayer and (not C.Integer(profile.curWounds, 0, 254)
        or not C.Integer(profile.maxWounds, 1, 255)) then return nil, "invalid_wounds" end
    local draft = S.CopyProfile(profile)
    local mitigation = blockMitigation + (damageType == "physical" and draft.armor or 0)
    local damage = math.max(0, rawDamage - mitigation)
    draft.curHealth = math.max(0, draft.curHealth - damage)
    local result = {rawDamage = rawDamage, mitigation = mitigation, damage = damage, woundAdded = false}
    if draft.isPlayer and profile.curHealth > 0 and draft.curHealth == 0 then
        draft.curWounds = draft.curWounds + 1
        result.woundAdded = true
        if draft.curWounds >= draft.maxWounds then
            local roll = C.Roll3d6(0, 0, 0, rng)
            result.deathRoll = roll
            local total = roll.total
            draft.deathOutcome = total <= 6 and "death" or total <= 12 and "injury" or total <= 17 and "defeated" or "second_wind"
            if draft.deathOutcome == "second_wind" then
                if not C.Integer(draft.maxEnergy, 0, 1000000) then return nil, "invalid_energy" end
                draft.curWounds = draft.curWounds - 1
                draft.curHealth = draft.maxHealth
                draft.curEnergy = math.max(draft.curEnergy, draft.maxEnergy)
            end
            result.deathOutcome = draft.deathOutcome
        end
    end
    return draft, result
end

function M.GetNpcDefense(profile, statKey, rng)
    local modifier = type(profile) == "table" and profile.stats and profile.stats[statKey]
    if not C.Integer(modifier, -1000, 1000) then return nil, "missing_defense_stat" end
    if profile.isStaticThreshold then return modifier end
    local roll = C.Roll3d6(modifier, 0, 0, rng)
    return roll.total, roll
end

-- Ownership, expiry and exactly-once consumption belong to the runtime queue.
-- This function only resolves the previously validated server attack snapshot.
function M.HandleDefenseReaction(profile, attack, choice, defenseStatKey, useFateDie, rng, fatigueStacks)
    if type(profile) ~= "table" or type(attack) ~= "table" or not C.Integer(attack.attackTotal, -1000, 3000)
        or not C.ParseDice(attack.weaponDice) or (attack.damageType ~= "physical" and attack.damageType ~= "magic") then
        return nil, "invalid_attack"
    end
    if choice ~= "TAKE" and choice ~= "AVOID" and choice ~= "BLOCK" then return nil, "invalid_reaction" end
    if type(useFateDie) ~= "boolean" or (useFateDie and choice ~= "AVOID") then return nil, "invalid_fate_choice" end
    local draft = S.CopyProfile(profile)
    local reaction = {choice = choice}
    local block = 0
    if choice == "AVOID" then
        if defenseStatKey ~= "evasion" and defenseStatKey ~= "resistance" then return nil, "invalid_defense_stat" end
        local err
        draft, reaction.roll = M.ExecuteStatRoll(draft, defenseStatKey, useFateDie, rng, fatigueStacks)
        if not draft then err = reaction.roll; return nil, err end
        if reaction.roll.total >= attack.attackTotal then reaction.avoided = true; return draft, reaction end
    elseif choice == "BLOCK" then
        local err
        draft, err = M.SpendEnergy(draft, C.BLOCK_ENERGY_COST)
        if not draft then return nil, err end
        local resistance = draft.stats and draft.stats.resistance
        if not C.Integer(resistance, -1000, 1000) then return nil, "missing_defense_stat" end
        local roll = C.RollDiceString(draft.blockDice, 0, rng)
        if not roll then return nil, "invalid_dice" end
        block, reaction.blockRoll = math.max(0, roll.total + resistance), roll
    end
    local damageRoll = C.RollDiceString(attack.weaponDice, 0, rng)
    local damaged, result = M.ApplyDamageToUnit(draft, damageRoll.total, attack.damageType, block, rng)
    if not damaged then return nil, result end
    reaction.damage, reaction.damageRoll = result, damageRoll
    return damaged, reaction
end

function M.BuildUnitSyncPayload(unit, canEdit)
    if not unit then return nil end
    local guidStr = tostring(unit:GetGUID())
    local guidLow = C.IdString(unit:GetGUIDLow())
    local isPlayer = unit:ToPlayer() ~= nil
    local tStats = S.ResolveUnitStats(unit)

    if not tStats then
        return {
            guid       = guidStr,
            targetGuid = guidStr,
            guidLow    = guidLow,
            inSystem   = false,
            isPlayer   = isPlayer,
            name       = unit:GetName(),
            canEdit    = canEdit == true,
        }
    end

    local stats = {}
    for k, v in pairs(tStats.stats or {}) do
        if C.StatDefs[k] then stats[k] = v end
    end
    if tStats.isPlayer then
        for _, def in ipairs(C.StatOrder) do
            if (def.category == "combat" or def.category == "mastery") and stats[def.key] == nil then
                stats[def.key] = def.defaultValue
            end
        end
    end

    return {
        guid              = guidStr,
        targetGuid        = guidStr,
        guidLow           = guidLow,
        runtimeGuid       = tStats.runtimeGuid,
        inSystem          = true,
        isPlayer          = tStats.isPlayer,
        name              = tStats.name or unit:GetName(),
        archetype         = tStats.archetype,
        raceId            = tStats.raceId,
        level             = tStats.level or 1,
        roleType          = tStats.roleType,
        isStaticThreshold = tStats.isStaticThreshold,
        curHealth         = tStats.curHealth or 0,
        maxHealth         = math.max(1, tStats.maxHealth or 1),
        curEnergy         = tStats.curEnergy or 0,
        maxEnergy         = math.max(0, tStats.maxEnergy or 0),
        energySpentRound  = tStats.energySpentRound or 0,
        curWounds         = tStats.curWounds or 0,
        maxWounds         = tStats.maxWounds or 3,
        armor             = tStats.armor or 0,
        speed             = tStats.speed or 10,
        weaponDice        = tStats.weaponDice or "1d6",
        blockDice         = tStats.blockDice or "1d4",
        revision          = tStats.revision or 0,
        deathOutcome      = tStats.deathOutcome,
        canEdit           = canEdit == true,
        stats             = stats,
    }
end

function M.BroadcastUnitUpdate(unit, aio)
    aio = aio or _G.AIO
    if not unit or not aio or not aio.Handle then return end

    local recipients = (unit.GetPlayersInRange and unit:GetPlayersInRange(60))
        or (_G.GetPlayersInWorld and _G.GetPlayersInWorld()) or {}
    local selfPlayer = unit.ToPlayer and unit:ToPlayer() or nil
    if selfPlayer then
        recipients[#recipients + 1] = selfPlayer
    end

    local seen = {}
    for _, plr in ipairs(recipients) do
        local low = plr and plr.GetGUIDLow and tostring(plr:GetGUIDLow())
        if low and not seen[low] then
            if not _G.RpsTargetContext or plr == selfPlayer or _G.RpsTargetContext(plr, unit, false) then
                seen[low] = true
                local canEdit = _G.RpsTargetContext and _G.RpsTargetContext(plr, unit, true) or false
                local payload = M.BuildUnitSyncPayload(unit, canEdit)
                if payload then
                    aio.Handle(plr, C.AIO_PREFIX, "SyncUnit", payload)
                end
            end
        end
    end
end

function M.SyncTargetState(player, targetUnit, aio)
    aio = aio or _G.AIO
    if not player or not aio or not aio.Handle then return end
    local unit = targetUnit or (player.GetSelection and player:GetSelection())
    if unit and _G.RpsTargetContext and not _G.RpsTargetContext(player, unit, false) then
        unit = nil
    end
    if not unit then
        aio.Handle(player, C.AIO_PREFIX, "SyncTarget", { inSystem = false })
        return
    end
    local canEdit = _G.RpsTargetContext and _G.RpsTargetContext(player, unit, true) or false
    local payload = M.BuildUnitSyncPayload(unit, canEdit)
    aio.Handle(player, C.AIO_PREFIX, "SyncTarget", payload)
    aio.Handle(player, C.AIO_PREFIX, "SyncUnit", payload)
end

return M
