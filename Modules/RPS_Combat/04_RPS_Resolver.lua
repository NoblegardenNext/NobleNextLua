-- Pure ResolvedSheet calculation: base -> set -> add -> cap -> derived.
-- Every call recomputes from the inputs; nothing is cached, accumulated or mutated.
-- Action conditions (target, range, state) and hard Control belong to the action resolver.
local K = require("Modules.RPS_Combat.03_RPS_Catalog")
local V = {}

V.CORE_STATS = {"maxHealth", "maxEnergy", "accuracy", "healing", "evasion", "resistance", "speed", "armor",
    "woundLimit", "healDifficulty", "energySpendLimit",
    "mastery.skill", "mastery.knowledge", "mastery.endurance", "mastery.craft"}
local CORE = {}
for _, key in ipairs(V.CORE_STATS) do CORE[key] = true end
local OPS = {add = true, set = true, cap = true}
local HANDS = {mainHand = true, offHand = true}
local MAX_EXTRA_MODIFIERS, MAX_MASTERY = 64, 20

-- Conditions decidable from the choices alone; any other condition is runtime-only (passive).
local STATIC_CONDITIONS = {
    ["self.size == small"] = function(ctx) return ctx.raceSize == "small" end,
    only_craft_mastery = function(ctx)
        local m = ctx.mastery
        return m and m.craft > 0 and m.skill == 0 and m.knowledge == 0 and m.endurance == 0
    end,
}

local function Integer(value, low, high)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= low and value <= high
end

local function Copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = Copy(item) end
    return out
end

