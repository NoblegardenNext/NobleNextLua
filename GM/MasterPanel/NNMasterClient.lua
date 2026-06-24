--[[ GM/MasterPanel/NNMasterClient ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end
if package.loaded["GM.MasterPanel.NNMasterClient"] then return end

local AIO = AIO or require("AIO")
if AIO.AddAddon() then
    return
end

local AddonNDMHandlers = AIO.AddHandlers("AIOAddonMasterPanel", {})

_G.NobleNextMaster = _G.NobleNextMaster or {}

function AddonNDMHandlers.ElunaGetTalkingHead(player, line, UnitName, creator)
    if _G.NobleNextMaster.OnTalkingHead then
        _G.NobleNextMaster.OnTalkingHead(line, UnitName, creator)
    end
end
