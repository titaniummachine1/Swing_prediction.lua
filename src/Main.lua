--[[ Swing prediction for  Lmaobox  ]] --
--[[          --Authors--           ]] --
--[[           Terminator           ]] --
--[[  (github.com/titaniummachine1  ]] --


-- Unload the module if it's already loaded
if package.loaded["ImMenu"] then
    package.loaded["ImMenu"] = nil
end

-- Initialize libraries
local lnxLib = require("lnxlib")
local ImMenu = require("immenu")
local Config = require("utils.Config")
local Simulation = require("Simulation")
local Visuals = require("Visuals")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
--local Prediction = lnxLib.TF2.Prediction
--local Fonts = lnxLib.UI.Fonts
local Input = lnxLib.Utils.Input
local Notify = lnxLib.UI.Notify

local function GetPressedkey()
    local pressedKey = Input.GetPressedKey()
    if not pressedKey then
        -- Check for standard mouse buttons
        if input.IsButtonDown(MOUSE_LEFT) then return MOUSE_LEFT end
        if input.IsButtonDown(MOUSE_RIGHT) then return MOUSE_RIGHT end
        if input.IsButtonDown(MOUSE_MIDDLE) then return MOUSE_MIDDLE end

        -- Check for additional mouse buttons
        for i = 1, 10 do
            if input.IsButtonDown(MOUSE_FIRST + i - 1) then return MOUSE_FIRST + i - 1 end
        end
    end
    return pressedKey
end

--[[menu:AddComponent(MenuLib.Button("Debug", function() -- Disable Weapon Sway (Executes commands)
    client.SetConVar("cl_vWeapon_sway_interp",              0)             -- Set cl_vWeapon_sway_interp to 0
    client.SetConVar("cl_jiggle_bone_framerate_cutoff", 0)             -- Set cl_jiggle_bone_framerate_cutoff to 0
    client.SetConVar("cl_bobcycle",                     10000)         -- Set cl_bobcycle to 10000
    client.SetConVar("sv_cheats", 1)                                    -- debug fast setup
    client.SetConVar("mp_disable_respawn_times", 1)
    client.SetConVar("mp_respawnwavetime", -1)
    client.SetConVar("mp_teams_unbalance_limit", 1000)
end, ItemFlags.FullWidth))]]

local Menu = {
    -- Tab management - Start with Aimbot tab open by default
    currentTab = 1, -- 1 = Aimbot, 2 = Charge, 3 = Visuals, 4 = Misc
    tabs = { "Aimbot", "Demoknight", "Visuals", "Misc" },

    -- Aimbot settings
    Aimbot = {
        Aimbot = true,
        Silent = true,
        AimbotFOV = 360,
        SwingTime = 13,
        AlwaysUseMaxSwingTime = false, -- Default to always use max for best experience
        MaxSwingTime = 11,             -- Starting value, will be updated based on weapon
        ChargeBot = true,              -- Moved to Charge tab in UI but kept here for backward compatibility
    },

    -- Charge settings (moved from mixed locations to a dedicated section)
    Charge = {
        ChargeBot = false,
        ChargeControl = false,
        ChargeSensitivity = 1.0,
        ChargeReach = true,
        ChargeJump = true,
        LateCharge = true,
    },

    -- Visuals settings
    Visuals = {
        EnableVisuals = true,
        Sphere = false,
        Section = 1,
        Sections = { "Local", "Target", "Experimental" },
        Local = {
            RangeCircle = true,
            path = {
                enable = true,
                Color = { 255, 255, 255, 255 },
                Styles = { "Pavement", "ArrowPath", "Arrows", "L Line", "dashed", "line" },
                Style = 1,
                width = 5,
            },
        },
        Target = {
            path = {
                enable = true,
                Color = { 255, 255, 255, 255 },
                Styles = { "Pavement", "ArrowPath", "Arrows", "L Line", "dashed", "line" },
                Style = 1,
                width = 5,
            },
        },
    },

    -- Misc settings
    Misc = {
        strafePred = true,
        CritRefill = { Active = true, NumCrits = 1 },
        CritMode = 1,
        CritModes = { "Rage", "On Button" },
        InstantAttack = false,
        WarpOnAttack = true, -- New option to control warp during instant attack
        TroldierAssist = false,
        advancedHitreg = true,
    },

    -- Global settings
    Keybind = KEY_NONE,
    KeybindName = "Always On",
}

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("([^/\\]+)%.lua$")
if not Lua__fileName or Lua__fileName == "" then
    Lua__fileName = "A_Swing_Prediction"
end

Menu = Config.LoadCFG(Menu, Lua__fileName)

local function CreateCFG(folder_name, cfg)
    return Config.CreateCFG(cfg or Menu, Lua__fileName, folder_name)
end



-- Entity-independent constants
local swingrange = 48.0
local TotalSwingRange = 48.0
local SwingHullSize = 38.0
local SwingHalfhullSize = SwingHullSize / 2
local Charge_Range = 128.0
local normalWeaponRange = 48.0
local normalTotalSwingRange = 48.0
local vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local gravity = client.GetConVar("sv_gravity") or 800
local stepSize = 18

-- Function to update server cvars only on events
local function UpdateServerCvars()
    gravity = client.GetConVar("sv_gravity") or 800
    Simulation.UpdatePhysics(gravity, stepSize, vHitbox)
end

UpdateServerCvars() -- Initialize on script load
Simulation.Init(Menu)

-- Weapon smack delay → ticks (matches C++ ceil(smackDelay / TICK_INTERVAL))
local function smackDelayToTicks(smackDelaySeconds)
    return Simulation.smackDelayToTicks(smackDelaySeconds)
end

-- Remaining ticks until melee impact when windup is active (TF2 m_flSmackTime > 0)
local function getMeleeSwingTicksRemaining(pWeapon)
    return Simulation.getMeleeSwingTicksRemaining(pWeapon)
end

local function getOutgoingLatencyTicks()
    return Simulation.getOutgoingLatencyTicks()
end

-- Charge-reach IN_ATTACK2 window: max(out_latency_ticks + choke_margin, 2) — same shape as reference C++
local function getChargeReachWindowTicks()
    return Simulation.getChargeReachWindowTicks()
end

-- Per-tick variables (reset each tick)
local isMelee = false
local pLocal = nil
local players = nil
local tick_count = 0
local can_attack = false
local can_charge = false
local pLocalPath = {}
local vPlayerPath = {}
local drawVhitbox = {}

-- Track swing ticks after +attack is sent
local swingTickCounter = 0

-- Helpers for charge-bot yaw clamping
local function NormalizeYaw(y)
    return Simulation.NormalizeYaw(y)
end
local function Clamp(val, min, max)
    return Simulation.Clamp(val, min, max)
end
local MAX_CHARGE_BOT_TURN = 17

-- Variables to track attack and charge state
local attackStarted = false
local attackTickCount = 0
local lastChargeTime = 0
local chargeAimAngles = nil -- yaw/pitch to look at when triggering charge reach exploit
local chargeState = "idle"
-- chargeJumpDone no longer needed (simplified)

-- Track the tick index of the last +attack press (user or script)
local lastAttackTick = -1000 -- initialize far in the past

-- Add this function to reset the attack tracking when needed
local function resetAttackTracking()
    attackStarted = false
    attackTickCount = 0
end

local function applySilentAttackTick(pCmd, aimAngles)
    if not Menu.Aimbot.Silent or not aimAngles then
        return
    end
    if (pCmd:GetButtons() & IN_ATTACK) == 0 then
        return
    end

    pCmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
end




-- Per-tick entity variables (will be reset each tick)
local pLocalClass = nil
local pLocalFuture = nil
local pLocalOrigin = nil
local pWeapon = nil
local Latency = nil
local viewheight = nil
local Vheight = nil
local vPlayerFuture = nil
local vPlayer = nil
local vPlayerOrigin = nil
local chargeLeft = nil
local onGround = nil
local CurrentTarget = nil
local aimposVis = nil
local tickCounterrecharge = 0

local settings = {
    MinDistance = 0,
    MaxDistance = 770,
    MinFOV = 0,
    MaxFOV = Menu.Aimbot.AimbotFOV,
}

local lastAngles = {} ---@type table<number, EulerAngles>
local lastDeltas = {} ---@type table<number, number>
local avgDeltas = {} ---@type table<number, number>
local strafeAngles = {} ---@type table<number, number>
local inaccuracy = {} ---@type table<number, number>
local pastPositions = {} -- Stores past positions of the local player
local maxPositions = 4   -- Number of past positions to consider

local function CalcStrafe()
    if not players then
        return
    end

    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then
        return
    end

    local autostrafe = gui.GetValue("Auto Strafe")
    local flags = localPlayer:GetPropInt("m_fFlags")
    local OnGround = (flags & FL_ONGROUND) ~= 0

    for idx, entity in pairs(players) do
        local entityIndex = entity:GetIndex()

        if entity:IsDormant() or not entity:IsAlive() then
            lastAngles[entityIndex] = nil
            lastDeltas[entityIndex] = nil
            avgDeltas[entityIndex] = nil
            strafeAngles[entityIndex] = nil
            inaccuracy[entityIndex] = nil
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        if entity == pLocal then
            table.insert(pastPositions, 1, entity:GetAbsOrigin())
            if #pastPositions > maxPositions then
                table.remove(pastPositions)
            end

            if not OnGround and autostrafe == 2 and #pastPositions >= maxPositions then
                v = Vector3(0, 0, 0)
                for i = 1, #pastPositions - 1 do
                    v = v + (pastPositions[i] - pastPositions[i + 1])
                end
                v = v / (maxPositions - 1)
            else
                v = entity:EstimateAbsVelocity()
            end
        end

        local angle = v:Angles()

        if lastAngles[entityIndex] == nil then
            lastAngles[entityIndex] = angle
            goto continue
        end

        local delta = angle.y - lastAngles[entityIndex].y

        -- Calculate the average delta using exponential smoothing
        local smoothingFactor = 0.2
        local avgDelta = (lastDeltas[entityIndex] or delta) * (1 - smoothingFactor) + delta * smoothingFactor

        -- Save the average delta
        avgDeltas[entityIndex] = avgDelta

        local vector1 = Vector3(1, 0, 0)
        local vector2 = Vector3(1, 0, 0)

        -- Apply deviation
        local ang1 = vector1:Angles()
        ang1.y = ang1.y + (lastDeltas[entityIndex] or delta)
        vector1 = ang1:Forward() * vector1:Length()

        local ang2 = vector2:Angles()
        ang2.y = ang2.y + avgDelta
        vector2 = ang2:Forward() * vector2:Length()

        -- Calculate the distance between the two vectors
        local distance = (vector1 - vector2):Length()

        -- Save the strafe angle
        strafeAngles[entityIndex] = avgDelta

        -- Calculate the inaccuracy as the distance between the two vectors
        inaccuracy[entityIndex] = distance

        -- Save the last delta
        lastDeltas[entityIndex] = delta

        lastAngles[entityIndex] = angle

        ::continue::
    end
end

function Normalize(vec)
    local length = vec:Length()
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

-- Class max speeds (units per second)
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

local function shouldHitEntityFun(entity, player, ignoreEntities)
    for _, ignoreEntity in ipairs(ignoreEntities) do --ignore custom
        if entity:GetClass() == ignoreEntity then
            return false
        end
    end

    local pos = entity:GetAbsOrigin() + Vector3(0, 0, 1)
    local contents = engine.GetPointContents(pos)
    if contents ~= 0 then return true end
    if entity:GetName() == player:GetName() then return false end -- ignore self
    -- Ignore all players except world/props; we only need brushes for movement prediction
    if entity:IsPlayer() then return false end
    return true
end

--[[
    Extended PredictPlayer
    Added:   simulateCharge (boolean) – when true we pretend the local player starts a shield charge **right now**.
             The function will:
               • Each tick add forward acceleration of 750 uu/s (scaled by tick interval) to the horizontal velocity
               • Force horizontal velocity to align with the view-angle forward direction (so walking backwards flips)
               • Skip ground speed-cap logic while the fake charge is simulated
]]
---@param player any
---@param t      integer                          -- number of ticks to simulate
---@param d      number?                          -- strafe deviation angle (optional)
---@param simulateCharge boolean?                -- simulate shield charge starting now
---@param fixedAngles EulerAngles?               -- if provided, use this view-angle for charge direction
---@return { pos : Vector3[], vel: Vector3[], onGround: boolean[] }?
local function PredictPlayer(player, t, d, simulateCharge, fixedAngles)
    if not gravity or not stepSize then return nil end
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize)
    local ignoreEntities = { "CTFAmmoPack", "CTFDroppedWeapon" }
    pLocal = entities.GetLocalPlayer()
    if not pLocal then return nil end
    local shouldHitEntity = function(entity) return shouldHitEntityFun(entity, player, ignoreEntities) end --trace ignore simulated player

    -- Get player class for speed capping
    local playerClass = player:GetPropInt("m_iClass")
    local maxSpeed = CLASS_MAX_SPEEDS[playerClass] or 240 -- Default to 240 if class not found

    -- Check if this is charge reach exploit simulation
    -- Only consider charging flag when doing charge reach exploit, not regular charging toward enemies
    local swingAttackWindowTicks = Menu.Aimbot.MaxSwingTime or 13
    local isChargeReachExploit = Menu.Charge.ChargeReach and player == pLocal and
        ((globals.TickCount() - lastAttackTick) <= swingAttackWindowTicks) and player:InCond(17)

    -- Add the current record
    local _out = {
        pos = { [0] = player:GetAbsOrigin() },
        vel = { [0] = player:EstimateAbsVelocity() },
        onGround = { [0] = player:IsOnGround() }
    }

    -- Perform the prediction
    for i = 1, t do
        local lastP, lastV, lastG = _out.pos[i - 1], _out.vel[i - 1], _out.onGround[i - 1]

        local pos = lastP + lastV * globals.TickInterval()
        local vel = lastV
        local onGround1 = lastG

        --------------------------------------------------------------------------
        -- Apply deviation requested by strafe predictor
        if d then
            local ang = vel:Angles()
            ang.y     = ang.y + d
            vel       = ang:Forward() * vel:Length()
        end

        -- =========================================================================
        --  Charge-reach simulation: add forward acceleration each tick so we can
        --  evaluate hits that would connect **if we pressed charge now**.
        -- =========================================================================
        if simulateCharge then
            -- Forward direction based on current view angles (horizontal only)
            local useAngles  = fixedAngles or engine.GetViewAngles()
            local forward    = useAngles:Forward()
            forward.z        = 0 -- ignore vertical component
            forward          = Normalize(forward)

            -- If we are currently moving "backwards" (dot < 0) wipe horizontal vel
            local horizontal = Vector3(vel.x, vel.y, 0)
            if horizontal:Dot(forward) < 0 then
                vel.x, vel.y = 0, 0
            end

            -- Add acceleration (750 uu/s) scaled by tick interval
            vel = vel + forward * (750 * globals.TickInterval())
        end

        -- Apply speed capping logic (simplified approach)
        -- Speed cap is only applied on ground, and only when not charging
        -- For regular charging toward enemies (not exploit), we assume swing stops charge immediately
        if onGround1 then
            -- Only bypass speed cap for charge reach exploit, not regular charging
            local shouldBypassSpeedCap = isChargeReachExploit or simulateCharge

            if not shouldBypassSpeedCap then
                -- Apply speed cap when on ground and not doing charge reach exploit
                -- Regular charging toward enemies gets speed capped since swing stops charge
                local currentSpeed = vel:Length2D() -- Get horizontal speed only
                if currentSpeed > maxSpeed then
                    local horizontalVel = Vector3(vel.x, vel.y, 0)
                    if currentSpeed > 0 then
                        horizontalVel = (horizontalVel / currentSpeed) * maxSpeed -- Normalize and scale
                    end
                    vel = Vector3(horizontalVel.x, horizontalVel.y, vel.z)        -- Preserve Z velocity
                end
            end
        end
        -- When in air, no speed cap is applied regardless of charging state

        --[[ Forward collision ]]

        local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID,
            shouldHitEntity)
        if wallTrace.fraction < 1 then
            -- We'll collide
            local normal = wallTrace.plane
            local angle = math.deg(math.acos(normal:Dot(vUp)))

            -- Check the wall angle
            if angle > 55 then
                -- The wall is too steep, we'll collide
                local dot = vel:Dot(normal)
                vel = vel - normal * dot
            end

            pos.x, pos.y = wallTrace.endpos.x, wallTrace.endpos.y
        end

        --[[ Ground collision ]]

        -- Don't step down if we're in-air
        local downStep = vStep
        if not onGround1 then downStep = Vector3() end

        -- Ground collision
        local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID,
            shouldHitEntity)
        if groundTrace.fraction < 1 then
            -- We'll hit the ground
            local normal = groundTrace.plane
            local angle = math.deg(math.acos(normal:Dot(vUp)))

            -- Check the ground angle
            if angle < 45 then
                if onGround1 and player:GetIndex() == pLocal:GetIndex() and gui.GetValue("Bunny Hop") == 1 and (input.IsButtonDown(KEY_SPACE) or Menu.Charge.ChargeJump) then
                    -- Jump
                    if gui.GetValue("Duck Jump") == 1 then
                        vel.z = 277
                        onGround1 = false
                    else
                        vel.z = 271
                        onGround1 = false
                    end
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
            -- We're in the air
            onGround1 = false
        end

        -- Gravity
        if not onGround1 then
            vel.z = vel.z - gravity * globals.TickInterval()
        end

        -- Add the prediction record
        _out.pos[i], _out.vel[i], _out.onGround[i] = pos, vel, onGround1
    end
    return _out
