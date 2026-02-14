--[[ Prediction module for Swing prediction ]]
--
--[[ Handles player movement prediction logic ]]
--

local lnxLib = require("lnxlib")
local Math = lnxLib.Utils.Math
local MathUtils = require("MathUtils")

local Prediction = {}

-- Game constants
local CLASS_MAX_SPEEDS = {
    [1] = 400, -- Scout
    [2] = 300, -- Sniper
    [3] = 240, -- Soldier
    [4] = 280, -- Demoman
    [5] = 320, -- Medic
    [6] = 240, -- Heavy
    [7] = 300, -- Pyro
    [8] = 280, -- Spy
    [9] = 240, -- Engineer
}

-- Helper function to determine if we should hit an entity
local function shouldHitEntityFun(entity, player, ignoreEntities)
    if entity == player then
        return false
    end
    if not entity or not entity:IsValid() then
        return false
    end

    for _, className in ipairs(ignoreEntities) do
        if entity:GetClass() == className then
            return false
        end
    end

    return true
end

-- Main prediction function
function Prediction.PredictPlayer(player, t, d, simulateCharge, fixedAngles, Menu, lastAttackTick, vHitbox)
    local gravity = client.GetConVar("sv_gravity") or 800
    local stepSize = 18
    if not gravity or not stepSize then
        return nil
    end

    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize)
    local ignoreEntities = { "CTFAmmoPack", "CTFDroppedWeapon" }
    local pLocal = entities.GetLocalPlayer()
    if not pLocal then
        return nil
    end
    local shouldHitEntity = function(entity)
        return shouldHitEntityFun(entity, player, ignoreEntities)
    end

    -- Get player class for speed capping
    local playerClass = player:GetPropInt("m_iClass")
    local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 240

    -- Check if this is charge reach exploit simulation
    local isChargeReachExploit = Menu.Misc.ChargeReach
        and player == pLocal
        and ((globals.TickCount() - lastAttackTick) <= 13)
        and player:InCond(17)

    -- Add the current record
    local _out = {
        pos = { [0] = player:GetAbsOrigin() },
        vel = { [0] = player:EstimateAbsVelocity() },
        onGround = { [0] = player:IsOnGround() },
    }

    -- Perform the prediction
    for i = 1, t do
        local lastP, lastV, lastG = _out.pos[i - 1], _out.vel[i - 1], _out.onGround[i - 1]

        local pos = lastP + lastV * globals.TickInterval()
        local vel = lastV
        local onGround1 = lastG

        -- Apply deviation requested by strafe predictor
        if d then
            local ang = vel:Angles()
            ang.y = ang.y + d
            vel = ang:Forward() * vel:Length()
        end

        -- Charge-reach simulation: add forward acceleration each tick
        if simulateCharge then
            local useAngles = fixedAngles or engine.GetViewAngles()
            local forward = useAngles:Forward()
            forward.z = 0 -- ignore vertical component
            forward = MathUtils.Normalize(forward)

            -- If we are currently moving "backwards" (dot < 0) wipe horizontal vel
            local horizontal = Vector3(vel.x, vel.y, 0)
            if horizontal:Dot(forward) < 0 then
                vel.x, vel.y = 0, 0
            end

            -- Add acceleration (750 uu/s) scaled by tick interval
            vel = vel + forward * (750 * globals.TickInterval())
        end

        -- Apply speed capping logic
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

        -- Forward collision detection
        local wallTrace =
            engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        if wallTrace.fraction < 1 then
            local normal = wallTrace.plane
            local angle = math.deg(math.acos(normal:Dot(vUp)))

            if angle > 55 then
                local dot = vel:Dot(normal)
                vel = vel - normal * dot
            end

            pos = lastP + vel * globals.TickInterval()
        end

        -- Ground collision detection
        local groundTrace =
            engine.TraceHull(pos, pos - vStep * 2, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
        if groundTrace.fraction < 1 then
            pos = groundTrace.endpos

            if vel.z < 0 then
                vel.z = 0
            end

            onGround1 = true
        else
            onGround1 = false
            vel.z = vel.z - gravity * globals.TickInterval()
        end

        _out.pos[i] = pos
        _out.vel[i] = vel
        _out.onGround[i] = onGround1
    end

    return _out
end

return Prediction
