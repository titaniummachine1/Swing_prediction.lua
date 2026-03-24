--[[ Imported by: Main ]]

local Simulation = {}

-- --- Constants --------------------------------------------------------------

local CLASS_MAX_SPEEDS = {
    [1] = 400, -- Scout
    [2] = 240, -- Sniper
    [3] = 240, -- Soldier
    [4] = 280, -- Demoman
    [5] = 230, -- Medic
    [6] = 300, -- Heavy
    [7] = 240, -- Pyro
    [8] = 320, -- Spy
    [9] = 320  -- Engineer
}

local MIN_SPEED = 10
local MAX_SPEED = 650
local MASK_PLAYERSOLID = MASK_PLAYERSOLID or 33636363
local MASK_SHOT_HULL = MASK_SHOT_HULL or 10067459
local CONTENTS_GRATE = CONTENTS_GRATE or 0x8

-- --- Initialization ----------------------------------------------------------

function Simulation.Init(menu)
    -- Simulation currently uses globals and menu directly in some checks
end

-- --- Module state ------------------------------------------------------------

local _lastAngles = {}
local _lastDeltas = {}
local _avgDeltas = {}
local _strafeAngles = {}
local _inaccuracy = {}
local _pastPositions = {}
local _maxPositions = 4

-- --- Pure Math Helpers -------------------------------------------------------

function Simulation.NormalizeYaw(y)
    return ((y + 180) % 360) - 180
end

function Simulation.Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

function Simulation.Normalize(vec)
    local length = vec:Length()
    if length == 0 then return Vector3(0, 0, 0) end
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

function Simulation.NormalizeVector(vector)
    return Simulation.Normalize(vector)
end

function Simulation.CalculateMaxAngleChange(currentVelocity, minVelocity, maxTurnRate)
    if currentVelocity < minVelocity then return 0 end
    local velocityBuffer = currentVelocity - minVelocity
    return (velocityBuffer / currentVelocity) * maxTurnRate
end

-- --- Melee Helpers -----------------------------------------------------------

function Simulation.smackDelayToTicks(smackDelay)
    return math.floor((smackDelay / globals.TickInterval()) + 0.5)
end

function Simulation.ResolveMeleeParams(pWeapon, pWeaponDef)
    local swingRange = 48.0
    local hullSize = 38.0

    if not pWeapon then return swingRange, hullSize end

    local weaponClass = pWeapon:GetClass()
    if weaponClass == "CTFKnife" then
        swingRange = 48.0
        hullSize = 30.0 -- Knives have smaller hull
    else
        swingRange = 48.0
        hullSize = 38.0
    end

    -- Swords
    local defIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
    if defIndex == 132 or defIndex == 172 or defIndex == 327 or defIndex == 404 or defIndex == 482 or defIndex == 1082 then
        swingRange = 72.0
    end

    -- Disciplinary Action
    if defIndex == 354 then
        swingRange = 72.0
    end

    return swingRange, hullSize
end

-- --- Movement Helpers --------------------------------------------------------

function Simulation.ComputeMove(pCmd, a, b)
    assert(pCmd, "Simulation.ComputeMove: pCmd missing")
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = pCmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    -- local pitch = math.rad(ang.x - cPitch) -- Unused but kept for logic parity
    local move = Vector3(math.cos(yaw) * MAX_SPEED, -math.sin(yaw) * MAX_SPEED, 0)

    return move
end

function Simulation.WalkTo(pCmd, pLocal, pDestination)
    assert(pCmd, "Simulation.WalkTo: pCmd missing")
    assert(pLocal, "Simulation.WalkTo: pLocal missing")
    if not pDestination then return end

    local localPos = pLocal:GetAbsOrigin()
    local distVector = pDestination - localPos

    if not distVector or distVector:Length() > 1000 then return end

    local dist = distVector:Length()
    local speed = math.max(MIN_SPEED, math.min(MAX_SPEED, dist))

    if dist > 1 then
        local result = Simulation.ComputeMove(pCmd, localPos, pDestination)
        if not result then return end

        local scaleFactor = speed / MAX_SPEED
        pCmd:SetForwardMove(result.x * scaleFactor)
        pCmd:SetSideMove(result.y * scaleFactor)
    else
        pCmd:SetForwardMove(0)
        pCmd:SetSideMove(0)
    end
