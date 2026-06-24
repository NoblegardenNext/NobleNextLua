--[[ GM/GobTele/NNGobTeleInit.lua — bootstrap (C++: .gobtele + gossip) ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")

if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_GM_GOBTELE_BOOTSTRAPPED then
    return package.loaded["GM.GobTele.NNGobTeleInit"] or {}
end
_G.NN_GM_GOBTELE_BOOTSTRAPPED = true

NobleNext.RegisterModule("GobTele", { layer = "GM", table = "gameobject_teleport", core = "Custom/NobleNext/GobTele" })
NobleNext.Log("GobTele", "registered (C++ authoritative)")
