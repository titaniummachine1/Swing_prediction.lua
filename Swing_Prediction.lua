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
--local mAutoMelee    = menu:AddComponent(MenuLib.Checkbox("Auto Melee", true, ItemFlags.FullWidth))
local mFov          = menu:AddComponent(MenuLib.Slider("Aimbot FOV",10 ,360 ,180 ))
local mAutoRefill   = menu:AddComponent(MenuLib.Checkbox("Crit Refill", true))
local Achargebot    = menu:AddComponent(MenuLib.Checkbox("Charge Reach", true, ItemFlags.FullWidth))
local mAutoGarden   = menu:AddComponent(MenuLib.Checkbox("Troldier assist", false))
local mmVisuals     = menu:AddComponent(MenuLib.Checkbox("Enable Visuals", false))
local mKeyOverrite  = menu:AddComponent(MenuLib.Keybind("Manual overide", key))
local Visuals = {
    ["Range Circle"] = true,
    ["Visualization"] = true
}

local mVisuals = menu:AddComponent(MenuLib.MultiCombo("^Visuals", Visuals, ItemFlags.FullWidth))
local closestDistance = 2000
local fDistance = 1
local hitbox_max = Vector3(-14, -14, 85)
local hitbox_min = Vector3(14, 14, 0)
local isMelee = false
local mresolution = 128
local mTHeightt = 85
local msamples = 66
local pastPredictions = {}
local pLocal = entities.GetLocalPlayer()
local pLocalClass
local pLocalFuture
local pLocalOrigin
local ping = 0
local pWeapon
local Safe_Strafe = false
local swingrange
local time = 16
local Latency
local tick
local tickRate = 66
local tick_count = 0
local viewheight
local Vheight
local vdistance = 1
local vPlayerFuture
local vPlayer
local vPlayerOrigin
local vPlayerOriginLast
local chargeLeft
local target_strafeAngle
local onGround


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
local lastAngles = {} ---@type EulerAngles[]
local strafeAngles = {} ---@type number[]

---@param me WPlayer
local function CalcStrafe(me)
    local players = entities.FindByClass("CTFPlayer")
    for idx, entity in ipairs(players) do
        if entity:IsDormant() or not entity:IsAlive() then
            lastAngles[idx] = nil
            strafeAngles[idx] = nil
            goto continue
        end

        -- Ignore teammates (for now)
        if entity:GetTeamNumber() == me:GetTeamNumber() then
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        local angle = v:Angles()

        -- Play doesn't have a last angle
        if lastAngles[idx] == nil then
            lastAngles[idx] = angle
            goto continue
        end

        -- Calculate the delta angle
        if angle.y ~= lastAngles[idx].y then
            strafeAngles[idx] = angle.y - lastAngles[idx].y
        end
        lastAngles[idx] = angle

        ::continue::
    end
end

---@param me WPlayer
---@return AimTarget? target
local function GetBestTarget(me)
    settings = {
        MinDistance = 200,
        MaxDistance = 1000,
        MinHealth = 10,
        MaxHealth = 100,
        MinFOV = 0,
        MaxFOV = mFov:GetValue(),
    }
    
    local players = entities.FindByClass("CTFPlayer")
    local localPlayer = entities.GetLocalPlayer()
    if not localPlayer then return end

    ---@type Target[]
    local targetList = {}

    -- Calculate target factors
    for entIdx, player in pairs(players) do
        if entIdx == localPlayer:GetIndex() then goto continue end

        local distance = (player:GetAbsOrigin() - localPlayer:GetAbsOrigin()):Length()
        local height_diff = math.floor(math.abs(player:GetAbsOrigin().z - localPlayer:GetAbsOrigin().z))
        local health = player:GetHealth()
        --pLocal:InCond(17)
        local angles = Math.PositionAngles(localPlayer:GetAbsOrigin(), player:GetAbsOrigin())
        local fov = Math.AngleFov(engine.GetViewAngles(), angles)
        if fov > settings.MaxFOV then goto continue end
        if height_diff > swingrange * 2 then goto continue end

        local distanceFactor = Math.RemapValClamped(distance, settings.MinDistance, settings.MaxDistance, 1, 0.1)
        local healthFactor = Math.RemapValClamped(health, settings.MinHealth, settings.MaxHealth, 1, 0.5)
        local fovFactor = Math.RemapValClamped(fov, settings.MinFOV, settings.MaxFOV, 1, 0.5)

        local factor = distanceFactor * healthFactor * fovFactor
        table.insert(targetList, { player = player, factor = factor})

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
        if gui.GetValue("ignore cloaked") == 1 and (target.player:InCond(4)) then goto continue end

        -- Visibility Check
        if not Helpers.VisPos(player, pLocalOrigin, aimPos) then goto continue end

        if target.player == nil or not target.player:IsAlive() or target.player:GetTeamNumber() == pLocal:GetTeamNumber() then goto continue end
        
        -- Set as best target
        bestTarget = { entity = player, pos = aimPos, angles = angles, factor = target.factor }
        break

        ::continue::
    end

    return bestTarget
