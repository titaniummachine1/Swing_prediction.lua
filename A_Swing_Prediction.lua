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

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
--local Prediction = lnxLib.TF2.Prediction
--local Fonts = lnxLib.UI.Fonts
local Input = lnxLib.Utils.Input
local Notify = lnxLib.UI.Notify

-- Function to safely ensure a value is set, using a default if nil
local function SafeValue(value, default)
    if value == nil then
        return default
    end
    return value
end

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
        AlwaysUseMaxSwingTime = true, -- Default to always use max for best experience
        MaxSwingTime = 13,            -- Starting value, will be updated based on weapon
        ChargeBot = true,             -- Moved to Charge tab in UI but kept here for backward compatibility
    },

    -- Charge settings (moved from mixed locations to a dedicated section)
    Charge = {
        ChargeBot = true,
        ChargeControl = true,
        ChargeSensitivity = 1.0,
        ChargeReach = false,
        ChargeJump = true,
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
        TroldierAssist = false,
        advancedHitreg = false,

        -- These are moved to Charge tab in UI but kept here for backward compatibility
        ChargeControl = true,
        ChargeReach = false,
        ChargeJump = true,
        ChargeSensitivity = 1.0,
    },

    -- Global settings
    Keybind = KEY_NONE,
    KeybindName = "Always On",
}

local Lua__fullPath = GetScriptName()
local Lua__fileName = Lua__fullPath:match("\\([^\\]-)$"):gsub("%.lua$", "")

local function CreateCFG(folder_name, table)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.cfg")
    local file = io.open(filepath, "w")

    if file then
        local function serializeTable(tbl, level)
            level = level or 0
            local result = string.rep("    ", level) .. "{\n"
            for key, value in pairs(tbl) do
                result = result .. string.rep("    ", level + 1)
                if type(key) == "string" then
                    result = result .. '["' .. key .. '"] = '
                else
                    result = result .. "[" .. key .. "] = "
                end
                if type(value) == "table" then
                    result = result .. serializeTable(value, level + 1) .. ",\n"
                elseif type(value) == "string" then
                    result = result .. '"' .. value .. '",\n'
                else
                    result = result .. tostring(value) .. ",\n"
                end
            end
            result = result .. string.rep("    ", level) .. "}"
            return result
        end

        local serializedConfig = serializeTable(table)
        file:write(serializedConfig)
        file:close()
        printc(255, 183, 0, 255, "[" .. os.date("%H:%M:%S") .. "] Saved Config to " .. tostring(fullPath))
    end
end

local function LoadCFG(folder_name)
    local success, fullPath = filesystem.CreateDirectory(folder_name)
    local filepath = tostring(fullPath .. "/config.cfg")
    local file = io.open(filepath, "r")

    if file then
        local content = file:read("*a")
        file:close()
        local chunk, err = load("return " .. content)
        if chunk and not input.IsButtonDown(KEY_LSHIFT) then
            printc(0, 255, 140, 255, "[" .. os.date("%H:%M:%S") .. "] Loaded Config from " .. tostring(fullPath))
            return chunk()
        else
            CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
            print("Error loading configuration:", err)
        end
    end
end

local status, loadedMenu = pcall(function()
    return assert(LoadCFG(string.format([[Lua %s]], Lua__fileName)))
end) -- Auto-load config

if status and loadedMenu then
    Menu = loadedMenu
end

-- Ensure all the Menu settings are initialized
local function SafeInitMenu()
    -- Initialize Aimbot settings
    Menu.Aimbot = Menu.Aimbot or {}
    Menu.Aimbot.Aimbot = SafeValue(Menu.Aimbot.Aimbot, true)
    Menu.Aimbot.Silent = SafeValue(Menu.Aimbot.Silent, true)
    Menu.Aimbot.AimbotFOV = SafeValue(Menu.Aimbot.AimbotFOV, 360)
    Menu.Aimbot.SwingTime = SafeValue(Menu.Aimbot.SwingTime, 13)
    Menu.Aimbot.AlwaysUseMaxSwingTime = SafeValue(Menu.Aimbot.AlwaysUseMaxSwingTime, true)
    Menu.Aimbot.MaxSwingTime = SafeValue(Menu.Aimbot.MaxSwingTime, 13)
    Menu.Aimbot.ChargeBot = SafeValue(Menu.Aimbot.ChargeBot, true)

    -- Initialize other sections if needed
    -- (We can add more sections here if they also have nil issues)
end

-- Call the initialization function to ensure no nil values
-- This ensures settings are properly initialized even after loading the config
SafeInitMenu()

local isMelee = false
local pLocal = nil
local players = entities.FindByClass("CTFPlayer")
local swingrange = 48
local TotalSwingRange = 48
local SwingHullSize = 38
local SwingHalfhullSize = SwingHullSize / 2
local tick_count = 0
local can_attack = false
local can_charge = false
local Charge_Range = 128
local defFakeLatency = gui.GetValue("Fake Latency Value (MS)")
local pLocalPath = {}
local vPlayerPath = {}
local vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local drawVhitbox = {}
local gravity = client.GetConVar("sv_gravity") or 800 -- Get the current gravity
local stepSize = 18
local tickCounteratack = 0

-- Variables to track attack and charge state
local attackStarted = false
local attackTickCount = 0
local lastChargeTime = 0

-- Add this function to reset the attack tracking when needed
local function resetAttackTracking()
    attackStarted = false
    attackTickCount = 0
end


if pLocal then
    stepSize = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18
else
    stepSize = 18
end

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

local lastAngles = {} ---@type table<number, Vector3>
local lastDeltas = {} ---@type table<number, number>
local avgDeltas = {} ---@type table<number, number>
local strafeAngles = {} ---@type table<number, number>
local inaccuracy = {} ---@type table<number, number>
local pastPositions = {} -- Stores past positions of the local player
local maxPositions = 4   -- Number of past positions to consider

local function CalcStrafe()
    local autostrafe = gui.GetValue("Auto Strafe")
    local flags = entities.GetLocalPlayer():GetPropInt("m_fFlags")
    local OnGround = flags & FL_ONGROUND == 1

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

            if not onGround and autostrafe == 2 and #pastPositions >= maxPositions then
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

local function shouldHitEntityFun(entity, player, ignoreEntities)
    for _, ignoreEntity in ipairs(ignoreEntities) do --ignore custom
        if entity:GetClass() == ignoreEntity then
            return false
        end
    end

    local pos = entity:GetAbsOrigin() + Vector3(0, 0, 1)
    local contents = engine.GetPointContents(pos)
    if contents ~= 0 then return true end
    if entity:GetName() == player:GetName() then return false end             --ignore self
    if entity:GetTeamNumber() ~= player:GetTeamNumber() then return false end --ignore teammates
    return true
end

-- [WIP] Predict the position of a player
---@param player WPlayer
---@param t integer
---@param d number?
---@param shouldHitEntity fun(entity: WEntity, contentsMask: integer): boolean?
---@return { pos : Vector3[], vel: Vector3[], onGround: boolean[] }?
local function PredictPlayer(player, t, d)
    if not gravity or not stepSize then return nil end
    local vUp = Vector3(0, 0, 1)
    local vStep = Vector3(0, 0, stepSize)
    local ignoreEntities = { "CTFAmmoPack", "CTFDroppedWeapon" }
    pLocal = entities.GetLocalPlayer()
    if not pLocal then return nil end
    local shouldHitEntity = function(entity) return shouldHitEntityFun(entity, player, ignoreEntities) end --trace ignore simulated player
    local pFlags = player:GetPropInt("m_fFlags")
    -- Add the current record
    local _out = {
        pos = { [0] = player:GetAbsOrigin() },
        vel = { [0] = player:EstimateAbsVelocity() },
        onGround = { [0] = player:IsOnGround() }
    }

    -- Perform the prediction
    for i = 1, t do
        local lastP, lastV, lastG = _out.pos[i - 1], _out.vel[i - 1], _out.onGround[i - 1]

        --[[if chargeLeft < 100 and player:InCond(17) then

            end]]
        local pos = lastP + lastV * globals.TickInterval()
        local vel = lastV
        local onGround1 = lastG

        -- Apply deviation
        if d then
            local ang = vel:Angles()
            ang.y = ang.y + d
            vel = ang:Forward() * vel:Length()
        end

        --[[ Forward collision ]]

        local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID,
            shouldHitEntity)
        --DrawLine(last.p + vStep, pos + vStep)
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
        local simulateJump = false
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
        --local isSwimming, isWalking = checkPlayerState(player) -- todo: fix this
        if not onGround1 then
            vel.z = vel.z - gravity * globals.TickInterval()
        end

        -- Add the prediction record
        _out.pos[i], _out.vel[i], _out.onGround[i] = pos, vel, onGround1
    end
    return _out
end

-- Constants for minimum and maximum speed
local MIN_SPEED = 10                     -- Minimum speed to avoid jittery movements
local MAX_SPEED = 650                    -- Maximum speed the player can move

local MoveDir = Vector3(0, 0, 0)         -- Variable to store the movement direction
local pLocal = entities.GetLocalPlayer() -- Variable to store the local player

