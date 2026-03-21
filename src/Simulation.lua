--[[ Imported by: Main ]]
-- Physics simulation, strafe prediction, and pure movement math.

local Simulation      = {}

-- ─── Module state (set via Init / UpdatePhysics / SetLastAttackTick) ──────────

local _menu           = nil
local _gravity        = 800
local _stepSize       = 18
local _vHitbox        = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local _lastAttackTick = -1000

-- Strafe tracking state (owned here, read via GetStrafeAngle)
local _lastAngles     = {} ---@type table<number, EulerAngles>
local _lastDeltas     = {} ---@type table<number, number>
local _avgDeltas      = {} ---@type table<number, number>
local _strafeAngles   = {} ---@type table<number, number>
local _inaccuracy     = {} ---@type table<number, number>
local _pastPositions  = {}
local _maxPositions   = 4

-- ─── Init / setters ───────────────────────────────────────────────────────────

function Simulation.Init(menuRef)
    assert(menuRef, "Simulation.Init: menuRef is nil")
    _menu = menuRef
end

function Simulation.UpdatePhysics(gravity, stepSize, vHitbox)
    _gravity  = gravity or _gravity
    _stepSize = stepSize or _stepSize
    if vHitbox then _vHitbox = vHitbox end
end

function Simulation.SetLastAttackTick(t)
    _lastAttackTick = t
end

function Simulation.GetLastAttackTick()
    return _lastAttackTick
end

-- ─── Pure math ────────────────────────────────────────────────────────────────

function Simulation.NormalizeYaw(y)
    return ((y + 180) % 360) - 180
end

function Simulation.Clamp(val, minV, maxV)
    if val < minV then return minV end
    if val > maxV then return maxV end
    return val
end

function Simulation.Normalize(vec)
    local length = vec:Length()
    assert(length > 0, "Simulation.Normalize: zero-length vector")
    return vector.Divide(vec, length)
end

function Simulation.NormalizeVector(vector)
    local length = vector:Length()
    assert(length > 0, "Simulation.NormalizeVector: zero-length vector")
    return vector.Divide(vector, length)
end

function Simulation.calculateMaxAngleChange(currentVelocity, minVelocity, maxTurnRate)
    if currentVelocity < minVelocity then return 0 end
    local velocityBuffer = currentVelocity - minVelocity
    return (velocityBuffer / currentVelocity) * maxTurnRate
end

-- Closest point on player AABB (cheap prefilter for swing hit test)
function Simulation.ClosestPointOnHitbox(targetOrigin, fromPoint)
    local mn = targetOrigin + _vHitbox[1]
    local mx = targetOrigin + _vHitbox[2]
    return Vector3(
        math.max(mn.x, math.min(fromPoint.x, mx.x)),
        math.max(mn.y, math.min(fromPoint.y, mx.y)),
        math.max(mn.z, math.min(fromPoint.z, mx.z))
    )
end

-- Movement helpers
Simulation.MIN_SPEED = 10
Simulation.MAX_SPEED = 650

local MAX_SPEED = Simulation.MAX_SPEED

