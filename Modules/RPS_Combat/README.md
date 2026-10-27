# Серверный модуль RPS Combat

Профили, броски 3d6 и реакции. Четыре архетипа, уровни 1–10: ресурсы и боевые бонусы заданы в `00_RPS_Config.lua`.

| Файл | Реализованное поведение |
|---|---|
| `00_RPS_Config.lua` | Архетипы, проверка реестра и его атомарная замена, точные строковые ID, парсер костей, 3d6, дубли и усталость |
| `01_RPS_Storage.lua` | Чтение и подтверждённая запись профилей, GUID → template → nil, runtime-кэши, сохранение исходного JSON effects/equip |
| `02_RPS_Combat.lua` | Расчёт на копиях профилей: цена Судьбы/Блока, лимит раунда, бросок, защита, поглощение, Раны и таблица смерти |
| `Init.lua` | WORLD bootstrap, один AIO-канал, блокировки участников, журнал запросов, очередь реакций и команды |
| `Map.lua` | MAP hook для зарегистрированных спеллов, ограниченная передача GUID в WORLD |

Config, Storage и Combat возвращают таблицы через `require` без регистрации событий. `00_NobleNext.lua` подключает `Init` в WORLD и отдельный `Map` в MAP, включая карту 0. Runtime опубликован как `NobleNext.RPS`. Если схема или native bindings недоступны, WORLD отвечает `system_unavailable` и не выполняет игровые мутации.

Отсутствующий результат native Query не позволяет отличить отсутствие профиля от ошибки БД. Создание нового профиля требует отдельного успешного COUNT с нулевым результатом; его первая синхронизация следует только за успешным commit. Существующий недоступный профиль не заменяется полностью восстановленным бойцом.

`Combat` возвращает новый профиль и результат расчёта, сохраняя исходный профиль неизменным. WORLD проверяет данные, цель и ревизию, блокирует затронутых участников и вызывает `RpsCommitAsync`. Этот binding использует `AsyncCommitTransaction`; callbacks обрабатываются существующим циклом Eluna. Reload ожидает завершения query/transaction callbacks. В callback заново разрешается Player по полному GUID, а клиент получает `Committed` только после подтверждения записи.

Для одного пула состояние и `rps_action_receipts` записываются одной транзакцией. Повтор request ID с прежним содержимым возвращает сохранённый результат; другое содержимое даёт `request_conflict`. Точная ревизия проверяется в одном WORLD writer под блокировкой участника; это не CAS для внешних процессов, одновременно редактирующих эти таблицы.

Срок хранения receipts и очистка завершённых исторических записей задаются эксплуатационной политикой; автоматическая уборка SQL-журнала пока не включена.

Действие игрока против NPC затрагивает два пула. Сначала фиксируется characters, затем world, после чего подтверждается receipt. Общей транзакции между пулами нет: частичный сбой возвращает `partial_commit`, а незавершённый durable receipt после reload даёт `pending_recovery`. Такие запросы не бросаются повторно и требуют сверки состояния оператором. Автоматическая компенсация и доставка outbox не реализованы.

Урон при уже нулевых ОЗ повторно не добавляет Рану. `deathOutcome` сохраняется в профиле; native смерть Unit от этого автоматически не вызывается. Бюджет сбрасывается разрешённым ведущим через «Новый раунд цели», отдельно для выбранного игрока. Открытие окна, login и отдельный бросок его не сбрасывают. Автоматическая инициатива и общий координатор раундов ещё не реализованы.

`LoadNpcCaches` заменяет baseline-кэши только после успешного чтения обеих таблиц; живые экземпляры при этом сохраняются. `rps_creature_runtime_stats` хранит состояние с ключом process epoch + карта + instance + полный runtime GUID, включая временные NPC со spawn ID 0. Lua reload восстанавливает их ОЗ/ОЭ. Новый процесс использует новый epoch и baseline: перенос текущего состояния NPC между разными материализациями и очистка старых runtime-строк требуют отдельной политики. Кэш ограничен 4096 экземплярами; автоматическая очистка по despawn пока не подключена.

Ожидающие PvP-атаки сохраняются в `characters.rps_pending_attacks` вместе с действием атакующего. На одну цель допускается до восьми реакций. Ответ и timeout конкурируют за одну запись; удаление pending и изменение защитника попадают в одну транзакцию. Offline-защитник обрабатывается после возвращения. Если атакующий недоступен либо общий контекст потерян, реакция отменяется с подтверждённым удалением pending.