local function NormalizeVector(vector)
    local length = math.sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    if length == 0 then
        return Vector3(0, 0, 0)
    else
        return Vector3(vector.x / length, vector.y / length, vector.z / length)
    end
end

-- Function to compute the move direction
local function ComputeMove(pCmd, a, b)
    local diff = (b - a)
    if diff:Length() == 0 then return Vector3(0, 0, 0) end

    local x = diff.x
    local y = diff.y
    local vSilent = Vector3(x, y, 0)

    local ang = vSilent:Angles()
    local cPitch, cYaw, cRoll = pCmd:GetViewAngles()
    local yaw = math.rad(ang.y - cYaw)
    local pitch = math.rad(ang.x - cPitch)
    local move = Vector3(math.cos(yaw) * MAX_SPEED, -math.sin(yaw) * MAX_SPEED, 0)

    return move
end

-- Function to make the player walk to a destination smoothly
local function WalkTo(pCmd, pLocal, pDestination)
    -- Safety check - if destination is invalid, don't attempt to move
    if not pDestination or not pLocal then
        return
    end

    local localPos = pLocal:GetAbsOrigin()
    local distVector = pDestination - localPos

    -- Safety check - make sure the distance vector is valid
    if not distVector or distVector:Length() > 1000 then
        return
    end

    local dist = distVector:Length()

    -- Determine the speed based on the distance
    local speed = math.max(MIN_SPEED, math.min(MAX_SPEED, dist))

    -- If distance is greater than 1, proceed with walking
    if dist > 1 then
        local result = ComputeMove(pCmd, localPos, pDestination)

        -- Safety check - make sure result is valid
        if not result then return end

        -- Scale down the movements based on the calculated speed
        local scaleFactor = speed / MAX_SPEED
        pCmd:SetForwardMove(result.x * scaleFactor)
        pCmd:SetSideMove(result.y * scaleFactor)
    else
        pCmd:SetForwardMove(0)
        pCmd:SetSideMove(0)
    end
end

local playerTicks = {}
local maxTick = math.floor(((defFakeLatency) / 1000) / 0.015)

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

    -- Variables to track best target among all players
    local bestTarget = nil
    local bestFactor = 0

    -- Variables to track best target within melee range
    local bestMeleeTarget = nil
    local bestMeleeFactor = 0

    -- Range threshold - use TotalSwingRange plus a buffer of 50 units
    local meleeRangeThreshold = TotalSwingRange + 50
    local foundTargetInMeleeRange = false

    local localPlayerViewAngles = engine.GetViewAngles()
    local localPlayerOrigin = localPlayer:GetAbsOrigin()
    local localPlayerEyePos = localPlayerOrigin + Vector3(0, 0, 75)

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
        if fov > Menu.Aimbot.AimbotFOV then
            goto continue
        end

        -- Check if target is visible
        local isVisible = Helpers.VisPos(player, localPlayerEyePos, playerOrigin + Vector3(0, 0, 75))
        local visibilityFactor = isVisible and 1 or 0.1

        -- First priority: targets within melee range
        if distance <= meleeRangeThreshold then
            foundTargetInMeleeRange = true

            -- For targets in melee range, mostly consider visibility and a bit of FOV
            local meleeFovFactor = Math.RemapValClamped(fov, 0, Menu.Aimbot.AimbotFOV, 1, 0.7)
            local meleeFactor = meleeFovFactor * visibilityFactor

            if meleeFactor > bestMeleeFactor then
                bestMeleeTarget = player
                bestMeleeFactor = meleeFactor
            end
        elseif distance <= 770 then
            -- For targets outside melee range but within max distance, use standard targeting
            local distanceFactor = Math.RemapValClamped(distance, settings.MinDistance, settings.MaxDistance, 1, 0.9)
            local fovFactor = Math.RemapValClamped(fov, 0, Menu.Aimbot.AimbotFOV, 1, 0.1)

            local factor = distanceFactor * fovFactor * visibilityFactor
            if factor > bestFactor then
                bestTarget = player
                bestFactor = factor
            end
        end
        ::continue::
    end

    -- Return the best target in melee range if found, otherwise return best target by other factors
    if foundTargetInMeleeRange and bestMeleeTarget then
        return bestMeleeTarget
    else
        return bestTarget
    end
end

-- Function to check if target is in range
local function checkInRange(targetPos, spherePos, sphereRadius)
    local hitbox_min_trigger = targetPos + vHitbox[1]
    local hitbox_max_trigger = targetPos + vHitbox[2]

    -- Calculate the closest point on the hitbox to the sphere
    local closestPoint = Vector3(
        math.max(hitbox_min_trigger.x, math.min(spherePos.x, hitbox_max_trigger.x)),
        math.max(hitbox_min_trigger.y, math.min(spherePos.y, hitbox_max_trigger.y)),
        math.max(hitbox_min_trigger.z, math.min(spherePos.z, hitbox_max_trigger.z))
    )

    -- Calculate the distance from the closest point to the sphere center
    local distanceAlongVector = (spherePos - closestPoint):Length()

    -- Check if the target is within the sphere radius
    if sphereRadius > distanceAlongVector then
        -- Calculate the direction from spherePos to closestPoint
        local direction = Normalize(closestPoint - spherePos)
        local SwingtraceEnd = spherePos + direction * sphereRadius

        if Menu.Misc.AdvancedHitreg then
            local trace = engine.TraceLine(spherePos, SwingtraceEnd, MASK_SHOT_HULL)
            if trace.fraction < 1 and trace.entity == TargetEntity then
                return true, closestPoint
            else
                local SwingHull = {
                    Min = Vector3(-SwingHalfhullSize, -SwingHalfhullSize, -SwingHalfhullSize),
                    Max =
                        Vector3(SwingHalfhullSize, SwingHalfhullSize, SwingHalfhullSize)
                }
                trace = engine.TraceHull(spherePos, SwingtraceEnd, SwingHull.Min, SwingHull.Max, MASK_SHOT_HULL)
                if trace.fraction < 1 and trace.entity == TargetEntity then
                    return true, closestPoint
                else
                    return false, nil
                end
            end
        end

        return true, closestPoint
    else
        -- Target is not in range
        return false, nil
    end
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
    if not Menu.Misc.ChargeControl then
        return
    end

    -- Get the current view angles and sensitivity
    local sensitivity = Menu.Misc.ChargeSensitivity
    local currentAngles = engine.GetViewAngles()

    -- Get the mouse motion
    local mouseDeltaX = -(pCmd.mousedx * sensitivity)

    -- Calculate the new yaw angle
    local newYaw = currentAngles.yaw + mouseDeltaX

    -- Calculate the maximum allowed angle change to maintain a minimum velocity of 350
    local maxAngleChange = calculateMaxAngleChange(pLocal:EstimateAbsVelocity():Length(), 350, 55) -- Define this function based on your game mechanics

    -- Clamp the angle change to the maximum allowed
    local angleChange = newYaw - currentAngles.yaw
    angleChange = math.max(math.min(angleChange, maxAngleChange), -maxAngleChange)

    -- Interpolate between the current yaw and the new yaw
    local interpolationTime = 0.1515                           -- Time in seconds for a full transition
    local interpolationFraction = 1 / (66 * interpolationTime) -- Adjusted for smoother transition
    local interpolatedYaw = currentAngles.yaw + angleChange * interpolationFraction

    -- Set the new view angles
    engine.SetViewAngles(EulerAngles(engine:GetViewAngles().pitch, interpolatedYaw, 0))
end

local acceleration = 750

