--[[ Swing prediction for  Lmaobox  ]]--
--[[      (Modded misc-tools)       ]]--
--[[          --Authors--           ]]--
--[[           Terminator           ]]--
--[[  (github.com/titaniummachine1  ]]--

local menuLoaded, MenuLib = pcall(require, "Menu")                                -- Load MenuLib
assert(menuLoaded, "MenuLib not found, please install it!")                       -- If not found, throw error
assert(MenuLib.Version >= 1.44, "MenuLib version is too old, please update it!")  -- If version is too old, throw error

if UnloadLib then UnloadLib() end
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.981, "LNXlib version is too old, please update it!")

---@alias AimTarget { entity : Entity, pos : Vector3, angles : EulerAngles, factor : number }

local Math, Conversion = lnxLib.Utils.Math, lnxLib.Utils.Conversion
local WPlayer, WWeapon = lnxLib.TF2.WPlayer, lnxLib.TF2.WWeapon
local Helpers, Prediction = lnxLib.TF2.Helpers, lnxLib.TF2.Prediction
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
local Maimbot       = menu:AddComponent(MenuLib.Checkbox("Aimbot(Rage)", true, ItemFlags.FullWidth))
local mFov         = menu:AddComponent(MenuLib.Slider("Aimbot FOV",10 ,360 ,180 ))
local mtime         = menu:AddComponent(MenuLib.Slider("prediction(ticks)",3 ,20 ,14 ))
local mAutoRefill   = menu:AddComponent(MenuLib.Checkbox("Crit Refill", true))
local mAutoGarden   = menu:AddComponent(MenuLib.Checkbox("Troldier assist", false))
local mmVisuals     = menu:AddComponent(MenuLib.Checkbox("Enable Visuals", false))
local Visuals = {
    ["Range Circle"] = true,
    ["Draw Trail"] = false
}

local mVisuals = menu:AddComponent(MenuLib.MultiCombo("^Visuals", Visuals, ItemFlags.FullWidth))
local mcolor_close  = menu:AddComponent(MenuLib.Colorpicker("Color", color))

if GetViewHeight ~= nil then
    local mTHeightt = GetViewHeight()
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
local closestDistance = 2000
local tick
local pLocalClass
local swingrange
local mresolution = 128
local viewheight
local tick_count = 0
local isMelee = false
local vdistance
local fDistance
local vPlayerFuture
local pLocalFuture
local ping = 0

local settings = {
    MinDistance = 200,
    MaxDistance = 1000,
    MinHealth = 10,
    MaxHealth = 100,
    MinFOV = 0,
    MaxFOV = mFov:GetValue(),
}

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
        local health = player:GetHealth()

        local angles = Math.PositionAngles(localPlayer:GetAbsOrigin(), player:GetAbsOrigin())
        local fov = Math.AngleFov(engine.GetViewAngles(), angles)

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
        if fov > settings.MaxFOV then goto continue end

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

    

function TargetPositionPrediction(targetLastPos, time, targetEntity)
    -- If the last known position of the target is nil, return nil.
    if targetLastPos == nil then
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
        targetVelocity = targetLastPos - targetEntity:GetOrigin()
    end
    table.insert(targetVelocitySamples[targetKey], 1, targetVelocity)

    local samples = 3
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

    --if time is more then 5 then expect ticks and convert ticks into decimal of time
    if time > 2 then
        time = time / tickRate
    end

    -- Scale the curve by the tick rate and time to predict.
    curve = curve * tickRate * time

    -- Calculate the current predicted position.
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

function isWithinHitbox(hitboxMinTrigger, hitboxMaxTrigger, pLocalFuture, vPlayerFuture)
    if not pLocalFuture or not hitboxMinTrigger or not hitboxMaxTrigger then
        return false
    end
    
    -- Unpack hitbox vectors
    local minX, minY, minZ = hitboxMinTrigger:Unpack()
    local maxX, maxY, maxZ = hitboxMaxTrigger:Unpack()
  
    -- Check if pLocalFuture is within the hitbox
    return pLocalFuture.x >= minX and pLocalFuture.x <= maxX and
           pLocalFuture.y >= minY and pLocalFuture.y <= maxY and
           pLocalFuture.z >= minZ and pLocalFuture.z <= maxZ
end

local Hitbox = {
    Head = 1,
    Neck = 2,
    Pelvis = 4,
    Body = 5,
    Chest = 7
}


--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd)
    if not Swingpred:GetValue() then goto continue end -- enable or distable script
--[--if we are not existign then stop code--]
        pLocal = entities.GetLocalPlayer()     -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
        if not pLocal then return end  -- Immediately check if the local player exists. If it doesn't, return.
        ping = entities.GetPlayerResources():GetPropDataTableInt("m_iPing")[pLocal:GetIndex()]
        --[--Check local player class if spy or none then stop code--]

        pLocalClass = pLocal:GetPropInt("m_iClass") --getlocalclass
            if pLocalClass == nil then goto continue end --when local player did not chose class then skip code
            if pLocalClass == 8 then goto continue end --when local player is spy then skip code

--[--obtain secondary information after confirming we need it for fps boost whe nnot using script]
                local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
                local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game
                local time = mtime:GetValue()
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
        else
            pCmd:SetButtons(pCmd.buttons & (~IN_DUCK))
        end
    end
    
