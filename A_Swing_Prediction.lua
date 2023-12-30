--[[ Swing prediction for  Lmaobox  ]]--
--[[      (Modded misc-tools)       ]]--
--[[          --Authors--           ]]--
--[[           Terminator           ]]--
--[[  (github.com/titaniummachine1  ]]--

local menuLoaded, MenuLib = pcall(require, "Menu")                                -- Load MenuLib
assert(menuLoaded, "MenuLib not found, please install it!")                       -- If not found, throw error
---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
UnloadLib() --unloads all packages

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon, WEntity = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon, lnxLib.TF2.WEntity
local Helpers = lnxLib.TF2.Helpers
local Prediction = lnxLib.TF2.Prediction
local Fonts = lnxLib.UI.Fonts

--[[ Menu ]]--
local menu = MenuLib.Create("Swing Prediction", MenuFlags.AutoSize)
menu.Style.TitleBg = { 205, 95, 50, 255 } -- Title Background Color (Flame Pea)
menu.Style.Outline = true                 -- Outline around the menu

--[[menu:AddComponent(MenuLib.Button("Debug", function() -- Disable Weapon Sway (Executes commands)
    client.SetConVar("cl_vWeapon_sway_interp",              0)             -- Set cl_vWeapon_sway_interp to 0
    client.SetConVar("cl_jiggle_bone_framerate_cutoff", 0)             -- Set cl_jiggle_bone_framerate_cutoff to 0
    client.SetConVar("cl_bobcycle",                     10000)         -- Set cl_bobcycle to 10000
    client.SetConVar("sv_cheats", 1)                                    -- debug fast setup
    client.SetConVar("mp_disable_respawn_times", 1)
    client.SetConVar("mp_respawnwavetime", -1)
    client.SetConVar("mp_teams_unbalance_limit", 1000)
end, ItemFlags.FullWidth))]]


local mFov          = menu:AddComponent(MenuLib.Slider("Aimbot FOV",10 ,360 ,360 ))
local Maimbot       = menu:AddComponent(MenuLib.Checkbox("Aimbot", true, ItemFlags.FullWidth))
local MSilent       = menu:AddComponent(MenuLib.Checkbox("Silent ^", true, ItemFlags.FullWidth))
local Mchargebot    = menu:AddComponent(MenuLib.Checkbox("Charge Controll", true, ItemFlags.FullWidth))
local mSensetivity  = menu:AddComponent(MenuLib.Slider("Charge Sensetivity",1 ,100 ,50 ))
local mAutoRefill   = menu:AddComponent(MenuLib.Checkbox("Crit Refill", true))
local mInstaHit   = menu:AddComponent(MenuLib.Checkbox("Instant attack", true))
local mWhipMate   = menu:AddComponent(MenuLib.Checkbox("Whip teamamtes", true))
--local AutoFakelat   = menu:AddComponent(MenuLib.Checkbox("Adaptive Latency", true, ItemFlags.FullWidth))
local AchargeRange  = menu:AddComponent(MenuLib.Checkbox("Charge Reach", false, ItemFlags.FullWidth))
local mAutoGarden   = menu:AddComponent(MenuLib.Checkbox("Troldier assist", false))
local mmVisuals     = menu:AddComponent(MenuLib.Checkbox("Enable Visuals", false))
local mKeyOverrite  = menu:AddComponent(MenuLib.Keybind("Keybind", key))

local Visuals = {
    ["Range Circle"] = true,
    ["Visualization"] = true
}
local mVisuals = menu:AddComponent(MenuLib.MultiCombo("^Visuals", Visuals, ItemFlags.FullWidth))


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
local gravity = client.GetConVar("sv_gravity") or 800   -- Get the current gravity
local stepSize = pLocal:GetPropFloat("localdata", "m_flStepSize") or 18

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
    MinDistance = 100,
    MaxDistance = 1000,
    MinFOV = 0,
    MaxFOV = 360,
}

