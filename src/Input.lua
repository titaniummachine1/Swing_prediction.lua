local Input = {}

local _states = {}

local function normalizeBind(bind)
    if type(bind) == "table" then
        local key = bind.key
        local mode = bind.mode

        if type(key) == "table" then
            if mode == nil then
                mode = key.mode
            end
            key = key.key
        end

        key = tonumber(key) or 0
        mode = tonumber(mode)
        if mode == nil or mode < 0 or mode > 2 then
            if key == 0 then
                mode = 0
            else
                mode = 1
            end
        end

        return key, mode
    end

    local key = tonumber(bind) or 0
    return key, 1
end

---@param bind table {key: integer, mode: integer} 0=Always, 1=Hold, 2=Toggle
---@return boolean
function Input.IsKeybindActive(bind)
    local key, mode = normalizeBind(bind)

    if not key or key == 0 then
        return mode == 0 -- Always Active if key is 0
    end

    local isDown = input.IsButtonDown(key)
    local keyStr = tostring(key)

    if mode == 0 then     -- Always
        return true
    elseif mode == 1 then -- Hold
        return isDown
    elseif mode == 2 then -- Toggle
        if isDown then
            if not _states[keyStr] then
                _states[keyStr] = true
                _states[keyStr .. "_toggle"] = not _states[keyStr .. "_toggle"]
            end
        else
            _states[keyStr] = false
        end
        return _states[keyStr .. "_toggle"] or false
    end

    return false
end

return Input
