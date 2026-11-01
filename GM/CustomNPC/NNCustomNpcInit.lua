--[[ GM/CustomNPC/NNCustomNpcInit.lua — серверный AIO для custom NPC ]]

if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_GM_CUSTOMNPC_BOOTSTRAPPED then
    return package.loaded["GM.CustomNPC.NNCustomNpcInit"] or {}
end
_G.NN_GM_CUSTOMNPC_BOOTSTRAPPED = true

local HANDLER_NAME = "CustomNpcHandlers"
local AIO = NobleNext.AIO
local Handlers = AIO.AddHandlers(HANDLER_NAME, {})

local DEFAULT_LIST_LIMIT = 50

local function RequireStaff(player)
    return NobleNext.HasStaffPermission(player)
end

local function Trim(value)
    return type(value) == "string" and NobleNext.Trim(value) or ""
end

local function NpcKey(value)
    value = Trim(value)
    if value ~= "" and value:lower() ~= "all" and not value:find("[%s%c|]") then return value end
end

local function PageNumber(value, fallback, maximum)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.min(maximum, math.max(0, math.floor(value)))
end

local function ReadNpcList(player, includeAll, offset, limit)
    if type(player.GetCustomNpcList) ~= "function" then return nil end
    local ok, rows = pcall(player.GetCustomNpcList, player, includeAll, offset, limit)
    if ok and type(rows) == "table" then return rows end
    NobleNext.LogError("CustomNPC", "GetCustomNpcList failed: " .. tostring(rows))
end

local function OriginalId(value, maximum)
    value = tonumber(value)
    if value and value == math.floor(value) and value >= 1 and value <= (maximum or 4294967295) then
        return math.floor(value)
    end
end

local function RequestId(value)
    if type(value) == "string" and #value <= 80 then return value end
    if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then return value end
end

local function RunService(player, command)
    if not RequireStaff(player) then
        return false, "Недостаточно прав."
    end

    local ok, result = pcall(player.RunCommand, player, command)

    if not ok then
        NobleNext.LogError("CustomNPC", "RunCommand failed: " .. tostring(result) .. " cmd=" .. command)
        return false, "Команда не выполнена."
    end
    if result == false then return false, "Сервер отклонил действие. Подробности показаны в чате." end

    NobleNext.LogAudit("CustomNPC", "run", player, command)
    return true, nil, result == true
end

local function EditorRequest(player, key, variation, requestId, operation)
    key, variation, requestId = Trim(key), OriginalId(variation or 1, 255), RequestId(requestId)
    local function Reply(ok, message, detail)
        AIO.Handle(player, HANDLER_NAME, "EditorResult", {key = key, variation = variation,
            requestId = requestId, operation = operation, ok = ok, message = message, detail = detail})
    end
    if not RequireStaff(player) then Reply(false, "Недостаточно прав.");return end
    if key == "" or key:lower() == "all" or key:find("[%s%c|]") or not variation or requestId == nil then
        Reply(false, "Выберите NPC и существующий образ.");return
    end
    if type(player.GetCustomNpcDetail) ~= "function" then Reply(false, "Обновите сервер для работы редактора.");return end
    local ok, detail = pcall(player.GetCustomNpcDetail, player, key, variation)
    if not ok or type(detail) ~= "table" or detail.canEdit ~= true then
        Reply(false, "Образ недоступен или нет права изменять этого NPC.");return
    end
    if detail.supportsCommandResult ~= true then
        Reply(false, "Обновите сервер для подтверждаемого изменения образов. Действие не отправлено.");return
    end
    return key, variation, detail, Reply
end

local function FinishEditorCommand(player, key, variation, command, reply, message)
    local ok, err, confirmed = RunService(player, command)
    if not ok then reply(false, err);return end
    if not confirmed then
        reply(false, "Команда передана без подтверждения результата. Обновите сервер и перечитайте образ; действие не повторяется.")
        return
    end
    local readOk, detail = pcall(player.GetCustomNpcDetail, player, key, variation)
    reply(true, message, readOk and type(detail) == "table" and detail or nil)
end

