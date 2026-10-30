-- Native ownership is authoritative. RP properties of any single, nonstackable item come from:
-- entry definitions and sets (WORLD), instance metadata by item GUID (CHARACTERS), and native
-- enchant IDs on the item itself (permanent enchant + RP gem slots) mapped by WORLD rps_item_enchant.
local C = require("Modules.RPS_Combat.00_RPS_Config")
local S = require("Modules.RPS_Combat.01_RPS_Storage")
local V = require("Modules.RPS_Combat.04_RPS_Resolver")
local P = require("Modules.RPS_Combat.06_RPS_Progression")
local K = require("Modules.RPS_Combat.03_RPS_Catalog")
local DB = require("Core.DB")
local I = {}
local direct = {maxHealth = true, maxEnergy = true, armor = true, speed = true, woundLimit = "maxWounds"}
local cache = {}                       -- item GUID string -> {owner, state, metadata}
local templates, sets = {}, {}         -- entry -> {modifiers, set}; set key -> {name, bonuses = {{pieces, modifiers}}}
local enchants = {}                    -- native enchant ID -> {kind = "enchant"|"gem", name, description, modifiers}
local equipTypes = {}                  -- entry -> K.Weapons/K.Shields key (WORLD rps_item_equip_type)
-- Native weapon subclass -> design-document weapon type. Shield size and one-handed long, ranged and
-- gunpowder weapons have no native subclass of their own and come only from rps_item_equip_type.
local AUTO_WEAPON = {
    [0] = "one_handed_common", [4] = "one_handed_common", [7] = "one_handed_common",
    [9] = "one_handed_common", [13] = "one_handed_common",
    [15] = "one_handed_throwing", [16] = "one_handed_throwing",
    [1] = "two_handed_common", [5] = "two_handed_common", [8] = "two_handed_common",
    [6] = "two_handed_reach", [17] = "two_handed_reach",
    [10] = "two_handed_magic", [19] = "one_handed_magic",
    [2] = "two_handed_long_range", [18] = "two_handed_ranged", [3] = "two_handed_gunpowder",
}
local HAND_SLOTS = {mainHand = 15, offHand = 16}
local QUALITY_KEYS = {[0] = "poor", [1] = "simple"}
-- Gem slots by native quality (poor, common, uncommon, rare, epic, legendary); one enchant slot always.
local GEM_SLOTS = {[0] = 0, 0, 1, 2, 3, 3}
I.GEM_SLOTS, I.MAX_GRADE = GEM_SLOTS, 5
local function Clamp(n, low, high) return math.max(low, math.min(high, n)) end
local function Id(player) return C.IdString(player:GetGUIDLow()) end
local function Q(value) return "'" .. DB.EscapeSqlString(value) .. "'" end

-- Bags, the shirt (3) and the tabard (18) never grant stats.
local function EquipmentSlots()
    local slot = -1
    return function()
        repeat slot = slot + 1 until slot ~= 3 and slot ~= 18
        if slot <= 17 then return slot end
    end
end

local function IsRpItem(item)
    return item ~= nil and item:GetCount() == 1 and item:GetMaxStackCount() == 1
end

-- Native-stat-free carrier (item_template_addon RP_ONLY); only affects native tooltip filtering.
local function IsCarrier(item)
    return IsRpItem(item) and type(RpsIsRoleplayItem) == "function" and RpsIsRoleplayItem(item:GetEntry()) == true
end

local function Quality(item)
    return math.min(type(RpsGetItemQuality) == "function" and RpsGetItemQuality(item) or item:GetQuality(), I.MAX_GRADE)
end

local function GemSlots(item) return GEM_SLOTS[Quality(item)] or 0 end

local function EnchantIds(item)
    if type(RpsGetItemEnchants) ~= "function" then return {0, 0, 0, 0} end
    return {RpsGetItemEnchants(item)}
end

