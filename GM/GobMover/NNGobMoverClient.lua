--[[ GM/GobMover/NNGobMoverClient ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end
if package.loaded["GM.GobMover.NNGobMoverClient"] then return end

local AIO = AIO or require("AIO")
if AIO.AddAddon() then
    return
end

local GobMoverHandlers = AIO.AddHandlers("NN_GobMover", {})

_G.NobleNextGobMover = _G.NobleNextGobMover or _G.NobleNextGoMover or {}

function GobMoverHandlers.SetTarget(player, guid, name)
    if _G.NobleNextGobMover.SetTarget then
        _G.NobleNextGobMover.SetTarget(guid, name)
    end
end

-- Совместимость со старым именем глобала
_G.NobleNextGoMover = _G.NobleNextGobMover
