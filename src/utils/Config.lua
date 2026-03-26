--[[ Imported by: Main ]]

local Serializer = require("utils.Serializer")

local Config = {}

local function getConfigPath(luaFileName, folderName)
    local finalFolder = folderName or string.format([[Lua %s]], luaFileName)
    local _, fullPath = filesystem.CreateDirectory(finalFolder)
    local sep = package.config:sub(1, 1)
    return fullPath .. sep .. "config.cfg"
end

local function ensureFields(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = Serializer.deepCopy(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            ensureFields(target[key], value)
        end
    end

    return target
end

function Config.CreateCFG(cfgTable, luaFileName, folderName)
    local path = getConfigPath(luaFileName, folderName)
    local ok = Serializer.writeFile(path, Serializer.serializeTable(cfgTable))
    if not ok then
        printc(255, 0, 0, 255, "[Config] Failed to write: " .. path)
        return false
    end

    printc(100, 183, 0, 255, "[Config] Saved: " .. path)
    return true
end

function Config.LoadCFG(defaultConfig, luaFileName, folderName)
    local template = Serializer.deepCopy(defaultConfig)
    local path = getConfigPath(luaFileName, folderName)
    local content = Serializer.readFile(path)

    if not content then
        printc(255, 200, 100, 255, "[Config] No config found, creating default...")
        local fresh = Serializer.deepCopy(template)
        Config.CreateCFG(fresh, luaFileName, folderName)
        return ensureFields(fresh, template)
    end

    local chunk, err = load("return " .. content)
    if not chunk then
        printc(255, 100, 100, 255, "[Config] Compile error, regenerating: " .. tostring(err))
        local fresh = Serializer.deepCopy(template)
        Config.CreateCFG(fresh, luaFileName, folderName)
        return ensureFields(fresh, template)
    end

    local ok, cfg = pcall(chunk)
    local shiftHeld = input.IsButtonDown(KEY_LSHIFT)
    if not ok or type(cfg) ~= "table" or shiftHeld then
        if shiftHeld then
            printc(255, 200, 100, 255, "[Config] SHIFT held - regenerating config...")
        else
            printc(255, 100, 100, 255, "[Config] Invalid or corrupted config - regenerating...")
        end
        local fresh = Serializer.deepCopy(template)
        Config.CreateCFG(fresh, luaFileName, folderName)
        return ensureFields(fresh, template)
    end

    printc(0, 255, 140, 255, "[Config] Loaded: " .. path)
    return ensureFields(cfg, template)
end

return Config