function Simulation.ComputeMove(pCmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local vSilent         = Vector3(diff.x, diff.y, 0)
    local ang             = vSilent:Angles()
    local cPitch, cYaw, _ = pCmd:GetViewAngles()
    local yaw             = math.rad(ang.y - cYaw)
    local pitch           = math.rad(ang.x - cPitch)
    return Vector3(math.cos(yaw) * MAX_SPEED, -math.sin(yaw) * MAX_SPEED, 0)
end

function Simulation.WalkTo(pCmd, pLocal, pDestination)
    if not pDestination or not pLocal then return end

    local localPos   = pLocal:GetAbsOrigin()
    local distVector = pDestination - localPos

    if not distVector or distVector:Length() > 1000 then return end

    local dist = distVector:Length()
    if dist <= 1 then
        pCmd:SetForwardMove(0)
        pCmd:SetSideMove(0)
        return
    end

    local speed  = math.max(Simulation.MIN_SPEED, math.min(MAX_SPEED, dist))
    local result = Simulation.ComputeMove(pCmd, localPos, pDestination)
    if not result then return end

    local scaleFactor = speed / MAX_SPEED
    pCmd:SetForwardMove(result.x * scaleFactor)
    pCmd:SetSideMove(result.y * scaleFactor)
end

-- ─── Timing helpers ───────────────────────────────────────────────────────────

function Simulation.smackDelayToTicks(smackDelaySeconds)
    if not smackDelaySeconds or smackDelaySeconds <= 0 then
        return math.max((_menu and _menu.Aimbot.MaxSwingTime) or 13, 5)
    end
    return math.max(math.ceil(smackDelaySeconds / globals.TickInterval()), 5)
end

function Simulation.getMeleeSwingTicksRemaining(pWeapon)
    if not pWeapon then return nil end
    local ok, smackUntil = pcall(function()
        return pWeapon:GetPropFloat("m_flSmackTime")
    end)
    if not ok or not smackUntil or smackUntil <= 0 then return nil end
    local rem = smackUntil - globals.CurTime()
    if rem <= 0 then return nil end
    return math.max(math.ceil(rem / globals.TickInterval()), 1)
end

function Simulation.getOutgoingLatencyTicks()
    local lat = 0
    local net = clientstate and clientstate.GetNetChannel and clientstate:GetNetChannel() or nil
    if net and net.GetLatency then
        lat = math.max(net:GetLatency(0) or 0, 0)
    end
    return math.max(math.ceil(lat / globals.TickInterval()), 0)
end

function Simulation.getChargeReachWindowTicks()
    local choke = (clientstate and clientstate.GetChokedCommands and clientstate.GetChokedCommands()) or 0
    choke = math.max(choke, 1)
    return math.max(Simulation.getOutgoingLatencyTicks() + choke, 2)
end

-- ─── Melee hit simulation ─────────────────────────────────────────────────────

-- Approximate C++ CAimbotMelee::CanHit sweep (ray + hull trace).
-- pLocal is passed explicitly so the function has no Main.lua upvalue dependency.
function Simulation.MeleeSwingCanHit(eyePos, aimPoint, targetEntity, weaponSwingRange, hullHalf, pLocal)
    if not eyePos or not aimPoint or not targetEntity or not weaponSwingRange or weaponSwingRange <= 0 then
        return false
    end

    local dir = aimPoint - eyePos
    local len = dir:Length()
    if len < 1e-4 then
        dir = engine.GetViewAngles():Forward()
    else
        dir = Vector3(dir.x / len, dir.y / len, dir.z / len)
    end

    local traceEnd = eyePos + dir * weaponSwingRange
    local mask     = MASK_SHOT_HULL

    local function shouldHitEntity(ent, _)
        if ent and pLocal and ent == pLocal then return false end
        return true
    end

    local tRay = engine.TraceLine(eyePos, traceEnd, mask, shouldHitEntity)
    if tRay.fraction < 1 then
        return tRay.entity == targetEntity
    end

    local hm    = Vector3(-hullHalf, -hullHalf, -hullHalf)
    local hx    = Vector3(hullHalf, hullHalf, hullHalf)
    local tHull = engine.TraceHull(eyePos, traceEnd, hm, hx, mask, shouldHitEntity)
    if tHull.fraction < 1 then
        return tHull.entity == targetEntity
    end

    return false
end

-- ─── Player prediction ────────────────────────────────────────────────────────

local CLASS_MAX_SPEEDS = {
    [1] = 400, -- Scout
    [2] = 240, -- Sniper
    [3] = 240, -- Soldier
    [4] = 280, -- Demoman
    [5] = 230, -- Medic
    [6] = 300, -- Heavy
    [7] = 240, -- Pyro
    [8] = 320, -- Spy
    [9] = 320, -- Engineer
}
Simulation.CLASS_MAX_SPEEDS = CLASS_MAX_SPEEDS

local function shouldHitEntityFun(entity, player, ignoreEntities)
    for _, ignoreEntity in ipairs(ignoreEntities) do
        if entity:GetClass() == ignoreEntity then return false end
    end
    local pos      = entity:GetAbsOrigin() + Vector3(0, 0, 1)
    local contents = engine.GetPointContents(pos)
    if contents ~= 0 then return true end
    if entity:GetName() == player:GetName() then return false end
    if entity:IsPlayer() then return false end
    return true
end

---@param player      any
---@param t           integer          number of ticks to simulate
---@param d           number?          strafe deviation angle (optional)
---@param simulateCharge boolean?      simulate shield charge starting now
---@param fixedAngles EulerAngles?     if provided, use this view-angle for charge direction
---@return { pos: Vector3[], vel: Vector3[], onGround: boolean[] }?
function Simulation.PredictPlayer(player, t, d, simulateCharge, fixedAngles)
    assert(_menu, "Simulation.PredictPlayer: call Simulation.Init(menu) first")
    if not _gravity or not _stepSize then return nil end

    local vUp            = Vector3(0, 0, 1)
    local vStep          = Vector3(0, 0, _stepSize)
    local ignoreEntities = { "CTFAmmoPack", "CTFDroppedWeapon" }

    local pLocal         = entities.GetLocalPlayer()
    if not pLocal then return nil end

    local function shouldHitEntity(entity)
        return shouldHitEntityFun(entity, player, ignoreEntities)
    end

    local playerClass            = player:GetPropInt("m_iClass")
    local maxSpeed               = CLASS_MAX_SPEEDS[playerClass] or 240

    local swingAttackWindowTicks = _menu.Aimbot.MaxSwingTime or 13
    local isChargeReachExploit   = _menu.Charge.ChargeReach
        and player == pLocal
        and ((globals.TickCount() - _lastAttackTick) <= swingAttackWindowTicks)
        and player:InCond(17)

    local _out                   = {
        pos      = { [0] = player:GetAbsOrigin() },
        vel      = { [0] = player:EstimateAbsVelocity() },
        onGround = { [0] = player:IsOnGround() },
    }

    for i = 1, t do
        local lastP, lastV, lastG = _out.pos[i - 1], _out.vel[i - 1], _out.onGround[i - 1]

        local pos                 = lastP + lastV * globals.TickInterval()
        local vel                 = lastV
        local onGround1           = lastG

        if d then
            local ang = vel:Angles()
            ang.y     = ang.y + d
            vel       = ang:Forward() * vel:Length()
        end

        if simulateCharge then
            local useAngles  = fixedAngles or engine.GetViewAngles()
            local forward    = useAngles:Forward()
            forward.z        = 0
            forward          = Simulation.Normalize(forward)

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

        local wallTrace = engine.TraceHull(
            lastP + vStep, pos + vStep,
            _vHitbox[1], _vHitbox[2],
            MASK_PLAYERSOLID, shouldHitEntity
        )
        if wallTrace.fraction < 1 then
            local normal = wallTrace.plane
            local angle  = math.deg(math.acos(normal:Dot(vUp)))
            if angle > 55 then
                local dot = vel:Dot(normal)
                vel = vel - normal * dot
            end
            pos.x, pos.y = wallTrace.endpos.x, wallTrace.endpos.y
        end

        local downStep    = onGround1 and vStep or Vector3()
        local groundTrace = engine.TraceHull(
            pos + vStep, pos - downStep,
            _vHitbox[1], _vHitbox[2],
            MASK_PLAYERSOLID, shouldHitEntity
        )
        if groundTrace.fraction < 1 then
            local normal = groundTrace.plane
            local angle  = math.deg(math.acos(normal:Dot(vUp)))

            if angle < 45 then
                local isLocal     = player:GetIndex() == pLocal:GetIndex()
                local bhopEnabled = gui.GetValue("Bunny Hop") == 1
                local jumpInput   = input.IsButtonDown(KEY_SPACE) or _menu.Charge.ChargeJump
                if onGround1 and isLocal and bhopEnabled and jumpInput then
                    if gui.GetValue("Duck Jump") == 1 then
                        vel.z = 277
                    else
                        vel.z = 271
                    end
                    onGround1 = false
                else
                    pos       = groundTrace.endpos
                    onGround1 = true
                end
            elseif angle < 55 then
                vel.x, vel.y, vel.z = 0, 0, 0
                onGround1 = false
            else
                local dot = vel:Dot(normal)
                vel       = vel - normal * dot
                onGround1 = true
            end
        else
            onGround1 = false
        end

        if not onGround1 then
            vel.z = vel.z - _gravity * globals.TickInterval()
        end

        _out.pos[i], _out.vel[i], _out.onGround[i] = pos, vel, onGround1
    end

    return _out
end

-- ─── Strafe prediction ────────────────────────────────────────────────────────

-- Returns the strafe deviation angle (degrees) for a given entity index,
-- or 0 if not yet tracked.
function Simulation.GetStrafeAngle(entityIdx)
    return _strafeAngles[entityIdx] or 0
end

-- Call once per-tick with the current players list and local player entity.
function Simulation.CalcStrafe(players, pLocal)
    if not players then return end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    local autostrafe = gui.GetValue("Auto Strafe")
    local flags      = localPlayer:GetPropInt("m_fFlags")
    local onGround   = (flags & FL_ONGROUND) ~= 0

    for _, entity in pairs(players) do
        local entityIndex = entity:GetIndex()

        if entity:IsDormant() or not entity:IsAlive() then
            _lastAngles[entityIndex]   = nil
            _lastDeltas[entityIndex]   = nil
            _avgDeltas[entityIndex]    = nil
            _strafeAngles[entityIndex] = nil
            _inaccuracy[entityIndex]   = nil
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        if entity == pLocal then
            table.insert(_pastPositions, 1, entity:GetAbsOrigin())
            if #_pastPositions > _maxPositions then
                table.remove(_pastPositions)
            end

            if not onGround and autostrafe == 2 and #_pastPositions >= _maxPositions then
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

        local delta                = angle.y - _lastAngles[entityIndex].y
        local smoothFactor         = 0.2
        local avgDelta             = (_lastDeltas[entityIndex] or delta) * (1 - smoothFactor) + delta * smoothFactor

        _avgDeltas[entityIndex]    = avgDelta

        local vec1                 = Vector3(1, 0, 0)
        local vec2                 = Vector3(1, 0, 0)

        local ang1                 = vec1:Angles()
        ang1.y                     = ang1.y + (_lastDeltas[entityIndex] or delta)
        vec1                       = ang1:Forward() * vec1:Length()

        local ang2                 = vec2:Angles()
        ang2.y                     = ang2.y + avgDelta
        vec2                       = ang2:Forward() * vec2:Length()

        local distance             = (vec1 - vec2):Length()

        _strafeAngles[entityIndex] = avgDelta
        _inaccuracy[entityIndex]   = distance
        _lastDeltas[entityIndex]   = delta
        _lastAngles[entityIndex]   = angle

        ::continue::
    end
end

return Simulation
