--[[ MathUtils module for Swing prediction ]]--
--[[ Common mathematical functions and utilities ]]--

local MathUtils = {}

-- Normalize yaw to -180 to 180 range
function MathUtils.NormalizeYaw(y)
    return ((y + 180) % 360) - 180
end

-- Clamp value between min and max
function MathUtils.Clamp(val, min, max)
    if val < min then return min
    elseif val > max then return max end
    return val
end

return MathUtils