end

-- Constants for minimum and maximum speed
local MIN_SPEED = 10             -- Minimum speed to avoid jittery movements
local MAX_SPEED = 650            -- Maximum speed the player can move

local MoveDir = Vector3(0, 0, 0) -- Variable to store the movement direction
-- Using tick-scoped pLocal defined in OnCreateMove; avoid shadowing here

local function NormalizeVector(vector)
    return Simulation.Normalize(vector)
end

-- Function to compute the move direction
local function ComputeMove(pCmd, a, b)
    return Simulation.ComputeMove(pCmd, a, b)
end

-- Function to make the player walk to a destination smoothly
local function WalkTo(pCmd, pLocal, pDestination)
    return Simulation.WalkTo(pCmd, pLocal, pDestination)
end

local playerTicks = {}
-- Removed: maxTick calculation no longer needed with NetChannel API
local maxTick = 0

-- Returns if the player is visible
---@param target Entity
---@param from Vector3
---@param to Vector3
---@return boolean
local function VisPos(target, from, to)
    local trace = engine.TraceLine(from, to, MASK_SHOT | CONTENTS_GRATE)
    return (trace.entity == target) or (trace.fraction > 0.99)
end

-- Returns whether the entity can be seen from the given entity
---@param fromEntity Entity
function IsVisible(player, fromEntity)
    local from = fromEntity:GetAbsOrigin() + Vheight
    local to = player:GetAbsOrigin() + Vheight
    if from and to then
        return VisPos(player, from, to)
    else
        return false
    end