SQL подготовлен отдельно для `world` и `characters` в `RPS.WoWCore/sql/custom/`. В каждом пуле есть runtime NPC, pending attacks и receipts. Seed содержит 14 строк характеристик, сохраняет операторские изменения при повторном запуске и не импортирует примерных NPC. Колонка `rps_creature_spawn_stats.entry` защищает от применения override к изменившемуся шаблону. Это новая схема; `CREATE TABLE IF NOT EXISTS` не обновит таблицы, уже созданные вручную по более раннему примеру.

## Клиент и права

`NobleNext/Core/RPSClient.lua` владеет единственной клиентской таблицей AIO handlers. Это отдельный public player route; staff-обёртка `ns.AIOHandle` не используется для своего листа. CharacterFrame сохраняет native layout и соседние обработчики, а RP-данные заменяют её правый список после первого корректного серверного snapshot. Строки и категории переиспользуются. Shift + перенос требует отсутствия combat lockdown и действительного spell ID.

`CombatPrompt` хранит очередь, ждёт серверного подтверждения и не закрывает атаку от одного клика. Полный snapshot списка pending устраняет потерянные уведомления закрытия. Панель NobleNextDM «Бой 3d6» сохраняет GUID и ревизию открытой цели, блокирует повторную отправку до ответа и поддерживает ручное начало раунда цели. Историческая панель «Бой» остаётся отдельным legacy-контуром аур/команд и не является writer новых RP-таблиц.

`RpsTargetContext` переиспользует native `CanShareRoleplayContext` и `CanSeeOrDetect`, проверяет карту, дистанцию 40 ярдов и LOS. Для редактирования нужны GM2 либо роль editor своей logical RP phase; общий GM1 сам по себе этого права не даёт. `.rps reload`, `.rps diag spells`, `.rps race reset` и `.rps setstat <key> <value>` обслуживаются отдельно, не поглощая `.rps character` и `.rps npc`. C++-таблицы `.rps` не содержат подкоманд `diag` и `race`, поэтому Eluna event 42 их получает.

Лимиты: 128 определений и 64 KiB реестра; кэш 64 последних запросов одного игрока с вытеснением завершённых записей и durable lookup для старых ID; интервал мутаций 400 мс; 2048 pending атак; до 64 SQL statements и 256 KiB в native транзакции. JSON effects/equipment сохраняется без преобразования; полноценный интерпретатор эффектов и подбор RP-экипировки в этот срез не входят.

## Спеллы

Кандидат для десяти спеллов — **1500001–1500010**, в порядке accuracy, healing, evasion, resistance, skill, knowledge, endurance, craft, weapon_damage, shield_block. В локальных CSV максимум ID `SpellName/Spell` равен 1327777, `SpellEffect` — 1366434, `SpellMisc` — 873077. Выбранный диапазон превышает каждый из этих максимумов более чем на 100000.

Seed оставляет `spell_id = 0`, пока не подготовлены client/server records. Ненулевой ID проходит серверную проверку наличия и NONE/DUMMY effects через `RpsDiceSpellStatus` (fallback `RpsIsDiceSpell`). MAP отменяет такой каст и кладёт GUID/spell ID в ограниченную очередь. WORLD заново находит игрока, проверяет карту, instance, цель и срок события.

### Выдача и статусы

| Статус | Значение |
|---|---|
| `ok` | Спелл изучен, подтверждено `HasSpell` |
| `unmapped` | `spell_id = 0` в реестре |
| `no_spellinfo` | Ядро не загрузило SpellInfo (hotfix не применён/не загружен) |
| `unsafe` | В спелле есть эффект кроме NONE/DUMMY; `reason = effect:<index>:<type>` |
| `learn_failed` | `HasSpell` ложно после `LearnSpell` и одного повтора |

`R.IssueSpells` вызывается на login (не зависит от успеха `Ensure` профиля), после `.rps reload` для всех онлайн-игроков и в каждом `Refresh`. `learn_failed` кэшируется на игрока и не повторяется при обычном sync; повтор — на следующем login, reload или `.rps diag spells`. Отказ пишется `N.Log`. Статусы уходят в необязательное поле `SyncProfile.spells = {[statKey]={id,status,reason}}`.