local ARMOR_SLOTS = {head = true, shoulders = true, body = true, chest = true, waist = true,
    legs = true, feet = true, wrists = true, hands = true, tabard = true, back = true, all = true}
local WEAPON_SLOTS = {right = true, left = true, ranged = true}

function Handlers.SetEquipment(player, key, variation, requestId, operation, slot, item)
    local detail, reply
    key, variation, detail, reply = EditorRequest(player, key, variation, requestId, operation)
    if not key then return end
    if (operation ~= "equip" and operation ~= "unequip") or (not ARMOR_SLOTS[slot] and not WEAPON_SLOTS[slot]) then
        reply(false, "Выберите действие и слот снаряжения.");return
    end
    if ARMOR_SLOTS[slot] and detail.isOutfit ~= true then
        reply(false, "У готовой модели нельзя менять одежду. Создайте настраиваемый образ из персонажа.");return
    end
    if operation == "equip" then
        item = item == "self" and "self" or OriginalId(item)
        if not item or (slot == "all" and item ~= "self") then
            reply(false, "Укажите Item ID или выберите источник «С себя». Для всех слотов нужен источник «С себя».");return
        end
    elseif slot == "all" then
        reply(false, "Для снятия выберите конкретный слот.");return
    end
    local command = "cnpc " .. operation .. " " .. (ARMOR_SLOTS[slot] and ("armor " .. key .. " " .. slot) or (slot .. " " .. key))
    if operation == "equip" then command = command .. " " .. tostring(item) end
    FinishEditorCommand(player, key, variation, command .. " " .. variation, reply, "Снаряжение образа обновлено на сервере.")
end

function Handlers.SetAppearance(player, key, variation, requestId, operation, value)
    local detail, reply
    key, variation, detail, reply = EditorRequest(player, key, variation, requestId, operation)
    if not key then return end
    local command
    if operation == "name" or operation == "subname" then
        value = Trim(value)
        if value == "" or value:find("[%c|]") then reply(false, "Укажите текст без служебных символов.");return end
        command = "cnpc set " .. operation .. " " .. key .. " " .. value
    elseif operation == "displayid" then
        value = OriginalId(value)
        if not value then reply(false, "Укажите положительный целый Display ID.");return end
        command = "cnpc set displayid " .. key .. " " .. value .. " " .. variation
    elseif operation == "scale" then
        value = tonumber(value)
        if not value or value ~= value or value <= 0 or value > 3.402823466e38 then
            reply(false, "Масштаб должен быть положительным конечным числом.");return
        end
        command = "cnpc set scale " .. key .. " " .. tostring(value) .. " " .. variation
    elseif operation == "race" or operation == "gender" or operation == "face_self" or operation == "guild_self" then
        if detail.isOutfit ~= true then
            reply(false, "У готовой модели нет параметров персонажа. Добавьте настраиваемый образ.");return
        end
        if operation == "race" then
            value = OriginalId(value)
            if not value then reply(false, "Выберите доступную расу.");return end
            command = "cnpc set race " .. key .. " " .. value .. " " .. variation
        elseif operation == "gender" then
            value = tonumber(value)
            if value ~= 0 and value ~= 1 then reply(false, "Выберите мужской или женский пол.");return end
            command = "cnpc set gender " .. key .. " " .. math.floor(value) .. " " .. variation
        else
            command = (operation == "face_self" and "cnpc set face self " or "cnpc set guild ") .. key .. " " .. variation
        end
    else
        reply(false, "Выберите параметр внешности.");return
    end
    FinishEditorCommand(player, key, variation, command, reply, "Параметры NPC обновлены на сервере.")
end

function Handlers.WorldAction(player, key, variation, requestId, action)
    local detail, reply
    key, variation, detail, reply = EditorRequest(player, key, variation, requestId, action)
    if not key then return end
    local commands = {refresh = "cnpc refresh " .. key .. " " .. variation,
        refresh_all = "cnpc refresh " .. key, reload = "cnpc reload " .. key,
        spawn = "cnpc spawn " .. key, temp = "cnpc spawn temp " .. key, delete = "cnpc delete " .. key,
        apply = "cnpc apply " .. variation .. " " .. key}
    local messages = {refresh = "Образ обновлён у использующих его NPC в мире.",
        refresh_all = "Все образы этого NPC обновлены в мире.", reload = "NPC перечитан из базы и обновлён в мире.",
        spawn = "Постоянный NPC создан.", temp = "Временный NPC создан.", delete = "NPC удалён из памяти сервера.",
        apply = "Образ применён к выделенному в мире NPC."}
    if not commands[action] then reply(false, "Выберите действие в мире.");return end
    FinishEditorCommand(player, key, variation, commands[action], reply, messages[action])
