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

function MathUtils.Normalize(vec)
    return vec / vec:Length()
end

function MathUtils.RemapVal(val, A, B, C, D)
    if A == B then return val >= B and D or C end
    return C + (D - C) * (val - A) / (B - A)
end

function MathUtils.Sign(val)
    if val > 0 then return 1 end
    if val < 0 then return -1 end
    return 0
end

return MathUtils
--X
