--[[ Swing prediction for  Lmaobox  ]]--
--[[      (Modded misc-tools)       ]]--
--[[          --Authors--           ]]--
--[[           Terminator           ]]--
--[[  (github.com/titaniummachine1  ]]--

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
    client.SetConVar("mp_teams_unbalance_limit", 1000)
end, ItemFlags.FullWidth))]]

local Swingpred     = menu:AddComponent(MenuLib.Checkbox("Enable", true, ItemFlags.FullWidth))
local rangepred     = menu:AddComponent(MenuLib.Checkbox("range prediction", true))
local mtime         = menu:AddComponent(MenuLib.Slider("attack distance", 200 ,250 , 240 ))
local mAutoRefill   = menu:AddComponent(MenuLib.Checkbox("Crit Refill", true))
local mAutoGarden   = menu:AddComponent(MenuLib.Checkbox("Troldier assist", false))
local mmVisuals     = menu:AddComponent(MenuLib.Checkbox("Enable Visuals", false))
--local mKillaura     = menu:AddComponent(MenuLib.Checkbox("Killaura (soon)", false))
local Visuals = {
    ["Range Circle"] = true,
    ["Draw Trail"] = true
  }

local mVisuals = menu:AddComponent(MenuLib.MultiCombo("^Visuals", Visuals, ItemFlags.FullWidth))
local mcolor_close  = menu:AddComponent(MenuLib.Colorpicker("Color", color))

if GetViewHeight ~= nil then
    local mTHeightt     = GetViewHeight()
end
local mTHeightt = 85
local msamples = 66
local pastPredictions = {}
local hitbox_min = Vector3(14, 14, 0)
local hitbox_max = Vector3(-14, -14, 85)
local vPlayerOrigin = nil
local pLocal = entities.GetLocalPlayer()     -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
local tickRate = 66 -- game tick rate
local pLocalOrigin
local closestPlayer
local closestDistance = 2000
local tick = 0
local pLocalClass
local swingrange = 1
local mresolution = 128
local viewheight

--[[function GetViewHeight()
    if pLocal == nil then pLocalOrigin = pLocal:GetAbsOrigin() return pLocalOrigin end
    --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
    local viewOffset = vector3(0, 0, 75)
    local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
    viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()
        -- eye level 
        local Vheight = Vector3(0, 0, viewheight)
        pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)

    return pLocalOrigin
end]]


function GetClosestEnemy(pLocal, pLocalOrigin)
    local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game
    local closestDistance = 2000
    local maxDistance = 2000
    local closestPlayer = nil
    -- find closest enemy
    for _, vPlayer in ipairs(players) do
        if vPlayer ~= nil and vPlayer:IsAlive() and vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber() then
            local vPlayerOrigin = vPlayer:GetAbsOrigin()
            local distanceX = math.abs(vPlayerOrigin.x - pLocalOrigin.x)
            local distanceY = math.abs(vPlayerOrigin.y - pLocalOrigin.y)
            local distanceZ = math.abs(vPlayerOrigin.z - pLocalOrigin.z)
            local distance = math.sqrt(distanceX * distanceX + distanceY * distanceY + distanceZ * distanceZ)
            if distance < closestDistance and distance <= maxDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end
    end
    if closestDistance < 2000 then
    return closestPlayer
    else
        return nil
    end
end