end

local function QuoteDisplayName(name)
    -- ChatCommand Tail accepts the rest of the line; keep as single trailing arg.
    return Trim(name)
end

function Handlers.GetNpcList(player, includeAll, offset, limit)
    if not RequireStaff(player) then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Недостаточно прав.")
        return
    end
    local canIncludeAll = player:GetGMRank() >= 3
    includeAll = includeAll == true and canIncludeAll
    offset = PageNumber(offset, 0, 4294967295)
    limit = PageNumber(limit, DEFAULT_LIST_LIMIT, 200)
    if limit < 1 then limit = DEFAULT_LIST_LIMIT end

    local rows = ReadNpcList(player, includeAll, offset, limit)
    if not rows then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Список NPC недоступен (нужен обновлённый core).")
        return
    end
    local nextRows = #rows == limit and offset <= 4294967295 - limit
        and ReadNpcList(player, includeAll, offset + limit, 1) or {}

    AIO.Handle(player, HANDLER_NAME, "NpcList", rows, {
        includeAll = includeAll,
        offset = offset,
        limit = limit,
        hasMore = nextRows and #nextRows > 0 or false,
        canIncludeAll = canIncludeAll,
    })
end

function Handlers.GetCatalog(player, availableOnly)
    if not RequireStaff(player) then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Недостаточно прав.")
        return
    end
    if availableOnly == nil then availableOnly = true end

    local races = {}
    if type(player.GetCustomNpcRaceCatalog) == "function" then
        local ok, result = pcall(player.GetCustomNpcRaceCatalog, player, availableOnly and true or false)
        if ok and type(result) == "table" then
            races = result
        else
            NobleNext.LogError("CustomNPC", "GetCustomNpcRaceCatalog failed: " .. tostring(result))
            AIO.Handle(player, HANDLER_NAME, "Status", false, "Каталог рас недоступен (нужен обновлённый core).")
            return
        end
    else
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Каталог рас недоступен (нужен обновлённый core).")
        return
    end

    AIO.Handle(player, HANDLER_NAME, "Catalog", {
        rev = 1,
        races = races,
    })
end

--- Look hydrate: race/gender/subname/display/scale for one key + variation.
function Handlers.GetNpcDetail(player, key, variation, requestId, modelRequestId)
    if not RequireStaff(player) then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Недостаточно прав.")
        return
    end
    key, variation = NpcKey(key), OriginalId(variation or 1, 255)
    if not key or not variation then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Укажите ключ NPC и существующий образ.")
        return
    end

    if type(player.GetCustomNpcDetail) ~= "function" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Detail NPC недоступен (нужен обновлённый core).")
        return
    end

    local ok, detailOrErr, err = pcall(player.GetCustomNpcDetail, player, key, variation)
    if not ok then
        NobleNext.LogError("CustomNpc", "GetCustomNpcDetail pcall: " .. tostring(detailOrErr))
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Не удалось загрузить детали NPC.")
        return
    end
    if type(detailOrErr) ~= "table" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, tostring(err or detailOrErr or "not found"))
        return
    end

    detailOrErr.requestId = RequestId(requestId)
    detailOrErr.modelRequestId = RequestId(modelRequestId)
    AIO.Handle(player, HANDLER_NAME, "NpcDetail", detailOrErr)
end

-- Legacy chat dump (kept for /debug); UI uses GetNpcList.
function Handlers.List(player)
    if not RequireStaff(player) then return end
    local ok, err, confirmed = RunService(player, "cnpc list")
    AIO.Handle(player, HANDLER_NAME, "Status", ok and confirmed,
        ok and confirmed and "Список NPC выведен в чат." or err or "Сервер не подтвердил вывод списка.")
