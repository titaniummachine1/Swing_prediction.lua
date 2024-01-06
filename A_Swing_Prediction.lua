--[[ Swing prediction for  Lmaobox  ]]--
--[[      (Modded misc-tools)       ]]--
--[[          --Authors--           ]]--
--[[           Terminator           ]]--
--[[  (github.com/titaniummachine1  ]]--

-- Unload the module if it's already loaded
if package.loaded["ImMenu"] then
    package.loaded["ImMenu"] = nil
end

-- Load the module
local menuLoaded, ImMenu = pcall(require, "ImMenu")
assert(menuLoaded, "ImMenu not found, please install it!")
assert(ImMenu.GetVersion() >= 0.66, "ImMenu version is too old, please update it!")

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.Fonts
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

    tabs = { -- dont touch this, this is just for managing the tabs in the menu
    Aimbot = true,
    Visuals = false,
    Misc = false
    },

    Aimbot = {
        Aimbot = true,
        ChargeBot = true,
        AimbotFOV = 360,
        Silent = true,
    },
    Visuals = {
        EnableVisuals = false,
        Sphere = false,
        Section = 1,
        Sections = {"Local", "Target", "Experimental"},
        Local = {
            RangeCircle = true,
            path = {
                enable = true,
                Color = { 255, 255, 255, 255 },
                Styles = {"Pavement", "ArrowPath", "Arrows", "L Line" , "dashed", "line"},
                Style = 1,
            },
        },
        Target = {
            path = {
                enable = true,
                Color = { 255, 255, 255, 255 },
                Styles = {"Pavement", "ArrowPath", "Arrows", "L Line" , "dashed", "line"},
                Style = 1,
            },
        },
    },
    Misc = {
        ChargeControl = true,
        ChargeSensitivity = 50,
        CritRefill = {Active = true, NumCrits = 1},
        CritMode = 1,
        CritModes = {"Rage", "On Button"},
        InstantAttack = true,
        ChargeReach = false,
        TroldierAssist = false,
    },
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
        printc( 255, 183, 0, 255, "["..os.date("%H:%M:%S").."] Saved Config to ".. tostring(fullPath))
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
        if chunk then
            printc( 0, 255, 140, 255, "["..os.date("%H:%M:%S").."] Loaded Config from ".. tostring(fullPath))
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

-- Function to check if all expected functions exist in the loaded config
local function checkAllFunctionsExist(expectedMenu, loadedMenu)
    for key, value in pairs(expectedMenu) do
        if type(value) == 'function' then
            -- Check if the function exists in the loaded menu and has the correct type
            if not loadedMenu[key] or type(loadedMenu[key]) ~= 'function' then
                return false
            end
        end
    end
    for key, value in pairs(expectedMenu) do
        if not loadedMenu[key] or type(loadedMenu[key]) ~= type(value) then
            return false
        end
    end
    return true
end

-- Execute this block only if loading the config was successful
if status then
    if checkAllFunctionsExist(Menu, loadedMenu) and not input.IsButtonDown(KEY_LSHIFT) then
        Menu = loadedMenu
    else
        print("Config is outdated or invalid. Creating a new config.")
        CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) -- Save the config
    end
else
    print("Failed to load config. Creating a new config.")
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) -- Save the config
end

local closestDistance = 2000
local fDistance = 1
local hitbox_Height = 82
local hitbox_Width = 24
local isMelee = false
local mresolution = 64
local pLocal = entities.GetLocalPlayer()
local ping = 0
local swingrange = 48
local tickRate = 66
local tick_count = 0
local time = 15
local Gcan_attack = false
local Safe_Strafe = false
local can_charge = false
local Charge_Range = 128
local swingRangeMultiplier = 1
local defFakeLatency = gui.GetValue("Fake Latency Value (MS)")
local Backtrackpositions = {}
local pLocalPath = {}
local vPlayerPath = {}
local PredPath = {}
local vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local drawVhitbox = {}
local gravity = client.GetConVar("sv_gravity") or 800   -- Get the current gravity
local stepSize = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18
local backtrackTicks =  {}

local vdistance = nil
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
local target_strafeAngle = nil
local onGround = nil
local CurrentTarget = nil
local aimposVis = nil
local in_attack = nil

local settings = {
    MinDistance = 0,
    MaxDistance = 770,
    MinFOV = 0,
    MaxFOV = Menu.Aimbot.AimbotFOV,
}

local latency = 0
local lerp = 0
local lastAngles = {} ---@type table<number, Vector3>
local lastDeltas = {} ---@type table<number, number>
local avgDeltas = {} ---@type table<number, number>
local strafeAngles = {} ---@type table<number, number>
local inaccuracy = {} ---@type table<number, number>

