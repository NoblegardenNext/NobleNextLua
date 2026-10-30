# NobleNextLua

Серверные Lua-скрипты для Eluna (worldserver). Клиент — `Addons/NobleNext/`.
Полный гайд: [Docs/NOBLENEXT.md](../Docs/NOBLENEXT.md).

## Слои

| Слой | Папка | Назначение |
|------|-------|------------|
| **Core** | `Core/` | DB, Batch, AIO helpers, права через `NobleNext` |
| **GM** | `GM/` | Инструменты GM/DM: Army, Master, Waypoints, POI, … |
| **Modules** | `Modules/` | Общий геймплей: Housing, AutoMount |

Система 3d6: WORLD bootstrap
регистрирует AIO и подтверждённую запись, MAP bootstrap передаёт спеллы-кубы через
native очередь GUID. Модуль остаётся неактивным без соответствующих схем и bindings.

Точка входа — только `00_NobleNext.lua`. Init-модули в подпапках не регистрируют события сами.

## C++ vs Lua (2026)

GM-команды чата (`.weather`, `.daytime`, `.gob tele`, `.movego`, `.wp*`, `.pet*`, battle, …) — **C++** `Custom/NobleNext/`. Lua: AIO UI (в т.ч. GobMover move/rotate) и bootstrap.

## POI (важно)

- **Мутации и sync** — C++ `Custom/Poi/` (`.poi*`, `RPC_POI_INFO`).
- **Список** — `.poi list` / `.poilist` (C++).
- **Lua** — read-only AIO.

## Деплой

```powershell
.\scripts\deploy-noblenext.ps1 -ServerBin "<path-to-bin>"
.reload eluna
.nnstatus
```

SQL: `./docker/apply-noblenext-sql.sh` (см. `RPS.WoWCore/sql/custom/`).

## Структура

```
00_NobleNext.lua           — bootstrap Eluna
NobleNext.lua              — ядро (права, логи, registry)
Core/
  NNCoreInit.lua           — Batch, DB, RequireStaff, SendClient
GM/
  NNGmInit.lua             — bootstrap GM-слоя
  NNGmAIO.lua              — fallback AIO RunGmCommand (клиент шлёт whisper)
  Army/, MasterPanel/, Waypoints/, GobMover/, Pet/, Weather/, Time/, GobTele/, Status/, POI/
Modules/
  NNModulesInit.lua
  Housing/, AutoMount/
```

## Диагностика

`.nnstatus` — статус модулей и пути к Init-файлам.

## Логи

`NobleNext_audit.log`, `DeletedGobLog.txt` — cwd worldserver.
