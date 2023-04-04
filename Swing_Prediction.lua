--[[ Swing prediction for  Lmaobox  ]]--
--[[      (Modded misc-tools)       ]]--
--[[          --Authors--           ]]--
--[[           Terminator           ]]--
--[[  (github.com/titaniummachine1  ]]--
--[[                                ]]--
--[[    credit to thoose people     ]]--
--[[      LNX (github.com/lnx00)    ]]--
--[[             Muqa1              ]]--
--[[   https://github.com/Muqa1     ]]--
--[[         SylveonBottle          ]]--

local menuLoaded, MenuLib = pcall(require, "Menu")                                -- Load MenuLib
assert(menuLoaded, "MenuLib not found, please install it!")                       -- If not found, throw error
assert(MenuLib.Version >= 1.44, "MenuLib version is too old, please update it!")  -- If version is too old, throw error

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
end, ItemFlags.FullWidth))]]
local debug         = menu:AddComponent(MenuLib.Checkbox("indicator", false))
local Swingpred     = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local mKillaura     = menu:AddComponent(MenuLib.Checkbox("Killaura (soon)", false))
local mtime         = menu:AddComponent(MenuLib.Slider("movement ahead", 100 ,295 , 250 ))
local msamples      = menu:AddComponent(MenuLib.Slider("Velocity Samples", 1 ,777 , 132 ))
--amples    = menu:AddComponent(MenuLib.Slider("movement ahead", 1 ,25 , 200 ))

local pastPredictions = {}
local hitbox_min = Vector3(14, 14, 0)
local hitbox_max = Vector3(-14, -14, 85)
local vPlayerOrigin = nil


function GameData()
    local data = {}

    -- Get local player data
    data.pLocal = entities.GetLocalPlayer()     -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
    data.pWeapon = data.pLocal:GetPropEntity("m_hActiveWeapon")
    data.swingrange = data.pWeapon:GetSwingRange() -- + 11.17
    data.tickRate = 66 -- game tick rate
    --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
    local viewOffset = data.pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local adjustedHeight = data.pLocal:GetAbsOrigin() + viewOffset
    data.viewheight = (adjustedHeight - data.pLocal:GetAbsOrigin()):Length()
        -- eye level 
        local Vheight = Vector3(0, 0, data.viewheight)
        data.pLocalOrigin = (data.pLocal:GetAbsOrigin() + Vheight)
    --get local class
    data.pLocalClass = data.pLocal:GetPropInt("m_iClass")


    return data
end

function GetClosestEnemy(pLocal, pLocalOrigin, players)
    local closestDistance = 1000
    local maxDistance = 1000
    local closestPlayer = nil
    -- find closest enemy
    for _, vPlayer in ipairs(players) do
        if vPlayer ~= nil and vPlayer:IsAlive() and vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber() then
            local vPlayerOrigin = vPlayer:GetAbsOrigin()
            local distanceX = math.abs(vPlayerOrigin.x - pLocalOrigin.x)
            local distanceY = math.abs(vPlayerOrigin.y - pLocalOrigin.y)
            local distanceZ = 0
            local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY + distanceZ * distanceZ)
            if distance < closestDistance and distance <= maxDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end
    end
    return closestPlayer
end