Плохой ID не отключает весь реестр: `LoadStatDefinitions` собирает все отказы (`C.DiagnoseSpells`), обнуляет mapping только у них (сохраняя `configuredSpellId` и `spellUnavailable`) и публикует остальное. `R.ready` остаётся `true`, причина — в `R.degradedReason`. Пустой/нечитаемый реестр по-прежнему даёт `ready=false`.

`.rps diag spells` (staff) печатает в чат `ready`, `reason`, `degraded`, затем по каждому кубу `id`, `check` (живой результат `RpsDiceSpellStatus`), `HasSpell` до и после принудительной выдачи выбранному игроку (без выбора — себе) и итоговый статус; строки `action …` — так же `has=<до> -> has=<после> status=…`; затем отправляет игроку свежий `SyncProfile`.

Отказ `RpsQueueDiceCast` (`queue_full`, `cast_pending`, `caster_mismatch`) не молчит: native cast отменяется, игрок получает notification. `RpsPollDiceCasts` возвращает и отброшенные касты с полем `rejected` (`map_changed`, `target_changed`, `expired`); WORLD сообщает их игроку, как и cast отключённого спелла или без профиля. Одна запись в реестре не создаёт native заклинание и не доказывает наличие записи в клиенте; SQL-пакет создания десяти спеллов подготовлен в `sql/custom/hotfixes/2026_10_26_00_rps_dice_spells.sql`, но пока не применён. Отдельный `world/2026_10_26_01_rps_enable_dice_spells.sql` назначает ID только после проверки на клиенте и сервере.

### Действия и реакции

Кубы 1500001–1500010 — самостоятельные проверки: `R.Roll` больше не атакует выбранную цель. Атака, Избегание и Блок — `C.Actions` с отдельными ID 1500011–1500013 (`rps_action_attack/evade/block`, пакет `sql/custom/hotfixes/2026_10_27_00_rps_action_spells.sql`, на стенде не применён). `C.RefreshActionSpells` проверяет их тем же `RpsDiceSpellStatus`; отказ даёт статус `no_spellinfo`/`unsafe`/`collision` в `SyncProfile.actionSpells` и `.rps diag spells`, не трогая кубы.

| Вход | Обработчик | Результат |
|---|---|---|
| Native-каст action-спелла | `RpsPollDiceCasts` → `R.CastAction` → `R.PerformAction` | Тот же путь, что и кнопка окна |
| Кнопки CombatPrompt | AIO `PerformAction(actionKey, args, requestId)` | `attack` → `R.Attack`; `evade`/`block`/`take` → `R.React` по явному `attackId` |
| Избегание/Блок без `attackId` | `R.IncomingAttacks` (открытые, старшие первыми) | 0 → «Нет входящей атаки»; 1 → разрешение; несколько или атака, пришедшая < 1,5 с после прошлого ответа → `ChooseDefenseAttack` |

Ничья в пользу защиты (`M.AttackHits`). Блок: 2 ОЭ, без броска; `M.BlockAbsorb` = `max(0, 1 + Сопротивление)` без щита, Броня применяется к остатку физического урона в `ApplyDamageToUnit`. `M.ResolveShield` возвращает `nil`, пока щит не хранится; со щитом — кость щита + Сопротивление + качество. Ответ после deadline превращается в TAKE (`outcome.timedOut`). Атакующий получает `AttackResolved`.

## Локальная проверка

Из корня полного workspace:

```powershell
wsl -d Ubuntu-22.04 -- bash -lc 'cd /mnt/f/Projects/RP-S.Projects/RPS-eXtended/RPS.TrinityCore/Addons/tests && python3 -m unittest -v test_rps_combat_foundation test_rps_combat_integration test_rps_combat_client test_rps_combat_actions'
```

Тесты используют существующий Lua harness и `liblua5.3`, проверяют задержанный callback, отказ, блокировки, восстановление receipts/pending, разделение NPC и клиентскую очередь. Каталог `Addons/tests` исключён существующим `.gitignore` и не входит в поставку. Native bindings проверяются BuildOnly. Применение SQL, фактические Eluna hooks и поведение игрового клиента требуют отдельного стенда.

## Диагностика готовности