end

    
  -- those parrams are super important!!! dont change them
-- Predicts player position after set amount of ticks
---@param targetLastPos Vector3
---@param time integer
---@param targetEntity number
---@param strafeAngle number
---@return Vector3?, boolean?
local function TargetPositionPrediction(targetLastPos, time, targetEntity, strafeAngle)
    local player = WPlayer.FromEntity(targetEntity)
    local predData = Prediction.Player(player, time, strafeAngle)
    if not predData then return nil end

    local pos = predData.pos[time]
    if targetEntity == pLocal then
        onGround = (predData.onGround[time])
    end
    return pos
end





local vhitbox_Height = 85
local vhitbox_width = 18

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

function UpdateViewAngles(pCmd)
    -- Get the current view angles
    local currentAngles = engine.GetViewAngles()
    local sensetivity = client.GetConVar("sensitivity") + 2 --mSensetivity:GetValue() / 10 --0.4
    -- Get the mouse motion
    local mouseDeltaX = -(pCmd.mousedx * sensetivity / 100)
    -- Calculate the new yaw angle
    local newYaw = currentAngles.yaw + mouseDeltaX

    -- Create the new view angles
    aimpos = EulerAngles(currentAngles.pitch, newYaw, currentAngles.roll)

    -- Set the new view angles
    pCmd:SetViewAngles(aimpos:Unpack()) --engine.SetViewAngles(aimpos)
end

--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd)
    if not Swingpred:GetValue() then goto continue end -- enable or distable script
--[--if we are not existign then stop code--]
        pLocal = entities.GetLocalPlayer()     -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
        if not pLocal then return end  -- Immediately check if the local player exists. If it doesn't, return.
        
        ping = entities.GetPlayerResources():GetPropDataTableInt("m_iPing")[pLocal:GetIndex()]
        chargeLeft = pLocal:GetPropFloat( "m_flChargeMeter" )
        --[--Check local player class if spy or none then stop code--]

        pLocalClass = pLocal:GetPropInt("m_iClass") --getlocalclass
            if pLocalClass == nil then goto continue end --when local player did not chose class then skip code
            if pLocalClass == 8 then goto continue end --when local player is spy then skip code

 -- Get current latency and lerp
            local latOut = clientstate.GetLatencyOut()
            lerp = client.GetConVar("cl_interp") or 0
            --local Tolerance = 4
            --print(lerp)
            -- Define the reaction time in seconds
            Latency = (latOut + lerp )
            -- Convert the delay to ticks
            Latency = math.floor( Latency * tickRate + 1 )
            
            -- Add the ticks to the current time
            --time = time + Latency - Tolerance

            settings.MaxDistance = time * pLocal:EstimateAbsVelocity():Length()
