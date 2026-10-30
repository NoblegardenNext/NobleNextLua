-- No DB mutations, hooks, AIO or spell grants on require.
local C = require("Modules.RPS_Combat.00_RPS_Config")
local DB = require("Core.DB")
local S = {PlayerProfiles = {}, NpcTemplateCache = {}, NpcSpawnCache = {}, RuntimeNpcs = {}}
local MAX_JSON_BYTES, MAX_RUNTIME_NPCS = 16384, 4096

-- AIO already uses this non-executable codec. Retain the complete result, including
-- nested reaction outcomes, instead of reconstructing a lossy subset after reload.
function S.EncodeReceipt(result)
    local codec = Smallfolk or require("smallfolk")
    local ok, payload = pcall(codec.dumps, result)
    if not ok or type(payload) ~= "string" or #payload > MAX_JSON_BYTES then return nil, "invalid_receipt" end
    return payload
end

function S.DecodeReceipt(payload)
    if type(payload) ~= "string" or #payload > MAX_JSON_BYTES then return nil, "receipt_incomplete" end
    local codec = Smallfolk or require("smallfolk")
    local ok, result = pcall(codec.loads, payload, #payload)
    if not ok or type(result) ~= "table" then return nil, "invalid_receipt" end
    return result
end

-- stats_json is deliberately a flat integer dictionary. Nested equip/effects JSON
-- stays opaque and is retained byte-for-byte; it must not pass through this codec.
function S.EncodeFlatJson(stats)
    if type(stats) ~= "table" then return nil, "invalid_stats" end
    local keys, parts = {}, {}
    for key, value in pairs(stats) do
        if not C.ValidStatKey(key) or not C.Integer(value, -1000, 1000) then return nil, "invalid_stats" end
        keys[#keys + 1] = key
        if #keys > C.MAX_DEFINITIONS then return nil, "too_many_stats" end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do parts[#parts + 1] = '"' .. key .. '":' .. string.format("%d", stats[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function S.DecodeFlatJson(json)
    if type(json) ~= "string" or #json > MAX_JSON_BYTES then return nil, "invalid_stats_json" end
    local rest = json:match("^%s*{(.-)}%s*$")
    if not rest then return nil, "invalid_stats_json" end
    local stats, count = {}, 0
    if rest:match("^%s*$") then return stats end
    while true do
        local key, value, nextPos = rest:match('^%s*"([a-z][a-z0-9_]*)"%s*:%s*(%-?%d+)%s*()')
        if not key or not C.ValidStatKey(key) or stats[key] ~= nil
            or not C.Integer(tonumber(value), -1000, 1000)
            or value:match("^%-?0%d") then return nil, "invalid_stats_json" end
        count = count + 1
        if count > C.MAX_DEFINITIONS then return nil, "too_many_stats" end
        stats[key], rest = tonumber(value), rest:sub(nextPos)
        if rest == "" then return stats end
        if rest:sub(1, 1) ~= "," then return nil, "invalid_stats_json" end
        rest = rest:sub(2)
    end
end

local function Copy(record)
    local copy = {}
    for key, value in pairs(record) do
        if type(value) == "table" then
            copy[key] = {}; for k, v in pairs(value) do copy[key][k] = v end
        else copy[key] = value end
    end
    return copy
end
S.CopyProfile = Copy

local function ValidResources(p)
    return C.Integer(p.maxHealth, 1, C.MAX_RESOURCE) and C.Integer(p.curHealth, 0, C.MAX_RESOURCE)
        and C.Integer(p.maxEnergy, 0, C.MAX_RESOURCE) and C.Integer(p.curEnergy, 0, C.MAX_RESOURCE)
        and C.Integer(p.armor, 0, 1000000) and C.Integer(p.speed, 0, 1000)
        and C.ParseDice(p.weaponDice) and C.ParseDice(p.blockDice)
end

function S.BuildDefaultPlayerProfile(player, archetype)
    archetype = archetype or "fighter"
    local arch = C.Archetypes[archetype]
    local guid = player and C.IdString(player:GetGUIDLow())
    if not arch or not guid or guid == "0" then return nil, "invalid_player" end
    local stats = {}
    for _, def in ipairs(C.StatOrder) do
        if def.category == "combat" or def.category == "mastery" then
            stats[def.key] = arch.stats[def.key] and arch.stats[def.key][1] or def.defaultValue
        end
    end
    return {guid = guid, archetype = archetype, raceId = "human", racialTrait = "", commonTrait = "",
        level = 1, xp = 0, curHealth = arch.health[1], maxHealth = arch.health[1],
        curEnergy = arch.energy[1], maxEnergy = arch.energy[1], energySpentRound = 0,
        curWounds = 0, maxWounds = 3, armor = 0, speed = arch.speed, weaponDice = "1d8", blockDice = "1d4",
        stats = stats, equipJson = "{}", effectsJson = "{}", isPlayer = true}
end

function S.GetOrLoadPlayerProfile(player, query)
    local guid = player and C.IdString(player:GetGUIDLow())
    if not guid or guid == "0" then return nil, "invalid_player" end
    if S.PlayerProfiles[guid] then return S.PlayerProfiles[guid] end
    query = query or CharDBQuery
    if type(query) ~= "function" then return nil, "character_query_unavailable" end
    local q = query([[SELECT archetype, race_id, racial_trait, common_trait, rp_level, rp_xp,
        cur_health, max_health, cur_energy, max_energy, energy_spent_round, cur_wounds, max_wounds,
        armor, speed, weapon_dice, block_dice, stats_json, equip_json, effects_json
        , revision, death_outcome FROM character_rps_stats WHERE guid = ]] .. guid)
    -- The native Query API conflates empty results and errors. Do not silently
    -- replace an unavailable existing profile with a new fully healed fighter.
    if not q then return nil, "profile_missing_or_query_failed" end
    local stats, err = S.DecodeFlatJson(q:GetString(17))
    if not stats then return nil, err end
    local p = {guid = guid, archetype = q:GetString(0), raceId = q:GetString(1),
        racialTrait = q:GetString(2) or "", commonTrait = q:GetString(3) or "",
        level = q:GetUInt8(4), xp = q:GetUInt32(5), curHealth = q:GetInt32(6), maxHealth = q:GetInt32(7),
        curEnergy = q:GetInt32(8), maxEnergy = q:GetInt32(9), energySpentRound = q:GetInt32(10),
        curWounds = q:GetUInt8(11), maxWounds = q:GetUInt8(12), armor = q:GetInt32(13), speed = q:GetInt32(14),
        weaponDice = q:GetString(15), blockDice = q:GetString(16), stats = stats,
        equipJson = q:GetString(18) or "{}", effectsJson = q:GetString(19) or "{}", isPlayer = true,
        revision = q:GetUInt32(20) or 0, deathOutcome = q:GetString(21) or ""}
    if not C.Archetypes[p.archetype] or not C.Integer(p.level, 1, 10)
        or not C.Integer(p.energySpentRound, 0, 1000)
        or not C.Integer(p.maxWounds, 1, 255) or not C.Integer(p.curWounds, 0, 255)
        or not ValidResources(p) then return nil, "invalid_player_profile" end
    for _, def in ipairs(C.StatOrder) do
        if (def.category == "combat" or def.category == "mastery") and p.stats[def.key] == nil then
            p.stats[def.key] = def.defaultValue
        end
    end
    S.PlayerProfiles[guid] = p
    return p
end

function S.ReleasePlayer(player)
    local guid = player and C.IdString(player:GetGUIDLow())
    if guid then S.PlayerProfiles[guid], S.Creation[guid] = nil, nil end
end

local roles = {minion = true, lieutenant = true, boss = true}
local function ReadNpc(q, spawn, runtime)
    local offset = spawn and 2 or 0
    local stats, err = S.DecodeFlatJson(q:GetString(9 + offset))
    if not stats then return nil, err end
    local p = {entry = q:GetUInt32(spawn and 2 or 0), source = spawn and "guid" or "template",
        roleType = q:GetString(1 + offset), isStaticThreshold = q:GetUInt8(2 + offset) == 1,
        maxHealth = q:GetInt32(3 + offset), maxEnergy = q:GetInt32(4 + offset),
        armor = q:GetInt32(5 + offset), speed = q:GetInt32(6 + offset),
        weaponDice = q:GetString(7 + offset), blockDice = q:GetString(8 + offset), stats = stats,
        isPlayer = false}
    p.curHealth, p.curEnergy = p.maxHealth, p.maxEnergy
    if spawn then
        p.spawnGuid, p.customName = C.IdString(q:GetUInt64(0)), q:GetString(1)
        p.curHealth, p.curEnergy, p.effectsJson = q:GetInt32(12), q:GetInt32(13), q:GetString(14) or "{}"
        if not p.spawnGuid or (p.spawnGuid == "0" and not runtime) then return nil, "invalid_spawn_id" end
    end
    if not C.Integer(p.entry, 1, 4294967295) or not roles[p.roleType] or not ValidResources(p) then
        return nil, "invalid_npc_profile"
    end
    return p
end

function S.LoadNpcCaches(query)
    query = query or WorldDBQuery
    if type(query) ~= "function" then return false, "world_query_unavailable" end
    -- COUNT distinguishes a genuinely empty table from a failed table query.
    local function Load(tableName, columns, spawn)
        local countQuery = query("SELECT COUNT(*) FROM " .. tableName)
        if not countQuery then return nil, "npc_table_unavailable" end
        local count = countQuery:GetUInt32(0)
        if count > 100000 then return nil, "npc_cache_too_large" end
        local cache = {}
        if count == 0 then return cache end
        local q = query("SELECT " .. columns .. " FROM " .. tableName)
        if not q then return nil, "npc_table_unavailable" end
        local loaded = 0
        repeat
            local p, err = ReadNpc(q, spawn)
            if not p then return nil, err end
            cache[spawn and p.spawnGuid or p.entry] = p
            loaded = loaded + 1
            if loaded > 100000 then return nil, "npc_cache_too_large" end
        until not q:NextRow()
        return cache
    end
    local templates, err = Load("rps_creature_template_stats", [[entry, role_type, is_static_threshold,
        max_health, max_energy, armor, speed, weapon_dice, block_dice, stats_json]], false)
    if not templates then return false, err end
    local spawns
    spawns, err = Load("rps_creature_spawn_stats", [[spawn_guid, custom_name, entry, role_type, is_static_threshold,
        max_health, max_energy, armor, speed, weapon_dice, block_dice, stats_json, cur_health, cur_energy, effects_json]], true)
    if not spawns then return false, err end
    S.NpcTemplateCache, S.NpcSpawnCache = templates, spawns
    -- Keep the current runtime instances on a definitions reload; no implicit heal.
    return true
end

function S.GetCreatureStats(creature)
    if not creature then return nil, "invalid_creature" end
    local spawnId = C.IdString(creature:GetDBTableGUIDLow())
    if not spawnId then return nil, "invalid_spawn_id" end
    local runtimeGuid = tostring(creature:GetGUID())
    if runtimeGuid == "" or #runtimeGuid > 128 then return nil, "invalid_runtime_guid" end
    local runtimeKey = tostring(creature:GetMapId()) .. ":" .. tostring(creature:GetInstanceId()) .. ":" .. runtimeGuid
    local existing = S.RuntimeNpcs[runtimeKey]
    if existing then return existing end
    local baseline = (spawnId ~= "0" and S.NpcSpawnCache[spawnId]) or S.NpcTemplateCache[creature:GetEntry()]
    if not baseline and not S.RuntimePersistence then return nil end
    if baseline and baseline.entry ~= creature:GetEntry() then return nil, "spawn_template_changed" end
    local count = 0
    for _ in pairs(S.RuntimeNpcs) do count = count + 1 end
    if count >= MAX_RUNTIME_NPCS then return nil, "runtime_cache_full" end
    local p = baseline and Copy(baseline) or S.BuildCreatureProfile(creature)
    p.spawnGuid, p.runtimeKey, p.runtimeGuid = spawnId, runtimeKey, runtimeGuid
    p.entry = creature:GetEntry()
    p.name = p.customName and p.customName ~= "" and p.customName or creature:GetName()
    p.storageKey = (RpsRuntimeEpoch and RpsRuntimeEpoch() or "offline") .. ":" .. runtimeKey
    if S.RuntimePersistence then
        local key = "'" .. DB.EscapeSqlString(p.storageKey) .. "'"
        local count = WorldDBQuery("SELECT COUNT(*) FROM rps_creature_runtime_stats WHERE runtime_key=" .. key)
        if not count then return nil, "runtime_store_unavailable" end
        if count:GetUInt32(0) > 0 then
            local q = WorldDBQuery([[SELECT spawn_guid, custom_name, entry, role_type, is_static_threshold,
                max_health, max_energy, armor, speed, weapon_dice, block_dice, stats_json,
                cur_health, cur_energy, effects_json, revision FROM rps_creature_runtime_stats WHERE runtime_key=]] .. key)
            if not q then return nil, "runtime_store_unavailable" end
            local restored, err = ReadNpc(q, true, true)
            if not restored then return nil, err end
            if restored.entry ~= p.entry then return nil, "spawn_template_changed" end
            restored.runtimeKey, restored.runtimeGuid, restored.storageKey = runtimeKey, runtimeGuid, p.storageKey
            restored.name, restored.revision = p.name, q:GetUInt32(15)
            p = restored
        elseif not baseline then return nil end
    end
    S.RuntimeNpcs[runtimeKey] = p
    return p
end

-- Called by future despawn/scene lifecycle integration, never by definition reload.
function S.ReleaseCreature(creature)
    if not creature then return end
    local key = tostring(creature:GetMapId()) .. ":" .. tostring(creature:GetInstanceId()) .. ":" .. tostring(creature:GetGUID())
    S.RuntimeNpcs[key] = nil
end

function S.ResolveUnitStats(unit)
    if not unit then return nil end
    local player = unit:ToPlayer()
    if player then
        local profile, why = S.GetOrLoadPlayerProfile(player)
        return S.WithEquipment and S.WithEquipment(player, profile) or profile, why
    end
    local creature = unit:ToCreature()
    if creature then return S.GetCreatureStats(creature) end
end

local function Quote(value, maxBytes)
    if type(value) ~= "string" or #value > maxBytes or value:find("%z") then return nil end
    return "'" .. DB.EscapeSqlString(value) .. "'"
end

local function Upsert(tableName, columns, values)
    local names, encoded, updates = {}, {}, {}
    for i, col in ipairs(columns) do
        names[i], encoded[i] = "`" .. col .. "`", values[i]
        if not values[i] then return nil, "invalid_save_field" end
        if i > 1 then updates[#updates + 1] = "`" .. col .. "`=VALUES(`" .. col .. "`)" end
    end
    return "INSERT INTO `" .. tableName .. "` (" .. table.concat(names, ",") .. ") VALUES ("
        .. table.concat(encoded, ",") .. ") ON DUPLICATE KEY UPDATE " .. table.concat(updates, ",")
end

-- Creation state lives in character_rps_creation, apart from character_rps_stats: combat
-- profiles keep loading when the creation schema is not applied yet. No row means 'none'.
S.Creation = {}
S.CreationStates = {none = true, legacy = true, reconfigure = true, complete = true}
local MASTERY_COLUMNS = {"skill", "knowledge", "endurance", "craft"}

-- rp_name stays in the table for compatibility: it is no longer read or written.
function S.EmptyCreation(guid)
    return {guid = guid, state = "none", catalogVersion = "", race = "", racialFeature = "",
        archetype = "", traits = {}, traitChoice = "", mastery = {skill = 0, knowledge = 0, endurance = 0, craft = 0},
        revision = 0, confirmedAt = 0, confirmedBy = "0", starterGranted = false, starterGrantedAt = 0,
        racePresetVersion = 0}
end

-- race_preset_version comes from 2026_10_27_02; without it the version reads as 0 and is not saved.
-- nil = not probed yet (or the probe failed and is retried on the next load).
S.RacePresetColumn = nil
function S.HasRacePresetColumn(query)
    if S.RacePresetColumn == nil then
        query = query or CharDBQuery
        local q = type(query) == "function" and query([[SELECT COUNT(*) FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'character_rps_creation'
            AND COLUMN_NAME = 'race_preset_version']])
        if not q then return false end
        S.RacePresetColumn = q:GetUInt32(0) > 0
    end
    return S.RacePresetColumn
end

function S.LoadCreation(guid, query)
    guid = C.IdString(guid)
    if not guid or guid == "0" then return nil, "invalid_player" end
    query = query or CharDBQuery
    if type(query) ~= "function" then return nil, "character_query_unavailable" end
    local count = query("SELECT COUNT(*) FROM character_rps_creation WHERE guid = " .. guid)
    if not count then return nil, "creation_schema_unavailable" end
    if count:GetUInt32(0) == 0 then return S.EmptyCreation(guid) end
    local preset = S.HasRacePresetColumn(query)
    local q = query([[SELECT creation_state, catalog_version, race_key, racial_feature_key, archetype_key,
        trait_keys, trait_choice, mastery_skill, mastery_knowledge, mastery_endurance, mastery_craft,
        revision, confirmed_at, confirmed_by, starter_granted, starter_granted_at]]
        .. (preset and ", race_preset_version" or "") .. " FROM character_rps_creation WHERE guid = " .. guid)
    if not q then return nil, "creation_query_failed" end
    local rec = S.EmptyCreation(guid)
    rec.state, rec.catalogVersion = q:GetString(0), q:GetString(1) or ""
    rec.race, rec.racialFeature, rec.archetype = q:GetString(2) or "", q:GetString(3) or "", q:GetString(4) or ""
    for key in (q:GetString(5) or ""):gmatch("[^,]+") do rec.traits[#rec.traits + 1] = key end
    rec.traitChoice = q:GetString(6) or ""
    for i, key in ipairs(MASTERY_COLUMNS) do rec.mastery[key] = q:GetUInt8(6 + i) end
    rec.revision, rec.confirmedAt = q:GetUInt32(11), q:GetUInt32(12)
    rec.confirmedBy, rec.starterGranted = C.IdString(q:GetUInt64(13)) or "0", q:GetUInt8(14) == 1
    rec.starterGrantedAt = q:GetUInt32(15)
    rec.racePresetVersion = preset and q:GetUInt32(16) or 0
    if not C.Integer(rec.racePresetVersion, 0, 4294967295) then return nil, "invalid_creation_record" end
    if not S.CreationStates[rec.state] or not C.Integer(rec.revision, 0, 4294967295) then
        return nil, "invalid_creation_record"
    end
    for _, key in ipairs(MASTERY_COLUMNS) do
        if not C.Integer(rec.mastery[key], 0, 255) then return nil, "invalid_creation_record" end
    end
    return rec
end

function S.GetOrLoadCreation(guid, query)
    guid = C.IdString(guid)
    if guid and S.Creation[guid] then return S.Creation[guid] end
    local rec, err = S.LoadCreation(guid, query)
    if rec then S.Creation[guid] = rec end
    return rec, err
end

function S.CopyCreation(rec)
    local copy = Copy(rec)
    copy.traits = {}; for i, key in ipairs(rec.traits or {}) do copy.traits[i] = key end
    return copy
end

function S.BuildCreationSave(rec)
    local id = C.IdString(rec and rec.guid)
    if not id or id == "0" or not S.CreationStates[rec.state] or not C.Integer(rec.revision, 0, 4294967295)
        or not C.Integer(rec.confirmedAt or 0, 0, 4294967295) or not C.Integer(rec.starterGrantedAt or 0, 0, 4294967295) then
        return nil, "invalid_creation_record"
    end
    local values = {id, Quote(rec.state, 16), Quote(rec.catalogVersion or "", 64), Quote(rec.race or "", 32), Quote(rec.racialFeature or "", 64), Quote(rec.archetype or "", 32),
        Quote(table.concat(rec.traits or {}, ","), 255), Quote(rec.traitChoice or "", 32)}
    for _, key in ipairs(MASTERY_COLUMNS) do
        local value = C.Integer(rec.mastery and rec.mastery[key] or 0, 0, 255)
        if not value then return nil, "invalid_creation_record" end
        values[#values + 1] = tostring(value)
    end
    values[#values + 1] = tostring(rec.revision)
    values[#values + 1] = tostring(rec.confirmedAt or 0)
    values[#values + 1] = C.IdString(rec.confirmedBy or "0")
    values[#values + 1] = rec.starterGranted and "1" or "0"
    values[#values + 1] = tostring(rec.starterGrantedAt or 0)
    local columns = {"guid", "creation_state", "catalog_version", "race_key",
        "racial_feature_key", "archetype_key", "trait_keys", "trait_choice", "mastery_skill", "mastery_knowledge",
        "mastery_endurance", "mastery_craft", "revision", "confirmed_at", "confirmed_by", "starter_granted",
        "starter_granted_at"}
    if S.HasRacePresetColumn() then
        local version = C.Integer(rec.racePresetVersion or 0, 0, 4294967295)
        if not version then return nil, "invalid_creation_record" end
        columns[#columns + 1], values[#values + 1] = "race_preset_version", tostring(version)
    end
    return Upsert("character_rps_creation", columns, values)
end

-- entry = {guid, revision, action, fromState, toState, actorGuid, requestId, reason, snapshotJson, createdAt}
function S.BuildCreationLog(entry)
    local guid, actor = C.IdString(entry.guid), C.IdString(entry.actorGuid)
    local values = {guid, tostring(C.Integer(entry.revision, 0, 4294967295) or ""), Quote(entry.action, 16),
        Quote(entry.fromState, 16), Quote(entry.toState, 16), actor, Quote(entry.requestId, 80),
        Quote(entry.reason or "", 255), Quote(entry.snapshotJson or "{}", 1048576),
        tostring(C.Integer(entry.createdAt, 0, 4294967295) or "")}
    for i = 1, 10 do if not values[i] or values[i] == "" then return nil, "invalid_creation_log" end end
    return "INSERT INTO `character_rps_creation_log` (`guid`,`revision`,`action`,`from_state`,`to_state`,"
        .. "`actor_guid`,`request_id`,`reason`,`snapshot_json`,`created_at`) VALUES (" .. table.concat(values, ",") .. ")"
end

-- items = {{key, kind, quality, slot?, stack?}}; every row goes to the RP storage location.
function S.BuildStarterItems(guid, items, createdAt)
    local id = C.IdString(guid)
    if not id or id == "0" or type(items) ~= "table" or #items > 255 then return nil, "invalid_starter_items" end
    if #items == 0 then return {} end
    local rows = {}
    for i, item in ipairs(items) do
        local key, kind, quality = Quote(item.key, 64), Quote(item.kind, 16), Quote(item.quality or "simple", 16)
        local stack = C.Integer(item.stack or 1, 1, 65535)
        if not key or not kind or not quality or not stack then return nil, "invalid_starter_items" end
        rows[i] = "(" .. table.concat({id, key, kind, quality, "'storage'", Quote(item.slot or "", 16) or "''",
            tostring(stack), "'starter'", tostring(i), tostring(createdAt or 0)}, ",") .. ")"
    end
    return {"INSERT INTO `character_rps_items` (`owner_guid`,`item_key`,`item_kind`,`quality`,`location`,`slot`,"
        .. "`stack`,`source`,`starter_slot`,`created_at`) VALUES " .. table.concat(rows, ",")}
end

function S.BuildSave(profile)
    if S.CanonicalProfile then profile = S.CanonicalProfile(profile) end
    if type(profile) ~= "table" or not ValidResources(profile) then return nil, "invalid_profile" end
    local stats = S.EncodeFlatJson(profile.stats)
    if not stats then return nil, "invalid_stats" end
    local revision = C.Integer(profile.revision or 0, 0, 4294967294)
    if not revision then return nil, "revision_exhausted" end
    local resources = {tostring(profile.curHealth), tostring(profile.maxHealth), tostring(profile.curEnergy),
        tostring(profile.maxEnergy), tostring(profile.armor), tostring(profile.speed),
        Quote(profile.weaponDice,16), Quote(profile.blockDice,16), Quote(stats,MAX_JSON_BYTES),
        Quote(profile.effectsJson or "{}",65535), tostring(revision+1)}
    local cols = {"cur_health","max_health","cur_energy","max_energy","armor","speed",
        "weapon_dice","block_dice","stats_json","effects_json","revision"}
    local values, columns, pool, tableName
    if profile.isPlayer then
        local id = C.IdString(profile.guid)
        if not id or id == "0" or not C.Archetypes[profile.archetype]
            or not C.Integer(profile.level,1,10) or not C.Integer(profile.xp,0,4294967295)
            or not C.Integer(profile.energySpentRound,0,1000)
            or not C.Integer(profile.curWounds,0,255) or not C.Integer(profile.maxWounds,1,255) then
            return nil, "invalid_player_profile"
        end
        values = {id, Quote(profile.archetype,32), Quote(profile.raceId,32), Quote(profile.racialTrait or "",64),
            Quote(profile.commonTrait or "",64), tostring(profile.level), tostring(profile.xp),
            tostring(profile.energySpentRound), tostring(profile.curWounds), tostring(profile.maxWounds),
            Quote(profile.equipJson or "{}",65535), Quote(profile.deathOutcome or "",32)}
        columns = {"guid","archetype","race_id","racial_trait","common_trait","rp_level","rp_xp",
            "energy_spent_round","cur_wounds","max_wounds","equip_json","death_outcome"}
        pool, tableName = "characters", "character_rps_stats"
    else
        if not C.Integer(profile.entry,1,4294967295) or not roles[profile.roleType]
            or not C.IdString(profile.spawnGuid) then return nil, "invalid_npc_profile" end
        values = {Quote(profile.storageKey,200), C.IdString(profile.spawnGuid), Quote(profile.customName or "",128),
            tostring(profile.entry), Quote(profile.roleType,16), profile.isStaticThreshold and "1" or "0"}
        columns = {"runtime_key","spawn_guid","custom_name","entry","role_type","is_static_threshold"}
        pool, tableName = "world", "rps_creature_runtime_stats"
    end
    -- Explicit counts keep a nil encoded field from truncating ipairs silently.
    for i = 1, #cols do columns[#columns+1] = cols[i]; values[#columns] = resources[i] end
    local sql, err = Upsert(tableName, columns, values)
    return sql, sql and pool or err
end

function S.BuildCreatureProfile(creature)
    local guid = tostring(creature:GetGUID())
    local key = tostring(creature:GetMapId()) .. ":" .. tostring(creature:GetInstanceId()) .. ":" .. guid
    local p = {entry=creature:GetEntry(),spawnGuid=C.IdString(creature:GetDBTableGUIDLow()),
        runtimeKey=key,runtimeGuid=guid,storageKey=RpsRuntimeEpoch() .. ":" .. key,
        name=creature:GetName(),customName=creature:GetName(),roleType="minion",isStaticThreshold=true,
        curHealth=10,maxHealth=10,curEnergy=0,maxEnergy=0,armor=0,speed=10,weaponDice="1d6",blockDice="1d4",
        stats={},effectsJson="{}",isPlayer=false,source="guid",revision=0}
    for _, def in ipairs(C.StatOrder) do
        if def.category=="combat" or def.category=="mastery" then p.stats[def.key]=def.defaultValue end
    end
    return p
end

function S.BuildSpawnOverride(p)
    if not C.IdString(p.spawnGuid) or p.spawnGuid=="0" then return nil,"temporary_spawn" end
    return Upsert("rps_creature_spawn_stats",
        {"spawn_guid","custom_name","entry","role_type","is_static_threshold","cur_health","max_health",
            "cur_energy","max_energy","armor","speed","weapon_dice","block_dice","stats_json","effects_json"},
        {p.spawnGuid,Quote(p.customName or "",128),tostring(p.entry),Quote(p.roleType,16),p.isStaticThreshold and "1" or "0",
            tostring(p.curHealth),tostring(p.maxHealth),tostring(p.curEnergy),tostring(p.maxEnergy),tostring(p.armor),
            tostring(p.speed),Quote(p.weaponDice,16),Quote(p.blockDice,16),Quote(S.EncodeFlatJson(p.stats),MAX_JSON_BYTES),
            Quote(p.effectsJson or "{}",65535)})
end

-- The WORLD runtime holds actor locks until this callback. Publish only the
-- profiles actually committed. Separate pools are not a distributed transaction.
function S.SaveProfiles(profiles, callback, commit, extras)
    commit = commit or RpsCommitAsync
    if type(commit) ~= "function" then callback(false, "commit_binding_unavailable", {}); return end
    local groups = {characters={}, world={}}
    local drafts = {characters={}, world={}}
    for _, profile in ipairs(profiles) do
        local p = S.CanonicalProfile and S.CanonicalProfile(profile) or profile
        local sql, pool = S.BuildSave(p)
        if not sql then callback(false,pool,{}); return end
        groups[pool][#groups[pool]+1], drafts[pool][#drafts[pool]+1] = sql, p
        if not p.isPlayer and p.persistOverride and p.spawnGuid~="0" then
            local override, err = S.BuildSpawnOverride(p)
            if not override then callback(false,err,{}); return end
            groups.world[#groups.world+1] = override
        end
    end
    for pool, statements in pairs(extras or {}) do
        if not groups[pool] then callback(false,"invalid_pool",{}); return end
        for _, sql in ipairs(statements) do groups[pool][#groups[pool]+1]=sql end
    end
    local committed, pools = {}, {"characters","world"}
    local function Next(index)
        local pool = pools[index]
        if not pool then callback(true,nil,committed); return end
        if #groups[pool] == 0 then Next(index+1); return end
        local entered=false
        local called, failure=pcall(commit,pool,groups[pool],function(ok)
            entered=true
            if not ok then callback(false,#committed>0 and "partial_commit" or "save_failed",committed); return end
            for _, p in ipairs(drafts[pool]) do
                p.revision = (p.revision or 0)+1
                if p.isPlayer then S.PlayerProfiles[p.guid] = p else S.RuntimeNpcs[p.runtimeKey] = p end
                if p.persistOverride and p.spawnGuid~="0" then
                    p.persistOverride=nil
                    local baseline=Copy(p)
                    baseline.runtimeKey,baseline.runtimeGuid,baseline.storageKey=nil,nil,nil
                    baseline.revision=0
                    S.NpcSpawnCache[p.spawnGuid]=baseline
                end
                committed[#committed+1] = p
            end
            Next(index+1)
        end)
        if not called then
            if entered then error(failure) end
            callback(false,#committed>0 and "partial_commit" or "commit_binding_error",committed)
        end
    end
    Next(1)
end

return S
