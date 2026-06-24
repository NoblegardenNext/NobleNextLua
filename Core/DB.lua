--[[ Core/DB.lua — CharDB helpers ]]
local DB = {}

function DB.EscapeSqlString(s)
    s = tostring(s or "")
    return s:gsub("\\", "\\\\"):gsub("'", "''")
end

function DB.ToNumber(v)
    if v == nil then return 0 end
    if type(v) == "number" then return v end

    local direct = tonumber(v)
    if type(direct) == "number" then return direct end

    local text = tostring(v)
    return tonumber(text:match("%d+")) or 0
end

function DB.QueryRows(sql, mapper)
    local result = CharDBQuery(sql)
    if not result then return {} end
    local rows = {}
    repeat
        local row = result:GetRow()
        if row and mapper then
            table.insert(rows, mapper(row))
        end
    until not result:NextRow()
    return rows
end

function DB.Execute(sql)
    CharDBExecute(sql)
end

function DB.ScalarUInt32(sql)
    local result = CharDBQuery(sql)
    if not result then return 0 end
    return result:GetUInt32(0)
end

return DB