При отказе загрузки `RPS_Combat` пишет причину в серверный лог и возвращает её
в поле `reason` ошибки `system_unavailable`.
`missing_binding:<name>` указывает на несовпадение native/Lua версии,
`registry_unavailable` — на пустой или нечитаемый реестр.
Неверный spell ID модуль не выключает: лог содержит
`dice_spells_unavailable:accuracy:1500001:no_spellinfo,...`, значит ненулевой mapping
не прошёл проверку загруженного SpellInfo. Проверить наличие записи в hotfixes
и загрузку native stores после запуска; world mapping сам по себе спелл не создаёт.
Подробности по игроку — `.rps diag spells`.

## Каталог и расчёт листа

| Файл | Поведение |
|---|---|
| `03_RPS_Catalog.lua` | Сгенерирован из JSON каталога; вручную не править. Версия `K.CATALOG_VERSION`. Чистые данные и lookups, без `require` и hooks |
| `04_RPS_Resolver.lua` | Чистая функция `V.Resolve(input)` → ResolvedSheet; `V.Validate(input)` — только проверка выбора |

Содержимое каталога: 14 рас, все доступны, в порядке Орк, Тролль, Таурен, «Нежить (Отрекшийся)», Эльф крови, Огр, Гоблин, Пандарен, Человек, Высший эльф, Дворф, Ночной эльф, Дреней, Гном. У 8 рас `preset = 'book'` и по 2 особенности (16); у 6 рас без механик (`bookStatus = 'in_development'`) `preset = 'default'` — одна особенность-заглушка `<race>_default` «Без расовых особенностей (заглушка)» без механик (в листе — пассивная запись) и размер из каталога. Общий шаблон заглушки — `K.DEFAULT_RACE_PRESET`. У каждой расы `presetVersion` (целое, сейчас 1; переопределения — `RACE_PRESET_VERSIONS` генератора), `K.RacePresetVersion(key)` (0 для неизвестной). Отображаемые имена, отличные от исходного экспорта, — `RACE_NAMES` генератора. Также: 43 общие черты (19 доступны), 4 архетипа × 10 уровней, 6 размеров (3 игровых: 12/10/8 шагов), XP 0…500 (RP = серверный − 9), 4 слота персональных способностей (3/5/7/9, с Одарённостью 2/4/6/8), 8 общих способностей + полный блок большого щита, 12 оружия (двуручное обычное d12), 3 щита, 2 доспеха, 3 качества, лестница костей I–VII, 4 Мастерства (`persistence` каталога → `endurance` реестра). `K.Validate()` возвращает список ошибок данных.

Вход: `{archetype, rpLevel | serverLevel, race, racialFeature, trait | traits, traitChoice?, mastery = {skill, knowledge, endurance, craft}, equipment? = {mainHand, offHand, armor = {key, quality}}, extraModifiers? = {{source, op, target, value}}}`. Ответ — лист либо `nil, code, errors`.

| Фаза | Что делает |
|---|---|
| base | Строка архетипа уровня, скорость размера (±2 уже внутри 12/10/8), Броня 0, лимит Ран 3, Сложность исцеления 8, лимит трат 6, распределение Мастерства |
| set → add → cap | Операции рас, черт, размера, экипировки, `extraModifiers`. Разные `set` одного показателя — `conflicting_set`. Фиксирующие черты: `set +2`, затем прибавки, затем `cap +2` |
| derived | `abilitySlots`/`abilitySlotList`, `fateDie`, `block` (без щита `1 + Сопротивление + Броня`, со щитом кость щита + Сопротивление + качество щита; компоненты в полях `base`/`resistance`/`armor`/`quality`), `damageBonus` (Искусство войны), `attacks` (безоружная, Врождённые чары, режимы оружия, ступени костей) |

`trace[stat]` — список `{source, op, value, applied?, perLevel?}`. Условные и событийные механики (дубли, Раны, триггеры атак) не прибавляются к числам: они в `passive` с текстом и неприменёнными операциями; невыполненное статическое условие — в `skipped`. Флаги и прочие статические параметры — в `flags`/`extra`. Ситуативные условия действия и жёсткий Контроль считает отдельный резолвер действий.

Коды ошибок: `invalid_input`, `unknown_archetype`, `invalid_level`, `unknown_race`, `race_unavailable` (сейчас не возникает: все расы доступны), `racial_feature_required`, `unknown_racial_feature`, `racial_feature_not_of_race`, `trait_required`, `unknown_trait`, `trait_unavailable`, `trait_duplicate`, `too_many_traits`, `trait_choice_required`, `invalid_trait_choice`, `invalid_mastery`, `unknown_mastery`, `mastery_points_mismatch` (сумма = 2 + свободное очко Таурена), `invalid_equipment`, `unknown_item`, `invalid_quality`, `slot_mismatch`, `hands_conflict`, `invalid_modifier`, `conflicting_set`.