local function CalcStrafe()
    local players = entities.FindByClass("CTFPlayer")
    for idx, entity in ipairs(players) do
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
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function checkPlayerState(player)
    local flags = player:GetPropInt("m_fFlags")
    local waterLevel = player:GetPropInt("m_nWaterLevel")

    -- Constants for flag bits
    local FL_ONGROUND = 1 << 0  -- Bit for being on the ground
    local FL_INWATER = 1 << 9   -- Bit for being in water

    local isSwimming = (flags & FL_INWATER) ~= 0 and waterLevel > 1
    local isWalking = (flags & FL_ONGROUND) ~= 0 and waterLevel <= 1

    return isSwimming, isWalking
end

    -- [WIP] Predict the position of a player
    ---@param player WPlayer
    ---@param t integer
    ---@param d number?
    ---@param shouldHitEntity fun(entity: WEntity, contentsMask: integer): boolean?
    ---@return { pos : Vector3[], vel: Vector3[], onGround: boolean[] }?
    local function PredictPlayer(player, t, d, Hitbox, shouldHitEntity)
        if not gravity or not stepSize then return nil end
        local vUp = Vector3(0, 0, 1)
        local vStep = Vector3(0, 0, stepSize)
        shouldHitEntity = shouldHitEntity or function(entity) return entity:GetIndex() ~= player:GetIndex() end --trace ignore simulated player 
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

            local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, Hitbox[1], Hitbox[2], MASK_PLAYERSOLID_BRUSHONLY, shouldHitEntity)
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
            local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, Hitbox[1], Hitbox[2], MASK_PLAYERSOLID_BRUSHONLY, shouldHitEntity)
            if groundTrace.fraction < 1 then
                -- We'll hit the ground
                local normal = groundTrace.plane
                local angle = math.deg(math.acos(normal:Dot(vUp)))

                -- Check the ground angle
                if angle < 45 then
                    if onGround1 and player:GetName() == pLocal:GetName() and gui.GetValue("Bunny Hop") == 1 and input.IsButtonDown(KEY_SPACE) then
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
            if not onGround1 and isSwimming then
                vel.z = vel.z - gravity * globals.TickInterval()
            end

            -- Add the prediction record
            _out.pos[i], _out.vel[i], _out.onGround[i] = pos, vel, onGround1
        end

        return _out
    end

    local function getBacktrackTicks(fakeLatency)
        local tickInterval = 0.015  -- Typical value is 0.015 for 66-tick servers
        local totalLatencyMs = fakeLatency + 200  -- Total latency in milliseconds
        local totalLatencySeconds = totalLatencyMs / 1000  -- Convert milliseconds to seconds
        local backtrackTicks = math.floor(totalLatencySeconds / tickInterval)  -- Calculate the number of ticks
        return backtrackTicks
    end

local playerTicks = {}

local function GetBestTarget(me)

    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    local bestTarget = nil
    local bestFactor = 0

    local localPlayerOrigin = localPlayer:GetAbsOrigin()
    local localPlayerViewAngles = engine.GetViewAngles()


    for _, player in ipairs(players) do
        if player ~= nil and player:GetIndex() ~= pLocal:GetIndex() and player:IsAlive() and not player:IsDormant() then
            if player:GetTeamNumber() ~= localPlayer:GetTeamNumber() then
                
        
                    --local minTick = math.floor((defFakeLatency / 900) / 0.015)
                    local maxTick = math.floor(((defFakeLatency) / 1000)  / 0.015)

                    local numBacktrackTicks = gui.GetValue("Fake Latency") == 1 and maxTick or gui.GetValue("Fake Latency") == 0 and gui.GetValue("Backtrack") == 1 and 4 or 0

                    if numBacktrackTicks ~= 0 then
                        local playerIndex = player:GetIndex()
                        playerTicks[playerIndex] = playerTicks[playerIndex] or {}
                        table.insert(playerTicks[playerIndex], player:GetAbsOrigin())

                        -- If the player's tick count exceeds maxinteger, remove the oldest tick
                        if #playerTicks[playerIndex] > numBacktrackTicks then
                            table.remove(playerTicks[playerIndex], 1)
                        end
                    end

                    local playerOrigin = player:GetAbsOrigin()
                    local distance = math.abs(playerOrigin.x - localPlayerOrigin.x) +
                                     math.abs(playerOrigin.y - localPlayerOrigin.y) +
                                     math.abs(playerOrigin.z - localPlayerOrigin.z)

                    if distance <= settings.MaxDistance then
                        local angles = Math.PositionAngles(localPlayerOrigin, playerOrigin + Vector3(0, 0, viewheight))
                        local fov = Math.AngleFov(localPlayerViewAngles, angles)

                        if fov <= settings.MaxFOV and distance < settings.MaxDistance then
                            local distanceFactor = Math.RemapValClamped(distance, settings.MinDistance, settings.MaxDistance, 1, 0.07)
                            local fovFactor = Math.RemapValClamped(fov, settings.MinFOV, settings.MaxFOV, 1, 0.9)
                            
                            -- Check if the player is visible
                            local isVisible = Helpers.VisPos(player, pLocalOrigin, player:GetAbsOrigin())
                            
                            -- Add a visibility factor to the calculation
                            local visibilityFactor = isVisible and 1.0 or 0.5

                            local factor = distanceFactor * fovFactor * visibilityFactor

                            if factor > bestFactor then
                                bestTarget = player
                                bestFactor = factor
                            end
                        end
                    end
                end
            end
        end

    return bestTarget