end

-- --- Visibility Helpers ------------------------------------------------------

function Simulation.VisPos(target, from, to)
    local trace = engine.TraceLine(from, to, MASK_SHOT | CONTENTS_GRATE)
    return (trace.entity == target) or (trace.fraction > 0.99)
end

function Simulation.IsVisible(player, fromEntity, vHeight)
    assert(player, "Simulation.IsVisible: player missing")
    assert(fromEntity, "Simulation.IsVisible: fromEntity missing")
    assert(vHeight, "Simulation.IsVisible: vHeight missing")

    local from = fromEntity:GetAbsOrigin() + vHeight
    local to = player:GetAbsOrigin() + vHeight
    return Simulation.VisPos(player, from, to)
end

-- --- Strafe Prediction -------------------------------------------------------

function Simulation.CalcStrafe(players, pLocal)
    assert(players, "Simulation.CalcStrafe: players list missing")
    assert(pLocal, "Simulation.CalcStrafe: pLocal missing")

    local autostrafe = gui.GetValue("Auto Strafe")
    local flags = pLocal:GetPropInt("m_fFlags")
    local onGroundLocal = (flags & FL_ONGROUND) ~= 0

    for idx, entity in pairs(players) do
        if not entity or not entity:IsValid() then goto continue end
        local entityIndex = entity:GetIndex()

        if entity:IsDormant() or not entity:IsAlive() then
            _lastAngles[entityIndex] = nil
            _lastDeltas[entityIndex] = nil
            _avgDeltas[entityIndex] = nil
            _strafeAngles[entityIndex] = nil
            _inaccuracy[entityIndex] = nil
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        if entity:GetIndex() == pLocal:GetIndex() then
            table.insert(_pastPositions, 1, entity:GetAbsOrigin())
            if #_pastPositions > _maxPositions then
                table.remove(_pastPositions)
            end

            if not onGroundLocal and autostrafe == 2 and #_pastPositions >= _maxPositions then
                v = Vector3(0, 0, 0)
                for i = 1, #_pastPositions - 1 do
                    v = v + (_pastPositions[i] - _pastPositions[i + 1])
                end
                v = v / (_maxPositions - 1)
            else
                v = entity:EstimateAbsVelocity()
            end
        end

        local angle = v:Angles()

        if _lastAngles[entityIndex] == nil then
            _lastAngles[entityIndex] = angle
            goto continue
        end

        local delta = angle.y - _lastAngles[entityIndex].y
        local smoothingFactor = 0.2
        local avgDelta = (_lastDeltas[entityIndex] or delta) * (1 - smoothingFactor) + delta * smoothingFactor

        _avgDeltas[entityIndex] = avgDelta

        local vector1 = Vector3(1, 0, 0)
        local vector2 = Vector3(1, 0, 0)

        local ang1 = vector1:Angles()
        ang1.y = ang1.y + (_lastDeltas[entityIndex] or delta)
        vector1 = ang1:Forward() * vector1:Length()

        local ang2 = vector2:Angles()
        ang2.y = ang2.y + avgDelta
        vector2 = ang2:Forward() * vector2:Length()

        local distance = (vector1 - vector2):Length()
        _strafeAngles[entityIndex] = avgDelta
        _inaccuracy[entityIndex] = distance
        _lastDeltas[entityIndex] = delta
        _lastAngles[entityIndex] = angle

        ::continue::
    end
end

function Simulation.GetStrafeAngle(entityIndex)
    return _strafeAngles[entityIndex] or 0
end

-- --- Player Prediction -------------------------------------------------------