Открытые вопросы помечены `TODO` в коде и каталоге: ступень кости Блока Мясного щита без щита, опечатки диапазонов оружия (`bookTypos`), механика Телохранителя, момент «ниже 9» у Огра, снижение штрафа скорости Закалкой/Мясным щитом (на сумму или на предмет), ступень безоружной атаки.

Ничья атаки и защиты: попадание только при атака > защиты. Это резолвер атаки, не лист. Особенность Целителя — «Целебные чары».

Каталог пересобирается генератором из JSON (`--check` сверяет файл). Тест: `Addons/tests/test_rps_catalog_resolver.py`. Создание персонажа подключает каталог из `05_RPS_Creation.lua`.

## Создание персонажа и стартовый набор

`05_RPS_Creation.lua` — серверная часть создания. Без hooks на `require`; `Init.lua` одной строкой вызывает `Register(R, H, Ensure)` и добавляет `SyncProfile.creation`. Каталог `03` и резолвер `04` подключаются отсюда. Клиент передаёт только ID выборов; уровень, максимумы, бонусы и экипировка вычисляются `V.Resolve` при RP-уровне `GetLevel() − 9` (1..10). Поля черновика `equipment`, `extraModifiers`, `rpLevel` и любые числа листа игнорируются.

| Состояние | Смысл | Подтверждение |
|---|---|---|
| `none` | Нет строки `character_rps_creation` (профиль создан после миграции) | Первое создание: ОЗ/ОЭ = максимум |
| `legacy` | Профиль существовал до миграции (backfill SQL) | Один раз; текущие ОЗ/ОЭ, Раны, XP, кости, equip/effects JSON сохраняются |
| `reconfigure` | Разрешено ведущим (`scope = 'full'`) или после сброса расы (`scope = 'race'`) | Пересчёт без лечения и без повторного старта; в `scope = 'race'` меняются только раса и особенность |
| `complete` | Выбор подтверждён | `already_configured`; изменение только через ведущего или сброс расы |

RP-имя на сервере не хранится и не проверяется (имена в TotalRP): `draft.rpName` старого клиента игнорируется, колонка `rp_name` остаётся в таблице для совместимости и не пишется.

| Сообщение (канал `RPS_Combat`) | Направление | Содержимое |
|---|---|---|
| `RequestCharacterOptions()` | клиент → сервер | — |
| `CharacterOptions` | сервер → клиент | `{catalogVersion, races=[{key,name,size,sizeName,preset='book'\|'default',presetVersion,features=[{key,name,text,masteryFree?}]}], traits=[{key,name,text,fixing?,needsChoice?,choices?=[{key,name}]}], archetypes=[{key,name,description,featureName,featureText}], mastery={keys,names,basePoints=2}, starter={maxItems=6,quality='simple',items=[{key,name,slot,kind,dice?,armor?,stack?,quality}]}, state={creationState,revision,starterGranted,rpLevel,scope?,raceUpdateAvailable,racePresetVersion,draft?,…}}`. Все 14 рас в порядке каталога, только доступные черты |
| `PreviewCharacter(draft)` | клиент → сервер | `draft = {race, racialFeature, trait, traitChoice?, archetype, mastery={skill,knowledge,endurance,craft}, starterItems=[key \| {key,quality}]}` |
| `CharacterPreview` | сервер → клиент | `{ok=true, sheet={rpLevel,maxHealth,maxEnergy,accuracy,healing,evasion,resistance,speed,armor,woundLimit,healDifficulty,energySpendLimit,mastery,masteryPoints,abilitySlots,fateDie,block={die?,flat,base?},passive=[text],size,sizeName}, warnings=[{code,message_ru}], catalogVersion}` либо `{ok=false, errors=[{code,field,message_ru}], missing=[{step,field,message_ru,left?,optional?}]}`. Ничего не сохраняет |
| `ConfirmCharacter(draft, expectedRevision, requestId)` | клиент → сервер | `expectedRevision` — `state.revision` из опций |
| `CharacterConfirmed` | сервер → клиент | `{requestId, revision, creation, profile}`, затем обычный `SyncProfile` |
| `ReconfigureCharacter(targetGuid, reason, requestId)` | ведущий → сервер | `N.HasStaffPermission`; `targetGuid` — wire GUID, low GUID (в т.ч. offline) или `nil` = выбранный игрок; причина 3–255 байт |
| `CharacterReconfigured` | сервер → ведущему | `{requestId, targetGuid, revision, state}`; цели — `SyncProfile` и notification |
| `ResetRaceData(requestId)` | клиент → сервер | Сброс расы самим игроком: только `complete` и `raceUpdateAvailable` (сохранённая `race_preset_version` < `presetVersion` расы), иначе `race_preset_current` |
| `RaceDataReset` | сервер → инициатору | `{requestId, targetGuid, revision, state='reconfigure', scope='race'}`; цели — `SyncProfile` (и notification, если сбросил ведущий) |
| `CharacterError` | сервер → клиент | `{code, message_ru, requestId?, errors?}` |

