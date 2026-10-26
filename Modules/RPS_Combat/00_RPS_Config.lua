-- No hooks, SQL or spell grants on require.
local C = {
    AIO_PREFIX = "RPS_Combat",
    REACTION_TIMEOUT_SEC = 30,
    MAX_ENERGY_PER_ROUND = 6,
    FATE_DIE_COST = 3,
    BLOCK_ENERGY_COST = 2,
    DEFAULT_HEAL_DIFFICULTY = 8,
    MAX_DEFINITIONS = 128,
    -- Current health/energy may exceed the maximum ("bonus" resources); only this cap applies.
    MAX_RESOURCE = 1000000,
    StatDefs = {}, StatOrder = {}, SpellToStatKey = {},
}

C.Archetypes = {
    defender = { label = "Защитник", speed = 10,
        health = {20,22,24,26,29,31,33,35,37,40}, energy = {8,9,10,11,12,13,14,15,16,18},
        stats = { accuracy = {0,0,0,0,0,1,1,1,1,2}, healing = {-1,-1,-1,0,0,0,0,0,0,1},
            evasion = {2,2,2,2,2,3,3,3,3,4}, resistance = {1,1,1,1,1,2,2,2,2,3} } },
    fighter = { label = "Боец", speed = 10,
        health = {15,16,18,20,21,23,25,26,28,30}, energy = {10,11,12,14,15,16,18,19,20,22},
        stats = { accuracy = {2,2,2,2,2,3,3,3,3,4}, healing = {0,0,0,0,0,1,1,1,1,1},
            evasion = {1,1,1,1,1,2,2,2,2,3}, resistance = {-1,0,0,0,0,1,1,1,1,2} } },
    healer = { label = "Целитель", speed = 10,
        health = {10,11,12,14,15,16,18,19,20,22}, energy = {12,13,15,17,18,20,22,23,25,27},
        stats = { accuracy = {-1,-1,-1,0,0,0,0,0,0,1}, healing = {2,2,2,2,2,3,3,3,3,4},
            evasion = {1,1,1,1,1,2,2,2,2,3}, resistance = {0,0,0,0,0,1,1,1,1,2} } },
    caster = { label = "Заклинатель", speed = 10,
        health = {10,11,12,13,14,15,16,17,18,20}, energy = {14,16,18,20,23,25,27,29,31,34},
        stats = { accuracy = {1,1,1,1,1,2,2,2,2,3}, healing = {0,0,0,0,0,1,1,1,1,1},
            evasion = {-1,0,0,0,0,1,1,1,1,2}, resistance = {2,2,2,2,2,3,3,3,3,4} } },
}

function C.Integer(value, low, high)
    if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < low or value > high then
        return nil
    end
    return value
end

function C.ValidStatKey(key)
    return type(key) == "string" and #key <= 32 and key:match("^[a-z][a-z0-9_]*$") ~= nil
end

-- Preserve native uint64 userdata exactly. Never tonumber an identifier.
function C.IdString(value)
    if type(value) == "number" and not C.Integer(value, 0, 9007199254740991) then return nil end
    if type(value) ~= "number" and type(value) ~= "string" and type(value) ~= "userdata" then return nil end
    local text = type(value) == "number" and string.format("%.0f", value) or tostring(value)
    if not text:match("^%d+$") then return nil end
    text = text:gsub("^0+", "")
    if text == "" then text = "0" end
    if #text > 20 or (#text == 20 and text > "18446744073709551615") then return nil end
    return text
end

function C.ParseDice(formula)
    if type(formula) ~= "string" or #formula > 16 then return nil, "invalid_dice" end
    if formula:match("^%-?%d+$") then
        local flat = tonumber(formula)
        if C.Integer(flat, -1000, 1000) then return {count = 0, sides = 0, flat = flat} end
    end
    local count, sides, tail = formula:match("^(%d+)[dD](%d+)(.*)$")
    if not count then return nil, "invalid_dice" end
    if tail ~= "" and not tail:match("^[+-]%d+$") then return nil, "invalid_dice" end
    count, sides = tonumber(count), tonumber(sides)
    local flat = tail == "" and 0 or tonumber(tail)
    if not C.Integer(count, 1, 20) or not C.Integer(sides, 2, 100)
        or not C.Integer(flat, -1000, 1000) then return nil, "invalid_dice" end
    return {count = count, sides = sides, flat = flat}
end

local function Die(rng, sides)
    local value = (rng or math.random)(1, sides)
    assert(C.Integer(value, 1, sides), "RPS RNG returned an invalid face")
    return value
end