local function UpdateHomingMissile()
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
local function checkInRangeWithLatency(playerIndex, swingRange, pWeapon, cmd)
    local inRange = false
    local point = nil
    local Backtrack = gui.GetValue("Backtrack")
    local fakelatencyON = gui.GetValue("Fake Latency")
    local smackDelay = Menu.Aimbot.MaxSwingTime

    if Backtrack == 0 and fakelatencyON == 0 then
        -- Check for charge range bug
        if pLocalClass == 4 and Menu.Misc.ChargeReach and chargeLeft == 100 then -- charge meter is full
            if checkInRange(vPlayerOrigin, pLocalOrigin, Charge_Range) then
                inRange = true
                point = vPlayerOrigin
                can_charge = false -- Don't set can_charge yet, we'll track it separately

                -- Set the view angles to target
                local aimAngles = Math.PositionAngles(pLocalOrigin, vPlayerOrigin)

                -- Apply the aiming angles
                if Menu.Aimbot.Silent then
                    cmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
                else
                    engine.SetViewAngles(EulerAngles(aimAngles.pitch, aimAngles.yaw, 0))
                end
            elseif checkInRange(vPlayerFuture, pLocalFuture, Charge_Range) then
                inRange = true
                point = vPlayerFuture
                can_charge = false -- Don't set can_charge yet, we'll track it separately

                -- Set the view angles to target
                local aimAngles = Math.PositionAngles(pLocalFuture, vPlayerFuture)

                -- Apply the aiming angles
                if Menu.Aimbot.Silent then
                    cmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
                else
                    engine.SetViewAngles(EulerAngles(aimAngles.pitch, aimAngles.yaw, 0))
                end
            end

            if inRange then
                return inRange, point, false -- Return inRange but not can_charge yet
            end
        elseif chargeLeft < 100 then
            can_charge = false
            if checkInRange(vPlayerOrigin, pLocalOrigin, Charge_Range) then
                inRange = true
                point = vPlayerOrigin
                tick_count = tick_count + 1

                -- Calculate the exact tick to charge at based on ping
                local latOut = clientstate.GetLatencyOut() or 0
                local latIn = clientstate.GetLatencyIn() or 0
                local tickInterval = globals.TickInterval()
                local pingTicks = math.floor(((latOut + latIn) / tickInterval) + 1) -- Ping in ticks + 1 for safety
                local chargeAtTick = math.max(1, smackDelay - pingTicks)            -- Ensure we don't go negative

                -- Use a small range around the target tick to increase reliability
                if tick_count >= chargeAtTick and tick_count <= (chargeAtTick + 1) then
                    tick_count = 0
                    can_charge = true
                end
            else
                inRange = false
                can_charge = false
                tick_count = 0
            end
            return inRange, point, can_charge
        end

        -- Adjust hitbox for current position
        inRange, point = checkInRange(vPlayerOrigin, pLocalOrigin, swingRange - 18, pWeapon, cmd)
        if inRange then
            return inRange, point
        end


        inRange, point = checkInRange(vPlayerFuture, pLocalFuture, swingRange, pWeapon, cmd)
        if inRange then
            return inRange, point, can_charge
        end
    elseif fakelatencyON == 1 and playerTicks and playerTicks[playerIndex] then
        if not hasNotified then
            Notify.Simple("Fake Latency is enabled", " this may cause issues with the script", 7)
            hasNotified = true
        end

        local minTick = 1
        maxTick = #playerTicks[playerIndex]

        for tick = minTick, maxTick do
            if playerTicks[playerIndex] then
                local pastOrigin = playerTicks[playerIndex][tick]

                -- Check for charge range bug - only if instant attack is NOT ready
                if pLocalClass == 4 and Menu.Misc.ChargeReach and chargeLeft == 100 and not instantAttackReady then -- charge meter is full
                    if checkInRange(pastOrigin, pLocalOrigin, Charge_Range) then
                        inRange = true
                        point = vPlayerOrigin
                        tick_count = tick_count + 1

                        -- Calculate the exact tick to charge at based on ping
                        local latOut = clientstate.GetLatencyOut() or 0
                        local latIn = clientstate.GetLatencyIn() or 0
                        local tickInterval = globals.TickInterval()
                        local pingTicks = math.floor(((latOut + latIn) / tickInterval) + 1) -- Ping in ticks + 1 for safety
                        local chargeAtTick = math.max(1, smackDelay - pingTicks)            -- Ensure we don't go negative

                        -- Use a small range around the target tick to increase reliability
                        if tick_count >= chargeAtTick and tick_count <= (chargeAtTick + 1) then
                            -- Compensate for engine view angles being one tick behind
                            local vPlayerVelocity = CurrentTarget:EstimateAbsVelocity()
                            local predictedPos = vPlayerOrigin + (vPlayerVelocity * tickInterval)

                            -- Set the view angles to anticipate where the target will be in the next tick
                            local aimAngles = Math.PositionAngles(pLocalOrigin, predictedPos)

                            -- Apply the compensated angles
                            if Menu.Aimbot.Silent then
                                cmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
                            else
                                engine.SetViewAngles(EulerAngles(aimAngles.pitch, aimAngles.yaw, 0))
                            end

                            tick_count = 0
                            can_charge = true
                        end
                    end
                end

                inRange, point = checkInRange(pastOrigin, pLocalOrigin, swingRange, pWeapon, cmd)
                if inRange then
                    return inRange, point
                end
            end
        end
    elseif Backtrack == 1 then
        -- Check for charge range bug - only if instant attack is NOT ready
        if pLocalClass == 4 and Menu.Misc.ChargeReach and chargeLeft == 100 and not instantAttackReady then -- charge meter is full
            if checkInRange(vPlayerOrigin, pLocalOrigin, Charge_Range) then
                inRange = true
                point = vPlayerOrigin
                tick_count = tick_count + 1

                -- Calculate the exact tick to charge at based on ping
                local latOut = clientstate.GetLatencyOut() or 0
                local latIn = clientstate.GetLatencyIn() or 0
                local tickInterval = globals.TickInterval()
                local pingTicks = math.floor(((latOut + latIn) / tickInterval) + 1) -- Ping in ticks + 1 for safety
                local chargeAtTick = math.max(1, smackDelay - pingTicks)            -- Ensure we don't go negative

                -- Use a small range around the target tick to increase reliability
                if tick_count >= chargeAtTick and tick_count <= (chargeAtTick + 1) then
                    -- Compensate for engine view angles being one tick behind
                    local vPlayerVelocity = CurrentTarget:EstimateAbsVelocity()
                    local predictedPos = vPlayerOrigin + (vPlayerVelocity * tickInterval)

                    -- Set the view angles to anticipate where the target will be in the next tick
                    local aimAngles = Math.PositionAngles(pLocalOrigin, predictedPos)

                    -- Apply the compensated angles
                    if Menu.Aimbot.Silent then
                        cmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
                    else
                        engine.SetViewAngles(EulerAngles(aimAngles.pitch, aimAngles.yaw, 0))
                    end

                    tick_count = 0
                    can_charge = true
                elseif checkInRange(vPlayerFuture, pLocalFuture, Charge_Range) then
                    inRange = true
                    point = vPlayerFuture
                    tick_count = tick_count + 1

                    -- Calculate the exact tick to charge at based on ping
                    local latOut = clientstate.GetLatencyOut() or 0
                    local latIn = clientstate.GetLatencyIn() or 0
                    local tickInterval = globals.TickInterval()
                    local pingTicks = math.floor(((latOut + latIn) / tickInterval) + 1) -- Ping in ticks + 1 for safety
                    local chargeAtTick = math.max(1, smackDelay - pingTicks)            -- Ensure we don't go negative

                    -- Use a small range around the target tick to increase reliability
                    if tick_count >= chargeAtTick and tick_count <= (chargeAtTick + 1) then
                        -- Compensate for engine view angles being one tick behind
                        local vPlayerVelocity = CurrentTarget:EstimateAbsVelocity()
                        local predictedPos = vPlayerFuture + (vPlayerVelocity * tickInterval)

                        -- Set the view angles to anticipate where the target will be in the next tick
                        local aimAngles = Math.PositionAngles(pLocalFuture, predictedPos)

                        -- Apply the compensated angles
                        if Menu.Aimbot.Silent then
                            cmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
                        else
                            engine.SetViewAngles(EulerAngles(aimAngles.pitch, aimAngles.yaw, 0))
                        end

                        tick_count = 0
                        can_charge = true
                    end
                end
                if inRange then
                    return inRange, point, can_charge
                end
            end
        end

        -- Adjust hitbox for current position
        inRange, point = checkInRange(vPlayerOrigin, pLocalOrigin, swingRange, pWeapon, cmd)
        if inRange then
            return inRange, point
        end

        inRange = checkInRange(vPlayerFuture, pLocalFuture, swingRange, pWeapon, cmd)
        if inRange then
            return inRange, point
        end
    end

    return false, nil
end

-- Store the original Crit Hack Key value outside the main loop or function
local originalCritHackKey = 0
local originalMeleeCritHack = 0
local menuWasOpen = false
local critRefillActive = false
local dashKeyNotBoundNotified = false