--[--obtain secondary information after confirming we need it for fps boost whe nnot using script]

                                   --[[ Features that require access to the weapon ]]--
        pWeapon               = pLocal:GetPropEntity( "m_hActiveWeapon" )            -- Set "pWeapon" to the local player's active weapon
        local pWeaponDefIndex = pWeapon:GetPropInt( "m_iItemDefinitionIndex" )       -- Set "pWeaponDefIndex" to the "pWeapon"'s item definition index
        local pWeaponDef      = itemschema.GetItemDefinitionByID( pWeaponDefIndex )  -- Set "pWeaponDef" to the local "pWeapon"'s item definition
        local pWeaponName     = pWeaponDef:GetName()
        swingrange = pWeapon:GetSwingRange()

        local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game
                local closestPlayer
                if #players == 0 then return end  -- Immediately check if there are any players in the game. If there aren't, return.
--[--if we enabled trodlier assist run auto weapon script]
    if mAutoGarden:GetValue() == true then
        local flags = pLocal:GetPropInt( "m_fFlags" )
        local bhopping = false
        local state = ""
        local downheight = Vector3(0, 0, -250)
            if input.IsButtonDown( KEY_SPACE ) then
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
        flags = pLocal:GetPropInt( "m_fFlags" )
        
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

--[-------get vierwhegiht Optymised--------]
    if pLocalClass ~= pLocalClasslast then
        if pLocal == nil then pLocalOrigin = pLocal:GetAbsOrigin() return pLocalOrigin end
        --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
        local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]") --Vector3(0, 0, 70)
        local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
        viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()
            -- eye level 
            Vheight = Vector3(0, 0, viewheight)
            pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)
    end

--[-----Get best target------------------]
local keybind = mKeyOverrite:GetValue()
    if (keybind == KEY_NONE) and GetBestTarget(pLocal) ~= nil then -- check if player had no key bound
        closestPlayer = GetBestTarget(pLocal).entity --GetClosestEnemy(pLocal, pLocalOrigin, players)
        vPlayer = closestPlayer
    elseif input.IsButtonDown(keybind) and GetBestTarget(pLocal) ~= nil then -- if player boudn key for aimbot then only work when its on.
        closestPlayer = GetBestTarget(pLocal).entity
        vPlayer = closestPlayer
    end

--[[manual charge controll]]
    if Mchargebot:GetValue() and pLocal:InCond(17) then --manual charge controll
        UpdateViewAngles(pCmd)
    end
--[-----Refil and skip code when alone-----]

if closestPlayer == nil then
    if mAutoRefill:GetValue() and pWeapon:GetCritTokenBucket() <= 27 then
        pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
    end goto continue
end

    vPlayerOrigin = closestPlayer:GetAbsOrigin() -- get closest player origin
        local ONGround
        local Target_ONGround
        local flags = pLocal:GetPropInt( "m_fFlags" )
        local strafeAngle = 0
        local can_attack = false
        local stop = false
       

--[--------------Prediction-------------------] -- predict both players position after swing
            if pLocal:EstimateAbsVelocity() == 0 then
                -- If the local player is not accelerating, set the predicted position to the current position
                pLocalFuture = pLocalOrigin
                ONGround = (flags & FL_ONGROUND == 1)
            else
                ONGround = (flags & FL_ONGROUND == 1)
                CalcStrafe(pLocal)

                if ONGround then
                    strafeAngle = 0
                else
                    strafeAngle = strafeAngles[pLocal:GetIndex()]
                end
                -- If the local player is accelerating, predict the future position   
                pLocalFuture = TargetPositionPrediction(pLocalOrigin, time, pLocal, strafeAngle) + Vheight
                
            end

            if pLocal:EstimateAbsVelocity() == 0 then
                vPlayerFuture = closestPlayer:GetAbsOrigin()
                Target_ONGround = (flags & FL_ONGROUND == 1)
            else
                CalcStrafe(closestPlayer)
                Target_ONGround = (flags & FL_ONGROUND == 1)

                if not ONGround then
                    strafeAngle = strafeAngles[closestPlayer:GetIndex()]
                else
                    strafeAngle = 0
                end

                target_strafeAngle = strafeAngle
                vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, time, closestPlayer, strafeAngle)
            end

            
