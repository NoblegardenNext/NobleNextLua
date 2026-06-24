--[[ Modules/NNModulesInit.lua — bootstrap общих (не GM) модулей ]]
if not _G.NN_BOOTSTRAP_ACTIVE then return end

local NobleNext = require("NobleNext")
if NobleNext._modulesLayerBootstrapped then
    return { bootstrapped = true }
end
NobleNext._modulesLayerBootstrapped = true

NobleNext.RegisterModule("Modules", { role = "gameplay", layer = "Modules" })
NobleNext.Log("Modules", "layer marker loaded")

return { bootstrapped = true }