--[[ Code needed to run 66 times a second ]] --
-- Predicts player position after set amount of ticks
---@param strafeAngle number
local function OnCreateMove(pCmd)
    -- Get the local player entity
    pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        goto continue -- Return if the local player entity doesn't exist or is dead
    end

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

    local lerp = client.GetConVar("cl_interp") or 0
    Latency = (lerp)                                                  -- Calculate the reaction time in seconds
    Latency = math.floor(Latency * (globals.TickInterval() * 66) + 1) -- Convert the delay to ticks
    defFakeLatency = gui.GetValue("Fake Latency Value (MS)")

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

    isMelee = pWeapon:IsMeleeWeapon()     -- check if using melee weapon
    if not isMelee then goto continue end -- if not melee then skip code

    --[-------Get pLocalOrigin--------]

    -- Get pLocal eye level and set vector at our eye level to ensure we check distance from eyes
    local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") -- Vector3(0, 0, 70)
    local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
    viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()

    -- Eye level
    Vheight = Vector3(0, 0, viewheight)
    pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)

    --[-------- Get SwingRange --------]
    swingrange = pWeapon:GetSwingRange()

    SwingHullSize = 35.6
    SwingHalfhullSize = SwingHullSize / 2

    if pWeaponDef:GetName() == "The Disciplinary Action" then
        SwingHullSize = 55.8
        swingrange = 81.6
    end
    TotalSwingRange = swingrange + (SwingHullSize / 2)
    --[--Manual charge control--]

    if Menu.Misc.ChargeControl and pLocal:InCond(17) then
        ChargeControl(pCmd)
    end

    --[-----Get best target------------------]
    local keybind = Menu.Keybind

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
        NumCrits = math.clamp(NumCrits, 27, 1000)

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
    local OnGround = flags & FL_ONGROUND == 1

    --[[--------------Charge Jump-------------------]]
    if Menu.Misc.ChargeJump and input.IsButtonPressed(MOUSE_RIGHT) and chargeLeft == 100 and OnGround then
        pCmd:SetButtons(pCmd:GetButtons() & ~IN_JUMP)    -- stop jump for moment
        pCmd:SetButtons(pCmd:GetButtons() & ~IN_ATTACK2) -- stop charge for moment
        pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)     -- jump at 2 ticks before attack
    end

    --[--------------Prediction-------------------]
    -- Predict both players' positions after swing
    gravity = client.GetConVar("sv_gravity")
    stepSize = pLocal:GetPropFloat("m_flStepSize")

    CalcStrafe()

    -- Local player prediction
    if pLocal:EstimateAbsVelocity() == 0 then
        -- If the local player is not accelerating, set the predicted position to the current position
        pLocalFuture = pLocalOrigin
    else
        -- Always predict local player movement regardless of instant attack state
        local player = WPlayer.FromEntity(pLocal)
        strafeAngle = Menu.Misc.strafePred and strafeAngles[pLocal:GetIndex()] or 0

        -- Always use weapon-specific ticks for simulation with instant attack
        local instantAttackReady = Menu.Misc.InstantAttack and warp.CanWarp() and
            warp.GetChargedTicks() >= Menu.Aimbot.SwingTime and
            gui.GetValue("dash move key") ~= 0
        local simTicks = Menu.Aimbot.SwingTime
        if not instantAttackReady then
            simTicks = Menu.Aimbot.SwingTime
        end

        local predData = PredictPlayer(player, simTicks, strafeAngle)
        if not predData then return end

        if inaccuracyValue then
            TotalSwingRange = TotalSwingRange - math.abs(inaccuracyValue)
        end

        pLocalPath = predData.pos
        pLocalFuture = predData.pos[simTicks] + viewOffset
    end

    -- stop if no target
    if CurrentTarget == nil then
        vPlayerFuture = nil
        return
    end

    vPlayerOrigin = CurrentTarget:GetAbsOrigin() -- Get closest player origin

    local VpFlags = CurrentTarget:GetPropInt("m_fFlags")
    local DUCKING = VpFlags & FL_DUCKING == 2
    if DUCKING then
        vHitbox[2].z = 62
    else
        vHitbox[2].z = 82
    end

    --vHitbox[2].z = pViewheight + 7

    -- Check if instant attack is ready
    local dashKeyBound = gui.GetValue("dash move key") ~= 0
    local instantAttackReady = Menu.Misc.InstantAttack and warp.CanWarp() and
        warp.GetChargedTicks() >= Menu.Aimbot.SwingTime and
        dashKeyBound

    if not instantAttackReady then
        -- Only predict enemy movement when NOT using instant attack
        local player = WPlayer.FromEntity(CurrentTarget)
        strafeAngle = strafeAngles[CurrentTarget:GetIndex()] or 0

        -- Default to Menu.Aimbot.SwingTime since we're not using instant attack
        local simTicks = Menu.Aimbot.SwingTime

        local predData = PredictPlayer(player, simTicks, strafeAngle)
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

    --[--------------Distance check-------------------]
    -- Get current distance between local player and closest player
    vdistance = (vPlayerOrigin - pLocalOrigin):Length()

    -- Get distance between local player and closest player after swing
    fDistance = (vPlayerFuture - pLocalFuture):Length()
    local inRange = false
    local inRangePoint = Vector3(0, 0, 0)

    inRange, InRangePoint, can_charge = checkInRangeWithLatency(CurrentTarget:GetIndex(), swingrange, pWeapon, pCmd,
        OnGround, pLocal:InCond(17))
    -- Use inRange to decide if can attack
    can_attack = inRange

    --[--------------AimBot-------------------]                --get hitbox of ennmy pelwis(jittery but works)
    local aimpos = CurrentTarget:GetAbsOrigin() +
        Vheight --aimpos = (hitbox[1] + hitbox[2]) * 0.5 --if no InRange point accesable then aim at defualt hitbox

    -- Inside your game loop
    if Menu.Aimbot.Aimbot then
        local aim_angles
        if InRangePoint then
            aimpos = InRangePoint
            aimposVis = aimpos -- transfer aim point to visuals

            -- Calculate aim position only once
            aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
            aim_angles = aimpos
        end

        if Menu.Aimbot.ChargeBot and pLocal:InCond(17) and not can_attack then
            local trace = engine.TraceHull(pLocalOrigin, UpdateHomingMissile(), vHitbox[1], vHitbox[2],
                MASK_PLAYERSOLID_BRUSHONLY)
            if trace.fraction == 1 or trace.entity == CurrentTarget then
                -- If the trace hit something, set the view angles to the position of the hit
                aim_angles = Math.PositionAngles(pLocalOrigin, UpdateHomingMissile())
                -- Set view angles based on the future position of the local player
                engine.SetViewAngles(EulerAngles(engine.GetViewAngles().pitch, aim_angles.yaw, 0))
            end
        elseif Menu.Aimbot.ChargeBot and chargeLeft == 100 and input.IsButtonDown(MOUSE_RIGHT) and not can_attack and fDistance < 750 then
            local trace = engine.TraceHull(pLocalFuture, UpdateHomingMissile(), vHitbox[1], vHitbox[2],
                MASK_PLAYERSOLID_BRUSHONLY)
            if trace.fraction == 1 or trace.entity == CurrentTarget then
                -- If the trace hit something, set the view angles to the position of the hit
                aim_angles = Math.PositionAngles(pLocalOrigin, UpdateHomingMissile())
                -- Set view angles based on the future position of the local player
                engine.SetViewAngles(EulerAngles(engine.GetViewAngles().pitch, aim_angles.yaw, 0))
            end
        elseif can_attack and aim_angles and aim_angles.pitch and aim_angles.yaw then
            -- Set view angles based on whether silent aim is enabled
            if Menu.Aimbot.Silent then
                pCmd:SetViewAngles(aim_angles.pitch, aim_angles.yaw, 0)
            else
                engine.SetViewAngles(EulerAngles(aim_angles.pitch, aim_angles.yaw, 0))
            end
        end
    end

    -- Check if instant attack is available
    dashKeyBound = gui.GetValue("dash move key") ~= 0
    local canInstantAttack = Menu.Misc.InstantAttack and warp.CanWarp() and warp.GetChargedTicks() >= 13 and dashKeyBound

    -- No need to temporarily store ChargeReach - directly check it when needed
    -- Get distance check and target range check
    -- Get current distance between local player and closest player
    Vdistance = (vPlayerOrigin - pLocalOrigin):Length()

    -- Get distance between local player and closest player after swing
    FDistance = (vPlayerFuture - pLocalFuture):Length()
    local inRange = false
    local inRangePoint = Vector3(0, 0, 0)

    inRange, InRangePoint, can_charge = checkInRangeWithLatency(CurrentTarget:GetIndex(), swingrange, pWeapon, pCmd,
        OnGround, pLocal:InCond(17))
    -- Use inRange to decide if can attack
    can_attack = inRange

    --[--------------AimBot-------------------]                --get hitbox of ennmy pelwis(jittery but works)

    aimpos = nil
    --else
    aimpos = CurrentTarget:GetAbsOrigin() +
        Vheight --aimpos = (hitbox[1] + hitbox[2]) * 0.5 --if no InRange point accesable then aim at defualt hitbox
    --end

    -- Inside your game loop
    if Menu.Aimbot.Aimbot then
        local aim_angles
        if InRangePoint then
            aimpos = InRangePoint
            aimposVis = aimpos -- transfer aim point to visuals

            -- Calculate aim position only once
            aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
            aim_angles = aimpos
        end

        if Menu.Aimbot.ChargeBot and pLocal:InCond(17) and not can_attack then
            local trace = engine.TraceHull(pLocalOrigin, UpdateHomingMissile(), vHitbox[1], vHitbox[2],
                MASK_PLAYERSOLID_BRUSHONLY)
            if trace.fraction == 1 or trace.entity == CurrentTarget then
                -- If the trace hit something, set the view angles to the position of the hit
                aim_angles = Math.PositionAngles(pLocalOrigin, UpdateHomingMissile())
                -- Set view angles based on the future position of the local player
                engine.SetViewAngles(EulerAngles(engine.GetViewAngles().pitch, aim_angles.yaw, 0))
            end
        elseif Menu.Aimbot.ChargeBot and chargeLeft == 100 and input.IsButtonDown(MOUSE_RIGHT) and not can_attack and fDistance < 750 then
            local trace = engine.TraceHull(pLocalFuture, UpdateHomingMissile(), vHitbox[1], vHitbox[2],
                MASK_PLAYERSOLID_BRUSHONLY)
            if trace.fraction == 1 or trace.entity == CurrentTarget then
                -- If the trace hit something, set the view angles to the position of the hit
                aim_angles = Math.PositionAngles(pLocalOrigin, UpdateHomingMissile())
                -- Set view angles based on the future position of the local player
                engine.SetViewAngles(EulerAngles(engine.GetViewAngles().pitch, aim_angles.yaw, 0))
            end
        elseif can_attack and aim_angles and aim_angles.pitch and aim_angles.yaw then
            -- Set view angles based on whether silent aim is enabled
            if Menu.Aimbot.Silent then
                pCmd:SetViewAngles(aim_angles.pitch, aim_angles.yaw, 0)
            else
                engine.SetViewAngles(EulerAngles(aim_angles.pitch, aim_angles.yaw, 0))
            end
        end
    end

    -- Initialize tick_count if it hasn't been set yet
    if tick_count == nil then
        tick_count = 0
    end

    -- Only try instant attack when it's possible
    if can_attack then
        -- Get the actual weapon smack delay if available
        local weaponSmackDelay = 13 -- Default fallback value
        if pWeapon and pWeapon:GetWeaponData() then
            local weaponData = pWeapon:GetWeaponData()
            if weaponData and weaponData.smackDelay then
                -- Convert smackDelay time to ticks (rounded up to ensure we have enough time)
                weaponSmackDelay = math.floor(weaponData.smackDelay / globals.TickInterval())
                -- Ensure a minimum viable value
                weaponSmackDelay = math.max(weaponSmackDelay, 5)

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

        if Menu.Misc.InstantAttack and canInstantAttack then
            -- Remove cooldown code and directly proceed to instant attack logic
            local velocity = pLocal:EstimateAbsVelocity()
            -- Safety check: only calculate oppositePoint if we have actual velocity
            local oppositePoint
            if velocity:Length() > 10 then -- Only use if we have meaningful velocity
                oppositePoint = pLocal:GetAbsOrigin() - velocity
            else
                -- If no significant velocity, use a point slightly in front based on view angles
                local angles = engine.GetViewAngles()
                local forward = angles:Forward()
                oppositePoint = pLocal:GetAbsOrigin() + forward * 20
            end

            if tickCounteratack % 2 == 0 then
                -- IMPORTANT: First initiate the attack, THEN trigger warp
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK) -- First initiate attack
            else
                -- Safety check to prevent empty vectors or extreme values
                if oppositePoint and (oppositePoint - pLocal:GetAbsOrigin()):Length() < 300 then
                    WalkTo(pCmd, pLocal, oppositePoint)
                end
                client.RemoveConVarProtection("sv_maxusrcmdprocessticks") --bypass security

                -- Add safety cap to prevent freezes - never allow more than 20 ticks
                local safeTickValue = math.min(weaponSmackDelay, 20)
                client.SetConVar("sv_maxusrcmdprocessticks", safeTickValue)

                -- Safety check before triggering warp
                local chargedTicks = warp.GetChargedTicks() or 0
                if chargedTicks >= safeTickValue then
                    warp.TriggerWarp() -- Then trigger warp
                    -- We've removed the cooldown, so no need to track the last attack time
                else
                    -- Fall back to normal attack when we don't have enough ticks
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end
            end
            tickCounteratack = tickCounteratack + 1
        else
            -- Normal attack if instant attack is disabled or not enough ticks
            -- Use a higher value for normal attacks, but cap it for safety
            local normalAttackTicks = math.min(math.floor(weaponSmackDelay), 24)
            client.RemoveConVarProtection("sv_maxusrcmdprocessticks") --bypass security
            client.SetConVar("sv_maxusrcmdprocessticks", normalAttackTicks)
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)            -- attack

            -- Start tracking attack ticks if this is a Demoman with a full charge meter
            -- AND attack tracking hasn't already started
            if pLocalClass == 4 and Menu.Misc.ChargeReach and chargeLeft == 100 and not attackStarted then
                attackStarted = true
                attackTickCount = 0
                -- Get exact weapon smack delay
                weaponSmackDelay = Menu.Aimbot.MaxSwingTime
                if pWeapon and pWeapon:GetWeaponData() and pWeapon:GetWeaponData().smackDelay then
                    weaponSmackDelay = math.floor(pWeapon:GetWeaponData().smackDelay / globals.TickInterval())
                end
                --client.ChatPrintf("[Debug] Attack started! Will charge at end of swing (tick " ..(weaponSmackDelay - 1) .. ")")
            end

            can_attack = false
        end

        -- Track attack ticks and execute charge at right moment
        if attackStarted then
            attackTickCount = attackTickCount + 1

            -- Get weapon smack delay (when the weapon will hit)
            local weaponSmackDelay = Menu.Aimbot.MaxSwingTime
            if pWeapon and pWeapon:GetWeaponData() and pWeapon:GetWeaponData().smackDelay then
                weaponSmackDelay = math.floor(pWeapon:GetWeaponData().smackDelay / globals.TickInterval())
            end

            -- Execute charge exactly at the end of the swing animation (1 tick before the hit registers)
            if attackTickCount >= (weaponSmackDelay - 2) then
                --client.ChatPrintf("[Debug] Executing charge at end of swing, tick: " .. attackTickCount)
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2) -- charge

                -- Reset attack tracking
                attackStarted = false
                attackTickCount = 0
                can_charge = false
            end
        end
    end

    -- Update last variables
    vHitbox[2].z = 82
    ::continue::