--[--------------Distance check-------------------]
        --get current distance between local player and closest player
        vdistance = (vPlayerOrigin - pLocalOrigin):Length()

        -- get distance between local player and closest player after swing
        fDistance = (vPlayerFuture - pLocalFuture):Length()

                -- Simulate swing and return result
                local collisionPoint
                local pUsingMargetGarden = false

        if pWeaponDefIndex == 416 then                                               -- If "pWeapon" is not set, break
            pUsingMargetGarden = true                                             -- Set "pUsingProjectileWeapon" to true
        end                                          -- Set "pUsingProjectileWeapon" to false
        
        
--[[Hit Detection -------------------------------------------------]]
            ONGround = (flags & FL_ONGROUND == 1)
            local collision = false
            if pUsingMargetGarden == true then
                if pLocal:InCond(81) and not ONGround then
                    collision = checkCollision(vPlayerFuture, pLocalFuture, swingrange)
                        can_attack = collision
                        can_charge = false
                    
                        if collision and pLocal:InCond(81) then
                            can_attack = true
                        elseif not collision then
                            collision, collisionPoint = checkCollision(vPlayerOrigin ,pLocalOrigin ,swingrange)
                            if collision then
                                can_attack = true
                            end

                            --[[if not collision then -- test for attacks without lag compensation
                                local temp_pLocalFuture = TargetPositionPrediction(pLocalOrigin, time - Latency, pLocal) + Vheight
                                local temp_vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, time - Latency, closestPlayer)
                                local collision1
                                local collisionPoint1
                                collision1 = checkCollision(temp_vPlayerFuture , temp_pLocalFuture, swingrange)
                                if collision1 then
                                    can_attack = true
                                end
                            end]]
                        end

                        if pLocalClass == 4 and Achargebot:GetValue() and chargeLeft >= 100.0 then
                            collision, collisionPoint = checkCollision(vPlayerFuture, pLocalOrigin, (swingrange * 1.5)) --increased range when in charge
                            
                            if collision then
                                can_attack = true
                                tick_count = tick_count + 1
                                if tick_count %  (Latency + 2) == 0 then
                                    can_charge = true
                                end
                            end
                        end

                elseif not pLocal:InCond(81) and ONGround then

                        collision = checkCollision(vPlayerFuture, pLocalFuture, swingrange)
                        can_attack = collision
                        can_charge = false
                    
                        if collision and pLocal:InCond(81) then
                            can_attack = true
                        elseif not collision then
                            collision, collisionPoint = checkCollision(vPlayerOrigin ,pLocalOrigin ,swingrange)
                            if collision then
                                can_attack = true
                            end

                            --[[if not collision then -- test for attacks without lag compensation
                                local temp_pLocalFuture = TargetPositionPrediction(pLocalOrigin, time - Latency, pLocal) + Vheight
                                local temp_vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, time - Latency, closestPlayer)
                                local collision1
                                local collisionPoint1
                                collision1 = checkCollision(temp_vPlayerFuture , temp_pLocalFuture, swingrange)
                                if collision1 then
                                    can_attack = true
                                end
                            end]]
                        end

                        if pLocalClass == 4 and Achargebot:GetValue() and chargeLeft >= 100.0 then
                            collision = checkCollision(vPlayerFuture, pLocalOrigin, (swingrange * 1.5)) --increased range when in charge
                            
                            if collision then
                                can_attack = true
                                tick_count = tick_count + 1
                                if tick_count %  (Latency + 4) == 0 then
                                    can_charge = true
                                end
                            end
                        end
                end
                  
            else

                collision = checkCollision(vPlayerFuture, pLocalFuture, swingrange)
                    can_attack = collision
                    can_charge = false

                    if collision then
                        can_attack = true
                    elseif not collision then
                        collision, collisionPoint = checkCollision(vPlayerOrigin ,pLocalOrigin ,swingrange)
                        if collision then
                            can_attack = true
                        end

                    end

                    if pLocalClass == 4 and Achargebot:GetValue() and chargeLeft >= 100.0 then
                        collision = checkCollision(vPlayerFuture, pLocalOrigin, (swingrange * 1.5)) --increased range when in charge
                        
                        if collision then
                            can_attack = true
                            tick_count = tick_count + 1
                            if tick_count % (Latency + 4) == 0 then
                                can_charge = true
                            end
                        end
                    end
            end
                    
