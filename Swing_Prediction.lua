--[[ Swing prediction for  Lmaobox  ]]--
--[[      (Modded misc-tools)       ]]--
--[[          --Authors--           ]]--
--[[           Terminator           ]]--
--[[  (github.com/titaniummachine1  ]]--

local menuLoaded, MenuLib = pcall(require, "Menu")                                -- Load MenuLib
assert(menuLoaded, "MenuLib not found, please install it!")                       -- If not found, throw error
assert(MenuLib.Version >= 1.44, "MenuLib version is too old, please update it!")  -- If version is too old, throw error

if UnloadLib then UnloadLib() end

---@alias AimTarget { entity : Entity, angles : EulerAngles, factor : number }

---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.987, "lnxLib version is too old, please update it!")

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
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
local Swingpred     = menu:AddComponent(MenuLib.Checkbox("Enable", true, ItemFlags.FullWidth))
local Maimbot       = menu:AddComponent(MenuLib.Checkbox("Aimbot(Silent)", true, ItemFlags.FullWidth))
local Mchargebot    = menu:AddComponent(MenuLib.Checkbox("Charge Controll", true, ItemFlags.FullWidth))
local mSensetivity  = menu:AddComponent(MenuLib.Slider("Charge Sensetivity",1 ,50 ,10 ))
--local mAutoMelee    = menu:AddComponent(MenuLib.Checkbox("Auto Melee", true, ItemFlags.FullWidth))
local mFov          = menu:AddComponent(MenuLib.Slider("Aimbot FOV",10 ,360 ,360 ))
local mAutoRefill   = menu:AddComponent(MenuLib.Checkbox("Crit Refill", true))
local AchargeRange  = menu:AddComponent(MenuLib.Checkbox("Charge Reach", true, ItemFlags.FullWidth))
local mAutoGarden   = menu:AddComponent(MenuLib.Checkbox("Troldier assist", false))
local mmVisuals     = menu:AddComponent(MenuLib.Checkbox("Enable Visuals", false))
local mKeyOverrite  = menu:AddComponent(MenuLib.Keybind("Manual overide", key))
local Visuals = {
    ["Range Circle"] = true,
    ["Visualization"] = false
}

local mVisuals = menu:AddComponent(MenuLib.MultiCombo("^Visuals", Visuals, ItemFlags.FullWidth))
local closestDistance = 2000
local current_fps = 0
local fDistance = 1
local hitbox_max = Vector3(-14, -14, 85)
local hitbox_min = Vector3(14, 14, 0)
local isMelee = false
local mresolution = 128
local mTHeightt = 85
local msamples = 66
local pastPredictions = {}
local pLocal = entities.GetLocalPlayer()
local vdistance = 1
local ping = 0
local swingrange = 70
local tickRate = 66
local tick_count = 0
local time = 16
local last_time = time
local swing_delay = time

local pLocalClass = nil
local pLocalFuture = nil
local pLocalOrigin = nil
local pWeapon = nil
local Safe_Strafe = false
local Latency = nil
local tick = nil
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
local LastTarget = nil
local ExtendedRange = nil
local in_attack = nil
local Gcan_attack = false

local pivot
local can_charge = false

local settings = {
    MinDistance = 200,
    MaxDistance = 1000,
    MinHealth = 10,
    MaxHealth = 100,
    MinFOV = 0,
    MaxFOV = mFov:GetValue(),
}

local latency = 0
local lerp = 0
local lastAngles = {} ---@type table<number, EulerAngles>
local strafeAngles = {} ---@type table<number, number>

---@param me WPlayer
local function CalcStrafe(me)
    local players = entities.FindByClass("CTFPlayer")
    for idx, entity in ipairs(players) do
        if entity:IsDormant() or not entity:IsAlive() then
            lastAngles[entity:GetIndex()] = nil
            strafeAngles[entity:GetIndex()] = nil
            goto continue
        end

        -- Ignore teammates (for now)
        if entity:GetTeamNumber() == me:GetTeamNumber() then
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        local angle = v:Angles()

        -- Play doesn't have a last angle
        if lastAngles[entity:GetIndex()] == nil then
            lastAngles[entity:GetIndex()] = angle
            goto continue
        end

        -- Calculate the delta angle
        if angle.y ~= lastAngles[entity:GetIndex()].y then
            strafeAngles[entity:GetIndex()] = angle.y - lastAngles[entity:GetIndex()].y
        end
        lastAngles[entity:GetIndex()] = angle

        ::continue::
    end
