--[[ Config module for Swing prediction ]]
--
--[[ Handles configuration loading and saving ]]
--

local Config = {}

-- Build full path once from script name or supplied folder
local function GetConfigPath(folder_name)
    local Lua__fullPath = GetScriptName()
    local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")
    folder_name = folder_name or string.format([[Lua %s]], Lua__fileName)
    local _, fullPath = filesystem.CreateDirectory(folder_name)
    local sep = package.config:sub(1, 1)
    return fullPath .. sep .. "config.cfg"
end

-- Serialize a Lua table (simple, ordered by iteration)
local function serializeTable(tbl, level)
    level = level or 0
    local indent = string.rep("    ", level)
    local out = indent .. "{\n"
    for k, v in pairs(tbl) do
        local keyRepr = (type(k) == "string") and string.format('["%s"]', k) or string.format("[%s]", k)
        out = out .. indent .. "    " .. keyRepr .. " = "
        if type(v) == "table" then
            out = out .. serializeTable(v, level + 1) .. ",\n"
        elseif type(v) == "string" then
            out = out .. string.format('"%s",\n', v)
        else
            out = out .. tostring(v) .. ",\n"
        end
    end
    out = out .. indent .. "}"
    return out
end

-- Shallow-key presence check (recurses into subtables)
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

-- Save current (or supplied) menu
function Config.Save(folder_name, cfg)
    cfg = cfg or {}
    local path = GetConfigPath(folder_name)
    local f = io.open(path, "w")
    if not f then
        printc(255, 0, 0, 255, "[Config] Failed to write: " .. path)
        return
    end
    f:write(serializeTable(cfg))
    f:close()
    printc(100, 183, 0, 255, "[Config] Saved: " .. path)
end

-- Load config; regenerate if invalid/outdated/SHIFT bypass
function Config.Load(folder_name, default_config)
    local path = GetConfigPath(folder_name)
    local f = io.open(path, "r")
    if not f then
        -- First run – make directory & default cfg
        Config.Save(folder_name, default_config)
        return default_config
    end
    local content = f:read("*a")
    f:close()

    local chunk, err = load("return " .. content)
    if not chunk then
        print("[Config] Compile error, regenerating: " .. tostring(err))
        Config.Save(folder_name, default_config)
        return default_config
    end

    local ok, cfg = pcall(chunk)
    if not ok or type(cfg) ~= "table" or not keysMatch(default_config, cfg) or input.IsButtonDown(KEY_LSHIFT) then
        print("[Config] Invalid or outdated cfg – regenerating …")
        Config.Save(folder_name, default_config)
        return default_config
    end

    printc(0, 255, 140, 255, "[Config] Loaded: " .. path)
    return cfg
end

return Config
