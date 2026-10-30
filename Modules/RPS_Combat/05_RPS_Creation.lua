-- Server side: creation options, preview, confirm, staff reconfigure, race and archetype resets; starter kit.
-- No hooks, SQL or AIO on require: Init calls Cr.Register(R, H, Ensure) into its single handler table.
-- The client never supplies numbers: every sheet is recomputed by V.Resolve at the server RP level.
local C = require("Modules.RPS_Combat.00_RPS_Config")
local S = require("Modules.RPS_Combat.01_RPS_Storage")
local K = require("Modules.RPS_Combat.03_RPS_Catalog")
local V = require("Modules.RPS_Combat.04_RPS_Resolver")
local Escape = require("Core.DB").EscapeSqlString
local Cr = {Seen = {}, Ticks = {}}
local R, N, AIO, Ensure
local prefix = C.AIO_PREFIX
local MAX_SEEN, SEEN_TTL = 32, 300

local MESSAGES = {
    invalid_input = "Некорректные данные формы",
    unknown_archetype = "Выберите архетип из списка",
    invalid_level = "Недопустимый уровень персонажа",
    unknown_race = "Выберите расу из списка",
    race_unavailable = "Эта раса пока в разработке",
    racial_feature_required = "Выберите одну расовую особенность",
    unknown_racial_feature = "Неизвестная расовая особенность",
    racial_feature_not_of_race = "Особенность не принадлежит выбранной расе",
    trait_required = "Выберите одну общую черту",
    unknown_trait = "Неизвестная общая черта",
    trait_unavailable = "Эта черта пока в разработке",
    trait_duplicate = "Одну черту нельзя взять дважды",
    too_many_traits = "Можно выбрать только одну общую черту",
    trait_choice_required = "Черта требует выбрать Мастерство",
    invalid_trait_choice = "Выберите Мастерство для черты",
    invalid_mastery = "Очки Мастерства — целые неотрицательные числа",
    unknown_mastery = "Неизвестное Мастерство",
    mastery_points_mismatch = "Распределите все очки Мастерства ровно",
    invalid_equipment = "Некорректная экипировка",
    unknown_item = "Предмета нет в стартовом списке",
    invalid_quality = "При создании доступно только Простое качество",
    slot_mismatch = "Предмет не подходит для слота",
    hands_conflict = "Двуручное оружие занимает обе руки",
    invalid_modifier = "Некорректный модификатор",
    conflicting_set = "Выбранные особенности конфликтуют",
    invalid_starter = "Некорректный список стартовых предметов",
    too_many_items = "Можно взять не больше 6 стартовых предметов",
    invalid_draft = "В выборе персонажа есть ошибки",
    revision_conflict = "Персонаж уже изменён — обновите форму",
    request_conflict = "Этот запрос уже использован с другими данными",
    request_pending = "Запрос уже обрабатывается",
    request_window_full = "Слишком много незавершённых запросов",
    already_configured = "Персонаж уже настроен; изменение — через ведущего",
    not_configured = "У персонажа нет RP-настройки",
    already_reconfigure = "Перенастройка уже разрешена",
    permission_denied = "Недостаточно прав",
    invalid_reason = "Укажите причину (3–255 символов)",
    target_not_found = "Персонаж не найден",
    actor_busy = "Персонаж занят другой операцией, повторите",
    save_failed = "Не удалось сохранить; черновик сохранён — повторите",
    partial_commit = "Сохранение прервано; требуется проверка ведущим",
    system_unavailable = "RP-система временно недоступна",
    creation_unavailable = "Создание персонажа недоступно: схема БД не применена",
    creation_schema_unavailable = "Создание персонажа недоступно: схема БД не применена",
    receipt_unavailable = "Журнал запросов недоступен, повторите позже",
    rate_limited = "Слишком частые запросы",
    invalid_request_id = "Некорректный идентификатор запроса",
    invalid_revision = "Некорректная ревизия",
    profile_unavailable = "RP-профиль недоступен",
    player_offline = "Персонаж вышел из игры",
    starter_already_granted = "Стартовый набор уже выдан и повторно не выдаётся",
    resources_kept = "Текущие ОЗ/ОЭ, Раны и XP сохраняются; максимумы пересчитываются",
    first_creation = "После подтверждения ОЗ и ОЭ будут восполнены до максимума",
    race_scope_only = "Сейчас можно изменить только расу и расовую особенность",
    race_preset_current = "Расовый пресет не обновлялся — сброс расы недоступен",
    race_reset_scope = "Сброшены только раса и расовая особенность; остальной выбор и ресурсы сохранены",
    archetype_scope_only = "Сейчас можно изменить только архетип",
    archetype_reset_scope = "Сброшен только архетип; остальной выбор и ресурсы сохранены",
    archetype_reset_cost_changed = "Стоимость смены архетипа изменилась — проверьте цену и повторите",
    not_enough_money = "Недостаточно денег для смены архетипа",
}
function Cr.Message(code) return MESSAGES[code] or code end