end

function Handlers.Reload(player, key)
    if not RequireStaff(player) then return end
    key = Trim(key or "")
    if key == "" or key:lower() == "all" or key:find("[%s%c|]") then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Укажите ключ NPC (не all без подтверждения в UI).")
        return
    end
    local readOk, detail = pcall(player.GetCustomNpcDetail, player, key, 1)
    if not readOk or type(detail) ~= "table" or detail.canEdit ~= true then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Нет права обновлять этого NPC.");return
    end
    if detail.supportsCommandResult ~= true then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Обновите сервер. Команда обновления NPC не отправлена.");return
    end
    local ok, err, confirmed = RunService(player, "cnpc reload " .. key)
    AIO.Handle(player, HANDLER_NAME, "Status", ok and confirmed,
        not ok and err or (confirmed and "NPC перечитан на сервере (reload)." or "Команда передана без подтверждения результата. Обновите сервер."))
end

local function ReadOwnedRegistry(player)
    local registry, offset = {}, 0
    repeat
        local rows = ReadNpcList(player, false, offset, 200)
        if not rows then return nil end
        for _, row in ipairs(rows) do registry[row.key] = row end
        if #rows < 200 then return registry end
        offset = offset + #rows
    until false
end

local function CreateNpc(player, command, displayName, subName)
    local function Fail(message)
        AIO.Handle(player, HANDLER_NAME, "NpcCreateFailed", {message = message})
        AIO.Handle(player, HANDLER_NAME, "Status", false, message)
    end
    if not RequireStaff(player) then
        Fail("Недостаточно прав.")
        return
    end
    displayName, subName = QuoteDisplayName(displayName), Trim(subName)
    if displayName == "" or displayName:find("[%c|]") or subName:find("[%c|]") then
        Fail("Укажите имя и подпись без служебных символов.")
        return
    end
    local before = ReadOwnedRegistry(player)
    if not before then
        Fail("Не удалось загрузить ваши NPC. Создание отменено.")
        return
    end
    if not RunService(player, command .. " " .. displayName) then
        Fail("Команда создания не выполнена.")
        return
    end
    local after = ReadOwnedRegistry(player)
    if not after then
        Fail("Не удалось проверить создание. Обновите список NPC перед повтором.")
        return
    end
    local created
    for key, row in pairs(after) do
        if not before[key] then
            if created then
                Fail("Список NPC изменился. Обновите его и выберите созданного NPC.")
                return
            end
            created = row
        end
    end
    if not created then
        Fail("Новый NPC не появился в списке. Проверьте ответ сервера в чате.")
        return
    end
    -- Names are not unique; only the newly observed native key identifies the creation.
    local subtitleOk = true
    if subName ~= "" then subtitleOk = RunService(player, "cnpc set subname " .. created.key .. " " .. subName) end
    created.variation = 1
    AIO.Handle(player, HANDLER_NAME, "NpcCreated", created)
    Handlers.GetModelList(player, created.key)
    Handlers.GetNpcDetail(player, created.key, 1)
    AIO.Handle(player, HANDLER_NAME, "Status", subtitleOk,
        subtitleOk and ("NPC появился в списке сервера: " .. displayName .. ".")
        or "NPC создан, но подпись не применена. Повторите только изменение подписи во вкладке «Внешность».")
end

function Handlers.CreateBlank(player, displayName, subName)
    CreateNpc(player, "cnpc add", displayName, subName)
end

function Handlers.CloneSelf(player, displayName, subName)
    -- Explicit source keeps names like "target guard" from selecting a clone subcommand.
    CreateNpc(player, "cnpc clone player " .. player:GetName(), displayName, subName)
end

function Handlers.CloneTarget(player, displayName, subName)
    CreateNpc(player, "cnpc clone target", displayName, subName)
end

function Handlers.ApplySelected(player, variation)
    if not RequireStaff(player) then return end
    -- The old request has no key: it cannot identify which NPC the user intended to edit.
    AIO.Handle(player, HANDLER_NAME, "Status", false, "Обновите аддон и примените образ из раздела «В мире» выбранного NPC.")
end

