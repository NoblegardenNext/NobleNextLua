--[[ GM/POI/Store.lua — read-only доступ к ng_character_poi ]]
local NobleNext = require("NobleNext")
local Types = require("GM.POI.Types")
local Owner = require("GM.POI.Owner")

local Store = {}

local SELECT_LIST = [[
SELECT id, name, type, map, description,
       COALESCE(owner_type, 1), COALESCE(owner_name, ''), COALESCE(color_key, 0)
FROM ng_character_poi
ORDER BY id
]]

function Store.FetchListRows()
    local rows = {}
    local result = CharDBQuery(SELECT_LIST)
    if not result then return rows end

    repeat
        local ownerType = tonumber(result:GetUInt8(5)) or Types.Owner.Player
        local ownerName = result:GetString(6) or ""
        table.insert(rows, {
            id = result:GetUInt32(0),
            name = result:GetString(1) or "",
            type = result:GetUInt8(2) or 1,
            map = result:GetUInt32(3) or 0,
            desc = result:GetString(4) or "",
            ownerType = ownerType,
            ownerName = ownerName,
            owner = Owner.ResolveDisplayLabel(ownerType, 0, ownerName, nil),
            colorKey = result:GetUInt8(7) or 0,
        })
    until not result:NextRow()

    return rows
end

function Store.SearchListRows(filter)
    local all = Store.FetchListRows()
    filter = NobleNext.Trim(filter or ""):lower()
    if filter == "" then return all end

    local out = {}
    for _, row in ipairs(all) do
        local hay = string.format("%d %s %s %s", row.id, row.name or "", row.desc or "", row.owner or ""):lower()
        if hay:find(filter, 1, true) then
            table.insert(out, row)
        end
    end
    return out
end

return Store