local latency = 0
local lerp = 0
local lastAngles = {} ---@type table<number, EulerAngles>
local strafeAngles = {} ---@type table<number, number>
local strafeAngleHistories = {} ---@type table<number, table<number, number>>
local MAX_ANGLE_HISTORY = 4  -- Number of past angles to consider for averaging

---@param me WPlayer
local function CalcStrafe(me)
    local players = entities.FindByClass("CTFPlayer")
    for idx, entity in ipairs(players) do
        local entityIndex = entity:GetIndex()

        if entity:IsDormant() or not entity:IsAlive() then
            lastAngles[entityIndex] = nil
            strafeAngles[entityIndex] = nil
            strafeAngleHistories[entityIndex] = nil
            goto continue
        end

        if entity:GetTeamNumber() == me:GetTeamNumber() then
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        local angle = v:Angles()

        strafeAngleHistories[entityIndex] = strafeAngleHistories[entityIndex] or {}
        
        if lastAngles[entityIndex] == nil then
            lastAngles[entityIndex] = angle
            goto continue
        end

        local delta = angle.y - lastAngles[entityIndex].y

        -- Filtering out excessive changes
        if #strafeAngleHistories[entityIndex] > 0 then
            local lastDelta = strafeAngleHistories[entityIndex][#strafeAngleHistories[entityIndex]]
            if math.abs(delta - lastDelta) <= 90 then
                table.insert(strafeAngleHistories[entityIndex], delta)
            end
        else
            table.insert(strafeAngleHistories[entityIndex], delta)
        end

        if #strafeAngleHistories[entityIndex] > MAX_ANGLE_HISTORY then
            table.remove(strafeAngleHistories[entityIndex], 1)
        end

        -- Smoothing
        local weightedSum = 0
        local weight = 0.5
        local totalWeight = 0
        for i, delta1 in ipairs(strafeAngleHistories[entityIndex]) do
            weightedSum = weightedSum + delta1 * weight
            totalWeight = totalWeight + weight
            weight = weight * 0.9
        end
        local avgDelta = weightedSum / totalWeight

        strafeAngles[entityIndex] = avgDelta
        lastAngles[entityIndex] = angle

        ::continue::
    end
end



    local fFalse = function () return false end

    -- [WIP] Predict the position of a player
    ---@param player WPlayer
    ---@param t integer
    ---@param d number?
    ---@param shouldHitEntity fun(entity: WEntity, contentsMask: integer): boolean?
    ---@return { pos : Vector3[], vel: Vector3[], onGround: boolean[] }?
    local function PredictPlayer(player, t, d, shouldHitEntity)
        if not gravity or not stepSize then return nil end
        local vUp = Vector3(0, 0, 1)
        local vStep = Vector3(0, 0, stepSize)
        shouldHitEntity = shouldHitEntity or fFalse
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

            local wallTrace = engine.TraceHull(lastP + vStep, pos + vStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
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
            local groundTrace = engine.TraceHull(pos + vStep, pos - downStep, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID, shouldHitEntity)
            if groundTrace.fraction < 1 then
                -- We'll hit the ground
                local normal = groundTrace.plane
                local angle = math.deg(math.acos(normal:Dot(vUp)))

                -- Check the ground angle
                if angle < 45 then
                    if onGround1 and player:GetName() == pLocal:GetName() and gui.GetValue("Bunny Hop") and input.IsButtonDown(KEY_SPACE) then
                        -- Jump
                        vel.z = 271
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

---@param me WPlayer
---@return AimTarget? target
local function GetBestTarget(me)
    settings = {
        MinDistance = swingrange,
        MaxDistance = 770,
        MinFOV = 0,
        MaxFOV = 360,
    }

    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    local localPlayerOrigin = localPlayer:GetAbsOrigin()
    local localPlayerTeam = localPlayer:GetTeamNumber()
    local localPlayerViewAngles = engine.GetViewAngles()

    local targetList = {}
    local targetCount = 0
    -- Calculate target factors
    for i, player in ipairs(players) do
        local playerTeam = player:GetTeamNumber()
        local playerOrigin = player:GetAbsOrigin()

        -- Check if the player is invalid
        if player == nil or player == pLocal or not player:IsAlive() or player:IsDormant() then
            goto continue
        end

        -- Check if we have a whip and the "whip teammates" option is off, but the player is on the local player's team
        if not mWhipMate:GetValue() and swingrange == 109.5 and playerTeam == localPlayerTeam then
            goto continue
        elseif mWhipMate:GetValue() and swingrange ~= 109.5 and playerTeam == localPlayerTeam then
            goto continue
        end
    
        if gui.GetValue("ignore cloaked") == 1 and player:InCond(4) then
            goto continue
        end
    
        if not Helpers.VisPos(player, localPlayerOrigin, playerOrigin) then
            goto continue
        end

    
        -- Calculate Manhattan distance
        local distance = math.abs(playerOrigin.x - localPlayerOrigin.x) + math.abs(playerOrigin.y - localPlayerOrigin.y) + math.abs(playerOrigin.z - localPlayerOrigin.z)
    
        if distance > settings.MaxDistance then
            goto continue
        end

        local angles = Math.PositionAngles(localPlayerOrigin, playerOrigin + Vector3(0, 0, viewheight))
        local fov = Math.AngleFov(localPlayerViewAngles, angles)

        if fov > settings.MaxFOV then
            goto continue
        end

        local distanceFactor = Math.RemapValClamped(distance, settings.MinDistance, settings.MaxDistance, 1, 0.07)
        local fovFactor = Math.RemapValClamped(fov, settings.MinFOV, settings.MaxFOV, 1, 1)

        local factor = distanceFactor * fovFactor

        targetCount = targetCount + 1
        targetList[targetCount] = { player = player, factor = factor }

        ::continue::
    end

    -- Sort target list by factor in descending order manually
    for i = 1, targetCount - 1 do
        for j = 1, targetCount - i do
            if targetList[j].factor < targetList[j + 1].factor then
                targetList[j], targetList[j + 1] = targetList[j + 1], targetList[j]
            end
        end
    end

    local bestTarget = nil

    if targetCount > 0 then
        local bestPlayer = targetList[1].player
        local bestPlayerOrigin = bestPlayer:GetAbsOrigin()
        local aimPos = bestPlayerOrigin + Vector3(0, 0, 75)
        local angles = Math.PositionAngles(localPlayerOrigin, aimPos)
        local fov = Math.AngleFov(angles, localPlayerViewAngles)

        -- Set as best target
        bestTarget = { entity = bestPlayer, angles = angles, factor = targetList[1].factor }
    end

    return bestTarget
end


-- Define function to check InRange between the hitbox and the sphere
    local function checkInRange(targetPos, spherePos, sphereRadius, target)
        if vPlayerFuture == nil or not isMelee then
            return false, nil
        end
        
        local hitbox_min = Vector3(-hitbox_Width, -hitbox_Width, 0)
        local hitbox_max = Vector3(hitbox_Width, hitbox_Width, hitbox_Height)
        local hitbox_min_trigger = (targetPos + hitbox_min)
        local hitbox_max_trigger = (targetPos + hitbox_max)
    
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
            -- InRange detected (including intersecting)
            return true, closestPoint
            
        else
            -- No InRange
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
    local sensitivity = mSensetivity:GetValue() / 2
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



--[[Calculates the FOV between two angles and returns x and y position differences
---@param vFrom EulerAngles
---@param vTo EulerAngles
---@return number fov, number deltaX, number deltaY
local function AngleFovAndPositionDifference(vFrom, vTo)
    if vFrom == nil or vTo == nil then return 0,0,0 end

    local vSrc = vFrom:Forward()
    local vDst = vTo:Forward()

    -- Calculate the FOV
    local fov = math.deg(math.acos(vDst:Dot(vSrc) / vDst:LengthSqr()))

    -- Calculate the position differences
    local deltaX = vTo.x - vFrom.x
    local deltaY = vTo.y - vFrom.y

    return fov, deltaX, deltaY
end]]

local function calculateHitChancePercentage(lastPredictedPos, currentPos)
    if not lastPredictedPos then
        print("lastPosiion is NiLL ~~!!!!")
        return 0
    end
    local horizontalDistance = math.sqrt((currentPos.x - lastPredictedPos.x)^2 + (currentPos.y - lastPredictedPos.y)^2)

    local verticalDistanceUp = currentPos.z - lastPredictedPos.z + 10

    local verticalDistanceDown = (lastPredictedPos.z - currentPos.z) - 10
    
    -- You can adjust these values based on game's mechanics
    local maxHorizontalDistance = 40
    local maxVerticalDistanceUp = 50
    local maxVerticalDistanceDown = 50
    
    if horizontalDistance > maxHorizontalDistance or verticalDistanceUp > maxVerticalDistanceUp or verticalDistanceDown > maxVerticalDistanceDown then
        return 0 -- No chance to hit
    else
        local horizontalHitChance = 100 - (horizontalDistance / maxHorizontalDistance) * 100
        local verticalHitChance = 100 - (verticalDistanceUp / maxVerticalDistanceUp) * 100
        local overallHitChance = (horizontalHitChance + verticalHitChance) / 2
        return overallHitChance
    end
end

-- Initialize a counter outside of your game loop
local attackCounter = 0

--[[ Code needed to run 66 times a second ]]--
-- Predicts player position after set amount of ticks
---@param targetLastPos Vector3
---@param Ltime integer
---@param targetEntity number
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
    if mAutoGarden:GetValue() == true then
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
   -- local hitboxData = pLocal:EntitySpaceHitboxSurroundingBox()
    --local hitboxSize = hitboxData[1]
--local hitboxHeight = hitboxSize.z

--hitboxSize.z = 0 -- Set z component to 0 to get the horizontal size
--print(-hitboxSize.y)
-- Now you can use hitboxSize and hitboxHeight as variables representing the size and height of the hitbox respectively

local SwingHullSize = 36

if pWeaponDef:GetName() == "The Disciplinary Action" then
    SwingHullSize = 55.8
    swingrange = 81.6
end

    swingrange = swingrange + (SwingHullSize / 2)

    --[[
local forwardPosition = Vector3(
    pLocalOrigin.x + hitboxSize,
    pLocalOrigin.y + hitboxSize + swingrange,
    pLocalOrigin.z + hitboxSize
)

local cornerposition = Vector3( --ToDO: fix this
    pLocalOrigin.x,
    pLocalOrigin.y+ hitboxSize + swingrange,
    pLocalOrigin.z
)]]

--local distanceCorner = (pLocalOrigin - cornerposition):Length()

--local fov, offsetx, offsety = AngleFovAndPositionDifference(engine.GetViewAngles().x, cornerposition)

--[--Manual charge control--]

    if Mchargebot:GetValue() and pLocal:InCond(17) then
        ChargeControl(pCmd)
    end

--[-----Get best target------------------]
    local keybind = mKeyOverrite:GetValue()
        if keybind == KEY_NONE and GetBestTarget(pLocal) ~= nil then
            -- Check if player has no key bound
            CurrentTarget = GetBestTarget(pLocal).entity
            vPlayer = CurrentTarget
        elseif input.IsButtonDown(keybind) and GetBestTarget(pLocal) ~= nil then
            -- If player has bound key for aimbot, only work when it's on
            CurrentTarget = GetBestTarget(pLocal).entity
            vPlayer = CurrentTarget
        else
            CurrentTarget = nil
        end

    -- Refill and return when noone to target
    if CurrentTarget == nil then
        if mAutoRefill:GetValue() and pWeapon:GetCritTokenBucket() <= 27 then
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
        end
        goto continue
    end

    vPlayerOrigin = CurrentTarget:GetAbsOrigin() -- Get closest player origin
    local ONGround
    local Target_ONGround
    local strafeAngle = 0
    local can_attack = false
    local stop = false

--[--------------Prediction-------------------]
-- Predict both players' positions after swing
    gravity = client.GetConVar("sv_gravity")
    stepSize = pLocal:GetPropFloat("localdata", "m_flStepSize")

    -- Local player prediction
    if pLocal:EstimateAbsVelocity() == 0 then
        -- If the local player is not accelerating, set the predicted position to the current position
        pLocalFuture = pLocalOrigin
    else
        local player = WPlayer.FromEntity(pLocal)
        CalcStrafe(player)

        strafeAngle = strafeAngles[pLocal:GetIndex()] or 0

        local predData = PredictPlayer(player, time, strafeAngle)
        --local straightPredData = PredictPlayer(player, time, 0, vHitbox)

        if predData == nil then
            goto continue
        end

        pLocalPath = predData.pos
        pLocalFuture = predData.pos[time] + viewOffset
    end

    -- Target player prediction
    if CurrentTarget:EstimateAbsVelocity() == 0 then
        -- If the target player is not accelerating, set the predicted position to their current position
        vPlayerFuture = CurrentTarget:GetAbsOrigin()
    else
        local player = WPlayer.FromEntity(CurrentTarget)
        CalcStrafe(player)

        strafeAngle = strafeAngles[CurrentTarget:GetIndex()] or 0

        local predData = PredictPlayer(player, time, strafeAngle)
        --local straightPredData = PredictPlayer(player, time, 0, vHitbox)

        if not predData then
            goto continue
        end

        --local hitchance = calculateHitChancePercentage(predData.pos[time], straightPredData.pos[time])
        --if hitchance < 10 then
            --predData = straightPredData
        --end

        vPlayerPath = predData.pos
        vPlayerFuture = predData.pos[time]
    end

            
--[--------------Distance check-------------------]
-- Get current distance between local player and closest player
vdistance = (vPlayerOrigin - pLocalOrigin):Length()

-- Get distance between local player and closest player after swing
fDistance = (vPlayerFuture - pLocalFuture):Length()

-- Check for InRange with current position
local InRange1, InRangePoint = checkInRange(vPlayerOrigin, pLocalOrigin, swingrange)
local InRange2 = checkInRange(vPlayerFuture, pLocalFuture, swingrange)

-- Use an OR gate to set InRange to true if either InRange1 or InRange2 is true
InRange = InRange1 or InRange2

-- Decide if can attack based on InRange
can_attack = InRange

    -- Check for charge range bug
    if pLocalClass == 4 -- player is Demoman
        and AchargeRange:GetValue() -- menu option for such option is true
        and chargeLeft == 100 then -- charge metter is full
            if InRange then
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


    if InRangePoint ~= nil then

        aimpos = InRangePoint

    elseif aimpos == nil then
        aimpos = CurrentTarget:GetAbsOrigin() + Vheight --aimpos = (hitbox[1] + hitbox[2]) * 0.5 --if no InRange point accesable then aim at defualt hitbox
    end

    aimposVis = aimpos -- transfer aim point to visuals
    local Eaimpos = aimpos

    local angles = Math.PositionAngles(pLocalOrigin, Eaimpos)
    local fov = Math.AngleFov(engine.GetViewAngles(), angles)

    flags = pLocal:GetPropInt("m_fFlags")
    if fov > settings.MaxFOV then
        goto continue
    end
    
    -- Calculate aim position only once
    Eaimpos = Math.PositionAngles(pLocalOrigin, Eaimpos)
    -- Inside your game loop
    if Maimbot:GetValue() then
        if Helpers.VisPos(CurrentTarget, vPlayerFuture, pLocalFuture) and not can_attack and pLocal:InCond(17) then
            -- Set view angles based on the future position of the local player
            pCmd:SetViewAngles(engine.GetViewAngles().pitch, Eaimpos.yaw, 0)
        elseif InRange then
                -- Set view angles based on whether silent aim is enabled
                if MSilent:GetValue() then
                    pCmd:SetViewAngles(Eaimpos.pitch, Eaimpos.yaw, 0)
                else
                    engine.SetViewAngles(EulerAngles(Eaimpos.pitch, Eaimpos.yaw, 0))
                end
        end
    elseif Mchargebot:GetValue() and pLocal:InCond(17) then
        -- Control charge if charge bot is enabled and the local player is in condition 17
        ChargeControl(pCmd)
    end
    
    -- Shield bashing strat
        if pLocalClass == 4 and pLocal:InCond(17) then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
            local Bashed = checkInRange(vPlayerOrigin, pLocalOrigin, 20)

            if not Bashed then -- If Demoknight bashed on enemy
                can_attack = false
                goto continue
            end
        end

        --Check if attack simulation was succesfull
            if can_attack == true then
                --remove tick
                
                Gcan_attack = false
                if mInstaHit:GetValue() == true and warp.GetChargedTicks() > 15 then
                    warp.TriggerDoubleTap()
                    warp.TriggerWarp()
                end
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)-- attack

            elseif mAutoRefill:GetValue() == true then
                if pWeapon:GetCritTokenBucket() <= 18 and fDistance > 350 then
                    print(pWeapon:GetCritTokenBucket())
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)--refill
                end
                Gcan_attack = true
            else
                
                Gcan_attack = true
            end

            if can_charge and CurrentTarget:IsAlive() then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)-- charge
            end

        -- Update last variables

            Safe_Strafe = false -- reset safe strafe
            aimposVis = aimpos -- transfer aim point to visuals
    ::continue::
