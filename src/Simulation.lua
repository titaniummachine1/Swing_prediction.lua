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

-- Ring buffer for local player past positions (zero-alloc per tick)
local _maxPositions  = 4
local _posRing       = { [1]=nil, [2]=nil, [3]=nil, [4]=nil }
local _posRingHead   = 0   -- index of the most recently inserted slot (0 = empty)
local _posRingCount  = 0   -- how many valid entries (capped at _maxPositions)

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

function Simulation.ResolveMeleeParams(pWeapon)
    local swingRange = 48.0
    local hullSize = 35.6 -- Original used 35.6/38 interchangeably, 35.6 is standard

    if not pWeapon then return swingRange, hullSize end

    local defIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")

    -- Swords and other long range melee
    -- Claidheamh Mor, Eyelander, Nessie's Nine Iron, Horseless Headless Horsemann's Headtaker, Scotsman's Skullcutter
    if defIndex == 132 or defIndex == 172 or defIndex == 327 or defIndex == 404 or defIndex == 482 or defIndex == 1082 then
        swingRange = 72.0
        hullSize = 38.0
    end

    -- Disciplinary Action (Special Case)
    if defIndex == 354 then
        swingRange = 81.6
        hullSize = 55.8
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
            -- Insert into ring buffer (head wraps around, no heap alloc)
            _posRingHead                 = (_posRingHead % _maxPositions) + 1
            _posRing[_posRingHead]       = entity:GetAbsOrigin()
            if _posRingCount < _maxPositions then _posRingCount = _posRingCount + 1 end

            if not onGroundLocal and autostrafe == 2 and _posRingCount >= _maxPositions then
                -- Average velocity from ring buffer
                v = Vector3(0, 0, 0)
                for k = 1, _maxPositions - 1 do
                    local idx1 = ((_posRingHead - k  - 1) % _maxPositions) + 1
                    local idx2 = ((_posRingHead - k      ) % _maxPositions) + 1
                    v = v + (_posRing[idx2] - _posRing[idx1])
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

-- (shouldHitEntityFun replaced by shouldHitEntityShared below — no per-call closure alloc)

-- --- Pre-allocated Prediction Buffers (zero heap-alloc per tick) ---------------
-- Two named buffers: one for local player, one for target.
-- Each slot is a pre-created Vector3 so we can write x/y/z in-place.
local MAX_SIM_TICKS = 32  -- must be >= any swingTicks used

local function allocBuf()
    local b = { pos = {}, vel = {}, onGround = {} }
    b.pos[0]      = Vector3(0, 0, 0)
    b.vel[0]      = Vector3(0, 0, 0)
    b.onGround[0] = false
    for i = 1, MAX_SIM_TICKS do
        b.pos[i]      = Vector3(0, 0, 0)
        b.vel[i]      = Vector3(0, 0, 0)
        b.onGround[i] = false
    end
    return b
end

local _predBufLocal  = allocBuf()  -- reused for local player each tick
local _predBufTarget = allocBuf()  -- reused for target each tick

-- Pre-allocated shared constants (never recreated at runtime)
local _vUp          = Vector3(0, 0, 1)
local _ignoreEnts   = { "CTFAmmoPack", "CTFDroppedWeapon" }
local _defVHitboxMin = Vector3(-24, -24, 0)
local _defVHitboxMax = Vector3( 24,  24, 82)
local _downStep     = Vector3(0, 0, 0)  -- mutated each tick step (onGround branch)

-- The shouldHitEntity closure is created once per PredictPlayer call (captures player arg).
-- We keep a module-level reference so Lua doesn't allocate a fresh upvalue table
-- for every call — instead we swap _playerForHitTest before each call.
local _playerForHitTest = nil
local function shouldHitEntityShared(entity)
    for _, cls in ipairs(_ignoreEnts) do
        if entity:GetClass() == cls then return false end
    end
    local pos = entity:GetAbsOrigin() + Vector3(0, 0, 1)
    local contents = engine.GetPointContents(pos)
    if contents ~= 0 then return true end
    -- _playerForHitTest is always set before this closure is called
    if _playerForHitTest and entity:GetIndex() == _playerForHitTest:GetIndex() then return false end
    if entity:IsPlayer() then return false end
    return true
end

-- --- Player Prediction -------------------------------------------------------