`missing` в `CharacterPreview` (только при `ok=false`, порядок мастера): `race`/`racialFeature` (шаг `race`), `trait`/`traitChoice` (шаг `trait`), `mastery` с `left` — сколько очков не распределено (шаг `mastery`), `archetype` (шаг `archetype`), `starterItems` с `optional=true` (шаг `starter`, выбор необязателен). Ошибки выбранных, но неверных значений остаются в `errors`; при заполненном черновике с ошибками `missing` пуст.

`SyncProfile.creation` и `state` опций: `scope` (`race`/`full`/нет; выводится из записи: `reconfigure` с пустой расой = `race`), `raceUpdateAvailable` (bool), `racePresetVersion` (сохранённая версия; 0 без колонки).

Сброс расы: `.rps race reset [имяИгрока] [причина]` — staff (`N.HasStaffPermission`), без имени — выбранный игрок; имя ищется среди онлайн, затем в `characters` (offline). Обработчик — Eluna event 42 (C++-таблицы `.rps` не содержат подкоманды `race`). Игрок — `ResetRaceData`, только после обновления пресета его расы. Сброс очищает `race_key`/`racial_feature_key`, ставит `reconfigure` (`scope='race'`), пишет `character_rps_creation_log` (`action='reconfigure'`, `reason='race_reset[: причина]'`, снимок с `scope`) и receipt `race_reset`; лист, ресурсы, остальной выбор и флаг старта не меняются. Следующий `ConfirmCharacter` в `scope='race'` принимает только расу и особенность (`race_scope_only`); Мастерство можно перераспределить, лишь если сохранённая сумма не совпадает с бюджетом новой особенности (свободное очко Таурена). Подтверждение записывает `race_preset_version = presetVersion` выбранной расы. Без колонки (`2026_10_27_02_rps_race_preset.sql` не применён) версия читается как 0, не пишется, а сброс игроком отвечает `creation_unavailable`; staff-сброс работает.

Коды отказа: коды `V.Validate`, а также `race_scope_only`, `race_preset_current`, `invalid_starter`, `too_many_items`, `unknown_item`, `invalid_quality` (только `starterAllowed`), `invalid_draft`, `revision_conflict`, `already_configured`, `request_conflict`, `request_pending`, `request_window_full`, `rate_limited`, `actor_busy`, `save_failed`, `partial_commit`, `permission_denied`, `invalid_reason`, `target_not_found`, `not_configured`, `already_reconfigure`, `creation_unavailable`, `receipt_unavailable`, `system_unavailable`.

Подтверждение — одна транзакция пула characters: `character_rps_stats` (архетип, раса, особенность, черта, уровень, максимумы, четыре боевых бонуса, Мастерства, Броня, скорость, лимит Ран), строка `character_rps_creation` (`revision + 1`, `catalog_version`), запись `character_rps_creation_log` со снимком «до» и receipt в `rps_action_receipts` (`result_kind = char_confirm`). Повтор `requestId` с теми же данными отвечает `CharacterConfirmed` без записи (память, затем durable receipt); другие данные — `request_conflict`; повтор во время commit — `request_pending`. Неудачный commit ничего не оставляет: тот же `requestId` можно отправить снова.