function TargetPositionPrediction(targetLastPos, targetOriginLast, tickRate, time)
    -- If the origin of the target from the previous tick is nil, initialize it to a zero vector.
    if targetOriginLast == nil then
        targetOriginLast = Vector3(0, 0, 0)
    end

    -- If either the target's last known position or previous origin is nil, return nil.
    if targetOriginLast == nil or targetLastPos == nil then
        return nil
    end

    -- Initialize targetVelocitySamples as a table if it doesn't exist.
    if not targetVelocitySamples then
        targetVelocitySamples = {}
    end

    -- Initialize the table for this target if it doesn't exist.
    local targetKey = tostring(targetLastPos)
    if not targetVelocitySamples[targetKey] then
        targetVelocitySamples[targetKey] = {}
    end

    -- Insert the latest velocity sample into the table.
    local targetVelocity = targetLastPos - targetOriginLast
    table.insert(targetVelocitySamples[targetKey], 1, targetVelocity)

    local samples = msamples:GetValue()
    -- Remove the oldest sample if there are more than maxSamples.
    if #targetVelocitySamples[targetKey] > samples then
        table.remove(targetVelocitySamples[targetKey], samples + 1)
    end

    -- Calculate the average velocity from the samples.
    local totalVelocity = Vector3(0, 0, 0)
    for i = 1, #targetVelocitySamples[targetKey] do
        totalVelocity = totalVelocity + targetVelocitySamples[targetKey][i]
    end
    local averageVelocity = totalVelocity / #targetVelocitySamples[targetKey]

    -- Initialize the curve to a zero vector.
    local curve = Vector3(0, 0, 0)

    -- Calculate the curve of the path if there are enough samples.
    if #targetVelocitySamples[targetKey] >= 2 then
        local previousVelocity = targetVelocitySamples[targetKey][1]
        for i = 2, #targetVelocitySamples[targetKey] do
            local currentVelocity = targetVelocitySamples[targetKey][i]
            curve = curve + (previousVelocity - currentVelocity)
            previousVelocity = currentVelocity
        end
        curve = curve / (#targetVelocitySamples[targetKey] - 1)
    end

    -- Scale the curve by the tick rate and time to predict.
    curve = curve * tickRate * time

    -- Add the curve to the predicted future position of the target.
        local targetFuture = targetLastPos + (averageVelocity * tickRate * time) + curve
    -- Return the predicted future position.
    return targetFuture
end

local vhitbox_Height = 85
local vhitbox_width = 18
function GetTriggerboxMin(swingrange, vPlayerFuture)
    if vPlayerFuture ~= nil and isMelee then
        vhitbox_Height_trigger_bottom = swingrange
        vhitbox_width_trigger = (vhitbox_width + swingrange)
        local vhitbox_min = Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)
        local hitbox_min_trigger = (vPlayerFuture + vhitbox_min)
        return hitbox_min_trigger
    end
end

function GetTriggerboxMax(swingrange, vPlayerFuture)
    if vPlayerFuture ~= nil and isMelee then
        vhitbox_Height_trigger = (vhitbox_Height + swingrange)
        vhitbox_width_trigger = (vhitbox_width + swingrange)
        local vhitbox_max = Vector3(vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height_trigger)
        local hitbox_max_trigger = (vPlayerFuture + vhitbox_max)
        return hitbox_max_trigger
    end
end

function isWithinHitbox(hitbox_min_trigger, hitbox_max_trigger, pLocalFuture, vPlayerFuture)
    if pLocalFuture == nil or hitbox_min_trigger == nil or hitbox_max_trigger == nil then
        return false
    end
    -- Unpack hitbox vectors
    local hitbox_min_trigger_x, hitbox_min_trigger_y, hitbox_min_trigger_z = hitbox_min_trigger:Unpack()
    local hitbox_max_trigger_x, hitbox_max_trigger_y, hitbox_max_trigger_z = hitbox_max_trigger:Unpack()
  
    -- Check if pLocalFuture is within the hitbox
    if pLocalFuture.x < hitbox_min_trigger_x or pLocalFuture.x > hitbox_max_trigger_x then
        return false
    end
    if pLocalFuture.y < hitbox_min_trigger_y or pLocalFuture.y > hitbox_max_trigger_y then
        return false
    end
    if pLocalFuture.z < hitbox_min_trigger_z or pLocalFuture.z > hitbox_max_trigger_z then
        return false
    end
     -- Check if vPlayerFuture is within distanceThreshold distance from pLocalFuture
     if (vPlayerFuture - pLocalFuture):Length() > 200 then
        return false
    end
    return true
end

--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd, gameData)
    if not Swingpred:GetValue() then goto continue end -- enable or distable script

    local time = mtime:GetValue() * 0.001
    gameData = GameData()  -- Update gameData with latest information
    local pLocal, pWeapon, swingrange, viewheight, pLocalOrigin, pLocalClass, tickRate
    = gameData.pLocal, gameData.pWeapon, gameData.swingrange, gameData.viewheight, gameData.pLocalOrigin, gameData.pLocalClass, gameData.tickRate
    -- Use pLocal, pWeapon, pWeaponDefIndex, etc. as needed
    if not pLocal then return end  -- Immediately check if the local player exists. If it doesn't, return.
    if pLocalClass == nil then goto continue end
    if pLocalClass == 8 then return end

    -- Initialize closest distance and closest player
    isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon
    local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game