end

-- Function to get the best target
local function GetBestTarget(me)
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end
    if not players then return end

    -- Collect candidates
    local normalCandidates = {} -- { {player=Entity, factor=number} }

    local meleeCandidates = {}

    -- Range threshold - use TotalSwingRange plus a buffer of 50 units
    local meleeRangeThreshold = TotalSwingRange + 50
    local foundTargetInMeleeRange = false

    local localPlayerViewAngles = engine.GetViewAngles()
    local localPlayerOrigin = localPlayer:GetAbsOrigin()
    local localPlayerEyePos = localPlayerOrigin + Vector3(0, 0, 75)

    -- Use configured FOV without restrictions
    local effectiveFOV = Menu.Aimbot.AimbotFOV

    for _, player in pairs(players) do
        if player == nil
            or not player:IsValid()
            or not player:IsAlive()
            or player:IsDormant()
            or player == me or player:GetTeamNumber() == me:GetTeamNumber()
            or (gui.GetValue("ignore cloaked") == 1 and player:InCond(4))
            or (me:InCond(17) and (player:GetAbsOrigin().z - me:GetAbsOrigin().z) > 17)
            or not IsVisible(player, me) then
            goto continue
        end

        local playerOrigin = player:GetAbsOrigin()
        local distance = (playerOrigin - localPlayerOrigin):Length()
        local Pviewoffset = player:GetPropVector("localdata", "m_vecViewOffset[0]")
        local Pviewpos = playerOrigin + Pviewoffset

        -- Check if player is in FOV
        local angles = Math.PositionAngles(localPlayerOrigin, Pviewpos)
        local fov = Math.AngleFov(localPlayerViewAngles, angles)
        if fov > effectiveFOV then
            goto continue
        end

        -- Check if target is visible
        local isVisible = Helpers.VisPos(player, localPlayerEyePos, playerOrigin + Vector3(0, 0, 75))
        local visibilityFactor = isVisible and 1 or 0.1

        -- First priority: targets within melee range
        if distance <= meleeRangeThreshold then
            foundTargetInMeleeRange = true
            -- Base factor for melee targets
            local meleeFovFactor = Math.RemapValClamped(fov, 0, effectiveFOV, 1, 0.7)
            local factor = meleeFovFactor * visibilityFactor
            table.insert(meleeCandidates, { player = player, factor = factor })
        elseif distance <= 770 then
            -- Standard targets
            local distanceFactor = Math.RemapValClamped(distance, settings.MinDistance, settings.MaxDistance, 1, 0.9)
            local fovFactor = Math.RemapValClamped(fov, 0, effectiveFOV, 1, 0.1)
            local factor = distanceFactor * fovFactor * visibilityFactor
            table.insert(normalCandidates, { player = player, factor = factor })
        end
        ::continue::
    end

    -- Helper: choose best from candidates, applying health weighting if multiple
    local function chooseBest(cands)
        if #cands == 0 then return nil end
        -- If more than one, apply health weight
        if #cands > 1 then
            for _, c in ipairs(cands) do
                local p = c.player
                local hp = p:GetHealth() or 0
                local maxhp = p:GetPropInt("m_iMaxHealth") or hp
                local missing = (maxhp > 0) and ((maxhp - hp) / maxhp) or 0
                c.factor = c.factor * (1 + missing)
            end
        end
        -- Pick max
        local best = cands[1]
        for i = 2, #cands do
            if cands[i].factor > best.factor then best = cands[i] end
        end
        return best.player
    end

    if foundTargetInMeleeRange then
        return chooseBest(meleeCandidates)
    else
        return chooseBest(normalCandidates)
    end
end

-- Closest point on player AABB (vHitbox relative to target origin) — cheap prefilter only
local function closestPointOnTargetHitbox(targetOrigin, fromPoint)
    return Simulation.ClosestPointOnHitbox(targetOrigin, fromPoint)
end

--[[
    Approximate C++ CAimbotMelee::CanHit sweep: ray along eye→aim, length = weapon swing range (not total+hull),
    then hull trace with melee bounds. AABB closest-point only decides "worth tracing".
]]
local function meleeSwingCanHitSimulate(eyePos, aimPoint, targetEntity, weaponSwingRange, hullHalf)
    return Simulation.MeleeSwingCanHit(eyePos, aimPoint, targetEntity, weaponSwingRange, hullHalf, pLocal)
end

-- sphereRadius = generous reach for AABB prefilter (e.g. TotalSwingRange); swing trace uses global swingrange
local function checkInRange(targetPos, spherePos, sphereRadius)
    local closestPoint = closestPointOnTargetHitbox(targetPos, spherePos)
    local distanceAlongVector = (spherePos - closestPoint):Length()

    if sphereRadius <= distanceAlongVector then
        return false, nil
    end

    if Menu.Misc.advancedHitreg then
        local wr = swingrange
        local hh = SwingHalfhullSize
        if not wr or wr <= 0 or not CurrentTarget then
            return false, nil
        end
        if not meleeSwingCanHitSimulate(spherePos, closestPoint, CurrentTarget, wr, hh) then
            return false, nil
        end
    end

    return true, closestPoint
end

local Hitbox = {
    Head = 1,
    Neck = 2,
    Pelvis = 4,
    Body = 5,
    Chest = 7
}

local function calculateMaxAngleChange(currentVelocity, minVelocity, maxTurnRate)
    -- Assuming a linear relationship between turn rate and velocity drop
    -- More complex relationships will require a more sophisticated model

    -- If current velocity is already below the threshold, no turning is allowed
    if currentVelocity < minVelocity then
        return 0
    end

    -- Calculate the proportion of velocity we can afford to lose
    local velocityBuffer = currentVelocity - minVelocity

    -- Assuming maxTurnRate is the turn rate at which the velocity would drop to zero
    -- Calculate the maximum turn rate that would reduce the velocity to the threshold
    local maxSafeTurnRate = (velocityBuffer / currentVelocity) * maxTurnRate

    return maxSafeTurnRate