Стартовый набор: до 6 предметов качества «Простое» из списка, выведенного из каталога экипировки (12 оружий, 3 щита, 2 доспеха, 7 расходников). Выдаётся один раз при первом подтверждении (`starter_granted`), строками `character_rps_items` с `location = 'storage'` и `starter_slot` 1..6; уникальный ключ `(owner_guid, starter_slot)` отвергает вторую выдачу на уровне БД. Пустой набор допустим и тоже расходует выдачу. Предметы не экипируются и не влияют на лист, пока нет экипировки. Расходник занимает один предмет как полная ячейка (стрелы/пули — 10 шт.).

Перенастройка меняет только состояние и ревизию, сохраняет выбор, ресурсы и флаг старта; автор и причина пишутся в журнал. Если схема `2026_10_27_01_rps_character_creation.sql` не применена, создание отвечает `creation_unavailable` (повторная проверка не чаще раза в 60 с), а бой и `SyncProfile` работают без поля `creation`.

Проверка: `Addons/tests/test_rps_creation_server.py` (C01–C08, E01 — автоматическая часть; `missing`, пресет по умолчанию, сброс расы staff/игроком).

## Развитие и опыт

`06_RPS_Progression.lua` — родные уровни WoW как RP-уровни: RP = `GetLevel() − 9`, 10..19 → 1..10. Уровень растёт автоматически при наборе опыта; кнопки «Повысить» нет. Две части модуля:

| Часть | Где подключена | Что делает |
|---|---|---|
| `InstallMap()` | `Map.lua` (MAP-состояния Eluna) | `ON_GIVE_XP` (12): пропускает только выдачу ведущего (`player:Data()` ключ `rps_dm_xp` = сумма, без `victim`), прочее → `0`. `ON_LEVEL_CHANGE` (13): ставит флаг `rps_level_changed` |
| `InstallWorld(R, H)` | `Init.lua` одной строкой | Обработчики `RequestProgression`, `DmGrantXp`; таймер 1 с сверяет `profile.level` с `GetLevel()` у игроков в мире |

Пересчёт листа (`Reconcile`): `profile.level` — последний применённый RP-уровень. Для каждого шага уровня берутся максимумы `V.Resolve` (если `creationState = complete`) или `C.Archetypes` и к максимуму и текущим ОЗ/ОЭ прибавляется только разница максимумов; Раны, бюджет, правки ведущего и бонусы сверх таблицы сохраняются, лечения нет. Скачок на несколько уровней применяется по шагам один раз; повтор не даёт наград. Сохранение — `S.SaveProfiles` под `R.Locks["p:"..guid]`; при ошибке повтор не раньше чем через 30 с. Затем `SyncProfile`, `BroadcastUnitUpdate` и `Progression` с `levelUp`. Аудит: `N.Log` `level_sync …` и `xp_grant …`.

| Сообщение (канал `RPS_Combat`) | Направление | Содержимое |
|---|---|---|
| `RequestProgression()` | клиент → сервер | Не чаще 300 мс; заодно догоняет лист |
| `Progression` | сервер → клиент | `{serverLevel, rpLevel, xp, xpNeeded (0 на потолке), xpTotal, maxRpLevel=10, abilitySlots, slots=[{slot,unlockLevel,cost,open}], gifted, nextUnlock?={rpLevel,slot,cost,text}, atCap, sheetLevel, levelUp?={from,to}}`. Также после смены уровня и выдачи опыта |
| `DmGrantXp(targetGuid, amount, reason, requestId)` | ведущий → сервер | `N.HasStaffPermission`; `amount` 1..500, причина 3..200 символов, цель — игрок онлайн |
| `DmGrantXpResult` | сервер → ведущему | `{ok, code?, requestId, newLevel, newXp}` |

Слоты персональных способностей открываются на RP 3/5/7/9, с чертой «Одарённость» — 2/4/6/8 (`K.PersonalAbilitySlots`, `K.GiftedUnlockLevels`).

Коды `DmGrantXp`: `invalid_request_id`, `system_unavailable`, `permission_denied`, `invalid_amount`, `invalid_reason`, `invalid_target`, `target_unavailable`, `at_cap`, `target_dead`, `xp_not_applied`, `request_conflict`, `request_pending`, `receipt_failed`. Повтор `requestId` с той же подписью (`xp:guid:amount:reason`) отвечает `ok` без повторной выдачи (память, затем receipt `rps_action_receipts`, `result_kind = xp_grant`).

Проверка: `Addons/tests/test_rps_progression.py` (L01–L08 — автоматическая часть).
