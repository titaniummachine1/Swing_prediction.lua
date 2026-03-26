--[[ Imported by: utils.Config ]]

local Serializer = {}

local function deepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

local function serializeTable(tbl, level, visited)
    level = level or 0
    visited = visited or {}

    if type(tbl) ~= "table" then
        return "{}"
    end

    local indent = string.rep("    ", level)
    local innerIndent = indent .. "    "
    local entries = {}

    for k, v in pairs(tbl) do
        local chunks = {}

        local keyRepr
        if type(k) == "string" then
            local safeKey = k:gsub("\\", "\\\\"):gsub("\"", "\\\"")
            keyRepr = '["' .. safeKey .. '"]'
        else
            keyRepr = "[" .. tostring(k) .. "]"
        end

        chunks[#chunks + 1] = innerIndent .. keyRepr .. " = "

        if type(v) == "table" then
            if visited[v] then
                chunks[#chunks + 1] = '"--[[cycle]]"'
            else
                visited[v] = true
                chunks[#chunks + 1] = serializeTable(v, level + 1, visited)
            end
        elseif type(v) == "string" then
            local sanitized = v:gsub("[^%z\32-\126]", ""):sub(1, 128)
            sanitized = sanitized:gsub("\\", "\\\\")
                :gsub("\"", "\\\"")
                :gsub("\n", "\\n")
                :gsub("\r", "\\r")
            chunks[#chunks + 1] = '"' .. sanitized .. '"'
        else
            chunks[#chunks + 1] = tostring(v)
        end

        entries[#entries + 1] = table.concat(chunks)
    end

    if #entries == 0 then
        return "{}"
    end

    return "{\n" .. table.concat(entries, ",\n") .. "\n" .. indent .. "}"
end

local function keysMatch(template, loaded)
    for k, v in pairs(template) do
        if loaded[k] == nil then
            return false
        end
        if type(v) == "table" and type(loaded[k]) == "table" then
            if not keysMatch(v, loaded[k]) then
                return false
            end
        end
    end
    return true
end

local function writeFile(path, data)
    local file = io.open(path, "w")
    if not file then
        return false
    end
    file:write(data)
    file:close()
    return true
end

local function readFile(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

Serializer.deepCopy = deepCopy
Serializer.serializeTable = serializeTable
Serializer.keysMatch = keysMatch
Serializer.writeFile = writeFile
Serializer.readFile = readFile

return Serializer