end

-- debug command: ent_fire !picker Addoutput "health 99999" --superbot
local Verdana = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
--[[ Code called every frame ]]--
local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() or not pLocal or pLocal:IsAlive() == nil then
        return
    end
    if vPlayerOrigin == nil then return end
    if vPlayerFuture == nil or pLocalFuture == nil then return end

    --local pLocal = entities.GetLocalPlayer()
    pWeapon = pLocal:GetPropEntity("m_hActiveWeapon") -- Set "pWeapon" to the local player's active weapon
if not mmVisuals:GetValue() or not pWeapon:IsMeleeWeapon() then return end

    if pLocalFuture == nil or not pLocal:IsAlive() then return end
    if CurrentTarget == nil then return end
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()

            --draw predicted local position with strafe prediction
            local screenPos = client.WorldToScreen(aimposVis)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end

                -- Calculate trigger box vertices
                local vertices = {
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, 0)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(-hitbox_Width, -hitbox_Width, hitbox_Height)),
                    client.WorldToScreen(vPlayerFuture + Vector3(hitbox_Width, -hitbox_Width, hitbox_Height))
                }

                -- Check if vertices are not nil
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
                    if vertices[1] and vertices[5] then draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2]) end
                    if vertices[2] and vertices[6] then draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2]) end
                    if vertices[3] and vertices[7] then draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2]) end
                    if vertices[4] and vertices[8] then draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2]) end
                end


        -- Strafe prediction visualization
        if mVisuals:IsSelected("Visualization") then
            draw.Color(255, 255, 255, 255)

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

            -- enemy

            -- Draw lines between the predicted positions
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

        -- Check if the range circle is selected, the player future is not nil, and the player is melee
    if not pLocal:IsAlive() and not mVisuals:IsSelected("Range Circle") or vPlayerFuture == nil  or isMelee == nil  and GetBestTarget(pLocal) == nil then
        return
    end

    -- Define the two colors to interpolate between
    local color_close = {r = 255, g = 0, b = 0, a = 255} -- red
    local color_far = {r = 0, g = 0, b = 255, a = 255} -- blue

    -- Calculate the target distance for the color to be completely at the close color
    local target_distance = swingrange

    -- Calculate the vertex positions around the circle
    local center = pLocalFuture - Vheight
    local radius = swingrange -- radius of the circle
    local segments = 32 -- number of segments to use for the circle
    vertices = {} -- table to store circle vertices
    local colors = {} -- table to store colors for each vertex

    for i = 1, segments do
        local angle = math.rad(i * (360 / segments))
        local direction = Vector3(math.cos(angle), math.sin(angle), 0)
        if center == nil or direction == nil or radius == nil then return end
        
        local endpos = center + direction * radius
        local trace = engine.TraceLine(pLocalFuture, endpos, MASK_SHOT_HULL)

        local distance_to_hit = math.min((trace.endpos - center):Length(), radius)

        local x = center.x + math.cos(angle) * distance_to_hit
        local y = center.y + math.sin(angle) * distance_to_hit
        local z = center.z + 1

        -- adjust the height based on distance to trace hit point
        if distance_to_hit > 0 then
            local max_height_adjustment = 82 -- adjust as needed
            local height_adjustment = (1 - distance_to_hit / radius) * max_height_adjustment
            z = z + height_adjustment
        end

        vertices[i] = client.WorldToScreen(Vector3(x, y, z))
    end

    -- Calculate the top vertex position
    local top_height = 82 -- adjust as needed
    local top_vertex = client.WorldToScreen(Vector3(center.x, center.y, center.z + top_height))
    local color = {r = 0, g = 0, b = 255, a = 255} -- blue
    draw.Color(color.r, color.g, color.b, color.a)
    if not Gcan_attack then
        color = {r = 52, g = 235, b = 97, a = 255} -- red
        draw.Color(color.r, color.g, color.b, color.a)
    end
    -- Draw the circle and connect all the vertices to the top point
    for i = 1, segments do
        local j = i + 1
        if j > segments then j = 1 end
        if vertices[i] and vertices[j] then
            draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
        end
    end

    -- Draw a second circle if AchargeRange is enabled
    --center = pLocal:GetAbsOrigin()
    if pLocalClass == 4 and AchargeRange:GetValue() and chargeLeft >= 100 then
        -- Define the color for the second circle
        color = {r = 255, g = 0, b = 0, a = 255} -- red

        -- Calculate the radius for the second circle
        local radius2 = Charge_Range

        -- Calculate the vertex positions around the second circle
        local vertices2 = {} -- table to store circle vertices
        for i = 1, segments do
            local angle = math.rad(i * (360 / segments))
            local direction = Vector3(math.cos(angle), math.sin(angle), 0)
            local endpos = center + direction * radius2
            local trace = engine.TraceLine(pLocalFuture, endpos, MASK_SHOT_HULL)

            local distance_to_hit = math.min((trace.endpos - center):Length(), radius2)

            local x = center.x + math.cos(angle) * distance_to_hit
            local y = center.y + math.sin(angle) * distance_to_hit
            local z = center.z + 1

            -- adjust the height based on distance to trace hit point
            if distance_to_hit > 0 then
                local max_height_adjustment = 82 -- adjust as needed
                local height_adjustment = (1 - distance_to_hit / radius2) * max_height_adjustment
                z = z + height_adjustment
            end

            vertices2[i] = client.WorldToScreen(Vector3(x, y, z))
        end

        -- Draw the second circle and connect all the vertices to the top point
        for i = 1, segments do
            local j = i + 1
            if j > segments then j = 1 end
            if vertices2[i] and vertices2[j] then
                draw.Color(color.r, color.g, color.b, color.a)
                draw.Line(vertices2[i][1], vertices2[i][2], vertices2[j][1], vertices2[j][2])
            end
        end
    end
end

doDraw()

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    MenuLib.RemoveMenu(menu)                             -- Remove the menu
    UnloadLib() --unloading lualib
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