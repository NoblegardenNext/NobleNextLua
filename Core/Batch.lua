--[[ Core/Batch.lua — chunked processing ]]
local NobleNext = require("NobleNext")

local Batch = {}

function Batch.ScheduleBatch(label, items, perTick, delayMs, fn)
    if not items or #items == 0 then return end
    perTick = perTick or 50
    delayMs = delayMs or 25
    local index = 1

    local function step()
        local last = math.min(index + perTick - 1, #items)
        for i = index, last do
            local ok, err = pcall(fn, items[i], i)
            if not ok then
                NobleNext.LogError(label or "Batch", tostring(err))
            end
        end
        index = last + 1
        if index <= #items then
            CreateLuaEvent(step, delayMs, 1)
        end
    end

    step()
end

return Batch