function Handlers.GetFaceOptions(player, key, variation, requestId)
    if not RequireStaff(player) then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Недостаточно прав.")
        return
    end
    key, variation = NpcKey(key), OriginalId(variation or 1, 255)
    if not key or not variation then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Укажите ключ NPC.")
        return
    end

    if type(player.GetCustomNpcFaceOptions) ~= "function" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Face options недоступны (нужен обновлённый core).")
        return
    end

    local ok, payloadOrErr, err = pcall(player.GetCustomNpcFaceOptions, player, key, variation)
    if not ok then
        NobleNext.LogError("CustomNpc", "GetCustomNpcFaceOptions pcall: " .. tostring(payloadOrErr))
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Не удалось загрузить опции лица.")
        return
    end
    if type(payloadOrErr) ~= "table" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, tostring(err or payloadOrErr or "not found"))
        return
    end

    payloadOrErr.requestId = RequestId(requestId)
    payloadOrErr.supportsChoiceIds = payloadOrErr.supportsChoiceIds == true
        and type(player.GetCustomNpcFaceChoicesById) == "function"
    AIO.Handle(player, HANDLER_NAME, "FaceOptions", payloadOrErr)
end

function Handlers.GetFaceChoices(player, key, optionIndex, variation)
    if not RequireStaff(player) then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Недостаточно прав.")
        return
    end
    key, optionIndex, variation = NpcKey(key), OriginalId(optionIndex), OriginalId(variation or 1, 255)
    if not key or not optionIndex or not variation then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Нужны key и optionIndex.")
        return
    end

    if type(player.GetCustomNpcFaceChoices) ~= "function" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Face choices недоступны (нужен обновлённый core).")
        return
    end

    local ok, payloadOrErr, err = pcall(player.GetCustomNpcFaceChoices, player, key, math.floor(optionIndex), variation)
    if not ok then
        NobleNext.LogError("CustomNpc", "GetCustomNpcFaceChoices pcall: " .. tostring(payloadOrErr))
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Не удалось загрузить варианты лица.")
        return
    end
    if type(payloadOrErr) ~= "table" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, tostring(err or payloadOrErr or "not found"))
        return
    end

    AIO.Handle(player, HANDLER_NAME, "FaceChoices", payloadOrErr)
end

function Handlers.GetFaceChoicesById(player, key, optionId, variation, offset, limit, requestId)
    key, optionId, variation = Trim(key), OriginalId(optionId), OriginalId(variation or 1, 255)
    requestId = RequestId(requestId)
    local function Fail(message)
        AIO.Handle(player, HANDLER_NAME, "FaceChoices", {key = key, variation = variation, optionId = optionId,
            requestId = requestId, offset = offset, choices = {}, error = message, supportsChoiceIds = true})
    end
    if not RequireStaff(player) then return Fail("Недостаточно прав.") end
    if not NpcKey(key) or not optionId or not variation then return Fail("Укажите NPC, образ и исходный ID параметра.") end
    if type(player.GetCustomNpcFaceChoicesById) ~= "function" then
        return Fail("Сервер не поддерживает исходные ID вариантов внешности.")
    end
    offset, limit = PageNumber(offset, 0, 4294967295), math.max(1, PageNumber(limit, 100, 200))
    local ok, payload = pcall(player.GetCustomNpcFaceChoicesById, player, key, optionId, variation, offset, limit)
    if not ok or type(payload) ~= "table" then return Fail("Параметр недоступен для текущего образа. Обновите внешность.") end
    payload.requestId = requestId
    AIO.Handle(player, HANDLER_NAME, "FaceChoices", payload)
end