-- Slot 0 holds an RP enchant, slots 1..3 RP gems; a gem beyond the current grade's slots is dormant.
local function ActiveEnchants(item, metadata)
    local list, ids, gems = {}, EnchantIds(item), GemSlots(item)
    for socket = 0, 3 do
        local id = ids[socket + 1] or 0
        local definition = id ~= 0 and enchants[id]
        local kind = socket == 0 and "enchant" or "gem"
        local override = metadata and (socket == 0 and metadata.properties or
            socket > 0 and metadata.runes and metadata.runes[tostring(socket)])
        if type(override) == "table" then
            definition = {kind = kind, name = definition and definition.name or "",
                description = definition and definition.description or "", effects = definition and definition.effects, modifiers = override}
        end
        if definition and definition.kind == kind and socket <= gems then
            list[#list + 1] = {kind = kind, id = id, socket = socket, definition = definition}
        end
    end
    return list
end

local function TemplateEquipKey(entry, class, subclass, inventoryType)
    local key = equipTypes[entry]
    if key then return key end
    -- A one-handed polearm or spear (inventory type 13/21) is the one-handed long weapon.
    if class == 2 and (subclass == 6 or subclass == 17) and inventoryType ~= 17 then
        return "one_handed_reach"
    end
    if class == 2 then return AUTO_WEAPON[subclass] end
    if class == 4 and subclass == 6 then return "shield_small" end
end

local function EquipKey(item)
    return TemplateEquipKey(item:GetEntry(), item:GetClass(), item:GetSubClass(), item:GetInventoryType())
end

-- Native quality (with the RP grade) maps onto the design-document quality: poor -1, simple 0, quality +1.
local function EquipQuality(item) return QUALITY_KEYS[Quality(item)] or "quality" end

-- "1d1" (a fixed 1) is not a die for the dice parser; it becomes a flat value.
local function DiceString(die, bonus)
    local count, sides = die:match("^(%d+)d(%d+)$")
    count, sides = tonumber(count), tonumber(sides)
    if not count then return nil end
    local text = sides == 1 and tostring(count + bonus) or bonus == 0 and die or die .. string.format("%+d", bonus)
    return C.ParseDice(text) and text or nil
end

local function Average(die, bonus)
    local count, sides = die:match("^(%d+)d(%d+)$")
    return tonumber(count) * (tonumber(sides) + 1) / 2 + bonus
end

-- Resolver equipment from the hand slots; combinations it would reject are dropped, never fatal.
function I.HandEquipment(player)
    local out = {}
    for hand, slot in pairs(HAND_SLOTS) do
        local item = player:GetEquippedItemBySlot(slot)
        local key = IsRpItem(item) and EquipKey(item)
        if key then out[hand] = {key = key, quality = EquipQuality(item)} end
    end
    if out.mainHand and not K.Weapons[out.mainHand.key] then out.mainHand = nil end
    local off = out.offHand and K.Weapons[out.offHand.key]
    if off and off.hands > 1 then out.offHand = nil end
    if out.mainHand and K.Weapons[out.mainHand.key].hands > 1 then out.offHand = nil end
    return out
end

-- Damage of the strongest main hand attack (strike, shot or magic), else off hand, else unarmed 1-X.
local function WeaponDice(sheet)
    local best = {}
    for _, attack in ipairs(sheet.attacks) do
        local hand = attack.hand
        if HAND_SLOTS[hand] and attack.mode ~= "throw" and attack.dice then
            local value = Average(attack.dice, attack.bonus)
            if not best[hand] or value > best[hand].value then best[hand] = {attack = attack, value = value} end
        end
    end
    local pick = best.mainHand or best.offHand
    if pick then return DiceString(pick.attack.dice, pick.attack.bonus) end
    for _, attack in ipairs(sheet.attacks) do
        if attack.hand == "unarmed" then
            return DiceString(attack.dice or ("1d" .. math.min(attack.max, 100)), attack.bonus)
        end
    end
end

-- Tooltip description of a hand item: type, quality and its own dice (without character bonuses).
local function EquipmentInfo(key, qualityKey)
    if not key then return nil end
    local quality = K.Qualities[qualityKey]
    local weapon, shield = K.Weapons[key], K.Shields[key]
    local info = {key = key, quality = quality.name}
    if weapon then
        info.name, info.hands, info.dice = weapon.group .. ": " .. weapon.property, weapon.hands, {}
        for mode, die in pairs(weapon.dice) do info.dice[mode] = DiceString(die, quality.modifier) end
    elseif shield then
        info.name, info.hands, info.block = shield.name, shield.hands, DiceString(shield.blockDie, quality.modifier)
    else
        return nil
    end
    return info
end
local function EquipInfo(item)
    return EquipmentInfo(IsRpItem(item) and EquipKey(item), EquipQuality(item))
end
I.EquipKey, I.EquipInfo = EquipKey, EquipInfo

local function Cached(item)
    local entry = item and cache[tostring(item:GetGUID())]
    return entry and entry.state == "ready" and entry.metadata or nil
end
I.Cached = Cached

-- Definition modifiers reuse the instance parser, so both layers accept the same keys and bounds.
local function ParseModifiers(text)
    if type(RpsParseItemMetadata) ~= "function" or type(text) ~= "string" or text == "" then return end
    local parsed = RpsParseItemMetadata('{"version":1,"revision":1,"name":"","description":"","modifiers":' .. text .. '}')
    return parsed and parsed.modifiers
end

function I.LoadDefinitions(query)
    query = query or WorldDBQuery
    local loadedTemplates, loadedSets, problems = {}, {}, {}
    local q = query("SELECT set_key,name FROM rps_item_set")
    if q then
        repeat loadedSets[q:GetString(0)] = {name = q:GetString(1), bonuses = {}} until not q:NextRow()
    end
    q = query("SELECT set_key,pieces,modifiers FROM rps_item_set_bonus ORDER BY set_key,pieces")
    if q then
        repeat
            local set, modifiers = loadedSets[q:GetString(0)], ParseModifiers(q:GetString(2))
            if set and modifiers then
                set.bonuses[#set.bonuses + 1] = {pieces = q:GetUInt32(1), modifiers = modifiers}
            else problems[#problems + 1] = "set_bonus:" .. q:GetString(0) .. ":" .. q:GetString(1) end
        until not q:NextRow()
    end
    q = query("SELECT entry,modifiers,set_key FROM rps_item_template")
    if q then
        repeat
            local entry, setKey = q:GetUInt32(0), q:GetString(2)
            local modifiers = q:GetString(1) == "" and {} or ParseModifiers(q:GetString(1))
            if not modifiers or (setKey ~= "" and not loadedSets[setKey]) then
                problems[#problems + 1] = "template:" .. entry
            else
                loadedTemplates[entry] = {modifiers = modifiers, set = setKey ~= "" and setKey or nil}
            end
        until not q:NextRow()
    end
    local loadedEnchants = {}
    q = query("SELECT enchant_id,kind,name,modifiers,description FROM rps_item_enchant")
    if q then
        repeat
            local id, kind, modifiers = q:GetUInt32(0), q:GetString(1), ParseModifiers(q:GetString(3))
            if modifiers and (kind == "enchant" or kind == "gem") then
                loadedEnchants[id] = {kind = kind, name = q:GetString(2), modifiers = modifiers, description = q:GetString(4)}
            else problems[#problems + 1] = "enchant:" .. id end
        until not q:NextRow()
    end
    q = query("SELECT enchant_id,effect_index,trigger_kind,spell_id FROM rps_item_enchant_effect ORDER BY enchant_id,effect_index")
    if q then
        repeat
            local definition, trigger, spell = loadedEnchants[q:GetUInt32(0)], q:GetString(2), q:GetUInt32(3)
            if definition and (trigger == "equip" or trigger == "use" or trigger == "proc") and spell > 0 then
                definition.effects = definition.effects or {}
                definition.effects[#definition.effects + 1] = {trigger = trigger, spellId = spell}
            else problems[#problems + 1] = "enchant_effect:" .. q:GetUInt32(0) end
        until not q:NextRow()
    end
    local loadedTypes = {}
    q = query("SELECT entry,equip_key FROM rps_item_equip_type")
    if q then
        repeat
            local entry, key = q:GetUInt32(0), q:GetString(1)
            if K.Weapons[key] or K.Shields[key] then loadedTypes[entry] = key
            else problems[#problems + 1] = "equip_type:" .. entry end
        until not q:NextRow()
    end
    templates, sets, enchants, equipTypes = loadedTemplates, loadedSets, loadedEnchants, loadedTypes
    return problems
end

function I.EnchantCatalog()
    local list = {}
    for id, definition in pairs(enchants) do
        list[#list + 1] = {id = id, kind = definition.kind, name = definition.name,
            description = definition.description, modifiers = definition.modifiers, effects = definition.effects}
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Effective values are transient. Damage/resources survive saves, equipment bonuses do not.
function I.BaseProfile(profile)
    if type(profile) ~= "table" or not profile._itemDeltas then return profile end
    local base = S.CopyProfile(profile)
    for key, delta in pairs(profile._itemDeltas) do
        if direct[key] then
            local field = type(direct[key]) == "string" and direct[key] or key
            base[field] = base[field] - delta
        else
            local field = key:match("^mastery%.(.+)$") or key
            base.stats[field] = base.stats[field] - delta
        end
    end
    if profile._baseDice then base.weaponDice, base.blockDice = profile._baseDice.weapon, profile._baseDice.block end
    base._itemDeltas, base.itemModifiers, base._baseDice = nil, nil, nil
    base.energySpendLimit, base.healDifficulty = nil, nil
    return base
end

-- Sums every layer of the equipped carriers. A set counts each equipped slot once.
function I.EquipmentModifiers(player)
    local sums, sources, setCounts = {}, {}, {}
    local function Add(modifiers, source)
        for key, value in pairs(modifiers) do sums[key] = (sums[key] or 0) + value end
        sources[#sources + 1] = source
    end
    for slot in EquipmentSlots() do
        local item = player:GetEquippedItemBySlot(slot)
        if IsRpItem(item) then
            local guid, definition = tostring(item:GetGUID()), templates[item:GetEntry()]
            if definition then
                if next(definition.modifiers) then Add(definition.modifiers, {kind = "item", entry = item:GetEntry(), slot = slot}) end
                if definition.set then setCounts[definition.set] = (setCounts[definition.set] or 0) + 1 end
            end
            local metadata = Cached(item)
            if metadata then Add(metadata.modifiers, {kind = "instance", guid = guid, revision = metadata.revision, slot = slot}) end
            for _, enchant in ipairs(ActiveEnchants(item, metadata)) do
                if next(enchant.definition.modifiers) then
                    Add(enchant.definition.modifiers, {kind = enchant.kind, enchant = enchant.id, socket = enchant.socket, slot = slot})
                end
            end
        end
    end
    for key, count in pairs(setCounts) do
        for _, bonus in ipairs(sets[key].bonuses) do
            if count >= bonus.pieces then Add(bonus.modifiers, {kind = "set", set = key, pieces = bonus.pieces}) end
        end
    end
    return sums, sources
end

function I.WithEquipment(player, profile)
    if not profile or not profile.isPlayer or not player.GetEquippedItemBySlot then return profile end
    profile = I.BaseProfile(profile)
    if I.RefreshEquipment then I.RefreshEquipment(player) end
    local sums, sources = I.EquipmentModifiers(player)
    local creation = S.Creation[profile.guid]
    if creation == nil and S.GetOrLoadCreation then creation = S.GetOrLoadCreation(profile.guid) end
    local input = P.SheetInput(creation, profile.level)
    local before, after
    if input then
        before = V.Resolve(input)
        input.extraModifiers = {}
        for _, key in ipairs(V.CORE_STATS) do
            if sums[key] then
                input.extraModifiers[#input.extraModifiers + 1] = {source = "native_equipment", op = "add",
                    target = key, value = Clamp(sums[key], -1000, 1000)}
            end
        end
        -- Shield mechanics count as equipment deltas, so the hands join only the "after" sheet.
        input.equipment = I.HandEquipment(player)
        after = V.Resolve(input)
        if not after then
            input.equipment = nil
            after = V.Resolve(input)
        end
    end
    local out = S.CopyProfile(profile)
    out._itemDeltas, out.itemModifiers = {}, sources
    out._baseDice = {weapon = profile.weaponDice, block = profile.blockDice}
    if after then
        out.weaponDice = WeaponDice(after) or profile.weaponDice
        local block = after.block
        out.blockDice = block.die and DiceString(block.die, block.flat) or profile.blockDice
    end
    local function SheetValue(sheet, key)
        local mastery = key:match("^mastery%.(.+)$")
        return mastery and sheet.mastery[mastery] or sheet[key]
    end
    for _, key in ipairs(V.CORE_STATS) do
        local delta = input and (before and after and SheetValue(after, key) - SheetValue(before, key) or 0)
            or sums[key] or 0
        if key == "energySpendLimit" or key == "healDifficulty" then
            out[key] = Clamp(after and after[key] or K.Base[key] + delta, 0, 1000)
        elseif direct[key] then
            local field = type(direct[key]) == "string" and direct[key] or key
            local low, high = key == "maxHealth" and 1 or 0, C.MAX_RESOURCE
            if field == "maxWounds" then low, high = 1, 255 elseif key == "speed" then high = 1000 end
            out[field] = Clamp(profile[field] + delta, low, high)
            out._itemDeltas[key] = out[field] - profile[field]
        else
            local field = key:match("^mastery%.(.+)$") or key
            out.stats[field] = Clamp((profile.stats[field] or 0) + delta, -1000, 1000)
            out._itemDeltas[key] = out.stats[field] - (profile.stats[field] or 0)
        end
    end
    return out
end

function I.Install(R, H)
    local N = require("NobleNext")
    local AIO, prefix = N.AIO, C.AIO_PREFIX
    local reads, pending, equipment = {}, {}, {}
    S.WithEquipment, S.CanonicalProfile = I.WithEquipment, I.BaseProfile

    -- Item GUIDs may be reused after a restart once their rows are gone; drop stale properties first.
    if type(CharDBExecute) == "function" then
        CharDBExecute("DELETE rm FROM rps_item_metadata rm LEFT JOIN item_instance ii ON ii.guid=rm.item_guid WHERE ii.guid IS NULL")
    end

    local function Reply(player, method, result) AIO.Handle(player, prefix, method, result) end
    local function Find(player, guid)
        if type(guid) ~= "string" or #guid > 128 or not guid:match("^Item%-[%x%-]+$")
            or type(RpsFindOwnedItem) ~= "function" then return end
        return RpsFindOwnedItem(player, guid)
    end
    local function ConfirmStored(player, item, json, isNull)
        local state, metadata = "unknown", nil
        if isNull then
            state = "none"
        elseif type(json) == "string" and json ~= "" then
            metadata = RpsParseItemMetadata(json)
            if metadata then state = "ready" end
        end
        cache[tostring(item:GetGUID())] = {owner = Id(player), state = state, metadata = metadata}
        return metadata, state, json
    end

    -- Only an equipped GUID/revision fingerprint is checked on normal ticks. Batch reads
    -- recover newly equipped items and late commits whose Lua callback died during reload.
    function I.RefreshEquipment(player)
        if type(RpsParseItemMetadata) ~= "function" or type(CharDBQuery) ~= "function" then return end
        local key, now = Id(player), GetCurrTime()
        local record = equipment[key] or {}
        equipment[key] = record
        local refresh = not record.readAt or now < record.readAt or now - record.readAt >= 30000
        local ids, items = {}, {}
        for slot in EquipmentSlots() do
            local item = player:GetEquippedItemBySlot(slot)
            if IsRpItem(item) then
                local low = C.IdString(item:GetGUIDLow())
                if low and (refresh or not cache[tostring(item:GetGUID())]) then ids[#ids + 1], items[low] = low, item end
            end
        end
        if #ids == 0 then return end
        record.readAt = now
        local q = CharDBQuery("SELECT ii.guid,rm.metadata,rm.item_guid IS NULL FROM item_instance ii"
            .. " LEFT JOIN rps_item_metadata rm ON rm.item_guid=ii.guid WHERE ii.owner_guid="
            .. key .. " AND ii.guid IN (" .. table.concat(ids, ",") .. ")")
        if q then
            repeat
                local item = items[C.IdString(q:GetString(0))]
                if item then ConfirmStored(player, item, q:GetString(1), q:GetUInt8(2) == 1) end
            until not q:NextRow()
        end
    end

    function I.PollPlayer(player)
        if not player.GetEquippedItemBySlot then return end
        local key, now = Id(player), GetCurrTime()
        local record = equipment[key]
        if record and record.tickAt and now >= record.tickAt and now - record.tickAt < 500 then return end
        I.RefreshEquipment(player)
        record = equipment[key] or {}
        equipment[key], record.tickAt = record, now
        local parts = {}
        for slot in EquipmentSlots() do
            local item = player:GetEquippedItemBySlot(slot)
            if item then
                local metadata = Cached(item)
                parts[#parts + 1] = slot .. ":" .. tostring(item:GetGUID()) .. ":" .. (metadata and metadata.revision or 0)
                    .. ":" .. Quality(item) .. ":" .. table.concat(EnchantIds(item), ",")
            end
        end
        local fingerprint = table.concat(parts, "|")
        if fingerprint ~= record.fingerprint then
            record.fingerprint = fingerprint
            R.SyncPlayerState(player)
            if R.Combat.BroadcastUnitUpdate then R.Combat.BroadcastUnitUpdate(player, AIO) end
        end
    end

    function I.Release(player)
        local key = Id(player)
        for guid, entry in pairs(cache) do
            if entry.owner == key then cache[guid] = nil end
        end
        equipment[key], reads[key] = nil, nil
    end

    local ReadNative
    local function Apply(guid)
        for _, current in ipairs(GetPlayersInWorld() or {}) do
            local item = Find(current, guid)
            if item then
                -- Replays describe historical results. Publish the current stored revision,
                -- which may already include a later edit whose callback was lost.
                ReadNative(current, item)
                R.SyncPlayerState(current)
                if R.Combat.BroadcastUnitUpdate then R.Combat.BroadcastUnitUpdate(current, AIO) end
                Reply(current, "ItemChanged", {guid = guid, entry = item:GetEntry()})
                return current
            end
        end
    end
    -- Also repairs a lost post-commit callback after a Lua reload.
    ReadNative = function(player, item)
        local low = C.IdString(item:GetGUIDLow())
        if not low then return nil, "unknown" end
        local q = CharDBQuery("SELECT rm.metadata,rm.item_guid IS NULL FROM item_instance ii"
            .. " LEFT JOIN rps_item_metadata rm ON rm.item_guid=ii.guid WHERE ii.guid=" .. low .. " AND ii.owner_guid=" .. Id(player))
        if not q then return nil, "unknown" end
        return ConfirmStored(player, item, q:GetString(0), q:GetUInt8(1) == 1)
    end

    -- A burst accommodates the hovered item and both comparison panes in the same frame.
    local function AllowRead(player)
        local now, key = GetCurrTime(), Id(player)
        local window = reads[key]
        if not window or now < window.at or now - window.at >= 1000 then
            window = {at = now, count = 0}
            reads[key] = window
        end
        if window.count >= 20 then return false end
        window.count = window.count + 1
        return true
    end

    function H.RequestItemTemplate(player, entry)
        if not R.ready or type(RpsGetItemTemplate) ~= "function" or type(entry) ~= "number"
            or entry < 1 or entry > 2147483647 or entry % 1 ~= 0 or not AllowRead(player) then return end
        local class, subclass, inventoryType, quality, stack, noVendorValue = RpsGetItemTemplate(entry)
        local supported = stack == 1 and (class == 2 or class == 4)
        local definition = supported and templates[entry] or nil
        local set = definition and definition.set and sets[definition.set]
        Reply(player, "ItemTemplate", {entry = entry, state = supported and "none" or "unknown", rpItem = supported, noVendorValue = noVendorValue,
            equip = supported and EquipmentInfo(TemplateEquipKey(entry, class, subclass, inventoryType),
                QUALITY_KEYS[quality] or "quality") or nil,
            gemSlots = supported and (GEM_SLOTS[math.min(quality, I.MAX_GRADE)] or 0) or 0,
            definition = definition and {modifiers = definition.modifiers, set = definition.set} or nil,
            set = set and {key = definition.set, name = set.name, bonuses = set.bonuses} or nil})
    end

    function H.RequestItemMetadata(player, guid)
        if not R.ready or type(RpsParseItemMetadata) ~= "function" then return end
        if type(guid) ~= "string" or #guid > 128 or not guid:match("^Item%-[%x%-]+$") then return end
        if not AllowRead(player) then return end
        local item = Find(player, guid)
        if not item then return Reply(player, "ItemMetadata", {guid = guid, entry = 0, state = "unknown"}) end
        local metadata, state = ReadNative(player, item)
        local rpItem = IsRpItem(item)
        local definition = rpItem and templates[item:GetEntry()] or nil
        local set = definition and definition.set and sets[definition.set]
        local active = {}
        for _, enchant in ipairs(rpItem and ActiveEnchants(item, metadata) or {}) do
            active[#active + 1] = {kind = enchant.kind, id = enchant.id, socket = enchant.socket, name = enchant.definition.name,
                description = enchant.definition.description, modifiers = enchant.definition.modifiers, effects = enchant.definition.effects}
        end
        Reply(player, "ItemMetadata", {guid = tostring(item:GetGUID()), entry = item:GetEntry(), state = state,
            metadata = metadata, rpOnly = IsCarrier(item), rpItem = rpItem,
            noVendorValue = type(RpsGetItemTemplate) == "function" and select(6, RpsGetItemTemplate(item:GetEntry())) or false,
            grade = rpItem and Quality(item) or nil, gemSlots = rpItem and GemSlots(item) or nil, enchants = active,
            equip = EquipInfo(item),
            definition = definition and {modifiers = definition.modifiers, set = definition.set} or nil,
            set = set and {key = definition.set, name = set.name, bonuses = set.bonuses} or nil})
    end

    -- Staff (the game master) changes the RP grade, enchant or gems of an online player's item.
    -- Native enchant slots persist with the item itself; no RP table is written.
    local enchantMessages = {permission_denied = "Недостаточно прав", system_unavailable = "Система недоступна",
        invalid_target = "Игрок не найден", invalid_item_position = "Некорректный слот", invalid_item = "Предмет недоступен",
        item_not_rp_only = "Предмет со стопкой не поддерживает RP-свойства", invalid_operation = "Неизвестное действие",
        unknown_enchant = "Нет такого свойства в каталоге", unknown_gem = "Нет такой руны в каталоге",
        no_gem_slot = "У предмета нет такого гнезда при текущем качестве", invalid_grade = "Качество: 0..5",
        apply_failed = "Ядро отклонило изменение"}

    function I.Enchant(player, target, bag, slot, operation, socket, value)
        local function Done(ok, code, extra)
            local result = {ok = ok, code = code, operation = operation, bag = bag, slot = slot,
                target = target and R.NormalizeWireGuid(target:GetGUID())}
            for key, v in pairs(extra or {}) do result[key] = v end
            Reply(player, "ItemEnchantResult", result)
            player:SendBroadcastMessage(ok and ("Предмет изменён: " .. code) or ("Предмет не изменён: " .. (enchantMessages[code] or code)))
            return ok
        end
        if not N.HasStaffPermission(player) then return Done(false, "permission_denied") end
        if not R.ready or type(RpsSetItemEnchant) ~= "function" or type(RpsSetItemGrade) ~= "function" then
            return Done(false, "system_unavailable")
        end
        if not target then return Done(false, "invalid_target") end
        if not C.Integer(bag, 0, 255) or not C.Integer(slot, 0, 255) then return Done(false, "invalid_item_position") end
        local item = target:GetItemByPos(bag, slot)
        if not item or item:IsInTrade() then return Done(false, "invalid_item") end
        if not IsRpItem(item) then return Done(false, "item_not_rp_only") end
        local applied, label
        if operation == "grade" then
            if not C.Integer(value, 0, I.MAX_GRADE) then return Done(false, "invalid_grade") end
            applied, label = RpsSetItemGrade(target, item, value), "качество " .. value
        elseif operation == "enchant" or operation == "gem" or operation == "ability" then
            local kind = operation == "ability" and "enchant" or operation
            if kind == "enchant" then socket = 0 end
            if not C.Integer(socket, 0, 3) or (kind == "gem" and (socket < 1 or socket > GemSlots(item))) then
                return Done(false, "no_gem_slot")
            end
            if not C.Integer(value, 0, 4294967295) then return Done(false, "unknown_" .. kind) end
            local definition = value ~= 0 and enchants[value]
            if value ~= 0 and (not definition or definition.kind ~= kind) then return Done(false, "unknown_" .. kind) end
            if operation == "ability" and value ~= 0 and (not definition.effects or #definition.effects == 0) then return Done(false, "unknown_enchant") end
            applied = RpsSetItemEnchant(target, item, socket, value)
            label = value == 0 and (kind == "enchant" and "свойство снято" or "руна " .. socket .. " снята")
                or (definition.name .. (kind == "gem" and " (гнездо " .. socket .. ")" or ""))
        else
            return Done(false, "invalid_operation")
        end
        if not applied then return Done(false, "apply_failed") end
        target:SaveToDB()
        N.Log("RPS_Combat", "item_enchant:" .. Id(player) .. ":" .. Id(target) .. ":" .. tostring(item:GetGUID())
            .. ":" .. operation .. ":" .. tostring(socket or 0) .. ":" .. tostring(value))
        R.SyncPlayerState(target)
        if R.Combat.BroadcastUnitUpdate then R.Combat.BroadcastUnitUpdate(target, AIO) end
        Reply(target, "ItemChanged", {guid = tostring(item:GetGUID()), entry = item:GetEntry()})
        if target ~= player then target:SendBroadcastMessage("Ведущий изменил ваш предмет: " .. label) end
        return Done(true, label, {guid = tostring(item:GetGUID())})
    end

    local function FindTarget(player, targetGuid)
        if targetGuid == nil then return player end
        local wanted = R.NormalizeWireGuid(targetGuid)
        if not wanted then return nil end
        for _, other in ipairs(GetPlayersInWorld() or {}) do
            if R.NormalizeWireGuid(other:GetGUID()) == wanted then return other end
        end
    end

    -- Equipment snapshot of a player for the DM items tab: bag 255, slots 0..18.
    function I.EnchantState(target)
        local slots = {}
        for slot = 0, 18 do
            local item = target:GetItemByPos(255, slot)
            if item then
                local ids = EnchantIds(item)
                local metadata, metadataState = ReadNative(target, item)
                slots[#slots + 1] = {slot = slot, guid = tostring(item:GetGUID()), metadata = metadata, metadataState = metadataState, entry = item:GetEntry(), rpItem = IsRpItem(item), grade = Quality(item),
                    gemSlots = GemSlots(item), enchant = ids[1], gems = {ids[2], ids[3], ids[4]}}
            end
        end
        return {target = R.NormalizeWireGuid(target:GetGUID()), name = target:GetName(), slots = slots}
    end

    function H.RequestItemEnchantState(player, targetGuid, requestId)
        if not N.HasStaffPermission(player) then return end
        local target = FindTarget(player, targetGuid)
        Reply(player, "ItemEnchantState", {requestId = C.Integer(requestId, 1, 2147483647) and requestId or nil,
            catalog = I.EnchantCatalog(), stats = type(RpsGetItemModifierDefinitions) == "function" and RpsGetItemModifierDefinitions() or {}, gemSlots = GEM_SLOTS,
            state = target and I.EnchantState(target) or nil})
    end

    function H.DmItemEnchant(player, targetGuid, bag, slot, operation, socket, value)
        local target = FindTarget(player, targetGuid)
        if I.Enchant(player, target, bag, slot, operation, socket, value) and target then
            Reply(player, "ItemEnchantState", {catalog = I.EnchantCatalog(), stats = type(RpsGetItemModifierDefinitions) == "function" and RpsGetItemModifierDefinitions() or {}, gemSlots = GEM_SLOTS, state = I.EnchantState(target)})
        end
    end

    -- Staff-only own-inventory editor. A revision and durable request ID are explicit.
    function I.Set(player, bag, slot, json, reason, requestId, target, expectedGuid, requestSignature)
        local messages = {permission_denied = "Недостаточно прав", system_unavailable = "Система недоступна",
            invalid_request_id = "Некорректный номер запроса", invalid_item_position = "Некорректный слот",
            invalid_reason = "Укажите причину изменения", invalid_item_metadata = "Некорректные свойства предмета",
            request_conflict = "Этот номер запроса уже использован для другого изменения",
            receipt_incomplete = "Предыдущий результат повреждён; требуется проверка",
            receipt_unavailable = "Не удалось проверить предыдущий результат", invalid_item = "Предмет недоступен",
            stale_item = "Свойства уже изменились; проверьте текущую ревизию", actor_busy = "Дождитесь предыдущего изменения",
            item_not_rp_only = "Этот предмет не поддерживает RP-свойства", save_failed = "Не удалось сохранить изменение",
            item_unavailable = "Не удалось подтвердить свойства предмета в базе"}
        local function Fail(code)
            Reply(player, "ItemMetadataResult", {ok = false, code = code, requestId = requestId})
            player:SendBroadcastMessage("Предмет не изменён: " .. (messages[code] or code))
        end
        if not N.HasStaffPermission(player) then return Fail("permission_denied") end
        if not R.ready or type(RpsParseItemMetadata) ~= "function" or type(RpsCommitAsync) ~= "function" then return Fail("system_unavailable") end
        if type(requestId) ~= "string" or #requestId < 1 or #requestId > 80 or not requestId:match("^[%w_-]+$") then return Fail("invalid_request_id") end
        if not C.Integer(bag, 0, 255) or not C.Integer(slot, 0, 255) then return Fail("invalid_item_position") end
        if type(reason) ~= "string" or #reason < 3 or #reason > 200 or reason:find("%c") then return Fail("invalid_reason") end
        if type(json) ~= "string" or #json > 8192 then return Fail("invalid_item_metadata") end
        local metadata, canonical = RpsParseItemMetadata(json)
        if not metadata then return Fail("invalid_item_metadata") end
        target = target or player
        local issuer, owner = Id(player), Id(target)
        local signature = bag .. ":" .. slot .. ":" .. reason .. ":" .. canonical
        if expectedGuid then signature = owner .. ":" .. expectedGuid .. ":" .. signature end
        signature = requestSignature or signature
        local where = " WHERE issuer_guid=" .. issuer .. " AND request_id=" .. Q(requestId)
        local function Existing(notify, duplicate)
            local q = CharDBQuery("SELECT signature,state,result_payload,result_kind FROM rps_action_receipts" .. where)
            if not q then return false end
            if q:GetString(0) ~= signature or q:GetString(3) ~= "item_metadata" then
                if notify then Fail("request_conflict") end
                return true
            end
            local result = S.DecodeReceipt(q:GetString(2))
            local recorded = result and type(result.json) == "string" and RpsParseItemMetadata(result.json)
            if q:GetString(1) ~= "done" or not recorded or type(result.guid) ~= "string"
                or #result.guid > 128 or not result.guid:match("^Item%-[%x%-]+$")
                or (not requestSignature and result.json ~= canonical) or result.revision ~= recorded.revision then
                if notify then Fail("receipt_incomplete") end
                return true
            end
            local currentOwner = Apply(result.guid)
            if notify then
                Reply(player, "ItemMetadataResult", {ok = true, duplicate = duplicate == true, guid = result.guid, revision = result.revision, requestId = requestId,
                    state = currentOwner and I.EnchantState(currentOwner)})
                player:SendBroadcastMessage("Свойства предмета сохранены. Ревизия: " .. result.revision .. ". Запрос: " .. requestId)
            end
            return true
        end
        if Existing(true, true) then return end
        local count = CharDBQuery("SELECT COUNT(*) FROM rps_action_receipts" .. where)
        if not count then return Fail("receipt_unavailable") end
        if count:GetUInt32(0) > 0 then return Fail("receipt_unavailable") end
        local item = target:GetItemByPos(bag, slot)
        if expectedGuid and (not item or tostring(item:GetGUID()) ~= expectedGuid) then return Fail("stale_item") end
        if not item or item:GetCount() ~= 1 or item:IsInTrade() then return Fail("invalid_item") end
        if not IsRpItem(item) then return Fail("item_not_rp_only") end
        -- Read the stored revision before CAS; the cache can lag behind a completed write.
        local previous, state, old = ReadNative(target, item)
        if state == "unknown" then return Fail("item_unavailable") end
        local revision = previous and previous.revision or 0
        if metadata.revision ~= revision + 1 then return Fail("stale_item") end
        local low, guid = C.IdString(item:GetGUIDLow()), tostring(item:GetGUID())
        if not low or pending[low] then return Fail("actor_busy") end
        local payload = S.EncodeReceipt({guid = guid, revision = metadata.revision, json = canonical, reason = reason})
        if not payload then return Fail("invalid_item_metadata") end
        local predicate = "ii.guid=" .. low .. " AND ii.owner_guid=" .. owner .. " AND ii.count=1 AND "
            .. (revision == 0 and "rm.item_guid IS NULL" or "BINARY rm.metadata=" .. Q(old))
        local itemJoin = " FROM item_instance ii LEFT JOIN rps_item_metadata rm ON rm.item_guid=ii.guid"
        local claim = "INSERT INTO rps_action_receipts (issuer_guid,request_id,signature,state,result_kind,result_payload) SELECT "
            .. issuer .. "," .. Q(requestId) .. "," .. Q(signature) .. ",'done','item_metadata'," .. Q(payload)
            .. itemJoin .. " WHERE " .. predicate .. " FOR UPDATE"
        local claimed = " AND EXISTS (SELECT 1 FROM rps_action_receipts" .. where .. " AND BINARY signature=" .. Q(signature) .. ")"
        local update
        if revision == 0 then
            update = "INSERT INTO rps_item_metadata (item_guid,metadata) SELECT ii.guid," .. Q(canonical)
                .. itemJoin .. " WHERE " .. predicate .. claimed
        else
            update = "UPDATE rps_item_metadata rm INNER JOIN item_instance ii ON ii.guid=rm.item_guid SET rm.metadata="
                .. Q(canonical) .. " WHERE " .. predicate .. claimed
        end
        pending[low] = true
        local locator, entered = player:GetGUID(), false
        local function Done(saved)
            entered = true
            pending[low] = nil
            local current = GetPlayerByGUID(locator)
            if current then player = current end
            -- The item may have moved to another online owner while the issuer logged out.
            if Existing(current ~= nil, not saved) then return end
            if current then Fail(saved and "stale_item" or "save_failed") end
        end
        local called = pcall(RpsCommitAsync, "characters", {claim, update}, Done)
        if not called and not entered then Done(false) end
    end

    local function JsonString(value)
        return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
            if c == '"' then return '\\"' end
            if c == '\\' then return '\\\\' end
            return string.format('\\u%04x', c:byte())
        end) .. '"'
    end
    local function ModifierJson(values)
        if type(values) ~= "table" then return end
        local entries = {}
        for key, value in pairs(values) do
            if type(key) ~= "string" or #key > 40 or not C.Integer(value, -1000, 1000) then return end
            entries[#entries + 1] = JsonString(key) .. ":" .. value
            if #entries > 64 then return end
        end
        table.sort(entries)
        return "{" .. table.concat(entries, ",") .. "}"
    end
    function H.DmItemProperties(player, targetGuid, guid, slot, revision, operation, socket, values, reason, requestId)
        if not N.HasStaffPermission(player) then return end
        local function Fail(code)
            Reply(player, "ItemMetadataResult", {ok = false, code = code, requestId = requestId})
        end
        if not R.ready or type(CharDBQuery) ~= "function" or type(RpsParseItemMetadata) ~= "function"
            or type(RpsCommitAsync) ~= "function" then return Fail("system_unavailable") end
        if type(requestId) ~= "string" or #requestId < 1 or #requestId > 80 or not requestId:match("^[%w_-]+$") then return Fail("invalid_request_id") end
        if type(reason) ~= "string" or #reason < 3 or #reason > 200 or reason:find("%c") then return Fail("invalid_reason") end
        if type(targetGuid) ~= "string" or #targetGuid > 128 or type(guid) ~= "string" or #guid > 128
            or not C.Integer(slot, 0, 18) or not C.Integer(revision, 0, 4294967294) then return Fail("invalid_item") end
        if operation ~= "enchant" and operation ~= "gem" then return Fail("invalid_operation") end
        if not C.Integer(socket, 0, 3) then return Fail("no_gem_slot") end
        local json = ModifierJson(values)
        if not json then return Fail("invalid_item_metadata") end
        local signature = table.concat({"properties", targetGuid, guid, slot, revision, operation, socket, reason, json}, ":")
        local receipt = CharDBQuery("SELECT signature,state,result_payload,result_kind FROM rps_action_receipts WHERE issuer_guid="
            .. Id(player) .. " AND request_id=" .. Q(requestId))
        if receipt then
            if receipt:GetString(0) ~= signature or receipt:GetString(3) ~= "item_metadata" then return Fail("request_conflict") end
            local result = S.DecodeReceipt(receipt:GetString(2))
            local recorded = type(result) == "table" and type(result.json) == "string" and RpsParseItemMetadata(result.json)
            if not recorded or recorded.revision ~= revision + 1 then return Fail("receipt_incomplete") end
            if receipt:GetString(1) ~= "done" or type(result) ~= "table" or result.guid ~= guid
                or result.revision ~= revision + 1 then return Fail("receipt_incomplete") end
            local currentOwner = Apply(guid)
            return Reply(player, "ItemMetadataResult", {ok = true, duplicate = true, guid = guid,
                revision = result.revision, requestId = requestId, state = currentOwner and I.EnchantState(currentOwner)})
        end
        local target = FindTarget(player, targetGuid)
        local item = target and target:GetItemByPos(255, slot)
        if not item or tostring(item:GetGUID()) ~= guid or not IsRpItem(item) then return Fail("stale_item") end
        local metadata, state = ReadNative(target, item)
        if state == "unknown" or state == "invalid" then return Fail("item_unavailable") end
        if operation == "gem" and not C.Integer(socket, 1, GemSlots(item)) then return Fail("no_gem_slot") end
        metadata = metadata or {name = "", description = "", modifiers = {}}
        local fields = {'"version":1', '"revision":' .. (revision + 1), '"name":' .. JsonString(metadata.name),
            '"description":' .. JsonString(metadata.description), '"modifiers":' .. ModifierJson(metadata.modifiers)}
        if operation == "enchant" or metadata.properties then
            fields[#fields + 1] = '"properties":' .. (operation == "enchant" and json or ModifierJson(metadata.properties))
        end
        local runes = {}
        for n = 1, 3 do
            local rune = metadata.runes and metadata.runes[tostring(n)]
            if operation == "gem" and n == socket then
                runes[#runes + 1] = JsonString(tostring(n)) .. ":" .. json
            elseif rune then
                runes[#runes + 1] = JsonString(tostring(n)) .. ":" .. ModifierJson(rune)
            end
        end
        if #runes > 0 then fields[#fields + 1] = '"runes":{' .. table.concat(runes, ",") .. '}' end
        I.Set(player, 255, slot, "{" .. table.concat(fields, ",") .. "}", reason, requestId, target, guid, signature)
    end

    function I.Command(player, command)
        local args = command:match("^rps item%s+(.+)$")
        if not args then return end
        if not N.HasStaffPermission(player) then return false end
        local bag, slot = args:match("^show (%d+) (%d+)$")
        if bag then
            local item = player:GetItemByPos(tonumber(bag), tonumber(slot))
            if item then
                local metadata, state = ReadNative(player, item)
                local definition = templates[item:GetEntry()]
                player:SendBroadcastMessage(tostring(item:GetGUID()) .. " entry=" .. item:GetEntry()
                    .. " revision=" .. (metadata and metadata.revision or 0) .. " " .. state
                    .. (definition and definition.set and " set=" .. definition.set or "")
                    .. " grade=" .. Quality(item) .. " gems=" .. GemSlots(item)
                    .. " enchants=" .. table.concat(EnchantIds(item), ","))
            end
            return false
        end
        if args == "catalog" then
            for _, entry in ipairs(I.EnchantCatalog()) do
                player:SendBroadcastMessage(entry.id .. " [" .. (entry.kind == "gem" and "камень" or "чара") .. "] " .. entry.name)
            end
            return false
        end
        local selection = player:GetSelection()
        local target = selection and selection:ToPlayer() or player
        local value
        bag, slot, value = args:match("^grade (%d+) (%d+) (%d+)$")
        if bag then I.Enchant(player, target, tonumber(bag), tonumber(slot), "grade", 0, tonumber(value)); return false end
        bag, slot, value = args:match("^enchant (%d+) (%d+) (%d+)$")
        if bag then I.Enchant(player, target, tonumber(bag), tonumber(slot), "enchant", 0, tonumber(value)); return false end
        local socket
        bag, slot, socket, value = args:match("^gem (%d+) (%d+) (%d) (%d+)$")
        if bag then I.Enchant(player, target, tonumber(bag), tonumber(slot), "gem", tonumber(socket), tonumber(value)); return false end
        local request, reason, json
        bag, slot, request, reason, json = args:match("^set (%d+) (%d+) ([%w_-]+) (.-) | (.+)$")
        if bag then I.Set(player, tonumber(bag), tonumber(slot), json, reason, request)
        else
            player:SendBroadcastMessage("Используйте: .rps item show|set|catalog; .rps item grade <сумка> <слот> <0-5>;"
                .. " .rps item enchant <сумка> <слот> <id|0>; .rps item gem <сумка> <слот> <1-3> <id|0> (цель — выбранный игрок)")
        end
        return false
    end
    return I
end

return I