end

-- At the top of the file, after the initial libraries and imports

-- Constants for charge control
local CHARGE_CONSTANTS = {
    TURN_MULTIPLIER = 1.0,
    MAX_ROTATION_PER_FRAME = 73.04,
    SIDE_MOVE_VALUE = 450
}

-- State tracking variables
local prevCharging = false

-- Condition IDs
local CONDITIONS = {
    CHARGING = 17
}

-- Improved ChargeControl function that incorporates logic from Charge_controll.lua
local function ChargeControl(pCmd)
    -- Check if charge control is enabled in the menu
    if not Menu.Charge.ChargeControl then
        return
    end

    -- Skip if not charging
    if not pLocal or not pLocal:IsValid() or not pLocal:InCond(17) then
        return
    end

    -- Find all demo shields by class name
    local shields = entities.FindByClass("CTFWearableDemoShield")

    -- Check if any shield belongs to player and is Tide Turner
    for i, shield in pairs(shields) do
        if shield and shield:IsValid() then
            local owner = shield:GetPropEntity("m_hOwnerEntity")

            if owner == pLocal then
                local defIndex = shield:GetPropInt("m_iItemDefinitionIndex")

                -- Check if it's Tide Turner (ID 1099)
                if defIndex == 1099 then
                    -- Skip charge control for Tide Turner
                    return
                end
            end
        end
    end

    -- Get mouse X movement (negative = left, positive = right)
    local mouseDeltaX = -pCmd.mousedx

    -- Skip processing if no horizontal mouse movement
    if mouseDeltaX == 0 then
        return
    end

    -- Get current view angles and game settings
    local currentAngles = engine.GetViewAngles()
    local m_yaw = select(2, client.GetConVar("m_yaw")) -- Get m_yaw from game settings

    -- Calculate turn amount using standard Source engine formula
    local turnAmount = mouseDeltaX * m_yaw * CHARGE_CONSTANTS.TURN_MULTIPLIER

    -- Apply side movement based on turning direction (simulate A/D keys)
    if turnAmount > 0 then
        -- Turning left, simulate pressing D (right strafe)
        pCmd.sidemove = CHARGE_CONSTANTS.SIDE_MOVE_VALUE
    else
        -- Turning right, simulate pressing A (left strafe)
        pCmd.sidemove = -CHARGE_CONSTANTS.SIDE_MOVE_VALUE
    end

    -- CRITICAL: Limit maximum turn per frame to 73.04 degrees
    turnAmount = Clamp(turnAmount, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)

    -- Calculate new yaw angle
    local newYaw = currentAngles.yaw + turnAmount

    -- Handle -180/180 degree boundary crossing
    newYaw = newYaw % 360
    if newYaw > 180 then
        newYaw = newYaw - 360
    elseif newYaw < -180 then
        newYaw = newYaw + 360
    end

    -- Set the new view angles
    engine.SetViewAngles(EulerAngles(currentAngles.pitch, newYaw, currentAngles.roll))
end

local acceleration = 750

local function UpdateHomingMissile()
    if not pLocal or not pLocal:IsValid() then
        return nil
    end
    if not vPlayer or not vPlayer:IsValid() then
        return nil
    end
    if not vPlayerOrigin then
        return nil
    end

    local pLocalPos = pLocal:GetAbsOrigin()
    local vPlayerPos = vPlayerOrigin
    local pLocalVel = pLocal:EstimateAbsVelocity()
    local vPlayerVel = vPlayer:EstimateAbsVelocity()

    local timeStep = globals.TickInterval() -- Time step for simulation
    local interceptPoint = nil
    local interceptTime = 0

    while interceptTime <= 3 do
        -- Simulate the target's next position
        vPlayerPos = vPlayerPos + (vPlayerVel * timeStep)

        -- Calculate the distance to the target's new position
        local distanceToTarget = (vPlayerPos - pLocalPos):Length()

        -- Calculate the time it would take for Demoman to reach this distance
        -- with the given acceleration (using the formula: d = 0.5 * a * t^2)
        local timeToReach = math.sqrt(2 * distanceToTarget / acceleration)

        if timeToReach <= interceptTime then
            interceptPoint = vPlayerPos
            break
        end

        interceptTime = interceptTime + timeStep
    end

    if interceptPoint then
        return interceptPoint
    end
end

local hasNotified = false
local function checkInRangeSimple(playerIndex, swingRange, pWeapon, cmd)
    local inRange = false
    local point = nil

    -- Simple range check with current positions
    inRange, point = checkInRange(vPlayerOrigin, pLocalOrigin, swingRange)
    if inRange then
        return inRange, point, false
    end

    -- If instant attack (warp) is ready, skip future prediction checks.
    local instantAttackReady = Menu.Misc.InstantAttack and warp.CanWarp() and
        warp.GetChargedTicks() >= Menu.Aimbot.SwingTime
    if instantAttackReady then
        return false, nil, false
    end

    -- Simple range check with predicted positions
    inRange, point = checkInRange(vPlayerFuture, pLocalFuture, swingRange)
    if inRange then
        return inRange, point, false
    end

    return false, nil, false
end

-- Store the original Crit Hack Key value outside the main loop or function
local originalCritHackKey = 0
local originalMeleeCritHack = 0
local menuWasOpen = false
local critRefillActive = false
local dashKeyNotBoundNotified = true

