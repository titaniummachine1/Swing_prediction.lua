--[[ Input module for Swing prediction ]]
--
--[[ Handles key detection and input utilities ]]
--

local lnxLib = require("lnxlib")
local Input = lnxLib.Utils.Input

local InputModule = {}

-- Get pressed key with fallback to standard mouse buttons
function InputModule.GetPressedKey()
    local pressedKey = Input.GetPressedKey()
    if not pressedKey then
        -- Check for standard mouse buttons
        if input.IsButtonDown(MOUSE_LEFT) then
            return MOUSE_LEFT
        end
        if input.IsButtonDown(MOUSE_RIGHT) then
            return MOUSE_RIGHT
        end
        if input.IsButtonDown(MOUSE_MIDDLE) then
            return MOUSE_MIDDLE
        end

        -- Check for additional mouse buttons
        for i = 1, 10 do
            if input.IsButtonDown(MOUSE_FIRST + i - 1) then
                return MOUSE_FIRST + i - 1
            end
        end
    end
    return pressedKey
end

return InputModule