local function shouldHitEntityFun(entity, player, ignoreEntities)
    for _, ignoreEntity in ipairs(ignoreEntities) do
        if entity:GetClass() == ignoreEntity then return false end
    end

    local pos = entity:GetAbsOrigin() + Vector3(0, 0, 1)
    local contents = engine.GetPointContents(pos)
    if contents ~= 0 then return true end
    if entity:GetIndex() == player:GetIndex() then return false end
    if entity:IsPlayer() then return false end
    return true
end

function Simulation.PredictPlayer(player, t, d, simulateCharge, fixedAngles, params)
    assert(player, "Simulation.PredictPlayer: player missing")
    assert(params, "Simulation.PredictPlayer: params missing")
    local gravity = params.gravity or 800
    local stepSize = params.stepSize or 18
    local vHitbox = params.vHitbox or { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
    local lastAttackTick = params.lastAttackTick or -1000
    local isChargeReachEnabled = params.isChargeReachEnabled or false
    local swingTime = params.swingTime or 13

    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize)
    local ignoreEntities = { "CTFAmmoPack", "CTFDroppedWeapon" }
    
    local pLocal = entities.GetLocalPlayer()
    if not pLocal then return nil end
    local shouldHitEntity = function(entity) return shouldHitEntityFun(entity, player, ignoreEntities) end

    local playerClass = player:GetPropInt("m_iClass")
    local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 240

    local isChargeReachExploit = isChargeReachEnabled and player:GetIndex() == pLocal:GetIndex() and
        ((globals.TickCount() - lastAttackTick) <= swingTime) and player:InCond(17)

    local _out = {
        pos = { [0] = player:GetAbsOrigin() },
        vel = { [0] = player:EstimateAbsVelocity() },
        onGround = { [0] = player:IsOnGround() }
    }

    for i = 1, t do
        local lastP, lastV, lastG = _out.pos[i - 1], _out.vel[i - 1], _out.onGround[i - 1]

        local pos = lastP + lastV * globals.TickInterval()
        local vel = lastV
        local onGround1 = lastG

        if d then
            local ang = vel:Angles()
            ang.y = ang.y + d
            vel = ang:Forward() * vel:Length()
        end

        if simulateCharge then
            local useAngles = fixedAngles or engine.GetViewAngles()
            local forward = useAngles:Forward()
            forward.z = 0
            forward = Simulation.Normalize(forward)

            local horizontal = Vector3(vel.x, vel.y, 0)
            if horizontal:Dot(forward) < 0 then
                vel.x, vel.y = 0, 0
            end

            vel = vel + forward * (750 * globals.TickInterval())
        end

        if onGround1 then
            local shouldBypassSpeedCap = isChargeReachExploit or simulateCharge
            if not shouldBypassSpeedCap then
                local currentSpeed = vel:Length2D()
                if currentSpeed > maxSpeed then
                    local horizontalVel = Vector3(vel.x, vel.y, 0)
                    if currentSpeed > 0 then
                        horizontalVel = (horizontalVel / currentSpeed) * maxSpeed
                    end
                    vel = Vector3(horizontalVel.x, horizontalVel.y, vel.z)
                end
            end
        end

        local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        if wallTrace.fraction < 1 then
            local normal = wallTrace.plane
            local angle = math.deg(math.acos(normal:Dot(vUp)))
            if angle > 55 then
                local dot = vel:Dot(normal)
                vel = vel - normal * dot
            end
            pos.x, pos.y = wallTrace.endpos.x, wallTrace.endpos.y
        end

        local downStep = onGround1 and vStep or Vector3()
        local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        if groundTrace.fraction < 1 then
            local normal = groundTrace.plane
            local angle = math.deg(math.acos(normal:Dot(vUp)))

            if angle < 45 then
                local isLocal = player:GetIndex() == pLocal:GetIndex()
                local jumpInput = input.IsButtonDown(KEY_SPACE) or params.chargeJump
                if onGround1 and isLocal and gui.GetValue("Bunny Hop") == 1 and jumpInput then
                    if gui.GetValue("Duck Jump") == 1 then
                        vel.z = 277
                    else
                        vel.z = 271
                    end
                    onGround1 = false
                else
                    pos = groundTrace.endpos
                    onGround1 = true
                end
            elseif angle < 55 then
                vel.x, vel.y, vel.z = 0, 0, 0
                onGround1 = false
            else
                local dot = vel:Dot(normal)
                vel = vel - normal * dot
                onGround1 = true
            end
        else
            onGround1 = false
        end

        if not onGround1 then
            vel.z = vel.z - gravity * globals.TickInterval()
        end

        _out.pos[i], _out.vel[i], _out.onGround[i] = pos, vel, onGround1
    end
    return _out
