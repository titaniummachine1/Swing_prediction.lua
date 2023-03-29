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

menu:AddComponent(MenuLib.Button("Debug", function() -- Disable Weapon Sway (Executes commands)
    client.SetConVar("cl_vWeapon_sway_interp",              0)             -- Set cl_vWeapon_sway_interp to 0
    client.SetConVar("cl_jiggle_bone_framerate_cutoff", 0)             -- Set cl_jiggle_bone_framerate_cutoff to 0
    client.SetConVar("cl_bobcycle",                     10000)         -- Set cl_bobcycle to 10000
    client.SetConVar("sv_cheats", 1)                                    -- debug fast setup
    client.SetConVar("mp_disable_respawn_times", 1)
    client.SetConVar("mp_respawnwavetime", -1)
end, ItemFlags.FullWidth))

local debug         = menu:AddComponent(MenuLib.Checkbox("indicator", true))
local Swingpred     = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local Swingpred1     = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local Swingpred2     = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local mtime         = menu:AddComponent(MenuLib.Slider("movement ahead", 100 ,175 , 150 ))

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


function TargetPositionPrediction(targetLastPos, targetOriginLast, tickRate, time)
    if targetOriginLast == nil then
        targetOriginLast = Vector3(0, 0, 0)
    end
    if targetOriginLast == nil or targetLastPos == nil then
        return nil
    end
    
    local targetVelocity = targetLastPos - targetOriginLast
    local targetVelocityX, targetVelocityY, targetVelocityZ = targetVelocity:Unpack()
    local targetVelocityVec = Vector3(targetVelocityX * tickRate * time, targetVelocityY * tickRate * time, targetVelocityZ * tickRate * time)

    local targetFuture = targetLastPos + targetVelocityVec
    
    return targetFuture
end

function GetTriggerboxMin(swingrange, vPlayerFuture)
    if vPlayerFuture ~= nil then
        vhitbox_Height_trigger_bottom = swingrange
        vhitbox_width_trigger = (14 + swingrange)
        local vhitbox_min = Vector3(-vhitbox_width_trigger, -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom)
        local hitbox_min_trigger = (vPlayerFuture + vhitbox_min)
        return hitbox_min_trigger
    end
end

function GetTriggerboxMax(swingrange, vPlayerFuture)
    if vPlayerFuture ~= nil then
        vhitbox_Height_trigger = (85 + swingrange)
        vhitbox_width_trigger = (14 + swingrange)
        local vhitbox_max = Vector3(vhitbox_width_trigger, vhitbox_width_trigger, vhitbox_Height_trigger)
        local hitbox_max_trigger = (vPlayerFuture + vhitbox_max)
        return hitbox_max_trigger
    end
end

function isWithinHitbox(hitbox_min_trigger, hitbox_max_trigger, pLocalFuture)
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

    local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game

    -- Initialize closest distance and closest player



    local Vhitbox_Height = 85
    local vhitbox_width = 14
    local closestDistance = 1200

    local maxDistance = 1000

    if pLocalClass == nil then goto continue end

    if pLocalClass == 8 then
        return
    end

   
    -- find clsoest enemy
    for _, vPlayer in ipairs(players) do
        if vPlayer ~= nil and vPlayer:IsAlive() and vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber() then
            vPlayerOrigin = vPlayer:GetAbsOrigin()
            local distance = (vPlayerOrigin - pLocalOrigin):Length()
            if distance < closestDistance and distance <= maxDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end
    end
    
    if closestPlayer == nil then goto continue end

        vPlayerOrigin = closestPlayer:GetAbsOrigin()

if not Swingpred2:GetValue() then goto continue end
        --[[position prediction]]--
        vPlayerFuture = TargetPositionPrediction(vPlayerOrigin, vPlayerOriginLast, tickRate, time)
        pLocalFuture = TargetPositionPrediction(pLocalOrigin, pLocalOriginLast, tickRate, time)

            --[[-----------------------------Swing Prediction--------------------------------]]
        local isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon

            -- bypass problem with prior attacking with shield not beeign able to reach target..
            local stop = false
            if (pLocal:InCond(17)) and pLocalClass == 4 or pLocalClass == 8 then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
                stop = true
                dynamicstop = 30
                if (pCmd.forwardmove == 0) then dynamicstop = 30 end -- case if you dont hold w when charging
                if closestDistance <= dynamicstop and pLocalClass == 4 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end
            end

        --Attack when futere position is inside attack range triggerbox
            if isMelee and not stop and isWithinHitbox(GetTriggerboxMin(swingrange, vPlayerFuture), GetTriggerboxMax(swingrange, vPlayerFuture), pLocalFuture) then
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
    if vPlayerOriginvector == nil then return end
    if vPlayerFuture == nil and pLocalFuture == nil then return end

    local pLocal = entities.GetLocalPlayer()
    if debug and debug:GetValue() == true then
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
            if vertices[4] and vertices[8] then draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2]) end

            end


            --text

            --str2 = string.format("%.2f", vPla)
            --draw.TextShadow(screenPos[1], screenPos[2], str2)
           

            --[[ czapka
            -- ustawienie rozdzielczości koła
            local resolution = 36

            -- promień koła
            local radius = 50

            -- wektor środka koła
            local center = pLocalOrigin

            -- wektor wysokości ostrosłupa
            local height = Vector3(0, 0, 20)

            -- inicjalizacja tablicy wierzchołków koła
            local vertices = {}

            -- wyznaczanie pozycji wierzchołków koła
            for i = 1, resolution do
                local angle = (2 * math.pi / resolution) * (i - 1)
                local x = radius * math.cos(angle)
                local y = radius * math.sin(angle)
                vertices[i] = Vector3(center.x + x, center.y + y)
            end

            -- rysowanie linii z wierzchołków koła do punktu v2
            for i = 1, resolution do
                draw.line(vertices[i], height + vertices[i])
            end

            -- rysowanie linii łączących kolejne wierzchołki koła
            for i = 1, resolution do
                draw.line(vertices[i], vertices[(i % resolution) + 1])
            end

            -- rysowanie linii łączącej ostatni wierzchołek z pierwszym
            draw.line(vertices[resolution], vertices[1])
            ]]
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