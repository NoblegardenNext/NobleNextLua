--[[ GM/Army/NNArmyClient ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end
if package.loaded["GM.Army.NNArmyClient"] then return end

local AIO = AIO or require("AIO")
if AIO.AddAddon() then
    return
end

local ArmyHandlers = AIO.AddHandlers("ArmyHandlers", {})

_G.NobleNextArmy = _G.NobleNextArmy or {}

function ArmyHandlers.UnselectAll(player)
    _G.NobleNextArmy.NPCTable = nil
    if _G.NobleNextArmy.OnUnselectAll then
        _G.NobleNextArmy.OnUnselectAll()
    end
end

function ArmyHandlers.CallTableToDel(player)
    if _G.NobleNextArmy.OnDelete then
        _G.NobleNextArmy.OnDelete()
    end
end

function ArmyHandlers.CallTableToDelPerm(player)
    if _G.NobleNextArmy.OnDeletePerm then
        _G.NobleNextArmy.OnDeletePerm()
    end
end

function ArmyHandlers.CallTableToCommand(player, callType, xPos, yPos, zPos)
    if _G.NobleNextArmy.OnCommand then
        _G.NobleNextArmy.OnCommand(callType, xPos, yPos, zPos)
    end
end

function ArmyHandlers.CallEmoteFrame(player)
    if _G.NobleNextArmy.OnEmoteFrame then
        _G.NobleNextArmy.OnEmoteFrame()
    end
end

function ArmyHandlers.SelectNewNPCs(player, NPCTable)
    _G.NobleNextArmy.NPCTable = NPCTable or {}
    if _G.NobleNextArmy.OnSelectNewNPCs then
        _G.NobleNextArmy.OnSelectNewNPCs(NPCTable)
    end
end
