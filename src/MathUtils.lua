local MathUtils = {}

function MathUtils.NormalizeYaw(yaw)
    while yaw > 180 do yaw = yaw - 360 end
    while yaw < -180 do yaw = yaw + 360 end
    return yaw
end

function MathUtils.Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

return MathUtils
--X