end

-- Define function to check InRange between the hitbox and the sphere
    local function checkInRange(targetPos, spherePos, sphereRadius)

        local inaccuracyValue = inaccuracy[vPlayer:GetIndex()]
        if not inaccuracyValue then return nil end

        local hitbox_min_trigger = drawVhitbox[1]
        local hitbox_max_trigger = drawVhitbox[2]

        -- Calculate the closest point on the hitbox to the sphere
        local closestPoint = Vector3(
            math.max(hitbox_min_trigger.x, math.min(spherePos.x, hitbox_max_trigger.x)),
            math.max(hitbox_min_trigger.y, math.min(spherePos.y, hitbox_max_trigger.y)),
            math.max(hitbox_min_trigger.z, math.min(spherePos.z, hitbox_max_trigger.z))
        )

        -- Calculate the vector from the closest point to the sphere center
        local distanceAlongVector = (spherePos - closestPoint):Length()
            -- Compare the distance along the vector to the sum of the radius
            if sphereRadius > distanceAlongVector then
                return true, closestPoint
            else
                -- Not InRange
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

-- Control the player's charge by adjusting the view angles based on mouse input
-- Parameters:
--   pCmd (CUserCmd): The user command
local function ChargeControl(pCmd)
    -- Get the current view angles
    local sensitivity = Menu.Misc.ChargeSensitivity / 2
    local currentAngles = engine.GetViewAngles()

    -- Get the mouse motion
    local mouseDeltaX = -(pCmd.mousedx * sensitivity / 10)

    -- Calculate the new yaw angle
    local newYaw = currentAngles.yaw + mouseDeltaX

    -- Interpolate between the current yaw and the new yaw
    local interpolationFraction = 1 / 66  -- Assuming the function is called 66 times per second
    local interpolatedYaw = currentAngles.yaw + (newYaw - currentAngles.yaw) * interpolationFraction

    -- Set the new view angles
    pCmd:SetViewAngles(currentAngles.pitch, interpolatedYaw, 0)
end

local hasNotified = false
local function checkInRangeWithLatency(playerIndex, swingRange)
        -- If latency is enabled, check if pLocalFuture or pLocalOrigin are in range to attack the ticks
        local closestPoint = nil
        local inRange = false
        local point = nil

        local Backtrack = gui.GetValue("Backtrack")
        local fakelatencyON = gui.GetValue("Fake Latency")

        if Backtrack == 0 and fakelatencyON == 0 then
            -- If latency is disabled, check if vPlayerOrigin is in range from pLocalOrigin
            inRange, point = checkInRange(vPlayerOrigin, pLocalOrigin, swingRange - 18)
            
            if inRange then
                return inRange, point
            else
                local inRange2, point2 = checkInRange(vPlayerFuture, pLocalFuture, swingRange)
                if inRange2 then
                    return inRange2, point2
                end
            end
        elseif fakelatencyON == 1 then
            -- Inside your function
            if not hasNotified then
                Notify.Simple("Fake Latency is enabled", " this may cause issues with the script", 7)
                hasNotified = true
            end

            -- Calculate the range of ticks to check based on the current latency
            local minTick = 1
            local maxTick = #playerTicks[playerIndex]

            -- Check from the newest to the oldest tick within the range
            for tick = minTick, maxTick do
                if playerTicks[playerIndex] then
                    local pastOrigin = playerTicks[playerIndex][tick]

                    inRange, point = checkInRange(pastOrigin, pLocalOrigin, swingRange)
                    if inRange then
                        return inRange, point
                    else
                        local inRange2, point2 = checkInRange(pastOrigin, pLocalFuture, swingRange)
                        if inRange2 then
                            return inRange2, point2
                        end
                    end
                end
            end
        elseif Backtrack == 1 then
             -- If latency is disabled, check if vPlayerOrigin is in range from pLocalOrigin
             inRange, point = checkInRange(vPlayerOrigin, pLocalOrigin, swingRange)
            
             if inRange then
                 return inRange, point
             else
                 local inRange2, point2 = checkInRange(vPlayerFuture, pLocalFuture, swingRange)
                 if inRange2 then
                     return inRange2, point2
                 end
             end
        end
    return false, nil
end

