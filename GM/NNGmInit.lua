--[[ GM/NNGmInit.lua — bootstrap GM/DM staff layer ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
if not NobleNext.IsMainState() then
    return { bootstrapped = false }
end

if NobleNext._gmLayerBootstrapped then
    return { bootstrapped = true }
end
NobleNext._gmLayerBootstrapped = true

local GmAIO = require("GM.NNGmAIO")
GmAIO.Register()

NobleNext.RegisterModule("GM", { role = "staff-tools", layer = "GM" })
NobleNext.Log("GM", "layer loaded (staff tools)")

return { bootstrapped = true }