end

-- Sphere cache and drawn edges cache
local sphere_cache = { vertices = {}, radius = 90, center = Vector3(0, 0, 0) }
local drawnEdges = {}

local function setup_sphere(center, radius, segments)
    sphere_cache.center = center
    sphere_cache.radius = radius
    sphere_cache.segments = segments
    sphere_cache.vertices = {} -- Clear the old vertices

    local thetaStep = math.pi / segments
    local phiStep = 2 * math.pi / segments

    for i = 0, segments - 1 do
        local theta1 = thetaStep * i
        local theta2 = thetaStep * (i + 1)

        for j = 0, segments - 1 do
            local phi1 = phiStep * j
            local phi2 = phiStep * (j + 1)

            -- Generate a square for each segment
            table.insert(sphere_cache.vertices, {
                Vector3(math.sin(theta1) * math.cos(phi1), math.sin(theta1) * math.sin(phi1), math.cos(theta1)),
                Vector3(math.sin(theta1) * math.cos(phi2), math.sin(theta1) * math.sin(phi2), math.cos(theta1)),
                Vector3(math.sin(theta2) * math.cos(phi2), math.sin(theta2) * math.sin(phi2), math.cos(theta2)),
                Vector3(math.sin(theta2) * math.cos(phi1), math.sin(theta2) * math.sin(phi1), math.cos(theta2))
            })
        end
    end
end

local function arrowPathArrow2(startPos, endPos, width)
    if not (startPos and endPos) then return nil, nil end

    local direction = endPos - startPos
    local length = direction:Length()
    if length == 0 then return nil, nil end
    direction = Normalize(direction)

    local perpDir = Vector3(-direction.y, direction.x, 0)
    local leftBase = startPos + perpDir * width
    local rightBase = startPos - perpDir * width

    local screenStartPos = client.WorldToScreen(startPos)
    local screenEndPos = client.WorldToScreen(endPos)
    local screenLeftBase = client.WorldToScreen(leftBase)
    local screenRightBase = client.WorldToScreen(rightBase)

    if screenStartPos and screenEndPos and screenLeftBase and screenRightBase then
        draw.Line(screenStartPos[1], screenStartPos[2], screenEndPos[1], screenEndPos[2])
        draw.Line(screenLeftBase[1], screenLeftBase[2], screenEndPos[1], screenEndPos[2])
        draw.Line(screenRightBase[1], screenRightBase[2], screenEndPos[1], screenEndPos[2])
    end

    return leftBase, rightBase
end




local function arrowPathArrow(startPos, endPos, arrowWidth)
    if not startPos or not endPos then return end

    local direction = endPos - startPos
    if direction:Length() == 0 then return end

    -- Normalize the direction vector and calculate perpendicular direction
    direction = Normalize(direction)
    local perpendicular = Vector3(-direction.y, direction.x, 0) * arrowWidth

    -- Calculate points for arrow fins
    local finPoint1 = startPos + perpendicular
    local finPoint2 = startPos - perpendicular

    -- Convert world positions to screen positions
    local screenStartPos = client.WorldToScreen(startPos)
    local screenEndPos = client.WorldToScreen(endPos)
    local screenFinPoint1 = client.WorldToScreen(finPoint1)
    local screenFinPoint2 = client.WorldToScreen(finPoint2)

    -- Draw the arrow
    if screenStartPos and screenEndPos then
        draw.Line(screenEndPos[1], screenEndPos[2], screenFinPoint1[1], screenFinPoint1[2])
        draw.Line(screenEndPos[1], screenEndPos[2], screenFinPoint2[1], screenFinPoint2[2])
        draw.Line(screenFinPoint1[1], screenFinPoint1[2], screenFinPoint2[1], screenFinPoint2[2])
    end
end