--[-Don`t run script below when not usign melee--]

    isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon
    if not isMelee then goto continue end -- if not melee then skip code

--[-------get vierwhegiht Optymised--------]

    if pLocalClass ~= pLocalClasslast then
        if pLocal == nil then pLocalOrigin = pLocal:GetAbsOrigin() return pLocalOrigin end
        --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
        local viewOffset = Vector3(0, 0, 70)
        local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
        viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()
            -- eye level 
            local Vheight = Vector3(0, 0, viewheight)
            pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)
    end

--[-----Get best target------------------]
if GetBestTarget(pLocal) ~= nil then
    closestPlayer = GetBestTarget(pLocal).entity --GetClosestEnemy(pLocal, pLocalOrigin, players)
end
--[-----Refil and skip code when alone-----]

if closestPlayer == nil then
    if mAutoRefill:GetValue() and pWeapon:GetCritTokenBucket() <= 27 then
        pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
    end goto continue
end

    vPlayerOrigin = closestPlayer:GetAbsOrigin() -- get closest player origin

--[--------------Prediction-------------------] -- predict both players position after swing
        
            vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, time, closestPlayer)
            pLocalFuture =  TargetPositionPrediction(pLocalOrigin, time, pLocal)

--[--------------Distance check-------------------]
        --get current distance between local player and closest player
        vdistance = (vPlayerOrigin - pLocalOrigin):Length()

        -- get distance between local player and closest player after swing
        fDistance = (vPlayerFuture - pLocalFuture):Length()

--[[-----------------------------Swing Prediction------------------------------------------------------------------------]]

            local can_attack = false
            local stop = false
            swingrange = pWeapon:GetSwingRange()

        --[bypass problem with prior attacking with shield not beeign able to reach target]..
            if (pLocal:InCond(17)) and pLocalClass == 4 or pLocalClass == 8 then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
                stop = true
                local dynamicstop = swingrange
                if (pCmd.forwardmove == 0) then dynamicstop = swingrange - 10 end -- case if you dont hold w when charging
              
                if isMelee and pLocalClass == 4 and vdistance <= dynamicstop then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                    stop = false
                end
            end

--[--------------AimBot-------------------]                --get hitbox of ennmy pelwis(jittery but works)
                local hitboxes = closestPlayer:GetHitboxes()
                local hitbox = hitboxes[4]
                local aimpos = (hitbox[1] + hitbox[2]) * 0.5
        if Maimbot:GetValue() and Helpers.VisPos(closestPlayer,vPlayerFuture + Vector3(0, 0, 150), pLocalFuture) and pLocal:InCond(17) then

                -- change angles at target
                aimpos = Math.PositionAngles(pLocalOrigin, vPlayerFuture + Vector3(0, 0, 60))
                pCmd:SetViewAngles(aimpos:Unpack()) --engine.SetViewAngles(aimpos) 

        else -- if predicted position is visible then aim at it
                -- change angles at target
                aimpos = Math.PositionAngles(pLocalOrigin, aimpos)
                pCmd:SetViewAngles(aimpos:Unpack()) --engine.SetViewAngles(aimpos) 

        end

--[----------------wall check Future-------------]

        --trace = engine.TraceLine(pLocalFuture, vPlayerFuture + Vector3(0, 0, 150), MASK_SHOT_HULL)
        --if (trace.entity:GetClass() == "CTFPlayer") and (trace.entity:GetTeamNumber() ~= pLocal:GetTeamNumber()) then
-- Visiblity Check
if Helpers.VisPos(closestPlayer,vPlayerFuture + Vector3(0, 0, 150), pLocalFuture) then
                --[[check if can hit after swing]]
                    can_attack = isWithinHitbox(GetTriggerboxMin(swingrange, vPlayerFuture), GetTriggerboxMax(swingrange, vPlayerFuture), pLocalFuture, vPlayerFuture)

                    if fDistance <= (swingrange + 60) then
                        can_attack = true
                    elseif vdistance <= (swingrange + 60) then
                        can_attack = true
                    elseif can_attack == false then
                        can_attack = isWithinHitbox(GetTriggerboxMin(swingrange, vPlayerOrigin), GetTriggerboxMax(swingrange, vPlayerOrigin), pLocalOrigin, vPlayerOrigin)
                    end
           end
        
       
        --Attack when futere position is inside attack range triggerbox
            if isMelee and not stop and can_attack then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)

                    --[[if mKillaura:GetValue() == true and warp.GetChargedTicks() >= 22 then
                        warp.TriggerWarp()
                        --warp.TriggerDoubleTap()
                    end]]

            elseif mAutoRefill:GetValue() and isMelee and not stop then
                if pWeapon:GetCritTokenBucket() <= 27 and fDistance > 400 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)--refill
                end
            end


-- Update last variables
            vPlayerOriginLast = vPlayerOrigin
            pLocalOriginLast = pLocalOrigin
    ::continue::
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
        -- draw predicted local position with strafe prediction
            screenPos = client.WorldToScreen(pLocalFuture)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end

        -- draw predicted enemy position with strafe prediction connecting his local point and predicted position with line.
            screenPos = client.WorldToScreen(vPlayerTargetPos)
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
        local radius = swingrange + 40 -- radius of the circle
        local segments = mresolution -- number of segments to use for the circle
        vertices = {} -- table to store circle vertices
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