-- Initialize a counter outside of your game loop
local attackCounter = 0
-- Store the original Crit Hack Key value outside the main loop or function
local originalCritHackKey = gui.GetValue("Crit Hack Key")
local critkeyRestored = false

--[[ Code needed to run 66 times a second ]]--
-- Predicts player position after set amount of ticks
---@param strafeAngle number
local function OnCreateMove(pCmd)
    -- Get the local player entity
    pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        goto continue -- Return if the local player entity doesn't exist or is dead
    end

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

    -- Get the current latency and lerp
    local latOut = clientstate.GetLatencyOut()
    local latIn = clientstate.GetLatencyIn()
        lerp = client.GetConVar("cl_interp") or 0
        Latency = (latOut + lerp) -- Calculate the reaction time in seconds
        Latency = math.floor(Latency * tickRate + 1) -- Convert the delay to ticks
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
            -- If "pWeapon" is not set, break
            pUsingMargetGarden = true
            -- Set "pUsingProjectileWeapon" to true
        end                                        -- Set "pUsingProjectileWeapon" to false
    
--[--Troldier assist--]
    if Menu.Misc.TroldierAssist then
        local state = ""
        local downheight = Vector3(0, 0, -250)
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

local SwingHullSize = 36

if pWeaponDef:GetName() == "The Disciplinary Action" then
    SwingHullSize = 55.8
    swingrange = 81.6
end

    swingrange = swingrange + (SwingHullSize / 2)

--[--Manual charge control--]

    if Menu.Misc.ChargeControl and pLocal:InCond(17) then
        ChargeControl(pCmd)
    end

--[-----Get best target------------------]
    local keybind = Menu.Keybind
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
    if CurrentTarget == nil then
        local CritValue = 39  -- Base value for crit token bucket calculation
        local CritBucket = pWeapon:GetCritTokenBucket()
        local NumCrits = CritValue * Menu.Misc.CritRefill.NumCrits

        -- Cap NumCrits to ensure CritBucket does not exceed 1000
        NumCrits = math.clamp(NumCrits, 27, 1000)

        if Menu.Misc.CritRefill.Active then
            if CritBucket < NumCrits then
                -- Temporarily disable Crit Hack Key while refilling
                if critkeyRestored then
                    gui.SetValue("Crit Hack Key", 0)  -- Set to 0 to disable
                    critkeyRestored = false
                end
                gui.SetValue("Melee Crit Hack", 2) -- Stop using crit bucket to stock up crits
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            else
                -- Restore original Crit Hack Key value and enable crit hack
                if not critkeyRestored then
                    gui.SetValue("Crit Hack Key", originalCritHackKey)
                    critkeyRestored = true
                end
                gui.SetValue("Melee Crit Hack", Menu.Misc.CritMode)
            end
        else
            if not critkeyRestored then
                gui.SetValue("Crit Hack Key", originalCritHackKey)
                critkeyRestored = true
            end
            gui.SetValue("Melee Crit Hack", Menu.Misc.CritMode)
        end
    else
        -- Restore original Crit Hack Key value and enable crit hack
        if not critkeyRestored then
            gui.SetValue("Crit Hack Key", originalCritHackKey)
            critkeyRestored = true
        end
        gui.SetValue("Melee Crit Hack", Menu.Misc.CritMode)
    end

    local ONGround
    local Target_ONGround
    local strafeAngle = 0
    local can_attack = false
    local stop = false

--[--------------Prediction-------------------]
-- Predict both players' positions after swing
    gravity = client.GetConVar("sv_gravity")
    stepSize = pLocal:GetPropFloat("localdata", "m_flStepSize")

    CalcStrafe()
    if inaccuracyValue then
        swingrange = swingrange - inaccuracyValue
    end

    -- Local player prediction
    if pLocal:EstimateAbsVelocity() == 0 then
        -- If the local player is not accelerating, set the predicted position to the current position
        pLocalFuture = pLocalOrigin
    else
        local player = WPlayer.FromEntity(pLocal)

        strafeAngle = strafeAngles[pLocal:GetIndex()] or 0

        local predData = PredictPlayer(player, time, strafeAngle, vHitbox)

        pLocalPath = predData.pos
        pLocalFuture = predData.pos[time] + viewOffset
    end

-- stop if no target
if CurrentTarget == nil then
    vPlayerFuture = nil
    return
end
    vPlayerOrigin = CurrentTarget:GetAbsOrigin() -- Get closest player origin

    drawVhitbox = {}
    drawVhitbox[1] = vPlayerOrigin + vHitbox[1]
    drawVhitbox[2] = vPlayerOrigin + vHitbox[2]

    -- Target player prediction
    if CurrentTarget:EstimateAbsVelocity() == 0 then
        -- If the target player is not accelerating, set the predicted position to their current position
        vPlayerFuture = CurrentTarget:GetAbsOrigin()
    else
        local player = WPlayer.FromEntity(CurrentTarget)

        strafeAngle = strafeAngles[CurrentTarget:GetIndex()] or 0

        local predData = PredictPlayer(player, time, strafeAngle, drawVhitbox)

        vPlayerPath = predData.pos
        vPlayerFuture = predData.pos[time]
    end

            