local function drawPavement(startPos, endPos, width)
    if not (startPos and endPos) then return nil end

    local direction = endPos - startPos
    local length = direction:Length()
    if length == 0 then return nil end
    direction = Normalize(direction)

    -- Calculate perpendicular direction for the width
    local perpDir = Vector3(-direction.y, direction.x, 0)

    -- Calculate left and right base points of the pavement
    local leftBase = startPos + perpDir * width
    local rightBase = startPos - perpDir * width

    -- Convert positions to screen coordinates
    local screenStartPos = client.WorldToScreen(startPos)
    local screenEndPos = client.WorldToScreen(endPos)
    local screenLeftBase = client.WorldToScreen(leftBase)
    local screenRightBase = client.WorldToScreen(rightBase)

    -- Draw the pavement
    if screenStartPos and screenEndPos and screenLeftBase and screenRightBase then
        draw.Line(screenStartPos[1], screenStartPos[2], screenEndPos[1], screenEndPos[2])
        draw.Line(screenStartPos[1], screenStartPos[2], screenLeftBase[1], screenLeftBase[2])
        draw.Line(screenStartPos[1], screenStartPos[2], screenRightBase[1], screenRightBase[2])
    end

    return leftBase, rightBase
end


-- Call setup_sphere once at the start of your program
setup_sphere(Vector3(0, 0, 0), 90, 7)

local white_texture = draw.CreateTextureRGBA(string.char(
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25
), 2, 2);

local drawPolygon = (function()
    local v1x, v1y = 0, 0;
    local function cross(a, b)
        return (b[1] - a[1]) * (v1y - a[2]) - (b[2] - a[2]) * (v1x - a[1])
    end

    local TexturedPolygon = draw.TexturedPolygon;

    return function(vertices)
        local cords, reverse_cords = {}, {};
        local sizeof = #vertices;
        local sum = 0;

        v1x, v1y = vertices[1][1], vertices[1][2];
        for i, pos in ipairs(vertices) do
            local convertedTbl = { pos[1], pos[2], 0, 0 };

            cords[i], reverse_cords[sizeof - i + 1] = convertedTbl, convertedTbl;

            sum = sum + cross(pos, vertices[(i % sizeof) + 1]);
        end


        TexturedPolygon(white_texture, (sum < 0) and reverse_cords or cords, true)
    end
end)();

local bindTimer = 0
local bindDelay = 0.25 -- Delay of 0.25 seconds

local function handleKeybind(noKeyText, keybind, keybindName)
    if KeybindName ~= "Press The Key" and ImMenu.Button(KeybindName or noKeyText) then
        bindTimer = os.clock() + bindDelay
        KeybindName = "Press The Key"
    elseif KeybindName == "Press The Key" then
        ImMenu.Text("Press the key")
    end

    if KeybindName == "Press The Key" then
        if os.clock() >= bindTimer then
            local pressedKey = GetPressedkey()
            if pressedKey then
                if pressedKey == KEY_ESCAPE then
                    -- Reset keybind if the Escape key is pressed
                    keybind = 0
                    KeybindName = "Always On"
                    Notify.Simple("Keybind Success", "Bound Key: " .. KeybindName, 2)
                else
                    -- Update keybind with the pressed key
                    keybind = pressedKey
                    KeybindName = Input.GetKeyName(pressedKey)
                    Notify.Simple("Keybind Success", "Bound Key: " .. KeybindName, 2)
                end
            end
        end
    end
    return keybind, keybindName
end



local function L_line(start_pos, end_pos, secondary_line_size)
    if not (start_pos and end_pos) then
        return
    end
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then
        return
    end
    local normalized_direction = Normalize(direction)
    local perpendicular = Vector3(normalized_direction.y, -normalized_direction.x, 0) * secondary_line_size
    local w2s_start_pos = client.WorldToScreen(start_pos)
    local w2s_end_pos = client.WorldToScreen(end_pos)
    if not (w2s_start_pos and w2s_end_pos) then
        return
    end
    local secondary_line_end_pos = start_pos + perpendicular
    local w2s_secondary_line_end_pos = client.WorldToScreen(secondary_line_end_pos)
    if w2s_secondary_line_end_pos then
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_end_pos[1], w2s_end_pos[2])
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_secondary_line_end_pos[1], w2s_secondary_line_end_pos[2])
    end
end

-- Function to update the tabs
local function updateTabs(selectedTab)
    for tabName, _ in pairs(Menu.tabs) do
        Menu.tabs[tabName] = (tabName == selectedTab)
    end
end