function Handlers.SetFaceById(player, key, optionId, choiceId, variation, requestId)
    key = Trim(key)
    optionId, choiceId, variation = OriginalId(optionId), OriginalId(choiceId), OriginalId(variation or 1, 255)
    requestId = RequestId(requestId)
    local function Fail(message)
        AIO.Handle(player, HANDLER_NAME, "FaceChangeFailed", {key = key, variation = variation,
            optionId = optionId, requestId = requestId, message = message})
    end
    if not RequireStaff(player) then return Fail("Недостаточно прав.") end
    if not NpcKey(key) or not optionId or not choiceId or not variation then
        return Fail("Выберите NPC, образ и исходные ID параметра и варианта.")
    end
    if type(player.GetCustomNpcDetail) ~= "function" or type(player.GetCustomNpcFaceOptions) ~= "function"
        or type(player.GetCustomNpcFaceChoicesById) ~= "function" then
        return Fail("Сервер не поддерживает редактирование по исходным ID.")
    end
    local function ReadDetail()
        local ok, detail = pcall(player.GetCustomNpcDetail, player, key, variation)
        return ok and type(detail) == "table" and detail or nil
    end
    local function HasChoice(detail)
        for _, choice in ipairs(detail and detail.customizations or {}) do
            if tonumber(choice.optionId) == optionId and tonumber(choice.choiceId) == choiceId then return true end
        end
        return false
    end
    local detail = ReadDetail()
    if not detail or detail.canEdit ~= true or detail.isOutfit ~= true then
        return Fail("Образ недоступен для настройки внешности.")
    end
    if not HasChoice(detail) then
        if not RunService(player, string.format("cnpc set face rawoption %s %d %d %d", key, optionId, choiceId, variation)) then
            return Fail("Команда изменения внешности не выполнена.")
        end
        detail = ReadDetail()
    end
    if not HasChoice(detail) then
        return Fail("Вариант не применён. Он может быть недоступен для текущей расы, пола, класса или других параметров. Обновите список.")
    end
    local optionsOk, options = pcall(player.GetCustomNpcFaceOptions, player, key, variation)
    if not optionsOk or type(options) ~= "table" then
        return Fail("Не удалось перечитать внешность после команды. Обновите образ перед следующей правкой.")
    end
    options.supportsChoiceIds, options.requestId = true, requestId
    AIO.Handle(player, HANDLER_NAME, "FaceChanged", {key = key, variation = variation,
        optionId = optionId, choiceId = choiceId, requestId = requestId, detail = detail, options = options})
end

function Handlers.GetModelList(player, key)
    if not RequireStaff(player) then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Недостаточно прав.")
        return
    end
    key = NpcKey(key)
    if not key then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Укажите ключ NPC.")
        return
    end

    if type(player.GetCustomNpcModelList) ~= "function" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Model list недоступен (нужен обновлённый core).")
        return
    end

    local ok, payloadOrErr, err = pcall(player.GetCustomNpcModelList, player, key)
    if not ok then
        NobleNext.LogError("CustomNpc", "GetCustomNpcModelList pcall: " .. tostring(payloadOrErr))
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Не удалось загрузить список видов.")
        return
    end
    if type(payloadOrErr) ~= "table" then
        AIO.Handle(player, HANDLER_NAME, "Status", false, tostring(err or payloadOrErr or "not found"))
        return
    end

    AIO.Handle(player, HANDLER_NAME, "ModelList", payloadOrErr)
end