end

-- --- Range Checking ----------------------------------------------------------

function Simulation.ClosestPointOnHitbox(targetPos, spherePos, vHitbox)
    vHitbox = vHitbox or { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
    local hitbox_min = targetPos + vHitbox[1]
    local hitbox_max = targetPos + vHitbox[2]

    return Vector3(
        math.max(hitbox_min.x, math.min(spherePos.x, hitbox_max.x)),
        math.max(hitbox_min.y, math.min(spherePos.y, hitbox_max.y)),
        math.max(hitbox_min.z, math.min(spherePos.z, hitbox_max.z))
    )
end

function Simulation.MeleeSwingCanHit(spherePos, closestPoint, targetEntity, swingRange, halfHull, pLocal)
    local direction = Simulation.Normalize(closestPoint - spherePos)
    local swingTraceEnd = spherePos + direction * swingRange
    local swingHullMin = Vector3(-halfHull, -halfHull, -halfHull)
    local swingHullMax = Vector3(halfHull, halfHull, halfHull)

    -- Try hull trace first (more accurate for melee)
    local trace = engine.TraceHull(spherePos, swingTraceEnd, swingHullMin, swingHullMax, MASK_SHOT_HULL)
    if trace.fraction < 1 and trace.entity and targetEntity and trace.entity:GetIndex() == targetEntity:GetIndex() then
        return true
    end

    -- Fallback to line trace
    trace = engine.TraceLine(spherePos, swingTraceEnd, MASK_SHOT_HULL)
    if trace.fraction < 1 and trace.entity and targetEntity and trace.entity:GetIndex() == targetEntity:GetIndex() then
        return true
    end

    return false
end

function Simulation.CheckInRange(targetPos, spherePos, sphereRadius, targetEntity, params)
    assert(targetPos, "Simulation.CheckInRange: targetPos missing")
    assert(spherePos, "Simulation.CheckInRange: spherePos missing")
    assert(params, "Simulation.CheckInRange: params missing")

    local vHitbox = params.vHitbox or { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
    local swingHalfhullSize = params.swingHalfhullSize or 19
    local advancedHitreg = params.advancedHitreg or false

    local closestPoint = Simulation.ClosestPointOnHitbox(targetPos, spherePos, vHitbox)
    local distanceAlongVector = (spherePos - closestPoint):Length()

    if sphereRadius > distanceAlongVector then
        if advancedHitreg then
            if Simulation.MeleeSwingCanHit(spherePos, closestPoint, targetEntity, sphereRadius, swingHalfhullSize) then
                return true, closestPoint
            else
                return false, nil
            end
        end
        return true, closestPoint
    end

    return false, nil
end

function Simulation.CheckInRangeSimple(targetIdx, swingRange, pLocalPos, pLocalFuture, vPlayerOrigin, vPlayerFuture, targetEntity, params)
    local inRange, point = Simulation.CheckInRange(vPlayerOrigin, pLocalPos, swingRange, targetEntity, params)
    if inRange then return true, point, false end

    if params.instantAttackReady then return false, nil, false end

    inRange, point = Simulation.CheckInRange(vPlayerFuture, pLocalFuture, swingRange, targetEntity, params)
    if inRange then return true, point, false end

    return false, nil, false
end

return Simulation