if not isMelee then return end


    closestPlayer = GetClosestEnemy(pLocal, pLocalOrigin, players)
    if closestPlayer == nil then goto continue end
    if closestDistance == 1200 then goto continue end
        vPlayerOrigin = closestPlayer:GetAbsOrigin()

        local Killaura = mKillaura:GetValue()
        --[[position prediction]]--
        vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, vPlayerOriginLast, tickRate, time, Killaura)
        pLocalFuture = TargetPositionPrediction(pLocalOrigin, pLocalOriginLast, tickRate, time)
        targetFuture, targetVelocityTable = TargetPositionPrediction(pLocalOrigin, pLocalOriginLast, tickRate, time)
--[[-----------------------------Swing Prediction------------------------------------------------------------------------]]

            -- bypass problem with prior attacking with shield not beeign able to reach target..
            local stop = false
            if (pLocal:InCond(17)) and pLocalClass == 4 or pLocalClass == 8 then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
                stop = true
                local dynamicstop = swingrange + 10
                if (pCmd.forwardmove == 0) then dynamicstop = swingrange - 10 end -- case if you dont hold w when charging
                
                vdistance = (vPlayerOrigin - pLocalOrigin):Length()
                if pLocalClass == 4 and vdistance <= dynamicstop then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end
            end
        
        --wall check
        local can_attack = false
        
        local trace = engine.TraceLine(pLocalFuture, vPlayerOrigin, MASK_SHOT_HULL)
        if (trace.entity:GetClass() == "CTFPlayer") and (trace.entity:GetTeamNumber() ~= pLocal:GetTeamNumber()) then
            can_attack = isWithinHitbox(GetTriggerboxMin(swingrange, vPlayerFuture), GetTriggerboxMax(swingrange, vPlayerFuture), pLocalFuture, vPlayerFuture)
            if mKillaura:GetValue() == true and warp.GetChargedTicks() >= 22 then
                --warp.TriggerWarp()
                --warp.TriggerDoubleTap()
            end
        end

        --Attack when futere position is inside attack range triggerbox
            if isMelee and not stop and can_attack then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            end

-- Update last variables
            vPlayerOriginLast = vPlayerOrigin
            pLocalOriginLast = pLocalOrigin
    ::continue::
end

-- debug command: ent_fire !picker Addoutput "health 99"
local myfont = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
--[[ Code called every frame ]]--
local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end
    if vPlayerOrigin == nil then return end
    if vPlayerFuture == nil and pLocalFuture == nil then return end

    local pLocal = entities.GetLocalPlayer()
    if debug and debug:GetValue() == true and isMelee then
        if pLocalFuture == nil then return end
        draw.SetFont( myfont )
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()
        local screenPos = { w / 2 - 15, h / 2 + 35}



        local screenPos = client.WorldToScreen(vPlayerOrigin)
        if screenPos ~= nil then
            draw.Line( screenPos[1], screenPos[2], screenPos[1], screenPos[2] - 20)
        end
        local screenPos = client.WorldToScreen(pLocalFuture)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end

            local screenPos = client.WorldToScreen(vPlayerFuture)
            if screenPos ~= nil then
                local screenPos1 = client.WorldToScreen(vPlayerOrigin)
                if screenPos1 ~= nil then
                    draw.Line( screenPos1[1], screenPos1[2], screenPos[1], screenPos[2])
                end
            end
            if vhitbox_Height_trigger == nil then return end

            local vertices = {
                client.WorldToScreen(vPlayerFuture + Vector3(vhitbox_width_trigger, vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerFuture + Vector3(-vhitbox_width_trigger, vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerFuture + Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerFuture + Vector3(vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerFuture + Vector3(vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height_trigger)),
                client.WorldToScreen(vPlayerFuture + Vector3(-vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height_trigger)),
                client.WorldToScreen(vPlayerFuture + Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, vhitbox_Height_trigger)),
                client.WorldToScreen(vPlayerFuture + Vector3(vhitbox_width_trigger, -vhitbox_width_trigger, vhitbox_Height_trigger))
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
            if vertices[4] and vertices[8] then draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2]) 
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