-- debug command: ent_fire !picker Addoutput "health 99999" --superbot
local Verdana = draw.CreateFont("Verdana", 16, 800) -- Create a font for doDraw
draw.SetFont(Verdana)
--[[ Code called every frame ]]                     --
local function doDraw()
    if not (engine.Con_IsVisible() or engine.IsGameUIVisible()) and Menu.Visuals.EnableVisuals then
        pLocal = entities.GetLocalPlayer()
        pWeapon = pLocal:GetPropEntity("m_hActiveWeapon") -- Set "pWeapon" to the local player's active weapon
        if Menu.Visuals.EnableVisuals or pWeapon:IsMeleeWeapon() and pLocal and pLocal:IsAlive() then
            draw.Color(255, 255, 255, 255)
            local w, h = draw.GetScreenSize()
            if Menu.Visuals.Local.RangeCircle and pLocalFuture then
                draw.Color(255, 255, 255, 255)

                local center = pLocalFuture -
                    Vheight         -- Center of the circle at the player's feet
                local viewPos =
                    pLocalOrigin    -- View position to shoot traces from
                local radius = Menu.Misc.ChargeReach and pLocalClass == 4 and chargeLeft == 100 and Charge_Range or
                    TotalSwingRange -- Radius of the circle
                local segments = 32 -- Number of segments to draw the circle
                local angleStep = (2 * math.pi) / segments

                -- Determine the color of the circle based on TargetPlayer
                local circleColor = TargetPlayer and { 0, 255, 0, 255 } or
                    { 255, 255, 255, 255 } -- Green if TargetPlayer exists, otherwise white

                -- Set the drawing color
                draw.Color(table.unpack(circleColor))

                local vertices = {} -- Table to store adjusted vertices

                -- Calculate vertices and adjust based on trace results
                for i = 1, segments do
                    local angle = angleStep * i
                    local circlePoint = center + Vector3(math.cos(angle), math.sin(angle), 0) * radius

                    local trace = engine.TraceLine(viewPos, circlePoint, MASK_SHOT_HULL) --engine.TraceHull(viewPos, circlePoint, vHitbox[1], vHitbox[2], MASK_SHOT_HULL)
                    local endPoint = trace.fraction < 1.0 and trace.endpos or circlePoint

                    vertices[i] = client.WorldToScreen(endPoint)
                end

                -- Draw the circle using adjusted vertices
                for i = 1, segments do
                    local j = (i % segments) + 1 -- Wrap around to the first vertex after the last one
                    if vertices[i] and vertices[j] then
                        draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
                    end
                end
            end
            if Menu.Visuals.Local.path.enable and pLocalFuture then
                local style = Menu.Visuals.Local.path.Style
                local width1 = Menu.Visuals.Local.path.width
                if style == 1 then
                    local lastLeftBaseScreen, lastRightBaseScreen = nil, nil
                    -- Pavement Style
                    for i = 1, #pLocalPath - 1 do
                        local startPos = pLocalPath[i]
                        local endPos = pLocalPath[i + 1]

                        if startPos and endPos then
                            local leftBase, rightBase = drawPavement(startPos, endPos, width1)

                            if leftBase and rightBase then
                                local screenLeftBase = client.WorldToScreen(leftBase)
                                local screenRightBase = client.WorldToScreen(rightBase)

                                if screenLeftBase and screenRightBase then
                                    if lastLeftBaseScreen and lastRightBaseScreen then
                                        draw.Line(lastLeftBaseScreen[1], lastLeftBaseScreen[2], screenLeftBase[1],
                                            screenLeftBase[2])
                                        draw.Line(lastRightBaseScreen[1], lastRightBaseScreen[2], screenRightBase[1],
                                            screenRightBase[2])
                                    end

                                    lastLeftBaseScreen = screenLeftBase
                                    lastRightBaseScreen = screenRightBase
                                end
                            end
                        end
                    end

                    -- Draw the final line segment
                    if lastLeftBaseScreen and lastRightBaseScreen and #pLocalPath > 0 then
                        local finalPos = pLocalPath[#pLocalPath]
                        local screenFinalPos = client.WorldToScreen(finalPos)

                        if screenFinalPos then
                            draw.Line(lastLeftBaseScreen[1], lastLeftBaseScreen[2], screenFinalPos[1], screenFinalPos[2])
                            draw.Line(lastRightBaseScreen[1], lastRightBaseScreen[2], screenFinalPos[1],
                                screenFinalPos[2])
                        end
                    end
                elseif style == 2 then
                    local lastLeftBaseScreen, lastRightBaseScreen = nil, nil

                    -- Start from the second element (i = 2)
                    for i = 2, #pLocalPath - 1 do
                        local startPos = pLocalPath[i]
                        local endPos = pLocalPath[i + 1]

                        if startPos and endPos then
                            local leftBase, rightBase = arrowPathArrow2(startPos, endPos, width1)

                            if leftBase and rightBase then
                                local screenLeftBase = client.WorldToScreen(leftBase)
                                local screenRightBase = client.WorldToScreen(rightBase)

                                if screenLeftBase and screenRightBase then
                                    if lastLeftBaseScreen and lastRightBaseScreen then
                                        draw.Line(lastLeftBaseScreen[1], lastLeftBaseScreen[2], screenLeftBase[1],
                                            screenLeftBase[2])
                                        draw.Line(lastRightBaseScreen[1], lastRightBaseScreen[2], screenRightBase[1],
                                            screenRightBase[2])
                                    end

                                    lastLeftBaseScreen = screenLeftBase
                                    lastRightBaseScreen = screenRightBase
                                end
                            end
                        end
                    end
                elseif style == 3 then
                    -- Arrows Style
                    for i = 1, #pLocalPath - 1 do
                        local startPos = pLocalPath[i]
                        local endPos = pLocalPath[i + 1]

                        if startPos and endPos then
                            arrowPathArrow(startPos, endPos, width1)
                        end
                    end
                elseif style == 4 then
                    -- L Line Style
                    for i = 1, #pLocalPath - 1 do
                        local pos1 = pLocalPath[i]
                        local pos2 = pLocalPath[i + 1]

                        if pos1 and pos2 then
                            L_line(pos1, pos2, width1) -- Adjust the size for the perpendicular segment as needed
                        end
                    end
                elseif style == 5 then
                    -- Draw a dashed line for pLocalPath
                    for i = 1, #pLocalPath - 1 do
                        local pos1 = pLocalPath[i]
                        local pos2 = pLocalPath[i + 1]

                        local screenPos1 = client.WorldToScreen(pos1)
                        local screenPos2 = client.WorldToScreen(pos2)

                        if screenPos1 ~= nil and screenPos2 ~= nil and i % 2 == 1 then
                            draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
                        end
                    end
                elseif style == 6 then
                    -- Draw a dashed line for pLocalPath
                    for i = 1, #pLocalPath - 1 do
                        local pos1 = pLocalPath[i]
                        local pos2 = pLocalPath[i + 1]

                        local screenPos1 = client.WorldToScreen(pos1)
                        local screenPos2 = client.WorldToScreen(pos2)

                        if screenPos1 ~= nil and screenPos2 ~= nil then
                            draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
                        end
                    end
                end
            end
            ---------------------------------------------------------sphere
            if Menu.Visuals.Sphere then
                -- Function to draw the sphere
                local function draw_sphere()
                    local playerYaw = engine.GetViewAngles().yaw
                    local cos_yaw = math.cos(math.rad(playerYaw))
                    local sin_yaw = math.sin(math.rad(playerYaw))

                    local playerForward = Vector3(-cos_yaw, -sin_yaw, 0) -- Forward vector based on player's yaw

                    for _, vertex in ipairs(sphere_cache.vertices) do
                        local rotated_vertex1 = Vector3(-vertex[1].x * cos_yaw + vertex[1].y * sin_yaw,
                            -vertex[1].x * sin_yaw - vertex[1].y * cos_yaw, vertex[1].z)
                        local rotated_vertex2 = Vector3(-vertex[2].x * cos_yaw + vertex[2].y * sin_yaw,
                            -vertex[2].x * sin_yaw - vertex[2].y * cos_yaw, vertex[2].z)
                        local rotated_vertex3 = Vector3(-vertex[3].x * cos_yaw + vertex[3].y * sin_yaw,
                            -vertex[3].x * sin_yaw - vertex[3].y * cos_yaw, vertex[3].z)
                        local rotated_vertex4 = Vector3(-vertex[4].x * cos_yaw + vertex[4].y * sin_yaw,
                            -vertex[4].x * sin_yaw - vertex[4].y * cos_yaw, vertex[4].z)

                        local worldPos1 = sphere_cache.center + rotated_vertex1 * sphere_cache.radius
                        local worldPos2 = sphere_cache.center + rotated_vertex2 * sphere_cache.radius
                        local worldPos3 = sphere_cache.center + rotated_vertex3 * sphere_cache.radius
                        local worldPos4 = sphere_cache.center + rotated_vertex4 * sphere_cache.radius

                        -- Trace from the center to the vertices with a hull size of 18x18
                        local hullSize = Vector3(18, 18, 18)
                        local trace1 = engine.TraceHull(sphere_cache.center, worldPos1, -hullSize, hullSize,
                            MASK_SHOT_HULL)
                        local trace2 = engine.TraceHull(sphere_cache.center, worldPos2, -hullSize, hullSize,
                            MASK_SHOT_HULL)
                        local trace3 = engine.TraceHull(sphere_cache.center, worldPos3, -hullSize, hullSize,
                            MASK_SHOT_HULL)
                        local trace4 = engine.TraceHull(sphere_cache.center, worldPos4, -hullSize, hullSize,
                            MASK_SHOT_HULL)

                        local endPos1 = trace1.fraction < 1.0 and trace1.endpos or worldPos1
                        local endPos2 = trace2.fraction < 1.0 and trace2.endpos or worldPos2
                        local endPos3 = trace3.fraction < 1.0 and trace3.endpos or worldPos3
                        local endPos4 = trace4.fraction < 1.0 and trace4.endpos or worldPos4

                        local screenPos1 = client.WorldToScreen(endPos1)
                        local screenPos2 = client.WorldToScreen(endPos2)
                        local screenPos3 = client.WorldToScreen(endPos3)
                        local screenPos4 = client.WorldToScreen(endPos4)

                        -- Calculate normal vector of the square
                        local normal = Normalize(rotated_vertex2 - rotated_vertex1):Cross(rotated_vertex3 -
                            rotated_vertex1)

                        -- Draw square only if its normal faces towards the player
                        if normal:Dot(playerForward) > 0.1 then
                            if screenPos1 and screenPos2 and screenPos3 and screenPos4 then
                                -- Draw the square
                                drawPolygon({ screenPos1, screenPos2, screenPos3, screenPos4 })

                                -- Optionally, draw lines between the vertices of the square for wireframe visualization
                                draw.Color(255, 255, 255, 25) -- Set color and alpha for lines
                                draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
                                draw.Line(screenPos2[1], screenPos2[2], screenPos3[1], screenPos3[2])
                                draw.Line(screenPos3[1], screenPos3[2], screenPos4[1], screenPos4[2])
                                draw.Line(screenPos4[1], screenPos4[2], screenPos1[1], screenPos1[2])
                            end
                        end
                    end
                end

                -- Example draw call
                sphere_cache.center = pLocalOrigin    -- Replace with actual player origin
                sphere_cache.radius = TotalSwingRange -- Replace with actual swing range value
                draw_sphere()
            end

            -- enemy
            if vPlayerFuture then
                -- Draw lines between the predicted positions
                if Menu.Visuals.Target.path.enable then
                    local style = Menu.Visuals.Target.path.Style
                    local width = Menu.Visuals.Target.path.width

                    if style == 1 then
                        local lastLeftBaseScreen, lastRightBaseScreen = nil, nil
                        -- Pavement Style
                        for i = 1, #vPlayerPath - 1 do
                            local startPos = vPlayerPath[i]
                            local endPos = vPlayerPath[i + 1]

                            if startPos and endPos then
                                local leftBase, rightBase = drawPavement(startPos, endPos, width)

                                if leftBase and rightBase then
                                    local screenLeftBase = client.WorldToScreen(leftBase)
                                    local screenRightBase = client.WorldToScreen(rightBase)

                                    if screenLeftBase and screenRightBase then
                                        if lastLeftBaseScreen and lastRightBaseScreen then
                                            draw.Line(lastLeftBaseScreen[1], lastLeftBaseScreen[2], screenLeftBase[1],
                                                screenLeftBase[2])
                                            draw.Line(lastRightBaseScreen[1], lastRightBaseScreen[2], screenRightBase[1],
                                                screenRightBase[2])
                                        end

                                        lastLeftBaseScreen = screenLeftBase
                                        lastRightBaseScreen = screenRightBase
                                    end
                                end
                            end
                        end

                        -- Draw the final line segment
                        if lastLeftBaseScreen and lastRightBaseScreen and #vPlayerPath > 0 then
                            local finalPos = vPlayerPath[#vPlayerPath]
                            local screenFinalPos = client.WorldToScreen(finalPos)

                            if screenFinalPos then
                                draw.Line(lastLeftBaseScreen[1], lastLeftBaseScreen[2], screenFinalPos[1],
                                    screenFinalPos[2])
                                draw.Line(lastRightBaseScreen[1], lastRightBaseScreen[2], screenFinalPos[1],
                                    screenFinalPos[2])
                            end
                        end
                    elseif style == 2 then
                        local lastLeftBaseScreen, lastRightBaseScreen = nil, nil

                        -- Start from the second element (i = 2)
                        for i = 2, #vPlayerPath - 1 do
                            local startPos = vPlayerPath[i]
                            local endPos = vPlayerPath[i + 1]

                            if startPos and endPos then
                                local leftBase, rightBase = arrowPathArrow2(startPos, endPos, width)

                                if leftBase and rightBase then
                                    local screenLeftBase = client.WorldToScreen(leftBase)
                                    local screenRightBase = client.WorldToScreen(rightBase)

                                    if screenLeftBase and screenRightBase then
                                        if lastLeftBaseScreen and lastRightBaseScreen then
                                            draw.Line(lastLeftBaseScreen[1], lastLeftBaseScreen[2], screenLeftBase[1],
                                                screenLeftBase[2])
                                            draw.Line(lastRightBaseScreen[1], lastRightBaseScreen[2], screenRightBase[1],
                                                screenRightBase[2])
                                        end

                                        lastLeftBaseScreen = screenLeftBase
                                        lastRightBaseScreen = screenRightBase
                                    end
                                end
                            end
                        end
                    elseif style == 3 then
                        -- Arrows Style
                        for i = 1, #vPlayerPath - 1 do
                            local startPos = vPlayerPath[i]
                            local endPos = vPlayerPath[i + 1]

                            if startPos and endPos then
                                arrowPathArrow(startPos, endPos, width)
                            end
                        end
                    elseif style == 4 then
                        -- L Line Style
                        for i = 1, #vPlayerPath - 1 do
                            local pos1 = vPlayerPath[i]
                            local pos2 = vPlayerPath[i + 1]

                            if pos1 and pos2 then
                                L_line(pos1, pos2, width) -- Adjust the size for the perpendicular segment as needed
                            end
                        end
                    elseif style == 5 then
                        -- Draw a dashed line for vPlayerPath
                        for i = 1, #vPlayerPath - 1 do
                            local pos1 = vPlayerPath[i]
                            local pos2 = vPlayerPath[i + 1]

                            local screenPos1 = client.WorldToScreen(pos1)
                            local screenPos2 = client.WorldToScreen(pos2)

                            if screenPos1 ~= nil and screenPos2 ~= nil and i % 2 == 1 then
                                draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
                            end
                        end
                    elseif style == 6 then
                        -- Draw a dashed line for vPlayerPath
                        for i = 1, #vPlayerPath - 1 do
                            local pos1 = vPlayerPath[i]
                            local pos2 = vPlayerPath[i + 1]

                            local screenPos1 = client.WorldToScreen(pos1)
                            local screenPos2 = client.WorldToScreen(pos2)

                            if screenPos1 ~= nil and screenPos2 ~= nil then
                                draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
                            end
                        end
                    end
                end

                if aimposVis then
                    --draw predicted local position with strafe prediction
                    local screenPos = client.WorldToScreen(aimposVis)
                    if screenPos ~= nil then
                        draw.Line(screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                        draw.Line(screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
                    end
                end

                -- Calculate min and max points
                local minPoint = drawVhitbox[1]
                local maxPoint = drawVhitbox[2]

                -- Calculate vertices of the AABB
                -- Assuming minPoint and maxPoint are the minimum and maximum points of the AABB:
                local vertices = {
                    Vector3(minPoint.x, minPoint.y, minPoint.z), -- Bottom-back-left
                    Vector3(minPoint.x, maxPoint.y, minPoint.z), -- Bottom-front-left
                    Vector3(maxPoint.x, maxPoint.y, minPoint.z), -- Bottom-front-right
                    Vector3(maxPoint.x, minPoint.y, minPoint.z), -- Bottom-back-right
                    Vector3(minPoint.x, minPoint.y, maxPoint.z), -- Top-back-left
                    Vector3(minPoint.x, maxPoint.y, maxPoint.z), -- Top-front-left
                    Vector3(maxPoint.x, maxPoint.y, maxPoint.z), -- Top-front-right
                    Vector3(maxPoint.x, minPoint.y, maxPoint.z)  -- Top-back-right
                }

                -- Convert 3D coordinates to 2D screen coordinates
                for i, vertex in ipairs(vertices) do
                    vertices[i] = client.WorldToScreen(vertex)
                end

                -- Draw lines between vertices to visualize the box
                if vertices[1] and vertices[2] and vertices[3] and vertices[4] and vertices[5] and vertices[6] and vertices[7] and vertices[8] then
                    -- Draw front face
                    draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])

                    -- Draw back face
                    draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
                    draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])

                    -- Draw connecting lines
                    draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
                end
            end
        end
    end

    if gui.IsMenuOpen() and ImMenu and ImMenu.Begin("Swing Prediction", true) then
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
end