local function Fail(errors, code, field)
    errors[#errors + 1] = {code = code, field = field}
end

local function ValidateItem(errors, slot, item)
    if type(item) ~= "table" or type(item.key) ~= "string" then return Fail(errors, "unknown_item", slot) end
    local quality = item.quality or "simple"
    if not K.Qualities[quality] then return Fail(errors, "invalid_quality", slot) end
    local kind = K.Weapons[item.key] and "weapon" or K.Shields[item.key] and "shield"
        or K.Armor[item.key] and "armor" or nil
    if not kind then return Fail(errors, "unknown_item", slot) end
    if (slot == "armor") ~= (kind == "armor") or (slot == "mainHand" and kind == "shield")
        or (slot == "offHand" and kind == "weapon" and K.Weapons[item.key].hands > 1) then
        return Fail(errors, "slot_mismatch", slot)
    end
    return {key = item.key, quality = quality, kind = kind}
end

local function ValidateEquipment(errors, equipment)
    if equipment == nil then return {} end
    if type(equipment) ~= "table" then Fail(errors, "invalid_equipment", "equipment"); return {} end
    local out = {}
    for slot, item in pairs(equipment) do
        if not HANDS[slot] and slot ~= "armor" then
            Fail(errors, "slot_mismatch", tostring(slot))
        else
            out[slot] = ValidateItem(errors, slot, item)
        end
    end
    local main = out.mainHand and K.Weapons[out.mainHand.key]
    if main and main.hands > 1 and out.offHand then Fail(errors, "hands_conflict", "offHand") end
    return out
end

local function ValidateExtra(errors, list)
    if list == nil then return {} end
    if type(list) ~= "table" or #list > MAX_EXTRA_MODIFIERS then
        Fail(errors, "invalid_modifier", "extraModifiers"); return {}
    end
    local out = {}
    for i, m in ipairs(list) do
        if type(m) ~= "table" or not OPS[m.op] or not CORE[m.target] or not Integer(m.value, -1000, 1000)
            or type(m.source) ~= "string" or #m.source == 0 or #m.source > 64 then
            Fail(errors, "invalid_modifier", "extraModifiers[" .. i .. "]")
        else
            out[#out + 1] = {source = "extra:" .. m.source, op = m.op, target = m.target, value = m.value}
        end
    end
    return out
end

local function FreeMasteryPoints(feature)
    local free = 0
    for _, m in ipairs(feature and feature.mechanics or {}) do
        if m.target == "masteryPointsFree" and m.op == "add" then free = free + m.value end
    end
    return free
end

-- Returns normalized choices and a list of {code, field}. Nothing is resolved here.
function V.Validate(input)
    local errors, n = {}, {}
    if type(input) ~= "table" then Fail(errors, "invalid_input", "input"); return nil, errors end
    n.archetype = input.archetype
    if not K.Archetype(n.archetype) then Fail(errors, "unknown_archetype", "archetype") end
    n.rpLevel = input.rpLevel
    if n.rpLevel == nil and input.serverLevel ~= nil then n.rpLevel = K.RpLevelFromServerLevel(input.serverLevel) end
    if not Integer(n.rpLevel, 1, #K.Xp) then Fail(errors, "invalid_level", "rpLevel") end

    n.race = input.race
    local race = K.Race(n.race)
    if not race then Fail(errors, "unknown_race", "race")
    elseif not K.Available(race) then Fail(errors, "race_unavailable", "race") end

    n.racialFeature = input.racialFeature
    local feature, owner = K.RacialFeature(n.racialFeature)
    if n.racialFeature == nil then Fail(errors, "racial_feature_required", "racialFeature")
    elseif not feature then Fail(errors, "unknown_racial_feature", "racialFeature")
    elseif race and owner ~= n.race then Fail(errors, "racial_feature_not_of_race", "racialFeature") end

    local traits = input.traits
    if traits == nil then traits = input.trait ~= nil and {input.trait} or {} end
    n.traits = {}
    if type(traits) ~= "table" then traits = {}; Fail(errors, "unknown_trait", "traits") end
    local seen = {}
    for i, key in ipairs(traits) do
        local trait = K.Trait(key)
        if not trait then Fail(errors, "unknown_trait", "traits[" .. i .. "]")
        elseif not K.Available(trait) then Fail(errors, "trait_unavailable", "traits[" .. i .. "]")
        elseif seen[key] then Fail(errors, "trait_duplicate", "traits[" .. i .. "]")
        else
            seen[key] = true
            n.traits[#n.traits + 1] = key
            if trait.choice == "mastery" then
                if input.traitChoice == nil then Fail(errors, "trait_choice_required", "traitChoice")
                elseif not K.Masteries[input.traitChoice] then Fail(errors, "invalid_trait_choice", "traitChoice")
                else n.traitChoice = input.traitChoice end
            end
        end
    end
    if #traits == 0 then Fail(errors, "trait_required", "traits")
    elseif #traits > 1 and #n.traits == #traits then Fail(errors, "too_many_traits", "traits") end

    n.mastery = {}
    local mastery, sum = input.mastery, 0
    if type(mastery) ~= "table" then Fail(errors, "invalid_mastery", "mastery"); mastery = {} end
    for key in pairs(mastery) do
        if not K.Masteries[key] then Fail(errors, "unknown_mastery", "mastery." .. tostring(key)) end
    end
    for _, key in ipairs(K.MasteryOrder) do
        local value = mastery[key] or 0
        if not Integer(value, 0, MAX_MASTERY) then Fail(errors, "invalid_mastery", "mastery." .. key); value = 0 end
        n.mastery[key], sum = value, sum + value
    end
    local expected = K.MasteryPointsAtCreation + ((feature and owner == n.race) and FreeMasteryPoints(feature) or 0)
    if sum ~= expected then Fail(errors, "mastery_points_mismatch", "mastery") end

    n.equipment = ValidateEquipment(errors, input.equipment)
    n.extraModifiers = ValidateExtra(errors, input.extraModifiers)
    return n, errors
end

local function Evaluate(value, ctx, perLevel)
    if value == "level+1" then return ctx.rpLevel + 1 end
    if type(value) == "number" and perLevel then return value * ctx.rpLevel end
    return value
end

-- Sorts one mechanic into the phase that consumes it.
local function Route(state, source, m)
    local passive = m.trigger or m.per ~= nil
    local conditionFn = m.condition and STATIC_CONDITIONS[m.condition]
    if m.condition and not conditionFn then passive = true end
    local target = m.target
    if state.traitChoice then target = target:gsub("<chosen>", state.traitChoice) end
    if passive then
        local copy = Copy(m)
        copy.target = target
        state.unapplied[#state.unapplied + 1] = copy
        return
    end
    local op = {source = source, op = m.op, target = target, perLevel = m.perLevel,
        value = Evaluate(m.value, state.ctx, m.perLevel), condition = m.condition}
    if target:match("^damage%.") then
        state.damageOps[#state.damageOps + 1] = op
    elseif conditionFn and not conditionFn(state.ctx) then
        state.skipped[#state.skipped + 1] = {source = source, target = target, condition = m.condition}
    elseif target == "masteryPointsFree" or target == "size" or m.inBase then
        state.noted[#state.noted + 1] = op
    elseif target == "equipmentSpeedPenalty" then
        state.speedPenaltyReduction[#state.speedPenaltyReduction + 1] = op
    elseif CORE[target] and type(op.value) == "number" then
        state.statOps[#state.statOps + 1] = op
    elseif op.op == "add" and type(op.value) == "number" then
        state.extraOps[#state.extraOps + 1] = op
    else
        state.flagOps[#state.flagOps + 1] = op
    end
end

local function Collect(state, source, entry)
    state.unapplied = {}
    for _, m in ipairs(entry.mechanics or {}) do Route(state, source, m) end
    state.features[#state.features + 1] = {source = source, key = entry.key, name = entry.name, text = entry.text}
    if #state.unapplied > 0 or #(entry.mechanics or {}) == 0 or entry.todo then
        state.passive[#state.passive + 1] = {source = source, key = entry.key, name = entry.name, text = entry.text,
            mechanics = state.unapplied, todo = entry.todo}
    end
end

local function Push(trace, target, entry)
    trace[target] = trace[target] or {}
    local list = trace[target]
    list[#list + 1] = entry
end

local function ApplyStats(sheet, base, ops, errors)
    local values, sets, adds, caps = {}, {}, {}, {}
    for _, key in ipairs(V.CORE_STATS) do
        values[key] = base[key].value
        Push(sheet.trace, key, {source = base[key].source, op = "base", value = base[key].value})
    end
    for _, op in ipairs(ops) do
        local bucket = op.op == "set" and sets or op.op == "add" and adds or caps
        bucket[#bucket + 1] = op
    end
    local setValue = {}
    for _, op in ipairs(sets) do
        if setValue[op.target] ~= nil and setValue[op.target] ~= op.value then
            Fail(errors, "conflicting_set", op.target)
        end
        setValue[op.target] = op.value
        values[op.target] = op.value
        Push(sheet.trace, op.target, {source = op.source, op = "set", value = op.value})
    end
    for _, op in ipairs(adds) do
        values[op.target] = values[op.target] + op.value
        Push(sheet.trace, op.target, {source = op.source, op = "add", value = op.value, perLevel = op.perLevel})
    end
    for _, op in ipairs(caps) do
        local applied = values[op.target] > op.value
        if applied then values[op.target] = op.value end
        Push(sheet.trace, op.target, {source = op.source, op = "cap", value = op.value, applied = applied})
    end
    for _, key in ipairs(V.CORE_STATS) do
        local mastery = key:match("^mastery%.(.+)$")
        if mastery then sheet.mastery[mastery] = values[key] else sheet[key] = values[key] end
    end
end

local function EquipmentOps(state, equipment)
    local speedPenalty = 0
    local function Add(source, m, value)
        local op = {source = source, op = m.op, target = m.target, value = value or m.value}
        state.statOps[#state.statOps + 1] = op
        if op.target == "speed" and op.value < 0 then speedPenalty = speedPenalty + op.value end
    end
    local armor = equipment.armor
    if armor then
        local def, source = K.Armor[armor.key], "item:armor:" .. armor.key
        Add(source, {op = "add", target = "armor"}, def.armor + K.Qualities[armor.quality].modifier)
        for _, m in ipairs(def.mechanics) do Add(source, m) end
    end
    local shield = equipment.offHand and equipment.offHand.kind == "shield" and equipment.offHand
    if shield then
        for _, m in ipairs(K.Shields[shield.key].mechanics) do Add("item:offHand:" .. shield.key, m) end
    end
    -- TODO: reduction per item vs total penalty and "Закалка" + "Большой" are open; applied once to the total.
    local reduction, source = 0, nil
    for _, op in ipairs(state.speedPenaltyReduction) do reduction, source = reduction - op.value, op.source end
    if reduction > 0 and speedPenalty < 0 then
        state.statOps[#state.statOps + 1] = {source = source, op = "add", target = "speed",
            value = math.min(reduction, -speedPenalty)}
    end
end

local function SumOps(trace, ops, into)
    for _, op in ipairs(ops) do
        into[op.target] = (into[op.target] or 0) + op.value
        Push(trace, op.target, {source = op.source, op = op.op, value = op.value})
    end
end

local function Derive(sheet, state, equipment)
    local ctx, extra, flags = state.ctx, sheet.extra, sheet.flags
    ctx.mastery = sheet.mastery
    for _, op in ipairs(state.flagOps) do
        flags[op.target] = Copy(op.value)
        Push(sheet.trace, op.target, {source = op.source, op = op.op, value = Copy(op.value)})
    end
    SumOps(sheet.trace, state.extraOps, extra)

    local damage = {strike = 0, throw = 0, shot = 0, magic = 0, anyWeapon = 0}
    for _, op in ipairs(state.damageOps) do
        local fn = op.condition and STATIC_CONDITIONS[op.condition]
        local value = op.value
        if type(value) == "string" then value = sheet.mastery[value:match("^mastery%.(.+)$") or ""] end
        local key = op.target:match("^damage%.(.+)$")
        if (not fn or fn(ctx)) and type(value) == "number" and damage[key] then
            damage[key] = damage[key] + value
            Push(sheet.trace, op.target, {source = op.source, op = op.op, value = value})
        end
    end
    sheet.damageBonus = damage

    local unlock = flags.abilityUnlockLevels
    local open = 0
    for i, slot in ipairs(K.PersonalAbilitySlots) do
        local level = unlock and unlock[i] or slot.unlockLevel
        local isOpen = ctx.rpLevel >= level
        if isOpen then open = open + 1 end
        sheet.abilitySlotList[i] = {slot = slot.slot, cost = slot.cost, unlockLevel = level, open = isOpen}
    end
    sheet.abilitySlots = open
    Push(sheet.trace, "abilitySlots", {source = "archetype:" .. ctx.archetype, op = "base", value = ctx.row.abilitySlots})
    if open ~= ctx.row.abilitySlots then
        Push(sheet.trace, "abilitySlots", {source = "flags:abilityUnlockLevels", op = "set", value = open})
    end

    sheet.fateDie = {die = flags["fateDie.die"] or K.Base.fateDie, minResult = flags["fateDie.minResult"],
        deathSave = false}

    -- Without a shield: 1 + Resistance + Armor; with a shield: die + Resistance + shield quality.
    local shield = equipment.offHand and equipment.offHand.kind == "shield" and equipment.offHand
    if shield then
        local def, quality = K.Shields[shield.key], K.Qualities[shield.quality].modifier
        local die = K.StepDie(def.blockDie, extra["block.dieStep"] or 0)
        sheet.block = {source = "item:offHand:" .. shield.key, die = die, flat = sheet.resistance + quality,
            resistance = sheet.resistance, quality = quality, fullBlockCost = def.fullBlockCost}
    else
        -- TODO: "Мясной щит" raises the block die, but the no-shield base 1 has no stepped die yet.
        sheet.block = {source = "rule:block", base = 1, flat = 1 + sheet.resistance + sheet.armor,
            resistance = sheet.resistance, armor = sheet.armor}
    end

    local attacks = sheet.attacks
    local unarmedStep = extra["attack.unarmed.dieStep"] or 0
    attacks[#attacks + 1] = {hand = "unarmed", mode = "strike", range = K.AttackRanges.strike,
        min = 1, max = math.max(1, sheet.mastery.endurance), bonus = damage.strike,
        -- TODO: "1-X" counts as die I when stepped; replacing the range with the stepped die is unconfirmed.
        dice = unarmedStep > 0 and (K.StepDie("1d1", unarmedStep)) or nil}
    local magicStep = extra["attack.magic.dieStep"] or 0
    if flags["grants.innateSpell"] then
        local step = magicStep + (extra["attack.innate.dieStep"] or 0)
        attacks[#attacks + 1] = {hand = "innate", mode = "magic", range = K.AttackRanges.magic, energyCost = 1,
            min = 1, max = math.max(1, sheet.mastery.knowledge), bonus = damage.magic,
            dice = step > 0 and (K.StepDie("1d1", step)) or nil,
            canHeal = flags["grants.wandStaffHeal"] == true, healDieStep = extra["attack.innate.healDieStep"]}
    end
    for _, hand in ipairs({"mainHand", "offHand"}) do
        local item = equipment[hand]
        local def = item and item.kind == "weapon" and K.Weapons[item.key]
        if def then
            for _, mode in ipairs({"strike", "throw", "shot", "magic"}) do
                local die = def.dice[mode]
                if die then
                    local stepped = mode == "magic" and K.StepDie(die, magicStep) or die
                    attacks[#attacks + 1] = {hand = hand, mode = mode, item = item.key, dice = stepped,
                        range = K.AttackRanges[mode] * (mode == "strike" and def.strikeRangeMultiplier or 1),
                        bonus = K.Qualities[item.quality].modifier + damage[mode] + damage.anyWeapon,
                        energyCost = mode == "magic" and def.magicEnergyCost or nil,
                        reload = mode == "shot" and def.reload or nil, quick = hand == "offHand" or nil,
                        canHeal = mode == "magic" and flags["grants.wandStaffHeal"] == true or nil}
                end
            end
        end
    end
end

-- input = {archetype, rpLevel | serverLevel, race, racialFeature, trait | traits, traitChoice?,
--          mastery = {skill, knowledge, endurance, craft}, equipment?, extraModifiers?}
-- Returns sheet or nil, firstErrorCode, errors.
function V.Resolve(input)
    local n, errors = V.Validate(input)
    if #errors > 0 then return nil, errors[1].code, errors end
    local arch, race = K.Archetype(n.archetype), K.Race(n.race)
    local row = arch.levels[n.rpLevel]
    local feature = K.RacialFeature(n.racialFeature)
    local ctx = {rpLevel = n.rpLevel, archetype = n.archetype, row = row, raceSize = race.size}
    local state = {ctx = ctx, traitChoice = n.traitChoice, statOps = {}, extraOps = {}, flagOps = {},
        damageOps = {}, speedPenaltyReduction = {}, noted = {}, skipped = {}, features = {}, passive = {}}

    for _, entry in ipairs(arch.features) do Collect(state, "archetype:" .. n.archetype .. ":" .. entry.key, entry) end
    Collect(state, "race:" .. n.race .. ":" .. feature.key, feature)
    for _, key in ipairs(n.traits) do Collect(state, "trait:" .. key, K.Trait(key)) end

    local sizeKey, sizeSource = race.size, "race:" .. n.race
    for _, op in ipairs(state.noted) do
        if op.target == "size" and op.op == "set" then sizeKey, sizeSource = op.value, op.source end
    end
    local size = K.Size(sizeKey)
    for _, m in ipairs(size.mechanics) do
        if not m.inBase then state.statOps[#state.statOps + 1] = {source = "size:" .. sizeKey, op = m.op,
            target = m.target, value = m.value} end
    end
    EquipmentOps(state, n.equipment)
    for _, op in ipairs(n.extraModifiers) do state.statOps[#state.statOps + 1] = op end

    local sheet = {version = K.CATALOG_VERSION, archetype = n.archetype, rpLevel = n.rpLevel,
        serverLevel = K.ServerLevelFromRpLevel(n.rpLevel), race = n.race, racialFeature = n.racialFeature,
        traits = Copy(n.traits), traitChoice = n.traitChoice, size = sizeKey, sizeName = size.name,
        mastery = {}, extra = {}, flags = {}, attacks = {}, abilitySlotList = {}, trace = {},
        features = state.features, passive = state.passive, skipped = state.skipped,
        inputs = {mastery = Copy(n.mastery), equipment = Copy(n.equipment)}}
    local archSource = "archetype:" .. n.archetype
    local base = {
        maxHealth = {source = archSource, value = row.maxHealth}, maxEnergy = {source = archSource, value = row.maxEnergy},
        accuracy = {source = archSource, value = row.accuracy}, healing = {source = archSource, value = row.healing},
        evasion = {source = archSource, value = row.evasion}, resistance = {source = archSource, value = row.resistance},
        speed = {source = "size:" .. sizeKey, value = size.speed}, armor = {source = "rule", value = K.Base.armor},
        woundLimit = {source = "rule", value = K.Base.woundLimit},
        healDifficulty = {source = "rule", value = K.Base.healDifficulty},
        energySpendLimit = {source = "rule", value = K.Base.energySpendLimit},
    }
    for _, key in ipairs(K.MasteryOrder) do
        base["mastery." .. key] = {source = "allocation", value = n.mastery[key]}
    end
    Push(sheet.trace, "size", {source = sizeSource, op = sizeSource == "race:" .. n.race and "base" or "set",
        value = sizeKey})
    sheet.masteryPoints = K.MasteryPointsAtCreation
    Push(sheet.trace, "masteryPoints", {source = "rule", op = "base", value = K.MasteryPointsAtCreation})
    for _, op in ipairs(state.noted) do
        if op.target == "masteryPointsFree" then
            sheet.masteryPoints = sheet.masteryPoints + op.value
            Push(sheet.trace, "masteryPoints", {source = op.source, op = "add", value = op.value})
        end
    end

    ApplyStats(sheet, base, state.statOps, errors)
    if #errors > 0 then return nil, errors[1].code, errors end
    Derive(sheet, state, n.equipment)
    return sheet
end

return V