end

---@param me WPlayer
---@return AimTarget? target
local function GetBestTarget(me)
    settings = {
        MinDistance = 200,
        MaxDistance = 1000,
        MinHealth = 1,
        MaxHealth = 100,
        MinFOV = 0,
        MaxFOV = mFov:GetValue(),
    }
    
    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    ---@type Target[]
    local targetList = {}
    local targetCount = 0

    -- Calculate target factors
    for i, player in pairs(players) do
        if not Helpers.VisPos(player, pLocalOrigin, player:GetAbsOrigin()) then goto continue end
        if player == localPlayer or player:GetTeamNumber() == localPlayer:GetTeamNumber() then goto continue end
        if player == nil or not player:IsAlive() then goto continue end
        if gui.GetValue("ignore cloaked") == 1 and (player:InCond(4)) then goto continue end
        if player:IsDormant() then goto continue end
        
        local distance = (player:GetAbsOrigin() - localPlayer:GetAbsOrigin()):Length()
        local height_diff = math.floor(math.abs(player:GetAbsOrigin().z - localPlayer:GetAbsOrigin().z))
        
        if height_diff > 180 or distance > 700 then goto continue end
        
        -- Visibility Check
        local angles = Math.PositionAngles(localPlayer:GetAbsOrigin(), player:GetAbsOrigin())
        local fov = Math.AngleFov(engine.GetViewAngles(), angles)
        if fov > settings.MaxFOV then goto continue end
        
        local health = player:GetHealth()

        local distanceFactor = Math.RemapValClamped(distance, settings.MinDistance, settings.MaxDistance, 1, 0.1)
        local healthFactor = Math.RemapValClamped(health, settings.MinHealth, settings.MaxHealth, 1, 0.5)
        local fovFactor = Math.RemapValClamped(fov, settings.MinFOV, settings.MaxFOV, 1, 0.5)

        local factor = distanceFactor * healthFactor * fovFactor
        targetCount = targetCount + 1

        targetList[targetCount] = { player = player, factor = factor }
        
        ::continue::
    end

    -- Sort target list by factor
    table.sort(targetList, function(a, b)
        return a.factor > b.factor
    end)

    local bestTarget = nil

    for _, target in ipairs(targetList) do
        local player = target.player
        local aimPos = player:GetAbsOrigin()
        local angles = Math.PositionAngles(localPlayer:GetAbsOrigin(), aimPos)
        local fov = Math.AngleFov(angles, engine.GetViewAngles())
        
        -- Set as best target
        bestTarget = { entity = player, pos = aimPos, angles = angles, factor = target.factor }
        break
    end

    return bestTarget
end

    
-- Predicts player position after set amount of ticks
---@param targetLastPos Vector3
---@param Ltime integer
---@param targetEntity number
---@param strafeAngle number
---@return Vector3?
local function TargetPositionPrediction(TargetPos, Ltime, targetEntity, strafeAngle)
    if Ltime == 0 then return TargetPos end
    local player = WPlayer.FromEntity(targetEntity)
    local predData = Prediction.Player(player, Ltime, strafeAngle)

    if not predData then return nil end

    local pos = predData.pos[Ltime]
    return pos
end





local vhitbox_Height = 85
local vhitbox_width = 18

-- Define function to check collision between the hitbox and the sphere
-- Define function to check collision between the hitbox and the sphere
    local function checkCollision(vPlayerFuture, spherePos, sphereRadius)
        if vPlayerFuture ~= nil and isMelee then
            local vhitbox_Height_trigger_bottom = Vector3(0, 0, 0) --swingrange
            local vhitbox_width_trigger = (vhitbox_width) -- + swingrange)
            local vhitbox_min = Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)
            local vhitbox_max = Vector3(vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height)
            local hitbox_min_trigger = (vPlayerFuture + vhitbox_min)
            local hitbox_max_trigger = (vPlayerFuture + vhitbox_max)
    
            -- Calculate the closest point on the hitbox to the sphere
            local closestPoint = Vector3(
                math.max(hitbox_min_trigger.x, math.min(spherePos.x, hitbox_max_trigger.x)),
                math.max(hitbox_min_trigger.y, math.min(spherePos.y, hitbox_max_trigger.y)),
                math.max(hitbox_min_trigger.z, math.min(spherePos.z, hitbox_max_trigger.z))
            )
    
            -- Calculate the vector from the closest point to the sphere center
            local closestToPointVector = spherePos - closestPoint
    
            -- Calculate the distance along the vector from the closest point to the sphere center
            local distanceAlongVector = math.sqrt(closestToPointVector.x^2 + closestToPointVector.y^2 + closestToPointVector.z^2)
    
            -- Compare the distance along the vector to the sum of the radii
            if sphereRadius == 0 then
                -- Treat the sphere as a single point
                if distanceAlongVector <= 0 then
                    -- Collision detected
                    return true, closestPoint
                else
                    -- No collision
                    return false, nil
                end
            else
                if distanceAlongVector <= sphereRadius or distanceAlongVector <= sphereRadius + 0.5 then
                    -- Collision detected (including intersecting or touching)
                    return true, closestPoint
                else
                    -- No collision
                    return false, nil
                end
            end
        end
    end

