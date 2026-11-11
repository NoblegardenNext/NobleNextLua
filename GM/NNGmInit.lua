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

NobleNext.RegisterModule("GM", { role = "staff-tools", layer = "GM" })
NobleNext.RegisterModule("Weather", { layer = "GM", command = ".weather", core = "Custom/NobleNext/Weather" })
NobleNext.RegisterModule("TimeCommand", { layer = "GM", command = ".daytime", core = "Custom/NobleNext/Time" })
NobleNext.Log("GM", "layer loaded (staff tools)")

return { bootstrapped = true }