--[[ Remove the menu when unloaded ]]                         --
local function OnUnload()                                     -- Called when the script is unloaded
    UnloadLib()                                               --unloading lualib
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
    client.Command('play "ui/buttonclickrelease"', true)      -- Play the "buttonclickrelease" sound
end

local function damageLogger(event)
    if (event:GetName() == 'player_hurt') then
        local victim = entities.GetByUserID(event:GetInt("userid"))
        local attacker = entities.GetByUserID(event:GetInt("attacker"))
        if (attacker == nil or pLocal:GetName() ~= attacker:GetName()) then
            return
        end
        local damage = event:GetInt("damageamount")
        if damage <= victim:GetHealth() then return end

        -- Trigger recharge if instant attack is enabled, dash key is bound, and warp ticks are less than 13
        local dashKeyBound = gui.GetValue("dash move key") ~= 0
        if Menu.Misc.InstantAttack and dashKeyBound and warp.GetChargedTicks() < 13
            and not warp.IsWarping() then
            warp.TriggerCharge()
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

--[[ Charge Control Module ]]

-- Optional: Apply a small multiplier if you want slightly enhanced turning
-- Set to 1.0 for exactly normal mouse behavior
local TURN_MULTIPLIER = 1.0

-- Maximum degrees to rotate in one frame (prevents disorientation from extreme flicks)
local MAX_ROTATION_PER_FRAME = 73.04

-- Side movement value for A/D simulation (Source engine uses ±450 for full side movement)
local SIDE_MOVE_VALUE = 450

-- Main function that processes player input during charge
local function OnCreateMove_ChargeControl(cmd)
    -- Check if charge control is enabled in menu
    if not Menu.Misc.ChargeControl then
        return
    end

    pLocal = entities.GetLocalPlayer()

    -- Check if player exists and is the right class
    if not pLocal or not pLocal:IsAlive() then
        return
    end

    local currclass = pLocal:GetPropInt("m_iClass")
    if currclass ~= 4 then -- Only process for Demoman (class 4)
        return
    end

    -- Check if player is charging
    local isCharging = pLocal:InCond(17) -- 17 is the charge condition ID

    -- Skip if not charging
    if not isCharging then
        return
    end

    -- Find all demo shields by class name
    local shields = entities.FindByClass("CTFWearableDemoShield")

    -- Check if any shield belongs to player and is Tide Turner
    for i, shield in pairs(shields) do --pairs not ipairs because shields is insequential
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
    local mouseDeltaX = -cmd.mousedx

    -- Skip processing if no horizontal mouse movement
    if mouseDeltaX == 0 then
        return
    end

    -- Get current view angles and game settings
    local currentAngles = engine.GetViewAngles()
    local m_yaw = select(2, client.GetConVar("m_yaw")) -- Get m_yaw from game settings

    -- Calculate turn amount using standard Source engine formula
    local turnAmount = mouseDeltaX * m_yaw * TURN_MULTIPLIER

    -- Determine turning direction for side movement
    -- Apply side movement based on turning direction (simulate A/D keys)
    if turnAmount > 0 then
        -- Turning left, simulate pressing D (right strafe)
        cmd.sidemove = SIDE_MOVE_VALUE
    else
        -- Turning right, simulate pressing A (left strafe)
        cmd.sidemove = -SIDE_MOVE_VALUE
    end

    -- Limit maximum turn per frame to prevent disorientation
    turnAmount = math.max(-MAX_ROTATION_PER_FRAME, math.min(MAX_ROTATION_PER_FRAME, turnAmount))

    -- Calculate new yaw angle
    local newYaw = currentAngles.yaw + turnAmount

    -- Handle -180/180 degree boundary crossing
    newYaw = newYaw % 360
    if newYaw > 180 then
        newYaw = newYaw - 360
    elseif newYaw < -180 then
        newYaw = newYaw + 360
    end

    -- Compensate for engine view angles being one tick behind
    -- Calculate the predicted angle one tick ahead
    local playerVelocity = pLocal:EstimateAbsVelocity()
    local tickInterval = globals.TickInterval()

    -- Calculate the angular velocity based on current movement
    local angularVelocity = 0
    if playerVelocity:Length() > 0 then
        -- Use the current turning rate as an estimate of angular velocity
        angularVelocity = turnAmount / tickInterval
    end

    -- Predict the yaw angle one tick ahead
    local predictedYaw = newYaw + (angularVelocity * tickInterval)

    -- Normalize the predicted yaw
    predictedYaw = predictedYaw % 360
    if predictedYaw > 180 then
        predictedYaw = predictedYaw - 360
    elseif predictedYaw < -180 then
        predictedYaw = predictedYaw + 360
    end

    -- Apply the current angle to cmd for current tick movement
    cmd:SetViewAngles(currentAngles.pitch, newYaw, currentAngles.roll)

    -- Apply the predicted angle to engine for visual representation
    -- This compensates for the one-tick delay in engine view angles
    local predictedAngles = EulerAngles(currentAngles.pitch, predictedYaw, currentAngles.roll)
    engine.SetViewAngles(predictedAngles)
end

-- Register the callback for charge control
callbacks.Register("CreateMove", "ChargeControl", OnCreateMove_ChargeControl)