--[--------------AimBot-------------------]                --get hitbox of ennmy pelwis(jittery but works)
    local hitboxes = closestPlayer:GetHitboxes()
    local hitbox = hitboxes[4]
    local aimpos
    if collisionPoint ~= nil then
        aimpos = collisionPoint
    elseif aimpos == nil then
        aimpos = (hitbox[1] + hitbox[2]) * 0.5 --if no collision point accesable then aim at defualt hitbox
    end

    flags = pLocal:GetPropInt("m_fFlags")
    if Maimbot:GetValue() and Helpers.VisPos(closestPlayer, vPlayerFuture * 1.7, pLocalFuture)
    and pLocal:InCond(17)
    and not collision then
        -- change angles at target
        aimpos = Math.PositionAngles(pLocalOrigin, vPlayerFuture + Vector3(0, 0, 70))
        pCmd:SetViewAngles(aimpos:Unpack())      --engine.SetViewAngles(aimpos)
    
    elseif Maimbot:GetValue() and flags & FL_ONGROUND == 1 and can_attack then         -- if predicted position is visible then aim at it
        -- change angles at target
        aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
        pCmd:SetViewAngles(aimpos:Unpack())                                         --  engine.SetViewAngles(aimpos) --
    
    elseif Maimbot:GetValue() and flags & FL_ONGROUND == 0 and can_attack then         -- if we are in air then aim at target
        -- change angles at target
        aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
        pCmd:SetViewAngles(aimpos:Unpack()) --engine.SetViewAngles(aimpos)     --set angle at aim position manualy not silent aimbot
    elseif Mchargebot:GetValue() and pLocal:InCond(17) then --manual charge controll
            -- Calculate the source and destination vectors
            UpdateViewAngles(pCmd)
    end
       
    --[shield bashing strat]

    if pLocalClass == 4 and (pLocal:InCond(17)) then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
        local collision1 = checkCollision(vPlayerFuture, pLocalOrigin, 18)

        if not collision1 then -- if demoknight bashed on enemy
            can_attack = false
            goto continue
        end
    end

        --Check if attack simulation was succesfull
            if can_attack then
                
               pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)-- attack

            elseif mAutoRefill:GetValue() then
                if pWeapon:GetCritTokenBucket() <= 27 and fDistance > 400 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)--refill
                end
            end

            if can_charge then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)-- charge
            end
        


-- Update last variables
            vPlayerOriginLast = vPlayerOrigin
            pLocalOriginLast = pLocalOrigin
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

-- debug command: ent_fire !picker Addoutput "health 99999"
local myfont = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
--[[ Code called every frame ]]--
local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end
    if vPlayerOrigin == nil then return end
    if vPlayerFuture == nil and pLocalFuture == nil then return end

    --local pLocal = entities.GetLocalPlayer()