function TargetPositionPrediction(targetLastPos, targetOriginLast, tickRate, time, targetEntity)
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
    local targetVelocity = targetEntity:EstimateAbsVelocity()
    if targetVelocity == nil then
        targetVelocity = targetLastPos - targetOriginLast
    end
    table.insert(targetVelocitySamples[targetKey], 1, targetVelocity)

    local samples = msamples
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
        local targetFuture = targetLastPos + (averageVelocity * time) + curve
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
local function OnCreateMove(pCmd)
        if not Swingpred:GetValue() then goto continue end -- enable or distable script
        if not pLocal then goto continue end  -- Immediately check if the local player exists. If it doesn't, return.

            local pLocalClass = pLocal:GetPropInt("m_iClass") --getlocalclass
            if pLocalClass == nil then goto continue end --when local player did not chose class then skip code
            if pLocalClass == 8 then goto continue end --when local player is spy then skip code
            local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
            swingrange = pWeapon:GetSwingRange()
            local flags = pLocal:GetPropInt( "m_fFlags" )
            local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game
            local time = mtime:GetValue() * 0.001

    if mAutoGarden:GetValue() == true then
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

        if flags & FL_ONGROUND == 0 and not bhopping then
            pCmd:SetButtons(pCmd.buttons | IN_DUCK)
        else
            pCmd:SetButtons(pCmd.buttons & (~IN_DUCK))
        end
    end

    -- Initialize closest distance and closest player
    isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon

    --try get vierwhegiht without crash
    if pLocalClass ~= pLocalClasslast then
        if pLocal == nil then pLocalOrigin = pLocal:GetAbsOrigin() return pLocalOrigin end
        --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
        local viewOffset = Vector3(0, 0, 75)
        local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
        viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()
            -- eye level 
            local Vheight = Vector3(0, 0, viewheight)
            pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)
    end

    closestPlayer = GetClosestEnemy(pLocal, pLocalOrigin, players)
if closestPlayer == nil then goto continue end
        vPlayerOrigin = closestPlayer:GetAbsOrigin()
        vdistance = (vPlayerOrigin - pLocalOrigin):Length()
        --local Killaura = mKillaura:GetValue()
            vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, vPlayerOriginLast, tickRate, time, closestPlayer)
            pLocalFuture =  TargetPositionPrediction(pLocalOrigin, pLocalOriginLast, tickRate, time, pLocal)
            
            fDistance = (vPlayerFuture - pLocalFuture):Length()

--[[-----------------------------Swing Prediction------------------------------------------------------------------------]]
if not isMelee then goto continue end
            -- bypass problem with prior attacking with shield not beeign able to reach target..
            local stop = false
            if (pLocal:InCond(17)) and pLocalClass == 4 or pLocalClass == 8 then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
                stop = true
                local dynamicstop = swingrange + 10
                if (pCmd.forwardmove == 0) then dynamicstop = swingrange - 10 end -- case if you dont hold w when charging
              
                if isMelee and pLocalClass == 4 and vdistance <= dynamicstop then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end
            end
        --wall check
        local can_attack = false
        local trace = engine.TraceLine(pLocalFuture, vPlayerFuture, MASK_SHOT_HULL)
        if (trace.entity:GetClass() == "CTFPlayer") and (trace.entity:GetTeamNumber() ~= pLocal:GetTeamNumber()) then
            can_attack = isWithinHitbox(GetTriggerboxMin(swingrange, vPlayerFuture), GetTriggerboxMax(swingrange, vPlayerFuture), pLocalFuture, vPlayerFuture)
            swingrange = swingrange + 40
            if fDistance <= (swingrange + 20) then
                can_attack = true
            end
        end
        
       
        --Attack when futere position is inside attack range triggerbox
            if isMelee and not stop and can_attack then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                --[[if mKillaura:GetValue() == true and warp.GetChargedTicks() >= 22 then
                    warp.TriggerWarp()
                    --warp.TriggerDoubleTap()
                end]]
            elseif isMelee and not stop and pWeapon:GetCritTokenBucket() <= 27 and mAutoRefill:GetValue() == true then
                if vdistance > 400 and can_attack then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)--refill
                elseif vdistance > 500 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)--refill
                end
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

    --local pLocal = entities.GetLocalPlayer()
