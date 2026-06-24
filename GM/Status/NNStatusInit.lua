--[[ GM/Status/NNStatusInit.lua — bootstrap (C++: .nnstatus) ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")

if _G.NN_GM_STATUS_BOOTSTRAPPED then
    return package.loaded["GM.Status.NNStatusInit"] or {}
end
_G.NN_GM_STATUS_BOOTSTRAPPED = true

if not NobleNext.IsMainState() then
    return
end

NobleNext.RegisterModule("Status", { role = "diagnostics", layer = "GM", core = "Custom/NobleNext/Core" })
NobleNext.Log("Status", ".nnstatus → C++")
