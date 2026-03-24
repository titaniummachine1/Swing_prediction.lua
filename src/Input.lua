local Input = {}

local _states = {}

---@param bind table {key: integer, mode: integer} 0=Always, 1=Hold, 2=Toggle
---@return boolean
function Input.IsKeybindActive(bind)
    local key, mode
    if type(bind) == "table" then
        key = bind.key
        mode = bind.mode
    else
        key = bind
        mode = 1 -- Default to Hold
    end

    if not key or key == 0 then
        return mode == 0 -- Always Active if key is 0
    end

    local isDown = input.IsButtonDown(key)
    local keyStr = tostring(key)

    if mode == 0 then -- Always
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