if not mmVisuals:GetValue() then return end
    if pLocalFuture == nil then return end
        draw.SetFont( myfont )
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()
        local screenPos = { w / 2 - 15, h / 2 + 35}

        local vPlayerTargetPos = vPlayerFuture
        -- draw predicted local position with strafe prediction
            local screenPos = client.WorldToScreen(pLocalFuture)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end

        -- draw predicted enemy position with strafe prediction connecting his local point and predicted position with line.
            local screenPos = client.WorldToScreen(vPlayerTargetPos)
            if screenPos ~= nil then
                local screenPos1 = client.WorldToScreen(vPlayerOrigin)
                if screenPos1 ~= nil then
                    draw.Line( screenPos1[1], screenPos1[2], screenPos[1], screenPos[2])
                end
            end

            

            if vhitbox_Height_trigger == nil then return end
            
            local vertices = {
                client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)),
                client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height_trigger)),
                client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height_trigger)),
                client.WorldToScreen(vPlayerTargetPos + Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, vhitbox_Height_trigger)),
                client.WorldToScreen(vPlayerTargetPos + Vector3(vhitbox_width_trigger, -vhitbox_width_trigger, vhitbox_Height_trigger))
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

                -- Strafe prediction visualization
                if mVisuals:IsSelected("Draw Trail") then
                    local maxPositions = 20
                    if predictedPositions == nil then
                        predictedPositions = {}
                    end
        
                    -- Add the latest predicted position to the beginning of the table
                    table.insert(predictedPositions, 1, pLocalFuture)
        
                    -- Remove the last position in the table if there are more than 5
                    if #predictedPositions > maxPositions then
                        table.remove(predictedPositions, maxPositions + 1)
                    end
        
                    -- Draw lines between the past 5 positions
                    for i = 1, math.min(#predictedPositions - 1, maxPositions - 1) do
                        local pos1 = predictedPositions[i]
                        local pos2 = predictedPositions[i + 1]
        
                        local screenPos1 = client.WorldToScreen(pos1)
                        local screenPos2 = client.WorldToScreen(pos2)
        
                        if screenPos1 ~= nil and screenPos2 ~= nil then
                            draw.Line(screenPos1[1], screenPos1[2], screenPos2[1], screenPos2[2])
                        end
                    end
        end

    if mVisuals:IsSelected("Range Circle") == false then return end
    if vPlayerFuture == nil then return end
    if not isMelee then return end
        -- Define the two colors to interpolate between
        local color_close = {r = 255, g = 0, b = 0, a = 255} -- red
        local color_far = {r = 0, g = 0, b = 255, a = 255} -- blue

        -- Get the selected colors from the menu and convert them to the correct format
        local selected_color = mcolor_close:GetColor()
        color_close = {r = selected_color[1], g = selected_color[2], b = selected_color[3], a = selected_color[4]}

        local selected_color1 = mcolor_close:GetColor()
        color_far = {r = selected_color1[1], g = selected_color1[2], b = selected_color1[3], a = selected_color1[4]}

        -- Calculate the target distance for the color to be completely at the close color
        local target_distance = (swingrange)

        -- Calculate the vertex positions around the circle
        local center = vPlayerFuture
        local radius = swingrange -- radius of the circle
        local segments = mresolution -- number of segments to use for the circle
        local vertices = {} -- table to store circle vertices
        local colors = {} -- table to store colors for each vertex

        for i = 1, segments do
        local angle = math.rad(i * (360 / segments))
        local direction = Vector3(math.cos(angle), math.sin(angle), 0)
        local trace = engine.TraceLine(vPlayerFuture, center + direction * radius, MASK_SHOT_BRUSHONLY)
        local distance = radius
        local x = center.x + math.cos(angle) * distance
        local y = center.y + math.sin(angle) * distance
        local z = center.z + 1
        
    if trace == nil then return end
        local distance_to_hit = trace.fraction * radius -- calculate distance to hit point
    if  distance_to_hit == nil then return end

        if distance_to_hit > 0 then
            local max_height_adjustment = mTHeightt -- adjust as needed
            local height_adjustment = (1 - distance_to_hit / radius) * max_height_adjustment
            z = z + height_adjustment
        end
        
        vertices[i] = client.WorldToScreen(Vector3(x, y, z))
        
        -- calculate the color for this line based on the height of the point
        local t = (z - center.z - target_distance) / (mTHeightt - target_distance)
        if t < 0 then
            t = 0
        elseif t > 1 then
            t = 1
        end
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
            if vertices[i] ~= nil and vertices[j] ~= nil then
            draw.Color(colors[i].r, colors[i].g, colors[i].b, colors[i].a)
            draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
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