function Simulation.PredictPlayer(player, t, d, chargeMode, fixedAngles, params, outBuf)
    assert(player,  "Simulation.PredictPlayer: player missing")
    assert(params,  "Simulation.PredictPlayer: params missing")
    assert(outBuf,  "Simulation.PredictPlayer: outBuf missing — pass Simulation.BufLocal or Simulation.BufTarget")
    assert(t <= MAX_SIM_TICKS, "Simulation.PredictPlayer: t exceeds MAX_SIM_TICKS")

    -- chargeMode:
    -- 0 = no charge simulated
    -- 1 = full charge simulated (all ticks)
    -- 2 = exploit charge simulated (only starts on second-to-last tick: i >= t - 1)
    chargeMode = chargeMode or 0

    local gravity  = params.gravity  or 800
    local stepSize = params.stepSize or 18
    local vHitboxMin = params.vHitboxMin or _defVHitboxMin
    local vHitboxMax = params.vHitboxMax or _defVHitboxMax

    local vStep = Vector3(0, 0, stepSize)  -- stepSize rarely changes so small alloc is fine here

    local pLocal = entities.GetLocalPlayer()
    if not pLocal then return nil end

    _playerForHitTest = player  -- swap capture for shared closure
    local shouldHitEntity = shouldHitEntityShared

    local playerClass = player:GetPropInt("m_iClass")
    local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 240

    local isChargeReachEnabled = params.isChargeReachEnabled or false
    local lastAttackTick       = params.lastAttackTick or -1000
    local swingTime            = params.swingTime or 13
    local isChargeReachExploit = isChargeReachEnabled
        and player:GetIndex() == pLocal:GetIndex()
        and ((globals.TickCount() - lastAttackTick) <= swingTime)
        and player:InCond(17)

    -- Write initial state directly into pre-allocated slots (no table creation)
    local p0 = player:GetAbsOrigin()
    local v0 = player:EstimateAbsVelocity()
    outBuf.pos[0].x,      outBuf.pos[0].y,      outBuf.pos[0].z      = p0.x, p0.y, p0.z
    outBuf.vel[0].x,      outBuf.vel[0].y,      outBuf.vel[0].z      = v0.x, v0.y, v0.z
    outBuf.onGround[0] = (player:GetPropInt("m_fFlags") & FL_ONGROUND) ~= 0

    local dt = globals.TickInterval()

    for i = 1, t do
        local lPos = outBuf.pos[i - 1]
        local lVel = outBuf.vel[i - 1]
        local lGnd = outBuf.onGround[i - 1]

        -- New position = last pos + last vel * dt  (write into slot i)
        local px = lPos.x + lVel.x * dt
        local py = lPos.y + lVel.y * dt
        local pz = lPos.z + lVel.z * dt
        local vx, vy, vz = lVel.x, lVel.y, lVel.z
        local onGround1 = lGnd

        -- Strafe deviation
        if d and d ~= 0 then
            local tmp = Vector3(vx, vy, vz):Angles()
            tmp.y = tmp.y + d
            local fwd = tmp:Forward()
            local spd = math.sqrt(vx*vx + vy*vy + vz*vz)
            vx, vy, vz = fwd.x * spd, fwd.y * spd, fwd.z * spd
        end

        -- Charge simulation
        -- chargeMode 1 = apply on all ticks
        -- chargeMode 2 = apply only starting from second-to-last tick (for exploit)
        local applyCharge = false
        if chargeMode == 1 then
            applyCharge = true
        elseif chargeMode == 2 and i >= (t - 1) then
            applyCharge = true
        end

        if applyCharge then
            local useAngles = fixedAngles or engine.GetViewAngles()
            local fwd = useAngles:Forward()
            fwd.z = 0
            local flen = math.sqrt(fwd.x*fwd.x + fwd.y*fwd.y)
            if flen > 0 then fwd.x = fwd.x/flen ; fwd.y = fwd.y/flen end

            -- If moving backwards, wipe horizontal vel
            local dot = vx * fwd.x + vy * fwd.y
            if dot < 0 then vx, vy = 0, 0 end

            local acc = 750 * dt
            vx = vx + fwd.x * acc
            vy = vy + fwd.y * acc
        end

        -- Speed cap (ground only, bypass for charge/exploit)
        if onGround1 then
            local bypass = isChargeReachExploit or applyCharge
            if not bypass then
                local hspd = math.sqrt(vx*vx + vy*vy)
                if hspd > maxSpeed and hspd > 0 then
                    local scale = maxSpeed / hspd
                    vx, vy = vx * scale, vy * scale
                end
            end
        end

        -- Wall collision
        outBuf.pos[i].x, outBuf.pos[i].y, outBuf.pos[i].z = lPos.x, lPos.y, lPos.z  -- temp: prev pos + step
        local wallTrace = engine.TraceHull(
            Vector3(lPos.x, lPos.y, lPos.z + stepSize),
            Vector3(px, py, pz + stepSize),
            vHitboxMin, vHitboxMax, MASK_PLAYERSOLID, shouldHitEntity)
        if wallTrace.fraction < 1 then
            local normal = wallTrace.plane
            local angle = math.deg(math.acos(normal:Dot(_vUp)))
            if angle > 55 then
                local dot = vx * normal.x + vy * normal.y + vz * normal.z
                vx = vx - normal.x * dot
                vy = vy - normal.y * dot
                vz = vz - normal.z * dot
            end
            px, py = wallTrace.endpos.x, wallTrace.endpos.y
        end

        -- Ground collision
        local groundDS = stepSize
        if not onGround1 then groundDS = 0 end
        local groundTrace = engine.TraceHull(
            Vector3(px, py, pz + stepSize),
            Vector3(px, py, pz - groundDS),
            vHitboxMin, vHitboxMax, MASK_PLAYERSOLID, shouldHitEntity)
        if groundTrace.fraction < 1 then
            local normal = groundTrace.plane
            local angle  = math.deg(math.acos(normal:Dot(_vUp)))
            if angle < 45 then
                local isLocal   = player:GetIndex() == pLocal:GetIndex()
                local jumpInput = input.IsButtonDown(KEY_SPACE) or params.chargeJump
                if onGround1 and isLocal and gui.GetValue("Bunny Hop") == 1 and jumpInput then
                    if gui.GetValue("Duck Jump") == 1 then vz = 277 else vz = 271 end
                    onGround1 = false
                else
                    px, py, pz = groundTrace.endpos.x, groundTrace.endpos.y, groundTrace.endpos.z
                    onGround1  = true
                end
            elseif angle < 55 then
                vx, vy, vz = 0, 0, 0
                onGround1  = false
            else
                local dot = vx * normal.x + vy * normal.y + vz * normal.z
                vx = vx - normal.x * dot
                vy = vy - normal.y * dot
                vz = vz - normal.z * dot
                onGround1 = true
            end
        else
            onGround1 = false
        end

        -- Gravity
        if not onGround1 then vz = vz - gravity * dt end

        -- Write results directly into pre-allocated Vector3 slots
        outBuf.pos[i].x,      outBuf.pos[i].y,      outBuf.pos[i].z      = px, py, pz
        outBuf.vel[i].x,      outBuf.vel[i].y,      outBuf.vel[i].z      = vx, vy, vz
        outBuf.onGround[i] = onGround1
    end
    return outBuf
end

-- Expose the two pre-allocated buffers so Main.lua can pass them in
Simulation.BufLocal  = _predBufLocal
Simulation.BufTarget = _predBufTarget



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
    if inRange then return true, point, nil end

    if params.instantAttackReady then return false, nil, nil end

    inRange, point = Simulation.CheckInRange(vPlayerFuture, pLocalFuture, swingRange, targetEntity, params)
    if inRange then return true, point, nil end

    if params.history then
        -- Latency-aware backtrack window passed in from Main via params
        local iOldest = params.btOldest
        local iLatest = params.btLatest

        if iOldest and iLatest then
            -- The smack happens `swingTicks` in the future. We must only target records
            -- that will STILL be valid (within the 200ms window) at the moment of the smack.
            local hitOldest = iOldest + (params.swingTicks or 0)

            for _, record in ipairs(params.history) do
                -- Only use records the server will still accept when the swing finishes
                if record.tick >= hitOldest and record.tick <= iLatest then
                    inRange, point = Simulation.CheckInRange(record.pos, pLocalFuture, swingRange, targetEntity, params)
                    if inRange then
                        return true, point, record.tick
                    end
                end
            end
        end
    end

    return false, nil, nil
end

return Simulation