if not mmVisuals:GetValue() then return end
    if pLocalFuture == nil then return end
        draw.SetFont( myfont )
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()
        local screenPos = { w / 2 - 15, h / 2 + 35}

        local vPlayerTargetPos = vPlayerFuture
        
            --[[ draw predicted local position with strafe prediction
            screenPos = client.WorldToScreen(pLocalFuture)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end]]


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
            CalcStrafe(pLocal)
            local flags = pLocal:GetPropInt( "m_fFlags" )
            local strafeAngle = 0
            local ONGround = (flags & FL_ONGROUND == 1)

            if not ONGround then
                strafeAngle = strafeAngles[pLocal:GetIndex()]
            else
                strafeAngle = 0
            end

                    

            local predictedPositions = {} -- table to store all predicted positions
            -- Predict the position for each tick until we reach the final tick we want to predict
            for i = 1, time do
                local tickTime = i
                local pos = TargetPositionPrediction(pLocalOrigin, tickTime, pLocal, strafeAngle)

                -- Add the predicted position to the table
                table.insert(predictedPositions, {pos = pos})
            end

            -- Draw lines between the predicted positions
            for i = 1, #predictedPositions - 1 do
                local pos1 = predictedPositions[i].pos
                local pos2 = predictedPositions[i + 1].pos

                local screenPos1 = client.WorldToScreen(pos1)
                local screenPos2 = client.WorldToScreen(pos2)

                if screenPos1 ~= nil and screenPos2 ~= nil then
                    draw.Color(255, 255, 255, 255) -- Set the color to white
                    if Latency ~= nil then
                        
                        if i <= (time - Latency) then
                            draw.Color(255, 255, 255, 255) -- Set the color to white 
                        else
                            draw.Color(255, 0, 0, 255) -- Set the color to red 
                        end
                    end

                    draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
                end
            end

            -- enemy

            local predictedPositions1 = {} -- table to store all predicted positions
            -- Predict the position for each tick until we reach the final tick we want to predict
            for i = 1, time do
                local tickTime = i
                local pos = TargetPositionPrediction(vPlayerOrigin, tickTime, vPlayer, target_strafeAngle)

                -- Add the predicted position to the table
                table.insert(predictedPositions1, pos)
            end

            -- Draw lines between the predicted positions
            for i = 1, #predictedPositions1 - 1 do
                local pos1 = predictedPositions1[i]
                local pos2 = predictedPositions1[i + 1]

                local screenPos3 = client.WorldToScreen(pos1)
                local screenPos4 = client.WorldToScreen(pos2)

                if screenPos3 ~= nil and screenPos4 ~= nil then
                    draw.Line(screenPos3[1], screenPos3[2], screenPos4[1], screenPos4[2])
                end
            end
                
            end

        -- Check if the range circle is selected, the player future is not nil, and the player is melee
    if not mVisuals:IsSelected("Range Circle") or not vPlayerFuture or not isMelee and GetBestTarget(pLocal) == nil then
        return
    end

    -- Define the two colors to interpolate between
    local color_close = {r = 255, g = 0, b = 0, a = 255} -- red
    local color_far = {r = 0, g = 0, b = 255, a = 255} -- blue

    -- Calculate the target distance for the color to be completely at the close color
    local target_distance = swingrange

    -- Calculate the vertex positions around the circle
    local center = pLocalFuture + Vector3(0, 0, -70) -- center of the circle
    local radius = swingrange -- radius of the circle
    local segments = 64 -- number of segments to use for the circle
    vertices = {} -- table to store circle vertices
    local colors = {} -- table to store colors for each vertex

    for i = 1, segments do
        local angle = math.rad(i * (360 / segments))
        local direction = Vector3(math.cos(angle), math.sin(angle), 0)
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

        -- calculate the color for this line based on the height of the point
        local t = math.max(math.min((z - center.z - target_distance) / (mTHeightt - target_distance), 1), 0)
        local color = {}
        for key, value in pairs(color_close) do
            color[key] = math.floor((1 - t) * value + t * color_far[key])
        end
        colors[i] = color
    end

    -- Calculate the top vertex position
    local top_height = mTHeightt -- adjust as needed
    local top_vertex = client.WorldToScreen(Vector3(center.x, center.y, center.z + top_height))

    -- Draw the circle and connect all the vertices to the top point
    for i = 1, segments do
        local j = i + 1
        if j > segments then j = 1 end
        if vertices[i] and vertices[j] then
            draw.Color(colors[i].r, colors[i].g, colors[i].b, colors[i].a)
            draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
        end
    end

    -- Draw a second circle if Achargebot is enabled
    if pLocalClass == 4 and Achargebot:GetValue() and chargeLeft >= 100 then
        -- Define the color for the second circle
        local color = {r = 0, g = 0, b = 255, a = 255} -- blue

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