local Hitbox = {
    Head = 1,
    Neck = 2,
    Pelvis = 4,
    Body = 5,
    Chest = 7
}

local function ChargeControll(pCmd)
    -- Get the current view angles
    local sensetivity = mSensetivity:GetValue() --client.GetConVar("sensitivity") --mSensetivity:GetValue() / 10 --0.4 --client.GetConVar("sensitivity") +
    local currentAngles = engine.GetViewAngles()
    -- Get the mouse motion
    local mouseDeltaX = -(pCmd.mousedx * sensetivity / 100)
    -- Calculate the new yaw angle
    local newYaw = currentAngles.yaw + mouseDeltaX

    -- Set the new view angles
    pCmd:SetViewAngles(currentAngles.pitch, newYaw, 0) --engine.SetViewAngles(aimpos1)
end

--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd)
    if not Swingpred:GetValue() then goto continue end

    pLocal = entities.GetLocalPlayer() -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
    if not pLocal or not pLocal:IsAlive() then
        return -- Immediately check if the local player exists. If it doesn't, return.
    end
    local flags = pLocal:GetPropInt("m_fFlags")
    --[[ping = entities.GetPlayerResources():GetPropDataTableInt("m_iPing")[pLocal:GetIndex()]]
    chargeLeft = pLocal:GetPropFloat("m_flChargeMeter")
    chargeLeft = math.floor(chargeLeft)

    --[--Check local player class if spy or none then stop code--]

    pLocalClass = pLocal:GetPropInt("m_iClass") -- Get local class
    if pLocalClass == nil then
        goto continue -- When local player did not choose class then skip code
    end
    if pLocalClass == 8 then
        goto continue -- When local player is spy then skip code
    end

    -- Get current latency and lerp
    local latOut = clientstate.GetLatencyOut()
    lerp = client.GetConVar("cl_interp") or 0
    --local Tolerance = 4
    --print(lerp)
    -- Define the reaction time in seconds
    Latency = (latOut + lerp)
    -- Convert the delay to ticks
    Latency = math.floor(Latency * tickRate + 1)


    -- Add the ticks to the current time
    --time = time + Latency - Tolerances

    --settings.MaxDistance = ((time / tickRate) * pLocal:EstimateAbsVelocity():Length()) * 2

    --[--obtain secondary information after confirming we need it for fps boost when not using script--]

    --[[ Features that require access to the weapon ]]--
    pWeapon = pLocal:GetPropEntity("m_hActiveWeapon") -- Set "pWeapon" to the local player's active weapon
    if not pWeapon then
        return
    end
    local pWeaponData = pWeapon:GetWeaponData()
    local pWeaponDefIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex") -- Set "pWeaponDefIndex" to the "pWeapon"'s item definition index
    local pWeaponDef = itemschema.GetItemDefinitionByID(pWeaponDefIndex) -- Set "pWeaponDef" to the local "pWeapon"'s item definition
    local pWeaponName = pWeaponDef:GetName()
    swingrange = pWeapon:GetSwingRange()
    local players = entities.FindByClass("CTFPlayer") -- Create a table of all players in the game
    if #players == 0 then
        return -- Immediately check if there are any players in the game. If there aren't, return.
    end

    --[--if we enabled trodlier assist run auto weapon script--]
    if mAutoGarden:GetValue() == true then
        local bhopping = false
        local state = ""
        local downheight = Vector3(0, 0, -250)
        if input.IsButtonDown(KEY_SPACE) then
            bhopping = true
        end
        if flags & FL_ONGROUND == 0 or bhopping then
            state = "slot3"
        else
            state = "slot1"
        end
        if state then
            client.Command(state, true)
        end

        if flags & FL_ONGROUND == 0 and not bhopping then
            pCmd:SetButtons(pCmd.buttons | IN_DUCK)
        end
    end


--[[ Auto Melee Switch ]]-- (Automatically switches to slot3 when an enemy is in range)
--[[if mAutoMelee:GetValue()  then
    local minDistance = 200
    local closestEnemyDist = 600
    local closestEnemy

    for i, enemy in ipairs(players) do
        if enemy == pLocal then goto continue end
        local pos = enemy:GetAbsOrigin()
        local vel = enemy:EstimateAbsVelocity()
        local futurePos = (pos + vel) * 0.5
        print(futurePos)


        local dist = (pLocal:GetAbsOrigin() - futurePos):Length()
        if dist < closestEnemyDist then
            closestEnemyDist = dist
            closestEnemy = enemy
        end
    end

    if closestEnemyDist < minDistance and not pWeapon:IsMeleeWeapon() then
        client.Command("slot3", true)
    end
end]]--

--[-Don`t run script below when not usign melee--]

    isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon
    if not isMelee then goto continue end -- if not melee then skip code
--[-------get vierwhegiht--------]

    if pLocal == nil then
        pLocalOrigin = pLocal:GetAbsOrigin()
        return pLocalOrigin
    end

    -- Get pLocal eye level and set vector at our eye level to ensure we check distance from eyes
    local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") -- Vector3(0, 0, 70)
    local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
    viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()

    -- Eye level 
    Vheight = Vector3(0, 0, viewheight)
    pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)

    --SwingRange calculation
    if ExtendedRange == nil then
        -- Extend the cube by the swingrange value forward
        local halfsize = 18
        -- Calculate the distance from the view position to the center of the furthest plane of the extended cube
        ExtendedRange = swingrange + halfsize
    end
swingrange = ExtendedRange

-- Manual charge control

        if Mchargebot:GetValue() and pLocal:InCond(17) then
            ChargeControll(pCmd)
        end

--[-----Get best target------------------]
    local keybind = mKeyOverrite:GetValue()
    if not pLocal:InCond(17) then
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
    end

    -- Refill and skip code when alone
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

--[--------------Prediction-------------------] -- predict both players position after swing
        ONGround = (flags & FL_ONGROUND == 1)
    if pLocal:EstimateAbsVelocity() == 0 then
        -- If the local player is not accelerating, set the predicted position to the current position
        pLocalFuture = pLocalOrigin
    else
        CalcStrafe(pLocal)
        strafeAngle = strafeAngles[pLocal:GetIndex()]

        -- If the local player is accelerating, predict the future position
        pLocalFuture = TargetPositionPrediction(pLocalOrigin, time, pLocal, strafeAngle) + Vheight
    end


    if CurrentTarget:EstimateAbsVelocity() == 0 then
        -- If the local player is not accelerating, set the predicted position to the current position of the closest player
        vPlayerFuture = CurrentTarget:GetAbsOrigin()
    else

        CalcStrafe(CurrentTarget)
        local flagsTarget = CurrentTarget:GetPropInt("m_fFlags")
        Target_ONGround = (flagsTarget & FL_ONGROUND == 1)

        strafeAngle = strafeAngles[CurrentTarget:GetIndex()]

        target_strafeAngle = strafeAngle

        -- Predict the future position of the closest player
        vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, time, CurrentTarget, strafeAngle)
    end

            
--[--------------Distance check-------------------]
    -- Get current distance between local player and closest player
    vdistance = (vPlayerOrigin - pLocalOrigin):Length()

    -- Get distance between local player and closest player after swing
    fDistance = (vPlayerFuture - pLocalFuture):Length()

    -- Simulate swing and return result
    local collisionPoint
    local pUsingMargetGarden = false

    if pWeaponDefIndex == 416 then
        -- If "pWeapon" is not set, break
        pUsingMargetGarden = true
        -- Set "pUsingProjectileWeapon" to true
    end                                        -- Set "pUsingProjectileWeapon" to false
        
        
--[[---Check for hit detection--------]]
ONGround = (flags & FL_ONGROUND == 1)
local collision = false

    -- Check for collision with current position
    collision, collisionPoint = checkCollision(vPlayerOrigin ,pLocalOrigin ,swingrange)
        can_attack = collision

    -- Check for collision with future position
    if not collision then
        collision, collisionPoint = checkCollision(vPlayerFuture, pLocalFuture, swingrange)
        
        -- Check for collision with future position
        can_attack = collision
        can_charge = false
    end
    
    -- Check for charge range
    if pLocalClass == 4 and AchargeRange:GetValue() and chargeLeft == 100 then -- Check for collision during charge
            collision = checkCollision(vPlayerFuture, pLocalOrigin, (swingrange * 1.5))
            if collision then
                can_attack = true
                tick_count = tick_count + 1
                if tick_count % (Latency + 4) == 0 then
                    can_charge = true
                end
            end
    end
                    
--[--------------AimBot-------------------]                --get hitbox of ennmy pelwis(jittery but works)
    local hitboxes = CurrentTarget:GetHitboxes()
    local hitbox = hitboxes[6]
    local aimpos = nil
    if collisionPoint ~= nil then
        aimpos = collisionPoint
    elseif aimpos == nil then
        aimpos = CurrentTarget:GetAbsOrigin() + Vheight --aimpos = (hitbox[1] + hitbox[2]) * 0.5 --if no collision point accesable then aim at defualt hitbox
    end

    aimposVis = aimpos -- transfer aim point to visuals
    flags = pLocal:GetPropInt("m_fFlags")
    local inAttackAim = false
    if Maimbot:GetValue() and Helpers.VisPos(CurrentTarget, vPlayerFuture, pLocalFuture)
    and pLocal:InCond(17)
    and not collision then
        -- change angles at target
        aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
        --aimpos = Math.PositionAngles(pLocalOrigin, vPlayerFuture + Vector3(0, 0, 70))
            pCmd:SetViewAngles(engine.GetViewAngles().pitch, aimpos.yaw, 0)      --engine.SetViewAngles(aimpos)

    elseif Maimbot:GetValue() and flags & FL_ONGROUND == 1 and can_attack then         -- if predicted position is visible then aim at it
        -- change angles at target
        aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
        pCmd:SetViewAngles(aimpos.pitch, aimpos.yaw, 0) --pCmd:SetViewAngles(aimpos:Unpack())  --engine.SetViewAngles(aimpos) --                                --  engine.SetViewAngles(aimpos) --


    elseif Maimbot:GetValue() and flags & FL_ONGROUND == 0 and can_attack then         -- if we are in air then aim at target
        -- change angles at target
        aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
            pCmd:SetViewAngles(aimpos.pitch, aimpos.yaw, 0) --engine.SetViewAngles(aimpos)     --set angle at aim position manualy not silent aimbot

    elseif not inAttackAim and Mchargebot:GetValue() and pLocal:InCond(17) then --manual charge controll
            -- Calculate the source and destination vectors
            ChargeControll(pCmd)
    end
       
    --[shield bashing strat]

    if pLocalClass == 4 and (pLocal:InCond(17)) then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
        local Bashed = checkCollision(vPlayerFuture, pLocalOrigin, 18)

        if not Bashed then -- if demoknight bashed on enemy
            can_attack = false
            goto continue
        end
    end

        --Check if attack simulation was succesfull
            if can_attack == true then
                --remove tick
                time = time - 1
                Gcan_attack = false

                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)-- attack

            elseif mAutoRefill:GetValue() == true then
                if pWeapon:GetCritTokenBucket() <= 27 and fDistance > 350 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)--refill
                end
                Gcan_attack = true
            else
                time = swing_delay
                Gcan_attack = true
            end

            if can_charge then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)-- charge
            end

            if time % swing_delay == 0 or time == last_time then
                time = swing_delay
            end


-- Update last variables
            last_time = time
            Safe_Strafe = false -- reset safe strafe
    ::continue::
end

            -- Define function to get the triggerbox dimensions
                local function GetTriggerboxDimensions()
                    vhitbox_Height = 85
                    vhitbox_width = 18
                    local vhitbox_Height_trigger_bottom = Vector3(0,0,0) --swingrange
                    local vhitbox_width_trigger = (vhitbox_width) -- + swingrange)
                    return vhitbox_width_trigger, vhitbox_Height_trigger_bottom
                end

-- debug command: ent_fire !picker Addoutput "health 99999" --superbot
local myfont = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
--[[ Code called every frame ]]--
local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() or not pLocal:IsAlive() then
        return
    end
    if vPlayerOrigin == nil then return end
    if vPlayerFuture == nil and pLocalFuture == nil then return end

    --local pLocal = entities.GetLocalPlayer()
    pWeapon = pLocal:GetPropEntity("m_hActiveWeapon") -- Set "pWeapon" to the local player's active weapon
if not mmVisuals:GetValue() or not pWeapon:IsMeleeWeapon() then return end

    if pLocalFuture == nil or not pLocal:IsAlive() then return end
    if CurrentTarget == nil then return end
        draw.SetFont( myfont )
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()
        local screenPos = { w / 2 - 15, h / 2 + 35}

        local vPlayerTargetPos = vPlayerFuture

            --draw predicted local position with strafe prediction
            screenPos = client.WorldToScreen(aimposVis)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end


            -- Define function to draw the triggerbox
                local vhitbox_width_trigger, vhitbox_Height_trigger_bottom = GetTriggerboxDimensions()
                local vertices = {
                    client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                    client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                    client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                    client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                    client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height)),
                    client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height)),
                    client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, vhitbox_Height)),
                    client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, -vhitbox_width_trigger, vhitbox_Height))
                }
                -- check if not nil
                if vertices[1] and vertices[2] and vertices[3] and vertices[4] and vertices[5] and vertices[6] and vertices[7] and vertices[8] then
                    -- Front face
                    draw.Line(vertices[1][1], vertices[1][2], vertices[2][1], vertices[2][2])
                    draw.Line(vertices[2][1], vertices[2][2], vertices[3][1], vertices[3][2])
                    draw.Line(vertices[3][1], vertices[3][2], vertices[4][1], vertices[4][2])
                    draw.Line(vertices[4][1], vertices[4][2], vertices[1][1], vertices[1][2])
                    
                    -- Back face
                    draw.Line(vertices[5][1], vertices[5][2], vertices[6][1], vertices[6][2])
                    draw.Line(vertices[6][1], vertices[6][2], vertices[7][1], vertices[7][2])
                    draw.Line(vertices[7][1], vertices[7][2], vertices[8][1], vertices[8][2])
                    draw.Line(vertices[8][1], vertices[8][2], vertices[5][1], vertices[5][2])
                    
                    -- Connecting lines
                    if vertices[1] and vertices[5] then draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2]) end
                    if vertices[2] and vertices[6] then draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2]) end
                    if vertices[3] and vertices[7] then draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2]) end
                    if vertices[4] and vertices[8] then draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2]) end
                end

        -- Strafe prediction visualization
        if mVisuals:IsSelected("Visualization") then
            
        local consolas = draw.CreateFont("Consolas", 17, 500)

            draw.SetFont(consolas)
            draw.Color(255, 255, 255, 255)

            -- update fps every 100 frames
            if globals.FrameCount() % 100 == 0 then
                current_fps = math.floor(1 / globals.FrameTime())
            end

            draw.Text(5, 5, "[lmaobox | fps: " .. current_fps .. "]")
            --[[-- Draw lines between the predicted positions
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
                for i = 1, #TargetPath - 1 do
                    local pos1 = TargetPath[i]
                    local pos2 = TargetPath[i + 1]

                    local screenPos3 = client.WorldToScreen(pos1)
                    local screenPos4 = client.WorldToScreen(pos2)

                    if screenPos3 ~= nil and screenPos4 ~= nil then
                        draw.Line(screenPos3[1], screenPos3[2], screenPos4[1], screenPos4[2])
                    end
                end
                ]]
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
            local max_height_adjustment = mTHeightt -- adjust as needed
            local height_adjustment = (1 - distance_to_hit / radius) * max_height_adjustment
            z = z + height_adjustment
        end

        vertices[i] = client.WorldToScreen(Vector3(x, y, z))
    end

    -- Calculate the top vertex position
    local top_height = mTHeightt -- adjust as needed
    local top_vertex = client.WorldToScreen(Vector3(center.x, center.y, center.z + top_height))
    local color = {r = 0, g = 0, b = 255, a = 255} -- blue
    draw.Color(color.r, color.g, color.b, color.a)
    if not Gcan_attack then
        print(Gcan_attack)
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
    if pLocalClass == 4 and AchargeRange:GetValue() and chargeLeft >= 100 then
        -- Define the color for the second circle
        color = {r = 255, g = 0, b = 0, a = 255} -- red

        -- Calculate the radius for the second circle
        local radius2 = radius * 1.5

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
                local max_height_adjustment = mTHeightt -- adjust as needed
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

--[[ Remove the menu when unloaded ]]--
local function OnUnload()                                -- Called when the script is unloaded
    MenuLib.RemoveMenu(menu)                             -- Remove the menu
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