function C.RollDiceString(formula, extraBonus, rng)
    local dice, err = C.ParseDice(formula)
    if not dice then return nil, err end
    extraBonus = extraBonus or 0
    if not C.Integer(extraBonus, -1000, 1000) then return nil, "invalid_bonus" end
    local sum, rolls = dice.flat + extraBonus, {}
    for i = 1, dice.count do rolls[i] = Die(rng, dice.sides); sum = sum + rolls[i] end
    return {total = math.max(0, sum), rolls = rolls, flat = dice.flat + extraBonus, formula = formula}
end

function C.Roll3d6(modifier, fateBonus, fatigueStacks, rng)
    modifier, fateBonus, fatigueStacks = modifier or 0, fateBonus or 0, fatigueStacks or 0
    if not C.Integer(modifier, -1000, 1000) or not C.Integer(fateBonus, 0, 1000)
        or not C.Integer(fatigueStacks, 0, 1000) then return nil, "invalid_roll_modifier" end
    local d1, d2, d3 = Die(rng, 6), Die(rng, 6), Die(rng, 6)
    local matchedFace = 0
    if d1 == d2 or d1 == d3 then matchedFace = d1 elseif d2 == d3 then matchedFace = d2 end
    return {d1 = d1, d2 = d2, d3 = d3, diceSum = d1 + d2 + d3,
        modifier = modifier, fateBonus = fateBonus, total = d1 + d2 + d3 + modifier + fateBonus,
        matchedFace = matchedFace, energyGained = matchedFace > 0 and math.max(0, matchedFace - fatigueStacks) or 0}
end

local categories = {general = 1, combat = 2, mastery = 3, weapon = 4, action = 5}

-- Validate the whole replacement before publishing it. An invalid reload keeps the last registry.
function C.ReplaceStatDefinitions(rows)
    if type(rows) ~= "table" or #rows == 0 or #rows > C.MAX_DEFINITIONS then return false, "invalid_registry_size" end
    local defs, order, spells = {}, {}, {}
    local bytes=0
    for _, row in ipairs(rows) do
        if type(row) ~= "table" or not C.ValidStatKey(row.key) or defs[row.key]
            or not categories[row.category] or type(row.name) ~= "string" or #row.name == 0 or #row.name > 256
            or type(row.icon) ~= "string" or #row.icon > 256
            or type(row.description) ~= "string" or #row.description > 4096
            or not C.Integer(row.sortOrder, -100000, 100000)
            or not C.Integer(row.defaultValue, -1000, 1000)
            or not C.Integer(row.spellId, 0, 2147483647) then return false, "invalid_stat_definition" end
        if row.diceFormula ~= "none" and row.diceFormula ~= "weapon" and row.diceFormula ~= "shield"
            and not C.ParseDice(row.diceFormula) then return false, "invalid_dice" end
        if row.spellId > 0 and (spells[row.spellId] or row.diceFormula == "none") then return false, "invalid_spell_mapping" end
        bytes=bytes+#row.key+#row.name+#row.icon+#row.description+256
        if bytes>65536 then return false,"registry_too_large" end
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        defs[copy.key], order[#order + 1] = copy, copy
        if copy.spellId > 0 then spells[copy.spellId] = copy.key end
    end
    table.sort(order, function(a, b)
        if categories[a.category] ~= categories[b.category] then return categories[a.category] < categories[b.category] end
        if a.sortOrder ~= b.sortOrder then return a.sortOrder < b.sortOrder end
        return a.key < b.key
    end)
    C.StatDefs, C.StatOrder, C.SpellToStatKey = defs, order, spells
    return true
end

function C.LoadStatDefinitions(query)
    query = query or WorldDBQuery
    if type(query) ~= "function" then return false, "world_query_unavailable" end
    local q = query([[SELECT stat_key, category, sort_order, name_ru, icon, spell_id,
        dice_formula, default_value, description_ru FROM rps_stat_definitions
        WHERE is_active = 1 ORDER BY sort_order, stat_key]])
    if not q then return false, "registry_unavailable" end
    local rows = {}
    repeat
        rows[#rows + 1] = {key = q:GetString(0), category = q:GetString(1), sortOrder = q:GetInt32(2),
            name = q:GetString(3), icon = q:GetString(4), spellId = q:GetUInt32(5), diceFormula = q:GetString(6),
            defaultValue = q:GetInt32(7), description = q:GetString(8) or ""}
        if #rows > C.MAX_DEFINITIONS then return false, "invalid_registry_size" end
    until not q:NextRow()
    for _, def in ipairs(rows) do
        if def.spellId>0 and (not RpsIsDiceSpell or not RpsIsDiceSpell(def.spellId)) then
            return false,"unsafe_or_missing_dice_spell:"..def.key..":"..def.spellId
        end
    end
    return C.ReplaceStatDefinitions(rows)
end

return C
