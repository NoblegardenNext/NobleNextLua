--[[ Core/NNCoreAIO.lua — server -> client AIO helpers ]]
local NobleNext = require("NobleNext")

local CoreAIO = {}

function CoreAIO.SendClient(player, handler, method, ...)
    if not player or not NobleNext.AIO then return false end
    NobleNext.AIO.Handle(player, handler, method, ...)
    return true
end

function CoreAIO.AddHandlers(name, handlers)
    if not NobleNext.AIO or not NobleNext.AIO.AddHandlers then return nil end
    return NobleNext.AIO.AddHandlers(name, handlers or {})
end

return CoreAIO