local function ChangeModel(player, key, source, sourceVariation, requestId)
    key = Trim(key)
    requestId = RequestId(requestId)
    local function Fail(message)
        AIO.Handle(player, HANDLER_NAME, "ModelChangeFailed", {key = key, operation = source, requestId = requestId, message = message})
        AIO.Handle(player, HANDLER_NAME, "Status", false, message)
    end
    if not RequireStaff(player) then return Fail("Недостаточно прав.") end
    if not NpcKey(key) then return Fail("Выберите NPC из списка.") end
    if source ~= "copy" and source ~= "blank" and source ~= "self" and source ~= "target" and source ~= "remove" then
        return Fail("Выберите источник нового образа.")
    end
    local variation = tonumber(sourceVariation)
    local needsVariation = source == "copy" or source == "blank" or source == "remove"
    if needsVariation and
        (not variation or variation ~= math.floor(variation) or variation < 1 or variation > 255) then
        return Fail("Выберите существующий образ.")
    end
    if source == "remove" and variation < 2 then return Fail("Первый образ удалить нельзя.") end
    if type(player.GetCustomNpcDetail) ~= "function" or type(player.GetCustomNpcModelList) ~= "function" then
        return Fail("Редактирование образов недоступно: обновите серверный модуль.")
    end
    local ok, detail = pcall(player.GetCustomNpcDetail, player, key,
        needsVariation and variation or 1)
    if not ok or type(detail) ~= "table" or detail.canEdit ~= true then
        return Fail("NPC или образ недоступен для редактирования.")
    end
    local listOk, before = pcall(player.GetCustomNpcModelList, player, key)
    if not listOk or type(before) ~= "table" or type(before.models) ~= "table" then
        return Fail("Не удалось загрузить список образов.")
    end
    if source ~= "remove" and #before.models >= 255 then return Fail("У NPC уже 255 образов. Новый образ добавить нельзя.") end

    local command = source == "remove" and string.format("cnpc model remove %s %d", key, variation)
        or source == "copy" and string.format("cnpc model copy %s %d", key, variation)
        or ("cnpc model add " .. source .. " " .. key .. (source == "blank" and string.format(" %d", variation) or ""))
    if not RunService(player, command) then return Fail("Команда изменения образа не выполнена.") end
    local afterOk, after = pcall(player.GetCustomNpcModelList, player, key)
    -- A command result does not identify the new model; reconcile the native list as well.
    if not afterOk or type(after) ~= "table" or type(after.models) ~= "table"
        or #after.models ~= #before.models + (source == "remove" and -1 or 1) then
        return Fail("Изменение списка образов не подтверждено. Проверьте список и ответ сервера в чате перед повтором.")
    end
    local selected = source == "remove" and after.models[math.min(variation, #after.models)] or after.models[#after.models]
    AIO.Handle(player, HANDLER_NAME, "ModelChanged", {
        key = key,
        requestId = requestId,
        variation = selected.variation,
        models = after.models,
        operation = source == "remove" and "remove" or source == "copy" and "copy" or "add",
    })
    AIO.Handle(player, HANDLER_NAME, "Status", true,
        source == "remove" and "Образ удалён из списка сервера. Нумерация оставшихся образов обновлена."
        or "Образ " .. tostring(selected.variation) .. " появился в списке сервера. Загружаются его настройки.")
    -- Hydration reports whether the model actually supports face/armor editing.
    Handlers.GetNpcDetail(player, key, selected.variation, nil, requestId)
end

function Handlers.AddModel(player, key, source, sourceVariation, requestId)
    ChangeModel(player, key, source, sourceVariation, requestId)
end

function Handlers.CopyModel(player, key, variation, requestId)
    ChangeModel(player, key, "copy", variation, requestId)
end

function Handlers.RemoveModel(player, key, variation, requestId)
    ChangeModel(player, key, "remove", variation, requestId)
end

--- Thin wrapper: same path as chat `.cnpc set face <key> <optionIndex> <choiceIndex> [variation]`.
function Handlers.SetFace(player, key, optionIndex, choiceIndex, variation)
    if not RequireStaff(player) then return end
    key, optionIndex, choiceIndex, variation = NpcKey(key), OriginalId(optionIndex), OriginalId(choiceIndex), OriginalId(variation or 1, 255)
    if not key or not optionIndex or not choiceIndex or not variation then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Нужны key, optionIndex, choiceIndex.")
        return
    end
    if type(player.GetCustomNpcDetail) ~= "function" then return end
    local readable, detail = pcall(player.GetCustomNpcDetail, player, key, variation)
    if not readable or type(detail) ~= "table" or detail.canEdit ~= true or detail.isOutfit ~= true then
        AIO.Handle(player, HANDLER_NAME, "Status", false, "Образ недоступен для настройки внешности.");return
    end
    local cmd = string.format(
        "cnpc set face %s %d %d",
        key,
        math.floor(optionIndex),
        math.floor(choiceIndex)
    )
    cmd = cmd .. " " .. variation
    local ok, _, confirmed = RunService(player, cmd)
    AIO.Handle(player, HANDLER_NAME, "Status", ok and confirmed,
        ok and confirmed and ("Face обновлён: " .. key) or "Изменение внешности не подтверждено. Обновите образ.")
end

NobleNext.RegisterModule("CustomNPC", { role = "staff-tools", layer = "GM" })
NobleNext.Log("CustomNPC", "server handlers loaded")

return Handlers