--[--------------Distance check-------------------]
-- Get current distance between local player and closest player
vdistance = (vPlayerOrigin - pLocalOrigin):Length()

    -- Get distance between local player and closest player after swing
    fDistance = (vPlayerFuture - pLocalFuture):Length()

    local inRange, InRangePoint = checkInRangeWithLatency(CurrentTarget:GetIndex(), swingrange)
    -- Use inRange to decide if can attack
    can_attack = inRange

    -- Check for charge range bug
    if pLocalClass == 4 -- player is Demoman
        and Menu.Misc.ChargeReach -- menu option for such option is true
        and chargeLeft == 100 then -- charge metter is full
            if checkInRange(vPlayerOrigin, pLocalOrigin, Charge_Range) then
                can_attack = true
                tick_count = tick_count + 1
                if tick_count % (time - 2) == 0 then
                    can_charge = true
                end
            end
    end

--[--------------AimBot-------------------]                --get hitbox of ennmy pelwis(jittery but works)
    local hitboxes = CurrentTarget:GetHitboxes()
    local hitbox = hitboxes[6]
    local aimpos = nil


    if InRangePoint then
        aimpos = InRangePoint
    else
        aimpos = CurrentTarget:GetAbsOrigin() + Vheight --aimpos = (hitbox[1] + hitbox[2]) * 0.5 --if no InRange point accesable then aim at defualt hitbox
    end
    aimposVis = aimpos -- transfer aim point to visuals

    -- Calculate aim position only once
    aimpos = Math.PositionAngles(pLocalOrigin, aimpos)

    -- Inside your game loop
    if Menu.Aimbot.Aimbot then
        if pLocal:InCond(17) then
            if Menu.Aimbot.ChargeBot and Helpers.VisPos(CurrentTarget, vPlayerFuture, pLocalFuture) and not can_attack then
                -- Set view angles based on the future position of the local player
                pCmd:SetViewAngles(engine.GetViewAngles().pitch, aimpos.yaw, 0)
            end
        elseif can_attack then
            -- Set view angles based on whether silent aim is enabled
            if Menu.Aimbot.Silent then
                pCmd:SetViewAngles(aimpos.pitch, aimpos.yaw, 0)
            else
                engine.SetViewAngles(EulerAngles(aimpos.pitch, aimpos.yaw, 0))
            end
        end
    elseif Menu.Misc.ChargeControl and pLocal:InCond(17) then
        -- Control charge if charge bot is enabled and the local player is in condition 17
        ChargeControl(pCmd)
    end
    
    --Shield bashing strat
        if pLocalClass == 4 and pLocal:InCond(17) then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
            local Bashed = (pLocalOrigin - vPlayerOrigin):Length() < swingrange - 18 -- If we bashed on enemy

            if not Bashed then -- If Demoknight bashed on enemy
                can_attack = false
                goto continue
            end
        end

        --Check if attack simulation was succesfull
            if can_attack == true then
                --remove tick
                
                Gcan_attack = false
                if Menu.Misc.InstantAttack == true and warp.GetChargedTicks() > 15 then
                    warp.TriggerDoubleTap()
                    warp.TriggerWarp()
                end
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)-- attack

            elseif Menu.Misc.CritRefill then
                if pWeapon:GetCritTokenBucket() <= 18 and fDistance > 350 then
                    print(pWeapon:GetCritTokenBucket())
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)--refill
                end
                Gcan_attack = true
            else
                
                Gcan_attack = true
            end

            if can_charge then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)-- charge
            end

        -- Update last variables

            Safe_Strafe = false -- reset safe strafe
            can_charge = false
    ::continue::
end

local lastToggleTime = 0
local Lbox_Menu_Open = true
local toggleCooldown = 0.2  -- 200 milliseconds

-- Sphere cache and drawn edges cache
local sphere_cache = { vertices = {}, radius = 90, center = Vector3(0, 0, 0) }
local drawnEdges = {}

local function setup_sphere(center, radius, segments)
    sphere_cache.center = center
    sphere_cache.radius = radius
    sphere_cache.segments = segments
    sphere_cache.vertices = {}  -- Clear the old vertices

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
		for i, pos in pairs(vertices) do
			local convertedTbl = {pos[1], pos[2], 0, 0};

			cords[i], reverse_cords[sizeof - i + 1] = convertedTbl, convertedTbl;

			sum = sum + cross(pos, vertices[(i % sizeof) + 1]);
		end


		TexturedPolygon(white_texture, (sum < 0) and reverse_cords or cords, true)
	end
end)();


