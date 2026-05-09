local Input = {}

local _states = {}

local function normalizeBind(bind)
    if type(bind) == "table" then
        local key = bind.key
        local mode = bind.mode
        local bindId = bind.id

        if type(key) == "table" then
            if mode == nil then
                mode = key.mode
            end
            key = key.key
        end

        key = tonumber(key) or 0
        mode = tonumber(mode)
        if mode == nil or mode < 0 or mode > 3 then
            if key == 0 then
                mode = 0
            else
                mode = 1
            end
        end

        if bindId == nil then
            bindId = "key:" .. tostring(key)
        end

        return key, mode, tostring(bindId)
    end

    local key = tonumber(bind) or 0
    if key == 0 then
        return key, 0, "key:0"
    end
    return key, 1, "key:" .. tostring(key)
end

---@param bind table {key: integer, mode: integer} 0=Always, 1=Hold, 2=Toggle, 3=Release
---@return boolean
function Input.IsKeybindActive(bind)
    local key, mode, bindStateKey = normalizeBind(bind)

    if not key or key == 0 then
        return true -- Unbound keybind always acts as enabled.
    end

    local isDown = input.IsButtonDown(key)
    local pressedStateKey = bindStateKey .. "_pressed"
    local toggleStateKey = bindStateKey .. "_toggle"

    if mode == 0 then     -- Always
        return true
    elseif mode == 1 then -- Hold
        return isDown
    elseif mode == 2 then -- Toggle
        if isDown then
            if not _states[pressedStateKey] then
                _states[pressedStateKey] = true
                _states[toggleStateKey] = not _states[toggleStateKey]
            end
        else
            _states[pressedStateKey] = false
        end
        return _states[toggleStateKey] or false
    elseif mode == 3 then -- Release
        return not isDown
    end

    return false
end

return Input