--[[ Code needed to run 66 times a second ]] --
-- Predicts player position after set amount of ticks
local function OnCreateMove(pCmd)
    -- Clear ALL entity variables at start of every tick to prevent stale references
    pLocal = nil
    pWeapon = nil
    players = nil
    CurrentTarget = nil
    vPlayer = nil
    pLocalClass = nil
    pLocalFuture = nil
    pLocalOrigin = nil
    vPlayerFuture = nil
    vPlayerOrigin = nil
    chargeLeft = nil
    onGround = nil
    aimposVis = nil
    Latency = nil
    viewheight = nil
    Vheight = nil

    -- Clear visual data
    pLocalPath = {}
    vPlayerPath = {}
    drawVhitbox = {}

    -- Reset state flags
    isMelee = false
    can_attack = false
    can_charge = false

    -- Get the local player entity
    pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        goto continue -- Return if the local player entity doesn't exist or is dead
    end

    -- Update stepSize per-tick based on current player
    stepSize = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18
    Simulation.UpdatePhysics(gravity, stepSize, vHitbox)

    -- Track latest +attack input (from user or script) for charge-reach logic
    if (pCmd:GetButtons() & IN_ATTACK) ~= 0 then
        lastAttackTick = globals.TickCount()
        Simulation.SetLastAttackTick(lastAttackTick)
    end

    -- Quick reference values used multiple times
    pLocalClass = pLocal:GetPropInt("m_iClass")
    chargeLeft  = pLocal:GetPropFloat("m_flChargeMeter")

    -- ===== Charge Reach State Machine (Demoman only) =====
    if pLocalClass == 4 then
        if chargeState == "aim" then
            if chargeAimAngles then
                engine.SetViewAngles(EulerAngles(chargeAimAngles.pitch, chargeAimAngles.yaw, 0))
            end
            chargeState = "charge" -- next tick will trigger charge
        elseif chargeState == "charge" then
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)
            chargeState = "idle"
            chargeAimAngles = nil
        end
    else
        -- Not Demoman: never drive charge reach state machine
        chargeState = "idle"
        chargeAimAngles = nil
    end
    -- =====================================

    -- Show notification if instant attack is enabled but dash key is not bound
    if Menu.Misc.InstantAttack and gui.GetValue("dash move key") == 0 and not dashKeyNotBoundNotified then
        Notify.Simple("Instant Attack Warning", "Dash key is not bound. Instant Attack will not work properly.", 4)
        dashKeyNotBoundNotified = true
    elseif (not Menu.Misc.InstantAttack or gui.GetValue("dash move key") ~= 0) and dashKeyNotBoundNotified then
        dashKeyNotBoundNotified = false
    end

    local fChargeBeginTime = (pLocal:GetPropFloat("PipebombLauncherLocalData", "m_flChargeBeginTime") or 0);

    -- Check if the local player is a spy
    pLocalClass = pLocal:GetPropInt("m_iClass")
    if pLocalClass == nil or pLocalClass == 8 then
        goto continue -- Skip the rest of the code if the local player is a spy or hasn't chosen a class
    end

    -- Get the local player's active weapon
    pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon then
        goto continue -- Return if the local player doesn't have an active weapon
    end
    local nextPrimaryAttack = pWeapon:GetPropFloat("LocalActiveWeaponData", "m_flNextPrimaryAttack")
    --print(Conversion.Time_to_Ticks(nextPrimaryAttack) .. "LastShoot", globals.TickCount())

    -- Latency compensation removed - TF2 handles this automatically

    -- Get the local player's flags and charge meter
    local flags = pLocal:GetPropInt("m_fFlags")
    local airbone = pLocal:InCond(81)
    chargeLeft = pLocal:GetPropFloat("m_flChargeMeter")
    chargeLeft = math.floor(chargeLeft)

    -- Get the local player's active weapon data and definition
    local pWeaponData = pWeapon:GetWeaponData()
    local pWeaponID = pWeapon:GetWeaponID()
    local pWeaponDefIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
    local pWeaponDef = itemschema.GetItemDefinitionByID(pWeaponDefIndex)
    local pWeaponName = pWeaponDef:GetName()
    local pUsingMargetGarden = false

    if pWeaponDefIndex == 416 then
        pUsingMargetGarden = true
    end

    --[--Troldier assist--]
    if Menu.Misc.TroldierAssist then
        local state = ""
        if airbone then
            pCmd:SetButtons(pCmd.buttons | IN_DUCK)
            state = "slot3"
        else
            state = "slot1"
        end

        client.Command(state, true)
    end

    --[-Don`t run script below when not usign melee--]

    isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon
    if not isMelee then
        goto continue
    end -- if not melee then skip code

    --[-------Get pLocalOrigin--------]

    -- Get pLocal eye level and set vector at our eye level to ensure we check distance from eyes
    local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") -- Vector3(0, 0, 70)
    local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
    viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()

    -- Eye level
    Vheight = Vector3(0, 0, viewheight)
    pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)

    --[-------- Get SwingRange --------]
    local weaponSwingRange = pWeapon:GetSwingRange() or swingrange
    swingrange = weaponSwingRange

    SwingHullSize = 35.6

    if pWeaponDef:GetName() == "The Disciplinary Action" then
        SwingHullSize = 55.8
        swingrange = 81.6
    end

    SwingHalfhullSize = SwingHullSize / 2

    -- Store normal weapon range when NOT charging (this is the true weapon range)
    local isCurrentlyCharging = pLocal:InCond(17)
    if not isCurrentlyCharging then
        normalWeaponRange = swingrange or normalWeaponRange
        normalTotalSwingRange = swingrange + (SwingHullSize / 2)
    end

    -- Simple charge reach logic
    local hasFullCharge = chargeLeft == 100
    local isDemoman = pLocalClass == 4
    local isExploitReady = Menu.Charge.ChargeReach and hasFullCharge and isDemoman
    local attackWindowTicks = Menu.Aimbot.MaxSwingTime or 13
    if pWeaponData and pWeaponData.smackDelay then
        attackWindowTicks = smackDelayToTicks(pWeaponData.smackDelay)
    end
    local withinAttackWindow = (globals.TickCount() - lastAttackTick) <= attackWindowTicks

    if isCurrentlyCharging then
        -- When charging: check if we swung within the current weapon's swing window
        local isDoingExploit = Menu.Charge.ChargeReach and withinAttackWindow

        if isDoingExploit then
            -- Use charge reach range (128) + hull size for total range
            TotalSwingRange = Charge_Range + (SwingHullSize / 2)
            --client.ChatPrintf("[Debug] Charge reach exploit active! TotalSwingRange = " .. TotalSwingRange)
        else
            -- Force back to normal weapon range
            swingrange = normalWeaponRange or swingrange
            TotalSwingRange = normalTotalSwingRange
            --client.ChatPrintf("[Debug] Charging without exploit, TotalSwingRange = " .. TotalSwingRange)
        end
    else
        -- Not charging: check if ready for exploit
        if isExploitReady then
            -- Use charge reach range (128) + hull size when ready
            TotalSwingRange = Charge_Range + (SwingHullSize / 2)
        else
            -- Normal weapon range
            TotalSwingRange = swingrange + (SwingHullSize / 2)
        end
    end
    --[--Manual charge control--]

    if Menu.Charge.ChargeControl and pLocal:InCond(17) then
        ChargeControl(pCmd)
    end

    --[-----Get best target------------------]
    local keybind = Menu.Keybind

    -- Get fresh player list each tick
    players = entities.FindByClass("CTFPlayer")

    if keybind == 0 then
        -- Check if player has no key bound
        CurrentTarget = GetBestTarget(pLocal)
        vPlayer = CurrentTarget
    elseif input.IsButtonDown(keybind) then
        -- If player has bound key for aimbot, only work when it's on
        CurrentTarget = GetBestTarget(pLocal)
        vPlayer = CurrentTarget
    else
        CurrentTarget = nil
        vPlayer = nil
    end

    ---------------critHack------------------
    -- Main logic

    -- Check if menu is open to capture user settings
    local menuIsOpen = gui.IsMenuOpen()

    -- If menu just opened, update our stored values
    if menuIsOpen and not menuWasOpen then
        originalCritHackKey = gui.GetValue("Crit Hack Key")
        originalMeleeCritHack = gui.GetValue("Melee Crit Hack")
    end

    -- Update menu state for next frame
    menuWasOpen = menuIsOpen

    -- Only proceed with crit refill logic when menu is closed
    if not menuIsOpen and pWeapon then
        local CritValue = 39 -- Base value for crit token bucket calculation
        local CritBucket = pWeapon:GetCritTokenBucket()
        local NumCrits = CritValue * Menu.Misc.CritRefill.NumCrits

        -- Cap NumCrits to ensure CritBucket does not exceed 1000
        NumCrits = Clamp(NumCrits, 27, 1000)

        if CurrentTarget == nil and Menu.Misc.CritRefill.Active then
            -- Check if we need to refill the crit bucket
            if CritBucket < NumCrits then
                -- Start crit refill mode if not already active
                if not critRefillActive then
                    gui.SetValue("Crit Hack Key", 0)   -- Disable crit hack key
                    gui.SetValue("Melee Crit Hack", 2) -- Set to "Stop" mode to store crits
                    critRefillActive = true
                end

                -- Keep attacking to build crits
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            else
                -- Crit bucket is full, restore user settings
                if critRefillActive then
                    gui.SetValue("Crit Hack Key", originalCritHackKey)
                    gui.SetValue("Melee Crit Hack", Menu.Misc.CritMode)
                    critRefillActive = false
                end
            end
        else
            -- We have a target or refill is disabled, restore settings if needed
            if critRefillActive then
                gui.SetValue("Crit Hack Key", originalCritHackKey)
                gui.SetValue("Melee Crit Hack", Menu.Misc.CritMode)
                critRefillActive = false
            end
        end
    end

    local Target_ONGround
    local strafeAngle = 0
    can_attack = false
    local stop = false
    local OnGround = (flags & FL_ONGROUND) ~= 0

    --[[--------------Modular Charge-Jump (manual) -------------------]]
    if Menu.Charge.ChargeJump and pLocalClass == 4 then
        if (pCmd:GetButtons() & IN_ATTACK2) ~= 0 and chargeLeft == 100 and OnGround then
            -- Add jump along with existing charge command
            pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
        end
    end

    --[--------------Prediction-------------------]
    -- Predict both players' positions after swing
    gravity = client.GetConVar("sv_gravity") or 800
    stepSize = pLocal:GetPropFloat("localdata", "m_flStepSize") or stepSize

    -- Ensure players list is populated before using in CalcStrafe
    if not players then
        players = entities.FindByClass("CTFPlayer")
    end
    CalcStrafe()

    -- Shared swing lookahead: full ticks for warp / charge-start lookahead; shorter when mid windup (m_flSmackTime)
    local instantAttackReady = Menu.Misc.InstantAttack and warp.CanWarp() and
        warp.GetChargedTicks() >= Menu.Aimbot.SwingTime
    local simulateCharge = (not isCurrentlyCharging) and isExploitReady and (not Menu.Charge.LateCharge)
    local simTicks = Menu.Aimbot.SwingTime
    if not instantAttackReady and not simulateCharge then
        local remSwing = getMeleeSwingTicksRemaining(pWeapon)
        if remSwing then
            simTicks = math.max(remSwing, 1)
        end
    end

    -- Local player prediction
    if pLocal:EstimateAbsVelocity() == 0 then
        -- If the local player is not accelerating, set the predicted position to the current position
        pLocalFuture = pLocalOrigin
    else
        -- Always predict local player movement regardless of instant attack state
        local player = WPlayer.FromEntity(pLocal)

        -- Don't use strafe prediction when warping (time is frozen for us too)
        local useStrafePred = Menu.Misc.strafePred and not (instantAttackReady and Menu.Misc.WarpOnAttack)
        strafeAngle = useStrafePred and strafeAngles[pLocal:GetIndex()] or 0

        -- If charge-reach exploit is READY (full meter, demo, exploit enabled) but we're **not yet charging**,
        -- run a secondary prediction that simulates starting a charge right now.
        local fixedAngles = nil
        if simulateCharge and CurrentTarget then
            -- Use current target's position to define intended charge heading for prediction
            fixedAngles = Math.PositionAngles(pLocalOrigin, CurrentTarget:GetAbsOrigin())
        end

        local predData = Simulation.PredictPlayer(player, simTicks, strafeAngle, simulateCharge, fixedAngles)
        if not predData then return end

        pLocalPath = predData.pos
        pLocalFuture = predData.pos[simTicks] + viewOffset
    end

    -- stop if no target
    if CurrentTarget == nil then
        return
    end

    -- Validate target is still valid (alive, not dormant, etc.)
    if not CurrentTarget:IsValid() or not CurrentTarget:IsAlive() or CurrentTarget:IsDormant() then
        return
    end

    vPlayerOrigin = CurrentTarget:GetAbsOrigin() -- Get closest player origin

    local VpFlags = CurrentTarget:GetPropInt("m_fFlags")
    local DUCKING = (VpFlags & FL_DUCKING) ~= 0
    if DUCKING then
        vHitbox[2].z = 62
    else
        vHitbox[2].z = 82
    end

    local canInstantAttack = instantAttackReady

    -- Debug output for instant attack status (only when instant attack is enabled)
    if Menu.Misc.InstantAttack and can_attack then
        local chargedTicks = warp.GetChargedTicks() or 0
        local canWarp = warp.CanWarp()
        local swingTime = Menu.Aimbot.SwingTime
        client.ChatPrintf(string.format(
            "[Debug] InstantAttack Check: CanWarp=%s, ChargedTicks=%d, SwingTime=%d, Ready=%s",
            tostring(canWarp), chargedTicks, swingTime, tostring(instantAttackReady)))
    end

    if not instantAttackReady then
        -- Only predict enemy movement when NOT using instant attack
        local player = WPlayer.FromEntity(CurrentTarget)
        strafeAngle = strafeAngles[CurrentTarget:GetIndex()] or 0

        local predData = Simulation.PredictPlayer(player, simTicks, strafeAngle, false, nil)
        if not predData then return end

        vPlayerPath = predData.pos
        vPlayerFuture = predData.pos[simTicks]

        drawVhitbox[1] = vPlayerFuture + vHitbox[1]
        drawVhitbox[2] = vPlayerFuture + vHitbox[2]
    else
        -- When using instant attack, enemy doesn't move (time is frozen for them)
        vPlayerFuture = CurrentTarget:GetAbsOrigin()
        drawVhitbox[1] = vPlayerFuture + vHitbox[1]
        drawVhitbox[2] = vPlayerFuture + vHitbox[2]
    end

    --[--------------Distance check using TotalSwingRange-------------------]
    -- Get current distance between local player and closest player
    local vdistance = (vPlayerOrigin - pLocalOrigin):Length()

    -- Get distance between local player and closest player after swing
    local fDistance = (vPlayerFuture - pLocalFuture):Length()
    local inRange = false
    local inRangePoint = nil

    -- Use TotalSwingRange for range checking (already calculated with charge reach logic)
    if not CurrentTarget then
        goto continue
    end
    inRange, inRangePoint, can_charge = checkInRangeSimple(CurrentTarget:GetIndex(), TotalSwingRange, pWeapon, pCmd)
    -- Use inRange to decide if can attack
    can_attack = inRange

    --[--------------AimBot-------------------]
    local aimpos = CurrentTarget:GetAbsOrigin() + Vheight

    -- Inside your game loop
    if Menu.Aimbot.Aimbot then
        local aim_angles
        if inRangePoint then
            aimpos = inRangePoint
            aimposVis = aimpos -- transfer aim point to visuals

            -- Calculate aim position only once
            aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
            aim_angles = aimpos
        end

        -- Charge-bot steering only relevant to Demoman shield charge (class 4)
        if Menu.Aimbot.ChargeBot and pLocalClass == 4 and pLocal:InCond(17) and not can_attack then
            local trace = engine.TraceHull(pLocalOrigin, inRangePoint or vPlayerFuture, vHitbox[1], vHitbox[2],
                MASK_PLAYERSOLID_BRUSHONLY)
            if trace.fraction == 1 or trace.entity == CurrentTarget then
                -- If the trace hit something, set the view angles to the position of the hit
                local aimPosTarget = inRangePoint or vPlayerFuture
                if aimPosTarget then
                    aim_angles = Math.PositionAngles(pLocalOrigin, aimPosTarget)
                end
                -- Limit yaw change to MAX_CHARGE_BOT_TURN per tick
                local currentAng = engine.GetViewAngles()
                local yawDiff = NormalizeYaw(aim_angles.yaw - currentAng.yaw)
                local limitedYaw = currentAng.yaw + Clamp(yawDiff, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
                engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
            end
        elseif Menu.Aimbot.ChargeBot and pLocalClass == 4 and chargeLeft == 100 and input.IsButtonDown(MOUSE_RIGHT) and not can_attack and fDistance < 750 then
            local trace = engine.TraceHull(pLocalFuture, inRangePoint or vPlayerFuture, vHitbox[1], vHitbox[2],
                MASK_PLAYERSOLID_BRUSHONLY)
            if trace.fraction == 1 or trace.entity == CurrentTarget then
                -- If the trace hit something, set the view angles to the position of the hit
                local aimPosTarget = inRangePoint or vPlayerFuture
                if aimPosTarget then
                    aim_angles = Math.PositionAngles(pLocalOrigin, aimPosTarget)
                end
                -- Limit yaw change to MAX_CHARGE_BOT_TURN per tick
                local currentAng = engine.GetViewAngles()
                local yawDiff = NormalizeYaw(aim_angles.yaw - currentAng.yaw)
                local limitedYaw = currentAng.yaw + Clamp(yawDiff, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
                engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
            end
        elseif can_attack and aim_angles and aim_angles.pitch and aim_angles.yaw then
            -- Use normal aimbot behavior regardless of charging state
            if not Menu.Aimbot.Silent then
                engine.SetViewAngles(EulerAngles(aim_angles.pitch, aim_angles.yaw, 0))
            end
        end
    end



    -- Only try instant attack when it's possible
    if can_attack then
        -- Get the actual weapon smack delay if available
        local weaponSmackDelay = 13 -- Default fallback value
        if pWeapon and pWeapon:GetWeaponData() then
            local weaponData = pWeapon:GetWeaponData()
            if weaponData and weaponData.smackDelay then
                weaponSmackDelay = smackDelayToTicks(weaponData.smackDelay)

                -- Update the menu's SwingTime setting to match the current weapon's properties
                -- Only update if it's different to avoid constant updates
                if Menu.Aimbot.SwingTime ~= weaponSmackDelay then
                    local oldValue = Menu.Aimbot.SwingTime or 13 -- Add default value if nil

                    -- If user has enabled "Always Use Max", or set the value to the current max,
                    -- update the swing time to the new maximum
                    if Menu.Aimbot.AlwaysUseMaxSwingTime or oldValue >= (Menu.Aimbot.MaxSwingTime or 13) then
                        Menu.Aimbot.SwingTime = weaponSmackDelay
                    end

                    -- Update the maximum swing time value for the slider
                    Menu.Aimbot.MaxSwingTime = weaponSmackDelay

                    -- Display notification about the change with weapon name
                    pWeaponName = "Unknown"
                    pcall(function()
                        pWeaponDefIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
                        pWeaponDef = itemschema.GetItemDefinitionByID(pWeaponDefIndex)
                        pWeaponName = pWeaponDef and pWeaponDef:GetName() or "Unknown"
                    end)

                    -- Display formatted notification with more details
                    Notify.Simple(string.format(
                        "Updated SwingTime for %s:\n - Old value: %d ticks\n - New value: %d ticks\n - Actual delay: %.2f seconds",
                        pWeaponName,
                        oldValue,
                        Menu.Aimbot.SwingTime or weaponSmackDelay,
                        weaponData.smackDelay
                    ))
                end
            end
        end

        local scheduledAimAngles = nil
        if inRangePoint then
            scheduledAimAngles = Math.PositionAngles(pLocalOrigin, inRangePoint)
        else
            scheduledAimAngles = Math.PositionAngles(pLocalOrigin, vPlayerFuture)
        end

        if Menu.Misc.InstantAttack and canInstantAttack and Menu.Misc.WarpOnAttack then
            -- Instant attack with warp is enabled and ready
            local velocity = pLocal:EstimateAbsVelocity()
            local oppositePoint

            -- Calculate opposite point for movement
            if velocity:Length() > 10 then
                oppositePoint = pLocal:GetAbsOrigin() - velocity
            else
                local angles = engine.GetViewAngles()
                local forward = angles:Forward()
                oppositePoint = pLocal:GetAbsOrigin() + forward * 20
            end

            -- Move to opposite point for better warp positioning
            if oppositePoint and (oppositePoint - pLocal:GetAbsOrigin()):Length() < 300 then
                Simulation.WalkTo(pCmd, pLocal, oppositePoint)
            end

            -- Set up the attack and warp
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK) -- Initiate attack
            applySilentAttackTick(pCmd, scheduledAimAngles)

            client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
            local safeTickValue = math.min(weaponSmackDelay, 20)
            client.SetConVar("sv_maxusrcmdprocessticks", safeTickValue)

            -- Trigger the warp
            local chargedTicks = warp.GetChargedTicks() or 0
            if chargedTicks >= safeTickValue then
                warp.TriggerWarp()
                -- Debug output
                client.ChatPrintf("[Debug] Instant Attack: Warping with " .. chargedTicks .. " ticks")
            else
                -- Not enough ticks for warp, but still do instant attack without warp
                client.ChatPrintf("[Debug] Instant Attack: Not enough ticks (" ..
                    chargedTicks .. "/" .. safeTickValue .. "), normal attack")
            end

            can_attack = false
        elseif Menu.Misc.InstantAttack and canInstantAttack and not Menu.Misc.WarpOnAttack then
            -- Instant attack enabled but warp disabled - just do normal attack
            client.ChatPrintf("[Debug] Instant Attack: Warp disabled, using normal attack")
            local normalAttackTicks = math.min(weaponSmackDelay, 24)
            client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
            client.SetConVar("sv_maxusrcmdprocessticks", normalAttackTicks)
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            applySilentAttackTick(pCmd, scheduledAimAngles)
            can_attack = false
        else
            -- Normal attack (instant attack disabled or not ready)
            local normalAttackTicks = math.min(weaponSmackDelay, 24)
            client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
            client.SetConVar("sv_maxusrcmdprocessticks", normalAttackTicks)
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            applySilentAttackTick(pCmd, scheduledAimAngles)

            -- Start tracking attack ticks for charge reach exploit
            if pLocalClass == 4 and Menu.Charge.ChargeReach and chargeLeft == 100 and not attackStarted then
                attackStarted = true
                attackTickCount = 0
                -- Store aim direction to target future position so charge travels correctly
                if inRangePoint then
                    chargeAimAngles = Math.PositionAngles(pLocalOrigin, inRangePoint)
                else
                    chargeAimAngles = Math.PositionAngles(pLocalOrigin, vPlayerFuture)
                end
            end

            can_attack = false
        end

        -- Track attack ticks and execute charge at right moment
        if attackStarted then
            attackTickCount = attackTickCount + 1

            -- Get weapon smack delay (when the weapon will hit)
            local weaponSmackDelayTicks = Menu.Aimbot.MaxSwingTime or 13
            local wd = pWeapon and pWeapon:GetWeaponData()
            if wd and wd.smackDelay then
                weaponSmackDelayTicks = smackDelayToTicks(wd.smackDelay)
            end

            -- If charge-jump enabled issue jump together with charge
            if Menu.Charge.ChargeJump and OnGround then
                pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
            end

            -- Fire +attack2 when within latency/choke window of impact (same idea as reference melee charge-reach)
            local chargeWindow = getChargeReachWindowTicks()
            local ticksToSmack = getMeleeSwingTicksRemaining(pWeapon)
            local shouldTriggerCharge = false
            if ticksToSmack then
                shouldTriggerCharge = ticksToSmack <= chargeWindow
            else
                shouldTriggerCharge = attackTickCount >= math.max(weaponSmackDelayTicks - 2, 1)
            end

            if shouldTriggerCharge then
                -- Schedule aim then charge via state machine
                chargeState = "aim" -- on this tick we aim; next tick we charge
                -- Reset attack tracking
                attackStarted = false
                attackTickCount = 0
            end
        end

        -- No need to track exploit flag anymore; logic is purely timing-based
    end

    -- Update last variables
    vHitbox[2].z = 82
    ::continue::
end

local bindTimer = 0
local bindDelay = 0.25 -- Delay of 0.25 seconds

local function handleKeybind(noKeyText, keybind, keybindName)
    if keybindName ~= "Press The Key" and ImMenu.Button(keybindName or noKeyText) then
        bindTimer = os.clock() + bindDelay
        keybindName = "Press The Key"
    elseif keybindName == "Press The Key" then
        ImMenu.Text("Press the key")
    end

    if keybindName == "Press The Key" then
        if os.clock() >= bindTimer then
            local pressedKey = GetPressedkey()
            if pressedKey then
                if pressedKey == KEY_ESCAPE then
                    -- Reset keybind if the Escape key is pressed
                    keybind = 0
                    keybindName = "Always On"
                    Notify.Simple("Keybind Success", "Bound Key: " .. keybindName, 2)
                else
                    -- Update keybind with the pressed key
                    keybind = pressedKey
                    keybindName = Input.GetKeyName(pressedKey)
                    Notify.Simple("Keybind Success", "Bound Key: " .. keybindName, 2)
                end
            end
        end
    end
    return keybind, keybindName
end

--[[ Code called every frame ]] --
local function doDraw()
    -- Render menu UI even when dead or visuals disabled
    if gui.IsMenuOpen() and ImMenu and ImMenu.Begin("Swing Prediction") then
        ImMenu.BeginFrame(1) -- tabs
        Menu.currentTab = ImMenu.TabControl(Menu.tabs, Menu.currentTab)
        ImMenu.EndFrame()

        if Menu.currentTab == 1 then -- Aimbot tab
            ImMenu.BeginFrame(1)
            Menu.Aimbot.Aimbot = ImMenu.Checkbox("Enable", Menu.Aimbot.Aimbot)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Aimbot.Silent = ImMenu.Checkbox("Silent Aim", Menu.Aimbot.Silent)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Aimbot.AimbotFOV = ImMenu.Slider("Fov", Menu.Aimbot.AimbotFOV, 1, 360)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            -- Use dynamic maximum value from the current weapon's smack delay
            local swingTimeMaxDisplay = Menu.Aimbot.MaxSwingTime or 13 -- Add default value if nil
            local swingTimeLabel = string.format("Swing Time (max: %d)", swingTimeMaxDisplay)
            Menu.Aimbot.SwingTime = ImMenu.Slider(swingTimeLabel, Menu.Aimbot.SwingTime, 1, swingTimeMaxDisplay)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Aimbot.AlwaysUseMaxSwingTime = ImMenu.Checkbox("Always Use Max Swing Time",
                Menu.Aimbot.AlwaysUseMaxSwingTime)
            -- If the user enables "Always Use Max", automatically set the value to max
            if Menu.Aimbot.AlwaysUseMaxSwingTime then
                Menu.Aimbot.SwingTime = Menu.Aimbot.MaxSwingTime or 13 -- Add default value if nil
            end
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            ImMenu.Text("Keybind: ")
            Menu.Keybind, Menu.KeybindName = handleKeybind("Always On", Menu.Keybind, Menu.KeybindName)
            ImMenu.EndFrame()
        end

        if Menu.currentTab == 2 then -- Demoknight tab
            ImMenu.BeginFrame(1)
            local oldValue = Menu.Charge.ChargeBot
            Menu.Charge.ChargeBot = ImMenu.Checkbox("Charge Bot", Menu.Charge.ChargeBot)
            -- If the value changed, synchronize with the Aimbot setting
            if oldValue ~= Menu.Charge.ChargeBot then
                Menu.Aimbot.ChargeBot = Menu.Charge.ChargeBot
            end
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            local oldChargeControl = Menu.Charge.ChargeControl
            Menu.Charge.ChargeControl = ImMenu.Checkbox("Charge Control", Menu.Charge.ChargeControl)
            -- If the value changed, synchronize with the Misc setting
            if oldChargeControl ~= Menu.Charge.ChargeControl then
                Menu.Misc.ChargeControl = Menu.Charge.ChargeControl
            end
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            local oldChargeReach = Menu.Charge.ChargeReach
            Menu.Charge.ChargeReach = ImMenu.Checkbox("Charge Reach", Menu.Charge.ChargeReach)
            -- If the value changed, synchronize with the Misc setting
            if oldChargeReach ~= Menu.Charge.ChargeReach then
                Menu.Misc.ChargeReach = Menu.Charge.ChargeReach
            end
            -- Late Charge option appears only if Charge Reach enabled
            if Menu.Charge.ChargeReach then
                Menu.Charge.LateCharge = ImMenu.Checkbox("Late Charge", Menu.Charge.LateCharge)
            end
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            local oldChargeJump = Menu.Charge.ChargeJump
            Menu.Charge.ChargeJump = ImMenu.Checkbox("Charge Jump", Menu.Charge.ChargeJump)
            -- If the value changed, synchronize with the Misc setting
            if oldChargeJump ~= Menu.Charge.ChargeJump then
                Menu.Misc.ChargeJump = Menu.Charge.ChargeJump
            end
            ImMenu.EndFrame()
        end

        if Menu.currentTab == 4 then -- Misc tab
            ImMenu.BeginFrame()
            Menu.Misc.InstantAttack = ImMenu.Checkbox("Instant Attack", Menu.Misc.InstantAttack)
            -- Add warp on attack button when instant attack is enabled
            if Menu.Misc.InstantAttack then
                Menu.Misc.WarpOnAttack = ImMenu.Checkbox("Warp On Attack", Menu.Misc.WarpOnAttack)
            end
            Menu.Misc.advancedHitreg = ImMenu.Checkbox("Advanced Hitreg", Menu.Misc.advancedHitreg)
            Menu.Misc.TroldierAssist = ImMenu.Checkbox("Troldier Assist", Menu.Misc.TroldierAssist)
            ImMenu.EndFrame()

            ImMenu.BeginFrame()
            Menu.Misc.CritRefill.Active = ImMenu.Checkbox("Auto Crit refill", Menu.Misc.CritRefill.Active)
            if Menu.Misc.CritRefill.Active then
                Menu.Misc.CritRefill.NumCrits = ImMenu.Slider("Crit Number", Menu.Misc.CritRefill.NumCrits, 1, 25)
            end
            ImMenu.EndFrame()
            ImMenu.BeginFrame()
            if Menu.Misc.CritRefill.Active then
                Menu.Misc.CritMode = ImMenu.Option(Menu.Misc.CritMode, Menu.Misc.CritModes)
            end
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Misc.strafePred = ImMenu.Checkbox("Local Strafe Pred", Menu.Misc.strafePred)
            ImMenu.EndFrame()
        end

        if Menu.currentTab == 3 then -- Visuals tab
            ImMenu.BeginFrame(1)
            Menu.Visuals.EnableVisuals = ImMenu.Checkbox("Enable", Menu.Visuals.EnableVisuals)
            ImMenu.EndFrame()

            ImMenu.BeginFrame(1)
            Menu.Visuals.Section = ImMenu.Option(Menu.Visuals.Section, Menu.Visuals.Sections)
            ImMenu.EndFrame()

            if Menu.Visuals.Section == 1 then
                Menu.Visuals.Local.RangeCircle = ImMenu.Checkbox("Range Circle", Menu.Visuals.Local.RangeCircle)
                Menu.Visuals.Local.path.enable = ImMenu.Checkbox("Local Path", Menu.Visuals.Local.path.enable)
                Menu.Visuals.Local.path.Style = ImMenu.Option(Menu.Visuals.Local.path.Style,
                    Menu.Visuals.Local.path.Styles)
                Menu.Visuals.Local.path.width = ImMenu.Slider("Width", Menu.Visuals.Local.path.width, 1, 20, 0.1)
            end

            if Menu.Visuals.Section == 2 then
                Menu.Visuals.Target.path.enable = ImMenu.Checkbox("Target Path", Menu.Visuals.Target.path.enable)
                Menu.Visuals.Target.path.Style = ImMenu.Option(Menu.Visuals.Target.path.Style,
                    Menu.Visuals.Target.path.Styles)
                Menu.Visuals.Target.path.width = ImMenu.Slider("Width", Menu.Visuals.Target.path.width, 1, 20, 0.1)
            end

            if Menu.Visuals.Section == 3 then
                ImMenu.BeginFrame(1)
                ImMenu.Text("Experimental")
                Menu.Visuals.Sphere = ImMenu.Checkbox("Range Shield", Menu.Visuals.Sphere)
                ImMenu.EndFrame()
            end
        end

        ImMenu.End()
    end

    -- Render visuals only when alive and visuals enabled
    if not (engine.Con_IsVisible() or engine.IsGameUIVisible()) and Menu.Visuals.EnableVisuals then
        local drawPLocal = entities.GetLocalPlayer()
        if drawPLocal and drawPLocal:IsAlive() then
            local drawPWeapon = drawPLocal:GetPropEntity("m_hActiveWeapon")
            if drawPWeapon and drawPWeapon:IsMeleeWeapon() then
                Visuals.Render(Menu, {
                    pLocalFuture = pLocalFuture,
                    pLocalOrigin = pLocalOrigin,
                    Vheight = Vheight,
                    TotalSwingRange = TotalSwingRange,
                    pLocalPath = pLocalPath,
                    vPlayerPath = vPlayerPath,
                    vPlayerFuture = vPlayerFuture,
                    CurrentTarget = CurrentTarget,
                    drawVhitbox = drawVhitbox,
                    aimposVis = aimposVis,
                })
            end
        end
    end
end

--[[ Remove the menu when unloaded ]] --
local function OnUnload()             -- Called when the script is unloaded
    local unloadLib = rawget(_G, "UnloadLib")
    if type(unloadLib) == "function" then
        unloadLib()                                           --unloading lualib
    end
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
    client.Command('play "ui/buttonclickrelease"', true)      -- Play the "buttonclickrelease" sound
end

local function damageLogger(event)
    UpdateServerCvars() -- Update cvars on event
    if (event:GetName() == 'player_hurt') then
        local victim = entities.GetByUserID(event:GetInt("userid"))
        local attacker = entities.GetByUserID(event:GetInt("attacker"))
        local localPlayer = entities.GetLocalPlayer()

        if (attacker == nil or not localPlayer or localPlayer:GetName() ~= attacker:GetName()) then
            return
        end
        local damage = event:GetInt("damageamount")
        if not victim then
            return
        end
        if damage <= victim:GetHealth() then return end

        -- Trigger recharge if instant attack is enabled and warp ticks are below threshold
        if Menu.Misc.InstantAttack and warp.GetChargedTicks() < 13
            and not warp.IsWarping() then
            warp.TriggerCharge() -- Trigger charge to max ticks
            tickCounterrecharge = 0
        end
    end
end



--[[ Unregister previous callbacks ]]                            --
callbacks.Unregister("CreateMove", "MCT_CreateMove")             -- Unregister the "CreateMove" callback
callbacks.Unregister("FireGameEvent", "adaamaXDgeLogger")
callbacks.Unregister("Unload", "MCT_Unload")                     -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "MCT_Draw")                         -- Unregister the "Draw" callback
--[[ Register callbacks ]]                                       --
callbacks.Register("CreateMove", "MCT_CreateMove", OnCreateMove) -- Register the "CreateMove" callback
callbacks.Register("FireGameEvent", "adaamaXDgeLogger", damageLogger)
callbacks.Register("Unload", "MCT_Unload", OnUnload)             -- Register the "Unload" callback
callbacks.Register("Draw", "MCT_Draw", doDraw)                   -- Register the "Draw" callback
--[[ Play sound when loaded ]]                                   --
client.Command('play "ui/buttonclick"', true)                    -- Play the "buttonclick" sound when the script is loaded