local function Integer(value, low, high) return C.Integer(value, low, high) ~= nil end
local function Id(player) return C.IdString(player:GetGUIDLow()) end
local function Q(value) return "'" .. Escape(value or "") .. "'" end
local function Trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Minimal JSON for the audit snapshot: strings, numbers, booleans, arrays and string-keyed tables.
local function Json(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('[%c"\\]', function(ch)
            local named = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}
            return named[ch] or string.format("\\u%04x", ch:byte())
        end) .. '"'
    elseif kind == "number" then
        return value % 1 == 0 and string.format("%d", value) or tostring(value)
    elseif kind == "boolean" then return tostring(value)
    elseif kind ~= "table" then return "null" end
    if #value > 0 or next(value) == nil then
        local parts = {}
        for i, item in ipairs(value) do parts[i] = Json(item) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = Json(key) .. ":" .. Json(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end
Cr.Json = Json

-- Starter catalog: every Simple-quality weapon, shield and armor plus the consumables.
-- The kit has no item list of its own, so it is derived from the equipment catalog.
local CONSUMABLES = {
    {key = "arrow", name = "Стрела", stack = 10}, {key = "bullet", name = "Пуля", stack = 10},
    {key = "healing_potion", name = "Зелье лечения", stack = 1}, {key = "mana_potion", name = "Зелье маны", stack = 1},
    {key = "ration", name = "Паёк", stack = 1}, {key = "repair_kit", name = "Ремонтный набор", stack = 1},
    {key = "first_aid_kit", name = "Аптечка", stack = 1},
}
local MODE_NAMES = {strike = "Удар", throw = "Бросок", shot = "Выстрел", magic = "Магия"}
local WEAPON_ORDER = {"one_handed_common", "one_handed_throwing", "one_handed_reach", "one_handed_magic",
    "one_handed_ranged", "one_handed_gunpowder", "two_handed_common", "two_handed_reach",
    "two_handed_magic", "two_handed_long_range", "two_handed_ranged", "two_handed_gunpowder"}

local function SortedKeys(map)
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function BuildStarterCatalog()
    local items, byKey = {}, {}
    local function Add(item) items[#items + 1], byKey[item.key] = item, item end
    local listed, weapons = {}, {}
    for _, key in ipairs(WEAPON_ORDER) do if K.Weapons[key] then listed[key] = true; weapons[#weapons + 1] = key end end
    for _, key in ipairs(SortedKeys(K.Weapons)) do if not listed[key] then weapons[#weapons + 1] = key end end
    for _, key in ipairs(weapons) do
        local def, dice = K.Weapons[key], {}
        for _, mode in ipairs({"strike", "throw", "shot", "magic"}) do
            if def.dice[mode] then dice[#dice + 1] = MODE_NAMES[mode] .. " " .. def.dice[mode] end
        end
        Add({key = key, name = def.group .. " (" .. def.property .. ")", kind = "weapon",
            slot = def.hands > 1 and "twoHand" or "oneHand", dice = table.concat(dice, ", "), quality = "simple"})
    end
    for _, key in ipairs(SortedKeys(K.Shields)) do
        local def = K.Shields[key]
        Add({key = key, name = def.name, kind = "shield", slot = "offHand", dice = "Блок " .. def.blockDie, quality = "simple"})
    end
    for _, key in ipairs(SortedKeys(K.Armor)) do
        local def = K.Armor[key]
        Add({key = key, name = def.name, kind = "armor", slot = "armor", armor = def.armor, quality = "simple"})
    end
    -- TODO: a consumable takes one starter item as a full cell (arrows/bullets 10 per cell).
    for _, def in ipairs(CONSUMABLES) do
        Add({key = def.key, name = def.name, kind = "consumable", slot = "consumable", stack = def.stack, quality = "simple"})
    end
    return items, byKey
end
Cr.StarterItems, Cr.StarterByKey = BuildStarterCatalog()

local function MasteryFree(feature)
    local free = 0
    for _, m in ipairs(feature.mechanics or {}) do
        if m.target == "masteryPointsFree" and m.op == "add" then free = free + m.value end
    end
    return free
end

local function BuildOptions()
    local races, traits, archetypes = {}, {}, {}
    for _, key in ipairs(K.RaceOrder) do
        local race = K.Races[key]
        if K.Available(race) then
            local features = {}
            for _, f in ipairs(race.features) do
                local free = MasteryFree(f)
                features[#features + 1] = {key = f.key, name = f.name, text = f.text, masteryFree = free > 0 and free or nil}
            end
            races[#races + 1] = {key = key, name = race.name, size = race.size,
                sizeName = K.Sizes[race.size] and K.Sizes[race.size].name, features = features,
                preset = race.preset, presetVersion = race.presetVersion}
        end
    end
    for _, key in ipairs(K.TraitOrder) do
        local trait = K.Traits[key]
        if K.Available(trait) then
            local entry = {key = key, name = trait.name, text = trait.text, fixing = trait.fixing or nil}
            if trait.choice == "mastery" then
                entry.needsChoice, entry.choices = true, {}
                for _, m in ipairs(K.MasteryOrder) do entry.choices[#entry.choices + 1] = {key = m, name = K.Masteries[m].name} end
            end
            traits[#traits + 1] = entry
        end
    end
    for _, key in ipairs(K.ArchetypeOrder) do
        local arch = K.Archetypes[key]
        local feature = arch.features[1] or {}
        archetypes[#archetypes + 1] = {key = key, name = arch.name, description = arch.description,
            featureName = feature.name, featureText = feature.text}
    end
    local masteryNames = {}
    for _, key in ipairs(K.MasteryOrder) do masteryNames[key] = K.Masteries[key].name end
    return {catalogVersion = K.CATALOG_VERSION, races = races, traits = traits, archetypes = archetypes,
        mastery = {keys = {"skill", "knowledge", "endurance", "craft"}, names = masteryNames,
            basePoints = K.MasteryPointsAtCreation},
        starter = {maxItems = K.StarterKit.maxItems, quality = K.StarterKit.quality, items = Cr.StarterItems}}
end
Cr.Options = BuildOptions()

function Cr.RpLevel(player)
    local level = player.GetLevel and player:GetLevel() or 10
    if type(level) ~= "number" then level = 10 end
    return math.max(1, math.min(#K.Xp, level - 9))
end

local function NormalizeStarter(list, errors)
    if list == nil then return {} end
    if type(list) ~= "table" then errors[#errors + 1] = {code = "invalid_starter", field = "starterItems"}; return {} end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count ~= #list then errors[#errors + 1] = {code = "invalid_starter", field = "starterItems"}; return {} end
    if #list > K.StarterKit.maxItems then
        errors[#errors + 1] = {code = "too_many_items", field = "starterItems"}; return {}
    end
    local items = {}
    for i, entry in ipairs(list) do
        local key, quality = entry, "simple"
        if type(entry) == "table" then key, quality = entry.key, entry.quality or "simple" end
        local def = type(key) == "string" and Cr.StarterByKey[key]
        local field = "starterItems[" .. i .. "]"
        if not def then errors[#errors + 1] = {code = "unknown_item", field = field}
        elseif type(quality) ~= "string" or not K.Qualities[quality] or not K.Qualities[quality].starterAllowed then
            errors[#errors + 1] = {code = "invalid_quality", field = field}
        else
            items[#items + 1] = {key = def.key, kind = def.kind, quality = quality, stack = def.stack or 1}
        end
    end
    return items
end

-- Returns {input, n, items, signature}, errors. Builds the resolver input field by field:
-- equipment, extraModifiers, levels or any number from the client never reach the resolver.
-- RP names live in TotalRP: a draft.rpName from an old client is ignored.
function Cr.NormalizeDraft(draft, rpLevel)
    local errors = {}
    if type(draft) ~= "table" then return nil, {{code = "invalid_input", field = "draft"}} end
    local input = {archetype = draft.archetype, rpLevel = rpLevel, race = draft.race,
        racialFeature = draft.racialFeature, trait = draft.trait, traitChoice = draft.traitChoice,
        mastery = draft.mastery}
    local n, validation = V.Validate(input)
    for _, e in ipairs(validation or {}) do errors[#errors + 1] = e end
    local items = NormalizeStarter(draft.starterItems, errors)
    if #errors > 0 then return nil, errors end
    local keys = {}
    for i, item in ipairs(items) do keys[i] = item.key .. "@" .. item.quality end
    local m = n.mastery
    local signature = table.concat({"v2", n.race, n.racialFeature, n.traits[1] or "", n.traitChoice or "",
        n.archetype, m.skill .. "," .. m.knowledge .. "," .. m.endurance .. "," .. m.craft, table.concat(keys, ",")}, "|")
    input.traitChoice = n.traitChoice
    return {input = input, n = n, items = items, signature = signature}, errors
end

-- Every unfilled choice of an incomplete draft, in wizard order, so the client can list them.
function Cr.MissingFields(draft)
    local missing = {}
    local function Add(step, field, message, extra)
        local entry = {step = step, field = field, message_ru = message}
        for key, value in pairs(extra or {}) do entry[key] = value end
        missing[#missing + 1] = entry
    end
    if type(draft) ~= "table" then draft = {} end
    local race = K.Race(draft.race)
    if not race then Add("race", "race", "Не выбрана раса") end
    local feature, owner = K.RacialFeature(draft.racialFeature)
    if not feature or (race and owner ~= draft.race) then
        Add("race", "racialFeature", "Не выбрана расовая особенность")
    end
    local traitKey = draft.trait
    if traitKey == nil and type(draft.traits) == "table" then traitKey = draft.traits[1] end
    local trait = K.Trait(traitKey)
    if not trait or not K.Available(trait) then Add("trait", "trait", "Не выбрана общая черта")
    elseif trait.choice == "mastery" and not K.Masteries[draft.traitChoice] then
        Add("trait", "traitChoice", "Не выбрано Мастерство для черты «" .. trait.name .. "»")
    end
    local expected, sum = K.MasteryPointsAtCreation + ((feature and race and owner == draft.race) and MasteryFree(feature) or 0), 0
    if type(draft.mastery) == "table" then
        for _, key in ipairs(K.MasteryOrder) do
            local value = draft.mastery[key]
            if Integer(value, 0, 20) then sum = sum + value end
        end
    end
    if sum < expected then
        Add("mastery", "mastery", "Осталось распределить очков Мастерства: " .. (expected - sum), {left = expected - sum})
    end
    if not K.Archetype(draft.archetype) then Add("archetype", "archetype", "Не выбран архетип") end
    -- Equipment is not part of the wizard (starter vendor); starterItems stays an optional legacy field.
    return missing
end

local function Localize(errors, n)
    local out = {}
    for i, e in ipairs(errors) do
        local message = Cr.Message(e.code)
        if e.code == "mastery_points_mismatch" and n then message = message .. " (нужно " .. n .. ")" end
        out[i] = {code = e.code, field = e.field, message_ru = message}
    end
    return out
end

local function ExpectedMastery(draft)
    local feature, owner = K.RacialFeature(type(draft) == "table" and draft.racialFeature or nil)
    local free = feature and type(draft) == "table" and owner == draft.race and MasteryFree(feature) or 0
    return K.MasteryPointsAtCreation + free
end

function Cr.SheetSummary(sheet)
    local passive = {}
    for _, entry in ipairs(sheet.passive or {}) do
        passive[#passive + 1] = tostring(entry.name or entry.key) .. ": " .. tostring(entry.text or "")
    end
    local mastery = {}
    for _, key in ipairs(K.MasteryOrder) do mastery[key] = sheet.mastery[key] end
    local block = sheet.block or {}
    return {rpLevel = sheet.rpLevel, archetype = sheet.archetype, race = sheet.race, size = sheet.size,
        sizeName = sheet.sizeName, maxHealth = sheet.maxHealth, maxEnergy = sheet.maxEnergy,
        accuracy = sheet.accuracy, healing = sheet.healing, evasion = sheet.evasion, resistance = sheet.resistance,
        speed = sheet.speed, armor = sheet.armor, woundLimit = sheet.woundLimit, healDifficulty = sheet.healDifficulty,
        energySpendLimit = sheet.energySpendLimit, mastery = mastery, masteryPoints = sheet.masteryPoints,
        abilitySlots = sheet.abilitySlots, fateDie = sheet.fateDie and sheet.fateDie.die,
        block = {die = block.die, flat = block.flat, base = block.base}, passive = passive}
end

-- 'race' after a race data reset (race cleared, other choices kept), 'archetype' after a player
-- archetype reset (archetype cleared), 'full' after a staff reconfigure.
-- Derived from the record, so it survives a relog without its own column.
function Cr.Scope(rec)
    if rec.state ~= "reconfigure" then return nil end
    if rec.race == "" then return "race" end
    return rec.archetype == "" and "archetype" or "full"
end

-- A player may reset race data only when the preset of their confirmed race got a newer version.
function Cr.RaceUpdateAvailable(rec)
    return rec.state == "complete" and rec.race ~= "" and S.HasRacePresetColumn()
        and (rec.racePresetVersion or 0) < K.RacePresetVersion(rec.race)
end

function Cr.Summary(rec)
    local out = {state = rec.state, revision = rec.revision, catalogVersion = rec.catalogVersion,
        starterGranted = rec.starterGranted, confirmedAt = rec.confirmedAt, scope = Cr.Scope(rec),
        raceUpdateAvailable = Cr.RaceUpdateAvailable(rec) == true, racePresetVersion = rec.racePresetVersion or 0}
    if rec.state ~= "none" and rec.state ~= "legacy" then
        out.race = rec.race ~= "" and rec.race or nil
        out.racialFeature = rec.racialFeature ~= "" and rec.racialFeature or nil
        out.archetype = rec.archetype
        out.trait, out.traitChoice = rec.traits[1], rec.traitChoice ~= "" and rec.traitChoice or nil
        out.mastery = {skill = rec.mastery.skill, knowledge = rec.mastery.knowledge,
            endurance = rec.mastery.endurance, craft = rec.mastery.craft}
    end
    return out
end

local function DraftFrom(rec, profile)
    if rec.state == "none" then return nil end
    local draft = {}
    if rec.state == "legacy" then
        draft.archetype = (profile and profile.archetype) or (rec.archetype ~= "" and rec.archetype or nil)
        local race = profile and profile.raceId or rec.race
        if K.Available(K.Race(race)) then draft.race = race end
        return draft
    end
    draft.race = rec.race ~= "" and rec.race or nil
    draft.racialFeature = rec.racialFeature ~= "" and rec.racialFeature or nil
    draft.archetype = rec.archetype ~= "" and rec.archetype or nil
    draft.trait, draft.traitChoice = rec.traits[1], rec.traitChoice ~= "" and rec.traitChoice or nil
    draft.mastery = {skill = rec.mastery.skill, knowledge = rec.mastery.knowledge,
        endurance = rec.mastery.endurance, craft = rec.mastery.craft}
    return draft
end

local function ProfileSummary(p)
    local stats = {}
    for key, value in pairs(p.stats or {}) do stats[key] = value end
    return {guid = p.guid, archetype = p.archetype, raceId = p.raceId, racialTrait = p.racialTrait,
        commonTrait = p.commonTrait, level = p.level, xp = p.xp, revision = p.revision,
        curHealth = p.curHealth, maxHealth = p.maxHealth, curEnergy = p.curEnergy, maxEnergy = p.maxEnergy,
        curWounds = p.curWounds, maxWounds = p.maxWounds, armor = p.armor, speed = p.speed, stats = stats}
end

local function Snapshot(rec, p)
    local before = Cr.Summary(rec)
    before.traits, before.race, before.archetype = rec.traits, rec.race, rec.archetype
    if p then
        before.profile = ProfileSummary(p)
        before.profile.weaponDice, before.profile.blockDice = p.weaponDice, p.blockDice
        before.profile.equipJsonBytes, before.profile.effectsJsonBytes = #(p.equipJson or ""), #(p.effectsJson or "")
    end
    return before
end

local function Send(player, method, payload) if player then AIO.Handle(player, prefix, method, payload) end end

function Cr.Fail(player, code, requestId, errors)
    if type(requestId) ~= "string" or #requestId > 80 then requestId = nil end
    Send(player, "CharacterError", {code = code, message_ru = Cr.Message(code), requestId = requestId,
        reason = code == "system_unavailable" and R and R.unavailableReason or nil, errors = errors})
end
local Fail = Cr.Fail

local function Guard(player, requestId)
    if not R.ready then Fail(player, "system_unavailable", requestId); return false end
    return true
end

local function Rate(player, kind, interval)
    local key = Id(player) .. ":" .. kind
    local now = GetCurrTime()
    local last = Cr.Ticks[key]
    if last and now >= last and now - last < interval then return false end
    Cr.Ticks[key] = now
    return true
end

local function ValidRequestId(id)
    return type(id) == "string" and #id >= 1 and #id <= 80 and id:match("^[%w_-]+$") ~= nil
end

local function LoadCreation(guid)
    if Cr.schemaRetryAt and os.time() < Cr.schemaRetryAt then return nil, "creation_unavailable" end
    local rec, err = S.GetOrLoadCreation(guid)
    if err == "creation_schema_unavailable" then
        Cr.schemaRetryAt = os.time() + 60
        if N then N.Log("RPS_Combat", "creation_schema_unavailable") end
        return nil, "creation_unavailable"
    end
    Cr.schemaRetryAt = nil
    return rec, err
end

-- Returns seen map or nil when the window of unfinished requests is full.
local function SeenFor(key)
    local seen, count, now = Cr.Seen[key] or {}, 0, os.time()
    Cr.Seen[key] = seen
    for id, record in pairs(seen) do
        if now - record.created > SEEN_TTL then seen[id] = nil else count = count + 1 end
    end
    return seen, count
end

-- false = no receipt; nil, why = lookup failed; table = stored receipt.
local function DurableReceipt(issuer, requestId)
    local where = " WHERE issuer_guid=" .. issuer .. " AND request_id=" .. Q(requestId)
    local count = CharDBQuery("SELECT COUNT(*) FROM rps_action_receipts" .. where)
    if not count then return nil, "receipt_unavailable" end
    if count:GetUInt32(0) == 0 then return false end
    local q = CharDBQuery("SELECT signature,state FROM rps_action_receipts" .. where)
    if not q then return nil, "receipt_unavailable" end
    return {signature = q:GetString(0), state = q:GetString(1)}
end

local function ReceiptSql(issuer, requestId, signature, kind, revision)
    return string.format([[INSERT INTO rps_action_receipts
        (issuer_guid,request_id,signature,state,result_kind,stat_key,total,damage,attack_id)
        VALUES (%s,%s,%s,'done',%s,'',%d,0,'')]], issuer, Q(requestId), Q(signature), Q(kind), revision)
end

-- Checks the in-memory and durable request journal. Returns record to proceed, or nil when answered.
local function BeginRequest(player, issuer, requestId, signature, onReplay)
    local seen, count = SeenFor(issuer)
    local prior = seen[requestId]
    if prior then
        if prior.signature ~= signature then Fail(player, "request_conflict", requestId)
        elseif not prior.done then Fail(player, "request_pending", requestId)
        else onReplay() end
        return nil
    end
    local receipt, why = DurableReceipt(issuer, requestId)
    if receipt == nil then Fail(player, why, requestId); return nil end
    if receipt then
        if receipt.signature ~= signature then Fail(player, "request_conflict", requestId) else onReplay() end
        return nil
    end
    if count >= MAX_SEEN then Fail(player, "request_window_full", requestId); return nil end
    local record = {signature = signature, created = os.time()}
    seen[requestId] = record
    return record, seen
end

local function SendConfirmed(player, requestId)
    local guid = Id(player)
    local rec, p = LoadCreation(guid), S.GetOrLoadPlayerProfile(player)
    if not rec or not p then Fail(player, "profile_unavailable", requestId); return end
    Send(player, "CharacterConfirmed", {requestId = requestId, revision = rec.revision, creation = Cr.Summary(rec),
        profile = ProfileSummary(p)})
    R.SyncPlayerState(player)
end

function Cr.StateFor(player)
    local guid = Id(player)
    local rec, err = LoadCreation(guid)
    if not rec then return nil, err end
    local state = Cr.Summary(rec)
    state.creationState, state.draft, state.rpLevel = rec.state, DraftFrom(rec, S.PlayerProfiles[guid]), Cr.RpLevel(player)
    return state
end

function Cr.RequestOptions(player)
    if not Guard(player) then return end
    if not Rate(player, "options", 500) then Fail(player, "rate_limited"); return end
    local state, err = Cr.StateFor(player)
    if not state then Fail(player, err or "creation_unavailable"); return end
    local o = Cr.Options
    Send(player, "CharacterOptions", {catalogVersion = o.catalogVersion, races = o.races, traits = o.traits,
        archetypes = o.archetypes, mastery = o.mastery, starter = o.starter, state = state})
end

local function Warnings(rec, norm)
    local list = {}
    local function Add(code) list[#list + 1] = {code = code, message_ru = Cr.Message(code)} end
    if rec.state == "complete" then Add("already_configured") end
    if rec.starterGranted and #norm.items > 0 then Add("starter_already_granted") end
    if rec.state == "none" then Add("first_creation") else Add("resources_kept") end
    local scope = Cr.Scope(rec)
    if scope == "race" or scope == "archetype" then Add(scope .. "_reset_scope") end
    return list
end

-- Scope 'race' accepts only race and racial feature changes. Mastery may differ only when the stored
-- allocation no longer matches the point total of the new racial feature.
-- Scope 'archetype' accepts only the archetype; everything else must match the record.
function Cr.ScopeErrors(rec, norm)
    local scope = Cr.Scope(rec)
    if scope ~= "race" and scope ~= "archetype" then return {} end
    local errors, n, code = {}, norm.n, scope .. "_scope_only"
    local function Check(same, field) if not same then errors[#errors + 1] = {code = code, field = field} end end
    if scope == "archetype" then
        Check(n.race == rec.race, "race")
        Check(n.racialFeature == rec.racialFeature, "racialFeature")
    else
        Check(n.archetype == rec.archetype, "archetype")
    end
    Check((n.traits[1] or "") == (rec.traits[1] or ""), "trait")
    Check((n.traitChoice or "") == (rec.traitChoice or ""), "traitChoice")
    local stored, sum = 0, 0
    for _, key in ipairs(K.MasteryOrder) do stored, sum = stored + rec.mastery[key], sum + n.mastery[key] end
    if stored == sum or scope == "archetype" then
        local same = true
        for _, key in ipairs(K.MasteryOrder) do same = same and rec.mastery[key] == n.mastery[key] end
        Check(same, "mastery")
    end
    return errors
end

function Cr.Preview(player, draft)
    if not Guard(player) then return end
    if not Rate(player, "preview", 250) then Fail(player, "rate_limited"); return end
    local rec, err = LoadCreation(Id(player))
    if not rec then Fail(player, err or "creation_unavailable"); return end
    local norm, errors = Cr.NormalizeDraft(draft, Cr.RpLevel(player))
    if not norm then
        Send(player, "CharacterPreview", {ok = false, errors = Localize(errors, ExpectedMastery(draft)),
            missing = Cr.MissingFields(draft)})
        return
    end
    local scopeErrors = Cr.ScopeErrors(rec, norm)
    if #scopeErrors > 0 then
        Send(player, "CharacterPreview", {ok = false, errors = Localize(scopeErrors), missing = {}})
        return
    end
    local sheet, _, resolveErrors = V.Resolve(norm.input)
    if not sheet then
        Send(player, "CharacterPreview", {ok = false, errors = Localize(resolveErrors or {{code = "invalid_draft"}}),
            missing = {}})
        return
    end
    Send(player, "CharacterPreview", {ok = true, sheet = Cr.SheetSummary(sheet), warnings = Warnings(rec, norm),
        catalogVersion = K.CATALOG_VERSION})
end

-- The confirmed choice rewrites only the computed sheet. XP, Wounds, dice, equip/effects JSON and,
-- except for the first creation, current resources stay as they were.
local function ApplySheet(p, sheet, norm, rpLevel, first)
    local draft = S.CopyProfile(p)
    draft.archetype, draft.raceId = norm.n.archetype, norm.n.race
    draft.racialTrait, draft.commonTrait = norm.n.racialFeature, norm.n.traits[1] or ""
    draft.level = rpLevel
    draft.maxHealth, draft.maxEnergy = sheet.maxHealth, math.max(0, sheet.maxEnergy)
    draft.armor, draft.speed = math.max(0, sheet.armor), math.max(0, sheet.speed)
    draft.maxWounds = math.max(1, math.min(255, sheet.woundLimit))
    for _, key in ipairs({"accuracy", "healing", "evasion", "resistance"}) do draft.stats[key] = sheet[key] end
    for _, key in ipairs(K.MasteryOrder) do draft.stats[key] = sheet.mastery[key] end
    if first then
        draft.curHealth, draft.curEnergy = draft.maxHealth, draft.maxEnergy
    else
        draft.curHealth = math.max(0, math.min(C.MAX_RESOURCE, draft.curHealth))
        draft.curEnergy = math.max(0, math.min(C.MAX_RESOURCE, draft.curEnergy))
    end
    return draft
end

local function CommitConfirm(player, p, norm, expectedRevision, requestId, record, seen)
    local guid = Id(player)
    local function Abort(code)
        seen[requestId] = nil
        Fail(player, code, requestId)
    end
    local rec, err = LoadCreation(guid)
    if not rec then Abort(err or "creation_unavailable"); return end
    if R.Locks["p:" .. guid] then Abort("actor_busy"); return end
    if rec.revision ~= expectedRevision then Abort("revision_conflict"); return end
    if rec.state == "complete" then Abort("already_configured"); return end
    local scopeErrors = Cr.ScopeErrors(rec, norm)
    if #scopeErrors > 0 then
        seen[requestId] = nil
        Fail(player, scopeErrors[1].code, requestId, Localize(scopeErrors))
        return
    end
    local rpLevel = Cr.RpLevel(player)
    norm.input.rpLevel = rpLevel
    local sheet = V.Resolve(norm.input)
    if not sheet then Abort("invalid_draft"); return end
    local now, first = os.time(), rec.state == "none"
    local draft = ApplySheet(p, sheet, norm, rpLevel, first)
    local nextRec = S.CopyCreation(rec)
    nextRec.state, nextRec.catalogVersion = "complete", K.CATALOG_VERSION
    nextRec.race, nextRec.racialFeature, nextRec.archetype = norm.n.race, norm.n.racialFeature, norm.n.archetype
    nextRec.racePresetVersion = K.RacePresetVersion(norm.n.race)
    nextRec.traits, nextRec.traitChoice = {norm.n.traits[1]}, norm.n.traitChoice or ""
    nextRec.mastery = {skill = norm.n.mastery.skill, knowledge = norm.n.mastery.knowledge,
        endurance = norm.n.mastery.endurance, craft = norm.n.mastery.craft}
    nextRec.revision, nextRec.confirmedAt, nextRec.confirmedBy = rec.revision + 1, now, guid
    local granted = {}
    if not rec.starterGranted then
        granted = norm.items
        nextRec.starterGranted, nextRec.starterGrantedAt = true, now
    end
    local sql = {}
    local save, saveErr = S.BuildCreationSave(nextRec)
    if not save then Abort(saveErr); return end
    sql[#sql + 1] = save
    local itemKeys = {}
    for i, item in ipairs(granted) do itemKeys[i] = item.key end
    local log, logErr = S.BuildCreationLog({guid = guid, revision = nextRec.revision, action = "confirm",
        fromState = rec.state, toState = "complete", actorGuid = guid, requestId = requestId, createdAt = now,
        snapshotJson = Json({before = Snapshot(rec, p), after = Cr.Summary(nextRec), starterItems = itemKeys,
            rpLevel = rpLevel, catalogVersion = K.CATALOG_VERSION, scope = Cr.Scope(rec)})})
    if not log then Abort(logErr); return end
    sql[#sql + 1] = log
    local items, itemsErr = S.BuildStarterItems(guid, granted, now)
    if not items then Abort(itemsErr); return end
    for _, statement in ipairs(items) do sql[#sql + 1] = statement end
    sql[#sql + 1] = ReceiptSql(guid, requestId, record.signature, "char_confirm", nextRec.revision)
    local locator, lock = player:GetGUID(), "p:" .. guid
    R.Locks[lock] = true
    S.SaveProfiles({draft}, function(ok, why)
        R.Locks[lock] = nil
        local current = GetPlayerByGUID(locator)
        if not ok then
            seen[requestId] = nil
            if current then Fail(current, why == "partial_commit" and why or "save_failed", requestId) end
            return
        end
        S.Creation[guid] = nextRec
        record.done, record.result = true, {revision = nextRec.revision}
        if current then SendConfirmed(current, requestId) end
    end, nil, {characters = sql})
end

function Cr.Confirm(player, draft, expectedRevision, requestId)
    if not Guard(player, requestId) then return end
    if not ValidRequestId(requestId) then Fail(player, "invalid_request_id"); return end
    if not Integer(expectedRevision, 0, 4294967295) then Fail(player, "invalid_revision", requestId); return end
    local norm, errors = Cr.NormalizeDraft(draft, Cr.RpLevel(player))
    if not norm then Fail(player, "invalid_draft", requestId, Localize(errors, ExpectedMastery(draft))); return end
    local guid = Id(player)
    local signature = "char_confirm:" .. expectedRevision .. ":" .. norm.signature
    local record, seen = BeginRequest(player, guid, requestId, signature, function() SendConfirmed(player, requestId) end)
    if not record then return end
    if not Rate(player, "confirm", 400) then seen[requestId] = nil; Fail(player, "rate_limited", requestId); return end
    if R.Locks["p:" .. guid] then seen[requestId] = nil; Fail(player, "actor_busy", requestId); return end
    local locator = player:GetGUID()
    Ensure(player, function(p, why)
        local current = GetPlayerByGUID(locator)
        if not p then
            seen[requestId] = nil
            if current then Fail(current, why or "profile_unavailable", requestId) end
            return
        end
        if not current then seen[requestId] = nil; return end
        CommitConfirm(current, p, norm, expectedRevision, requestId, record, seen)
    end)
end

local function ResolveTarget(player, targetGuid)
    if targetGuid == nil then
        local sel = player:GetSelection()
        local target = sel and sel:ToPlayer()
        return target and Id(target), target
    end
    if type(targetGuid) ~= "string" or #targetGuid > 128 then return nil end
    local wanted = R.NormalizeWireGuid and R.NormalizeWireGuid(targetGuid)
    local low = targetGuid:match("^%d+$") and C.IdString(targetGuid)
    for _, other in ipairs(GetPlayersInWorld and GetPlayersInWorld() or {}) do
        if (low and Id(other) == low) or (wanted and R.NormalizeWireGuid(other:GetGUID()) == wanted) then
            return Id(other), other
        end
    end
    if low and low ~= "0" then return low, nil end
end

-- Staff only. Flips the state to 'reconfigure' and keeps the choices, resources and starter flag;
-- the next ConfirmCharacter recomputes the sheet without healing and without a second starter kit.
function Cr.Reconfigure(player, targetGuid, reason, requestId)
    if not Guard(player, requestId) then return end
    if not ValidRequestId(requestId) then Fail(player, "invalid_request_id"); return end
    if not N.HasStaffPermission(player) then Fail(player, "permission_denied", requestId); return end
    reason = type(reason) == "string" and Trim(reason) or ""
    if #reason < 3 or #reason > 255 or reason:find("%c") then Fail(player, "invalid_reason", requestId); return end
    if not Rate(player, "reconfigure", 400) then Fail(player, "rate_limited", requestId); return end
    local guid, target = ResolveTarget(player, targetGuid)
    if not guid then Fail(player, "target_not_found", requestId); return end
    local staff = Id(player)
    local signature = "char_reconfig:" .. guid .. ":" .. reason
    local record, seen = BeginRequest(player, staff, requestId, signature, function()
        local rec = target and S.Creation[guid] or S.LoadCreation(guid)
        Send(player, "CharacterReconfigured", {requestId = requestId, targetGuid = guid,
            revision = rec and rec.revision, state = rec and rec.state})
    end)
    if not record then return end
    local function Abort(code) seen[requestId] = nil; Fail(player, code, requestId) end
    local lock = "p:" .. guid
    if R.Locks[lock] then Abort("actor_busy"); return end
    local rec, err
    if target then rec, err = LoadCreation(guid) else rec, err = S.LoadCreation(guid) end
    if err == "creation_schema_unavailable" then err = "creation_unavailable" end
    if not rec then Abort(err or "creation_unavailable"); return end
    if rec.state == "none" then Abort("not_configured"); return end
    if rec.state == "reconfigure" then Abort("already_reconfigure"); return end
    local now = os.time()
    local nextRec = S.CopyCreation(rec)
    nextRec.state, nextRec.revision = "reconfigure", rec.revision + 1
    local save, saveErr = S.BuildCreationSave(nextRec)
    if not save then Abort(saveErr); return end
    local log, logErr = S.BuildCreationLog({guid = guid, revision = nextRec.revision, action = "reconfigure",
        fromState = rec.state, toState = "reconfigure", actorGuid = staff, requestId = requestId, reason = reason,
        createdAt = now, snapshotJson = Json({before = Snapshot(rec, S.PlayerProfiles[guid])})})
    if not log then Abort(logErr); return end
    local sql = {save, log, ReceiptSql(staff, requestId, signature, "char_reconfig", nextRec.revision)}
    local staffLocator, targetLocator = player:GetGUID(), target and target:GetGUID()
    R.Locks[lock] = true
    local entered = false
    local called = pcall(RpsCommitAsync, "characters", sql, function(ok)
        entered = true
        R.Locks[lock] = nil
        local staffPlayer = GetPlayerByGUID(staffLocator)
        if not ok then seen[requestId] = nil; Fail(staffPlayer, "save_failed", requestId); return end
        record.done = true
        local current = targetLocator and GetPlayerByGUID(targetLocator)
        if current then
            S.Creation[guid] = nextRec
            R.SyncPlayerState(current)
            if current.SendNotification then current:SendNotification("Ведущий разрешил перенастройку RP-персонажа") end
        else S.Creation[guid] = nil end
        Send(staffPlayer, "CharacterReconfigured", {requestId = requestId, targetGuid = guid,
            revision = nextRec.revision, state = nextRec.state})
    end)
    if not called and not entered then R.Locks[lock] = nil; Abort("save_failed") end
end

-- Race data reset: clears race and racial feature, state 'reconfigure' with scope 'race'.
-- Other choices, resources, the profile sheet and the starter flag stay; the sheet is recomputed on
-- the next ConfirmCharacter. Staff may reset any time; a player only after their race preset was updated.
-- opts = {actor, guid, target, reason, requestId, staff, notify(code|nil, rec)}
local function ResetRace(opts)
    local actor, guid, target, requestId = opts.actor, opts.guid, opts.target, opts.requestId
    local actorId = Id(actor)
    local signature = "race_reset:" .. guid .. ":" .. (opts.reason or "")
    local function Done(code, rec) if opts.notify then opts.notify(code, rec) end end
    local record, seen = BeginRequest(actor, actorId, requestId, signature, function()
        local rec = target and S.Creation[guid] or S.LoadCreation(guid)
        Send(actor, "RaceDataReset", {requestId = requestId, targetGuid = guid, revision = rec and rec.revision,
            state = rec and rec.state, scope = rec and Cr.Scope(rec)})
        Done(nil, rec)
    end)
    if not record then return end
    local function Abort(code) seen[requestId] = nil; Fail(actor, code, requestId); Done(code) end
    local lock = "p:" .. guid
    if R.Locks[lock] then Abort("actor_busy"); return end
    local rec, err
    if target then rec, err = LoadCreation(guid) else rec, err = S.LoadCreation(guid) end
    if err == "creation_schema_unavailable" then err = "creation_unavailable" end
    if not rec then Abort(err or "creation_unavailable"); return end
    if rec.state == "none" or rec.state == "legacy" then Abort("not_configured"); return end
    if rec.state == "reconfigure" then Abort("already_reconfigure"); return end
    if not opts.staff then
        if not S.HasRacePresetColumn() then Abort("creation_unavailable"); return end
        if not Cr.RaceUpdateAvailable(rec) then Abort("race_preset_current"); return end
    end
    local now = os.time()
    local nextRec = S.CopyCreation(rec)
    nextRec.state, nextRec.revision, nextRec.race, nextRec.racialFeature = "reconfigure", rec.revision + 1, "", ""
    local save, saveErr = S.BuildCreationSave(nextRec)
    if not save then Abort(saveErr); return end
    local reason = opts.reason ~= "" and ("race_reset: " .. opts.reason) or "race_reset"
    local log, logErr = S.BuildCreationLog({guid = guid, revision = nextRec.revision, action = "reconfigure",
        fromState = rec.state, toState = "reconfigure", actorGuid = actorId, requestId = requestId, reason = reason,
        createdAt = now, snapshotJson = Json({scope = "race", staff = opts.staff == true,
            racePresetVersion = K.RacePresetVersion(rec.race), before = Snapshot(rec, S.PlayerProfiles[guid])})})
    if not log then Abort(logErr); return end
    local sql = {save, log, ReceiptSql(actorId, requestId, signature, "race_reset", nextRec.revision)}
    local actorLocator, targetLocator = actor:GetGUID(), target and target:GetGUID()
    R.Locks[lock] = true
    local entered = false
    local called = pcall(RpsCommitAsync, "characters", sql, function(ok)
        entered = true
        R.Locks[lock] = nil
        local actorPlayer = GetPlayerByGUID(actorLocator)
        if not ok then
            seen[requestId] = nil
            Fail(actorPlayer, "save_failed", requestId)
            Done("save_failed")
            return
        end
        record.done = true
        local current = targetLocator and GetPlayerByGUID(targetLocator)
        if current then
            S.Creation[guid] = nextRec
            R.SyncPlayerState(current)
            if opts.staff and current.SendNotification then
                current:SendNotification("Ведущий сбросил расовые данные RP-персонажа: выберите расу заново")
            end
        else S.Creation[guid] = nil end
        Send(actorPlayer, "RaceDataReset", {requestId = requestId, targetGuid = guid, revision = nextRec.revision,
            state = nextRec.state, scope = "race"})
        Done(nil, nextRec)
    end)
    if not called and not entered then R.Locks[lock] = nil; Abort("save_failed") end
end

-- AIO ResetRaceData(requestId): the player resets their own race data after a preset update.
function Cr.ResetRaceSelf(player, requestId)
    if not Guard(player, requestId) then return end
    if not ValidRequestId(requestId) then Fail(player, "invalid_request_id"); return end
    if not Rate(player, "race_reset", 400) then Fail(player, "rate_limited", requestId); return end
    ResetRace({actor = player, guid = Id(player), target = player, reason = "", requestId = requestId, staff = false})
end

-- Player archetype reset: the first one is free, each next costs ARCHETYPE_RESET_STEP copper more
-- (5, 10, 15 silver...). Resets are counted from the creation log rows with reason 'archetype_reset';
-- staff reconfigures and race resets do not count. Money is taken before the commit and returned
-- when the commit fails while the player is still online.
local ARCHETYPE_RESET_STEP, ARCHETYPE_RESET_REASON = 500, "archetype_reset"
Cr.ArchetypeResetStep, Cr.ArchetypeResets = ARCHETYPE_RESET_STEP, {}

local function ArchetypeResetCount(guid)
    local cached = Cr.ArchetypeResets[guid]
    if cached then return cached end
    local q = CharDBQuery("SELECT COUNT(*) FROM character_rps_creation_log WHERE guid = " .. guid
        .. " AND action = 'reconfigure' AND reason = " .. Q(ARCHETYPE_RESET_REASON))
    if not q then return nil end
    Cr.ArchetypeResets[guid] = q:GetUInt32(0)
    return Cr.ArchetypeResets[guid]
end

-- Copper for the next player reset; nil when the log is unreadable.
function Cr.ArchetypeResetCost(guid)
    local count = ArchetypeResetCount(guid)
    return count and count * ARCHETYPE_RESET_STEP or nil
end

local function SendArchetypeReset(player, requestId, rec, cost)
    Send(player, "ArchetypeReset", {requestId = requestId, revision = rec and rec.revision,
        state = rec and rec.state, scope = rec and Cr.Scope(rec), cost = cost})
end

-- AIO ResetArchetype(expectedCost, requestId): expectedCost is the copper price the client showed;
-- a different server price refuses the reset and resyncs the price.
function Cr.ResetArchetype(player, expectedCost, requestId)
    if not Guard(player, requestId) then return end
    if not ValidRequestId(requestId) then Fail(player, "invalid_request_id"); return end
    if not Integer(expectedCost, 0, 2147483647) then Fail(player, "invalid_input", requestId); return end
    if not Rate(player, "archetype_reset", 400) then Fail(player, "rate_limited", requestId); return end
    local guid = Id(player)
    local signature = "archetype_reset:" .. guid .. ":" .. expectedCost
    local record, seen = BeginRequest(player, guid, requestId, signature, function()
        SendArchetypeReset(player, requestId, LoadCreation(guid), expectedCost)
    end)
    if not record then return end
    local function Abort(code) seen[requestId] = nil; Fail(player, code, requestId) end
    local lock = "p:" .. guid
    if R.Locks[lock] then Abort("actor_busy"); return end
    local rec, err = LoadCreation(guid)
    if not rec then Abort(err or "creation_unavailable"); return end
    if rec.state == "reconfigure" then Abort("already_reconfigure"); return end
    if rec.state ~= "complete" or rec.archetype == "" then Abort("not_configured"); return end
    local count = ArchetypeResetCount(guid)
    if not count then Abort("creation_unavailable"); return end
    local cost = count * ARCHETYPE_RESET_STEP
    if cost ~= expectedCost then
        Abort("archetype_reset_cost_changed")
        R.SyncPlayerState(player)
        return
    end
    if cost > 0 and player:GetCoinage() < cost then Abort("not_enough_money"); return end
    local now = os.time()
    local nextRec = S.CopyCreation(rec)
    nextRec.state, nextRec.revision, nextRec.archetype = "reconfigure", rec.revision + 1, ""
    local save, saveErr = S.BuildCreationSave(nextRec)
    if not save then Abort(saveErr); return end
    local log, logErr = S.BuildCreationLog({guid = guid, revision = nextRec.revision, action = "reconfigure",
        fromState = rec.state, toState = "reconfigure", actorGuid = guid, requestId = requestId,
        reason = ARCHETYPE_RESET_REASON, createdAt = now, snapshotJson = Json({scope = "archetype", cost = cost,
            resetNumber = count + 1, before = Snapshot(rec, S.PlayerProfiles[guid])})})
    if not log then Abort(logErr); return end
    local sql = {save, log, ReceiptSql(guid, requestId, signature, "archetype_reset", nextRec.revision)}
    local locator = player:GetGUID()
    R.Locks[lock] = true
    if cost > 0 then player:ModifyMoney(-cost) end
    local entered = false
    local called = pcall(RpsCommitAsync, "characters", sql, function(ok)
        entered = true
        R.Locks[lock] = nil
        local current = GetPlayerByGUID(locator)
        if not ok then
            seen[requestId] = nil
            if cost > 0 then
                if current then current:ModifyMoney(cost)
                elseif N then N.Log("RPS_Combat", "archetype_reset_refund_lost guid=" .. guid .. " cost=" .. cost) end
            end
            Fail(current, "save_failed", requestId)
            return
        end
        record.done = true
        Cr.ArchetypeResets[guid] = count + 1
        if current then
            S.Creation[guid] = nextRec
            R.SyncPlayerState(current)
        else S.Creation[guid] = nil end
        SendArchetypeReset(current, requestId, nextRec, cost)
    end)
    if not called and not entered then
        R.Locks[lock] = nil
        if cost > 0 then player:ModifyMoney(cost) end
        Abort("save_failed")
    end
end

local function FindByName(name)
    local wanted = name:lower()
    for _, other in ipairs(GetPlayersInWorld and GetPlayersInWorld() or {}) do
        if other:GetName():lower() == wanted then return Id(other), other end
    end
    local q = CharDBQuery("SELECT guid FROM characters WHERE name = " .. Q(name))
    if q then return C.IdString(q:GetUInt64(0)) end
end

local staffSequence = 0
-- `.rps race reset [playerName] [reason]`: staff only, the selected player when no name is given.
function Cr.StaffResetRace(player, name, reason)
    local function Reply(text) if player.SendBroadcastMessage then player:SendBroadcastMessage(text) end end
    if not R.ready then Reply("RPS: " .. Cr.Message("system_unavailable")); return end
    if not N.HasStaffPermission(player) then Reply("RPS: " .. Cr.Message("permission_denied")); return end
    reason = type(reason) == "string" and Trim(reason) or ""
    if #reason > 200 or reason:find("%c") then Reply("RPS: " .. Cr.Message("invalid_reason")); return end
    local guid, target
    if name and name ~= "" then
        if #name > 48 or name:find("[%c%s%p]") then Reply("RPS: " .. Cr.Message("target_not_found")); return end
        guid, target = FindByName(name)
    else
        guid, target = ResolveTarget(player, nil)
    end
    if not guid or guid == "0" then Reply("RPS: " .. Cr.Message("target_not_found")); return end
    staffSequence = staffSequence + 1
    local requestId = "gm-race-" .. os.time() .. "-" .. staffSequence
    local label = target and target:GetName() or name or guid
    ResetRace({actor = player, guid = guid, target = target, reason = reason, requestId = requestId, staff = true,
        notify = function(code, rec)
            if code then Reply("RPS: сброс расы " .. label .. " — " .. Cr.Message(code))
            else Reply("RPS: расовые данные " .. label .. " сброшены (ревизия " .. tostring(rec and rec.revision) .. ")") end
        end})
end

-- Compact creation state for SyncProfile; nil when the creation schema is unavailable.
function Cr.SyncSummary(player)
    local rec = LoadCreation(Id(player))
    if not rec then return nil end
    local out = Cr.Summary(rec)
    out.rpLevel = Cr.RpLevel(player)
    if rec.state == "complete" and rec.archetype ~= "" then out.archetypeResetCost = Cr.ArchetypeResetCost(Id(player)) end
    return out
end

function Cr.Register(runtime, handlers, ensure)
    R, Ensure = runtime, ensure
    N = require("NobleNext")
    AIO = N.AIO
    handlers.RequestCharacterOptions = Cr.RequestOptions
    handlers.PreviewCharacter = Cr.Preview
    handlers.ConfirmCharacter = Cr.Confirm
    handlers.ReconfigureCharacter = Cr.Reconfigure
    handlers.ResetRaceData = Cr.ResetRaceSelf
    handlers.ResetArchetype = Cr.ResetArchetype
    R.Creation, R.CreationSummary = Cr, Cr.SyncSummary
    return Cr
end

return Cr
