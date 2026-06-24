--[[ GM/Time/NNTimeInit.lua — bootstrap (C++: .daytime / .setgrouptime) ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")

if not NobleNext.IsMainState() then
    return {}
end

if _G.NN_GM_TIME_BOOTSTRAPPED then
    return package.loaded["GM.Time.NNTimeInit"] or {}
end
_G.NN_GM_TIME_BOOTSTRAPPED = true

NobleNext.RegisterModule("TimeCommand", { layer = "GM", command = ".daytime", core = "Custom/NobleNext/Time" })
NobleNext.Log("TimeCommand", "registered (C++ authoritative)")
