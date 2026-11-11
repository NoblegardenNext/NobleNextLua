--[[ GM/GobMover/NNGobMoverClient

    Не проверять NN_BOOTSTRAP_ACTIVE до AddAddon — иначе клиент не получает SetTarget.
]]

local AIO = AIO or require("AIO")
if AIO.AddAddon() then
    return
end

if _G.__NN_GOBMOVER_AIO_CLIENT then
    return
end
_G.__NN_GOBMOVER_AIO_CLIENT = true

local GobMoverHandlers = AIO.AddHandlers("NN_GobMover", {})

_G.NobleNextGobMover = _G.NobleNextGobMover or _G.NobleNextGoMover or {}

function GobMoverHandlers.SetTarget(player, guid, name, serverPhaseId, entry, requestId)
    if _G.NobleNextGobMover.SetTarget then
        _G.NobleNextGobMover.SetTarget(guid, name, serverPhaseId, entry, requestId)
    end
end

function GobMoverHandlers.MineList(player, rows)
    _G.NobleNextGobMover.lastMineList = rows or {}
    if _G.NobleNextGobMover.OnMineList then
        _G.NobleNextGobMover.OnMineList(rows or {})
    end
end

-- Совместимость со старым именем глобала
_G.NobleNextGoMover = _G.NobleNextGobMover