local function toggleMenu()
    local currentTime = globals.RealTime()
    if currentTime - lastToggleTime >= toggleCooldown then
        Lbox_Menu_Open = not Lbox_Menu_Open  -- Toggle the state
        lastToggleTime = currentTime  -- Reset the last toggle time
    end
end

local bindTimer = 0
local bindDelay = 0.25  -- Delay of 0.25 seconds

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

-- debug command: ent_fire !picker Addoutput "health 99999" --superbot
local Verdana = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
--[[ Code called every frame ]]--
local function doDraw()
if not (engine.Con_IsVisible() or engine.IsGameUIVisible()) then

        --local pLocal = entities.GetLocalPlayer()
        pWeapon = pLocal:GetPropEntity("m_hActiveWeapon") -- Set "pWeapon" to the local player's active weapon
    if Menu.Visuals.EnableVisuals or pWeapon:IsMeleeWeapon() and pLocal and pLocal:IsAlive() then
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()
        if Menu.Visuals.Local.RangeCircle and pLocalFuture then
                    draw.Color(255, 255, 255, 255)

                    local center = pLocalFuture - Vheight -- Center of the circle at the player's feet
                    local viewPos = pLocalOrigin -- View position to shoot traces from
                    local radius = Menu.Misc.ChargeReach and Charge_Range or swingrange  -- Radius of the circle
                    local segments = 32 -- Number of segments to draw the circle
                    local angleStep = (2 * math.pi) / segments

                    -- Determine the color of the circle based on TargetPlayer
                    local circleColor = TargetPlayer and {0, 255, 0, 255} or {255, 255, 255, 255} -- Green if TargetPlayer exists, otherwise white

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
                    -- Draw lines between the predicted positions
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
---------------------------------------------------------sphere
                if Menu.Visuals.Sphere then
                    -- Function to draw the sphere
                    local function draw_sphere()
                        local playerYaw = engine.GetViewAngles().yaw
                        local cos_yaw = math.cos(math.rad(playerYaw))
                        local sin_yaw = math.sin(math.rad(playerYaw))

                        local playerForward = Vector3(-cos_yaw, -sin_yaw, 0)  -- Forward vector based on player's yaw

                        for _, vertex in ipairs(sphere_cache.vertices) do
                            local rotated_vertex1 = Vector3(-vertex[1].x * cos_yaw + vertex[1].y * sin_yaw, -vertex[1].x * sin_yaw - vertex[1].y * cos_yaw, vertex[1].z)
                            local rotated_vertex2 = Vector3(-vertex[2].x * cos_yaw + vertex[2].y * sin_yaw, -vertex[2].x * sin_yaw - vertex[2].y * cos_yaw, vertex[2].z)
                            local rotated_vertex3 = Vector3(-vertex[3].x * cos_yaw + vertex[3].y * sin_yaw, -vertex[3].x * sin_yaw - vertex[3].y * cos_yaw, vertex[3].z)
                            local rotated_vertex4 = Vector3(-vertex[4].x * cos_yaw + vertex[4].y * sin_yaw, -vertex[4].x * sin_yaw - vertex[4].y * cos_yaw, vertex[4].z)

                            local worldPos1 = sphere_cache.center + rotated_vertex1 * sphere_cache.radius
                            local worldPos2 = sphere_cache.center + rotated_vertex2 * sphere_cache.radius
                            local worldPos3 = sphere_cache.center + rotated_vertex3 * sphere_cache.radius
                            local worldPos4 = sphere_cache.center + rotated_vertex4 * sphere_cache.radius

                            -- Trace from the center to the vertices with a hull size of 18x18
                            local hullSize = Vector3(18, 18, 18)
                            local trace1 = engine.TraceHull(sphere_cache.center, worldPos1, -hullSize, hullSize, MASK_SHOT_HULL)
                            local trace2 = engine.TraceHull(sphere_cache.center, worldPos2, -hullSize, hullSize, MASK_SHOT_HULL)
                            local trace3 = engine.TraceHull(sphere_cache.center, worldPos3, -hullSize, hullSize, MASK_SHOT_HULL)
                            local trace4 = engine.TraceHull(sphere_cache.center, worldPos4, -hullSize, hullSize, MASK_SHOT_HULL)

                            local endPos1 = trace1.fraction < 1.0 and trace1.endpos or worldPos1
                            local endPos2 = trace2.fraction < 1.0 and trace2.endpos or worldPos2
                            local endPos3 = trace3.fraction < 1.0 and trace3.endpos or worldPos3
                            local endPos4 = trace4.fraction < 1.0 and trace4.endpos or worldPos4

                            local screenPos1 = client.WorldToScreen(endPos1)
                            local screenPos2 = client.WorldToScreen(endPos2)
                            local screenPos3 = client.WorldToScreen(endPos3)
                            local screenPos4 = client.WorldToScreen(endPos4)

                            -- Calculate normal vector of the square
                            local normal = Normalize(rotated_vertex2 - rotated_vertex1):Cross(rotated_vertex3 - rotated_vertex1)

                            -- Draw square only if its normal faces towards the player
                            if normal:Dot(playerForward) > 0.1 then
                                if screenPos1 and screenPos2 and screenPos3 and screenPos4 then
                                    -- Draw the square
                                    drawPolygon({screenPos1, screenPos2, screenPos3, screenPos4})

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
                    sphere_cache.center = pLocalOrigin  -- Replace with actual player origin
                    sphere_cache.radius = swingrange    -- Replace with actual swing range value
                    draw_sphere()
                end

                    -- enemy
                    if vPlayerFuture then

                        -- Draw lines between the predicted positions
                        if Menu.Visuals.Target.path.enable then
                            if style == 1 then
                                -- Draw a double L line in both directions
                                for i = 1, #vPlayerPath - 1 do
                                    local pos1 = vPlayerPath[i]
                                    local pos2 = vPlayerPath[i + 1]
                        
                                    -- Draw the left side of the L line
                                    draw.Line(pos1[1], pos1[2], pos2[1], pos2[2])
                                    -- Draw the right side of the L line
                                    draw.Line(pos1[1] + 1, pos1[2] + 1, pos2[1] + 1, pos2[2] + 1)
                                end
                            elseif style == 2 then
                                -- Draw the path with arrows
                                -- ...
                            elseif style == 3 then
                                -- Draw arrows
                                -- ...
                            elseif style == 4 then
                                -- Draw an L line
                                -- ...
                            elseif style == 5 then
                                -- Draw a dashed line
                                -- ...
                            elseif style == 6 then
                                -- Draw a line
                                for i = 1, #vPlayerPath - 1 do
                                    local pos1 = vPlayerPath[i]
                                    local pos2 = vPlayerPath[i + 1]
                        
                                    local screenPos3 = client.WorldToScreen(pos1)
                                    local screenPos4 = client.WorldToScreen(pos2)
                        
                                    if screenPos3 ~= nil and screenPos4 ~= nil then
                                        draw.Line(screenPos3[1], screenPos3[2], screenPos4[1], screenPos4[2])
                                    end
                                end
                            end
                        end

                        if aimposVis then
                            --draw predicted local position with strafe prediction
                            local screenPos = client.WorldToScreen(aimposVis)
                            if screenPos ~= nil then
                                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
                            end
                        end
                
                        -- Calculate min and max points
                        local minPoint = drawVhitbox[1]
                        local maxPoint = drawVhitbox[2]

                        -- Calculate vertices of the AABB
                        -- Assuming minPoint and maxPoint are the minimum and maximum points of the AABB:
                        local vertices = {
                            Vector3(minPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-left
                            Vector3(minPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-left
                            Vector3(maxPoint.x, maxPoint.y, minPoint.z),  -- Bottom-front-right
                            Vector3(maxPoint.x, minPoint.y, minPoint.z),  -- Bottom-back-right
                            Vector3(minPoint.x, minPoint.y, maxPoint.z),  -- Top-back-left
                            Vector3(minPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-left
                            Vector3(maxPoint.x, maxPoint.y, maxPoint.z),  -- Top-front-right
                            Vector3(maxPoint.x, minPoint.y, maxPoint.z)   -- Top-back-right
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

        -- Inside your OnCreateMove or similar function where you check for input
    if input.IsButtonDown(KEY_INSERT) then  -- Replace 72 with the actual key code for the button you want to use
        toggleMenu()
    end

    if Lbox_Menu_Open == true and ImMenu and ImMenu.Begin("Swing Prediction", true) then
            ImMenu.BeginFrame(1) -- tabs
                if ImMenu.Button("Aimbot") then
                    Menu.tabs.Aimbot = true
                    Menu.tabs.Misc = false
                    Menu.tabs.Visuals = false
                end
                if ImMenu.Button("Misc") then
                    Menu.tabs.Aimbot = false
                    Menu.tabs.Misc = true
                    Menu.tabs.Visuals = false
                end
                if ImMenu.Button("Visuals") then
                    Menu.tabs.Aimbot = false
                    Menu.tabs.Misc = false
                    Menu.tabs.Visuals = true
                end
            ImMenu.EndFrame()

            if Menu.tabs.Aimbot then
                ImMenu.BeginFrame(1)
                    Menu.Aimbot.Aimbot = ImMenu.Checkbox("Enable", Menu.Aimbot.Aimbot)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Menu.Aimbot.Silent = ImMenu.Checkbox("Silent Aim", Menu.Aimbot.Silent)
                    Menu.Aimbot.ChargeBot = ImMenu.Checkbox("Charge Bot", Menu.Aimbot.ChargeBot)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Menu.Aimbot.AimbotFOV = ImMenu.Slider("Fov", Menu.Aimbot.AimbotFOV, 1, 360)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    ImMenu.Text("Keybind: ")
                    Menu.Keybind, Menu.KeybindName = handleKeybind("Always On", Menu.Keybind,  Menu.KeybindName)
                ImMenu.EndFrame()
            end

            if Menu.tabs.Misc then
                ImMenu.BeginFrame(1)
                    Menu.Misc.ChargeReach = ImMenu.Checkbox("Charge Reach", Menu.Misc.ChargeReach)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Menu.Misc.InstantAttack = ImMenu.Checkbox("Instant Attack", Menu.Misc.InstantAttack)
                    Menu.Misc.TroldierAssist = ImMenu.Checkbox("Troldier Assist", Menu.Misc.TroldierAssist)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Menu.Misc.CritRefill.Active = ImMenu.Checkbox("Auto Crit refill", Menu.Misc.CritRefill.Active)
                    Menu.Misc.CritRefill.NumCrits = ImMenu.Slider("Crit Number", Menu.Misc.CritRefill.NumCrits, 1, 25)
                ImMenu.EndFrame()
                ImMenu.BeginFrame(1)
                    if Menu.Misc.CritRefill.Active then
                        Menu.Misc.CritMode = ImMenu.Option(Menu.Misc.CritMode, Menu.Misc.CritModes)
                    end
                ImMenu.EndFrame()


                ImMenu.BeginFrame(1)
                    Menu.Misc.ChargeControl = ImMenu.Checkbox("Charge Control", Menu.Misc.ChargeControl)
                ImMenu.EndFrame()

                ImMenu.BeginFrame(1)
                    Menu.Misc.ChargeSensitivity = ImMenu.Slider("Control Sensetivity", Menu.Misc.ChargeSensitivity, 1, 100)
                ImMenu.EndFrame()
            end
            
            if Menu.tabs.Visuals then
                ImMenu.BeginFrame(1)
                Menu.Visuals.EnableVisuals = ImMenu.Checkbox("Enable", Menu.Visuals.EnableVisuals)
                ImMenu.EndFrame()
        
                ImMenu.BeginFrame(1)
                    Menu.Visuals.Section = ImMenu.Option(Menu.Visuals.Section, Menu.Visuals.Sections)
                ImMenu.EndFrame()

                if Menu.Visuals.Section == 1 then
                    Menu.Visuals.Local.RangeCircle = ImMenu.Checkbox("Range Circle", Menu.Visuals.Local.RangeCircle)
                    Menu.Visuals.Local.path.enable = ImMenu.Checkbox("Local Path", Menu.Visuals.Local.path.enable)
                    Menu.Visuals.Local.path.Style = ImMenu.Option(Menu.Visuals.Local.path.Style, Menu.Visuals.Local.path.Styles)
                end

                if Menu.Visuals.Section == 2 then
                    Menu.Visuals.Target.path.enable = ImMenu.Checkbox("Target Path", Menu.Visuals.Target.path.enable)
                    Menu.Visuals.Target.path.Style = ImMenu.Option(Menu.Visuals.Target.path.Style, Menu.Visuals.Target.path.Styles)
                end

                if Menu.Visuals.Section == 3 then
                    ImMenu.BeginFrame(1)
                    ImMenu.Text("Experimental")
                    Menu.Visuals.Sphere = ImMenu.Checkbox("Range Shield", Menu.Visuals.Sphere)
                    ImMenu.EndFrame()
                end

                --[[ImMenu.BeginFrame(1)
                Menu.Visuals.Visualization = ImMenu.Checkbox("Visualization", Menu.Visuals.Visualization)
                Menu.Visuals.RangeCircle = ImMenu.Checkbox("Range Circle", Menu.Visuals.RangeCircle)
                ImMenu.EndFrame()]]


            end
        ImMenu.End()
    end
end

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    UnloadLib() --unloading lualib
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu) --saving the config
    client.Command('play "ui/buttonclickrelease"', true) -- Play the "buttonclickrelease" sound
end

--[[ Unregister previous callbacks ]]--
callbacks.Unregister("CreateMove", "MCT_CreateMove")            -- Unregister the "CreateMove" callback
callbacks.Unregister("Unload", "MCT_Unload")                    -- Unregister the "Unload" callback
callbacks.Unregister("Draw", "MCT_Draw")                        -- Unregister the "Draw" callback
--[[ Register callbacks ]]--
callbacks.Register("CreateMove", "MCT_CreateMove", OnCreateMove)             -- Register the "CreateMove" callback
callbacks.Register("Unload", "MCT_Unload", OnUnload)                         -- Register the "Unload" callback
callbacks.Register("Draw", "MCT_Draw", doDraw)                               -- Register the "Draw" callback
--[[ Play sound when loaded ]]--
client.Command('play "ui/buttonclick"', true) -- Play the "buttonclick" sound when the script is loaded