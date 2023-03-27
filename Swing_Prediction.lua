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

tickRate = 66 -- game tick rate
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
local mtime         = menu:AddComponent(MenuLib.Slider("movement ahead", 100 ,175 , 150 ))

function GameData()
    local data = {}

    -- Get local player data
    data.pLocal = entities.GetLocalPlayer()     -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
    data.pWeapon = data.pLocal:GetPropEntity("m_hActiveWeapon")
    -- Get player data for all players in the game

    -- Check if local player is invisible
    data.sneakyboy = (data.pLocal:InCond(4) or data.pLocal:InCond(2) or data.pLocal:InCond(13) or data.pLocal:InCond(9))

    return data
end

function PositionPrediction(closestPlayer, Vheight, vPlayerOriginLast, pLocalOriginLast, tickRate, time)
    if vPlayerOriginLast == nil then
        vPlayerOriginLast = Vector3(0, 0, 0)
        pLocalOriginLast = Vector3(0, 0, 0)
    end
    local vPlayerSpeed = vPlayerOrigin - vPlayerOriginLast
    local pLocalSpeed = pLocalOrigin - pLocalOriginLast
    -- Accessing x, y, z components of the vectors
    local vPlayerSpeedX, vPlayerSpeedY, vPlayerSpeedZ = vPlayerSpeed.x, vPlayerSpeed.y, vPlayerSpeed.z
    local pLocalSpeedX, pLocalSpeedY, pLocalSpeedZ = pLocalSpeed.x, pLocalSpeed.y, pLocalSpeed.z
    
    -- Calculating the length of each component
    local vPlayerSpeedLengthX = math.abs(vPlayerSpeedX)
    local vPlayerSpeedLengthY = math.abs(vPlayerSpeedY)
    local vPlayerSpeedLengthZ = math.abs(vPlayerSpeedZ)
    
    local pLocalSpeedLengthX = math.abs(pLocalSpeedX)
    local pLocalSpeedLengthY = math.abs(pLocalSpeedY)
    local pLocalSpeedLengthZ = math.abs(pLocalSpeedZ)

    -- Separate components of pLocalSpeed and vPlayerSpeed
    local pLocalSpeedX, pLocalSpeedY, pLocalSpeedZ = pLocalSpeed:Unpack()
    local vPlayerSpeedX, vPlayerSpeedY, vPlayerSpeedZ = vPlayerSpeed:Unpack()
    -- Create vectors from components
    pLocalSpeedVec = Vector3(pLocalSpeedX * tickRate * time, pLocalSpeedY * tickRate * time, pLocalSpeedZ * tickRate * time)
    vPlayerSpeedVec = Vector3(vPlayerSpeedX * tickRate * time, vPlayerSpeedY * tickRate * time, vPlayerSpeedZ * tickRate * time)

    pLocalFuture = pLocalOrigin + pLocalSpeedVec
    vPlayerFuture = vPlayerOrigin + vPlayerSpeedVec
    
    return vPlayerOriginvector, pLocalFuture, vPlayerFuture
end

function isWithinHitbox(hitbox_min_trigger, hitbox_max_trigger, pLocalFuture)
    if pLocalFuture == nil or hitbox_min_trigger == nil or hitbox_max_trigger == nil then
        return false
    end
    if pLocalFuture.x < hitbox_min_trigger.x or pLocalFuture.x > hitbox_max_trigger.x then
        return false
    end
    if pLocalFuture.y < hitbox_min_trigger.y or pLocalFuture.y > hitbox_max_trigger.y then
        return false
    end
    if pLocalFuture.z < hitbox_min_trigger.z or pLocalFuture.z > hitbox_max_trigger.z then
        return false
    end
    return true
end


function SmoothVector(vector, factor)
    local smoothedX = math.floor(vector.x) + (vector.x - math.floor(vector.x)) * factor
    local smoothedY = math.floor(vector.y) + (vector.y - math.floor(vector.y)) * factor
    local smoothedZ = math.floor(vector.z) + (vector.z - math.floor(vector.z)) * factor
    return Vector3(smoothedX, smoothedY, smoothedZ)
end


--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd, gameData)
    local time = mtime:GetValue() * 0.001
    gameData = GameData()  -- Update gameData with latest information
    local pLocal, pWeapon = gameData.pLocal, gameData.pWeapon
    -- Use pLocal, pWeapon, pWeaponDefIndex, etc. as needed

    if not pLocal then return end                    -- Immediately check if the local player exists. If it doesn't, return.

    local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game
    local pLocal = entities.GetLocalPlayer()
   -- local added_per_shot, bucket_current, crit_fired
    if pWeapon:GetSwingRange() ~= nil then
        swingrange = pWeapon:GetSwingRange()-- + 11.17
    else
        swingrange = 0
    end

    if sneakyboy then return end

-- Initialize closest distance and closest player
    if not Swingpred:GetValue() then goto continue end

        local PlayerClass = pLocal:GetPropInt("m_iClass")
        closestPlayer = vPlayer
        closestDistance = 1200
        Vhitbox_Height = 85
        vhitbox_width = 20

  
        local maxDistance = 1000
    --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
            local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
            local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
            viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()
          -- eye level 
          local Vheight = Vector3( 0, 0, viewheight )

          pLocalOrigin = (pLocal:GetAbsOrigin() + Vheight)

            if PlayerClass == nil then goto continue end

        if PlayerClass == 8 then
            return
        end
    if not Swingpred:GetValue() then goto continue end
    for _, vPlayer in ipairs(players) do
        if vPlayer == nil then goto continue end
        local enemy = (vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber())
        if enemy and vPlayer:IsAlive() then
            vPlayerOrigin = vPlayer:GetAbsOrigin()
            local distVector = vPlayerOrigin - pLocalOrigin
            local distance = distVector:Length()
            if distance < closestDistance and distance <= maxDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end
    end

if closestPlayer ~= nil then

    vPlayerOriginvector = vPlayerOrigin
        -- set surroundinghitbox boundaries.
        local hitbox_surrounding_box = closestPlayer:EntitySpaceHitboxSurroundingBox(0)
            local hitbox_height = Vector3( 0, 0, Vhitbox_Height )
            local hitbox_width = Vector3( 0,  vhitbox_width, 0 )
            local hitbox_min = hitbox_surrounding_box[1]
            local hitbox_max = hitbox_surrounding_box[2]
        -- set triggerbox boundariess
            vhitbox_Height_trigger = (85 + swingrange)
            vhitbox_Height_trigger_bottom = (swingrange)
            vhitbox_width_trigger = (14 + swingrange)

            hitbox_height_trigger = Vector3( 0, 0, vhitbox_Height_trigger )
            hitbox_width_trigger = Vector3( 0,  vhitbox_width_trigger, 0 )
            hitbox_min_trigger = (vPlayerFuture + hitbox_surrounding_box[1] + Vector3( -vhitbox_width_trigger,  -vhitbox_width_trigger, -vhitbox_Height_trigger_bottom ))
            hitbox_max_trigger = (vPlayerFuture + hitbox_surrounding_box[2] + Vector3( vhitbox_width_trigger,  vhitbox_width_trigger, vhitbox_Height_trigger))
        
--[[position prediction]]--
vPlayerOrigin = closestPlayer:GetAbsOrigin()

        PositionPrediction(closestPlayer, Vheight, vPlayerOriginLast, pLocalOriginLast, tickRate, time)
        pLocalFuture = pLocalOrigin + pLocalSpeedVec
        vPlayerFuture = vPlayerOrigin + vPlayerSpeedVec
    
--[[position prediction]]--

        -- Calculate distance between future positions (temporary)
        distance = (pLocalOrigin - vPlayerOrigin):Length()
    end

    -- Check if there is a valid closest player
    if closestPlayer == nil then return end
    --save for next it



            --[[-----------------------------Swing Prediction--------------------------------]]
            local isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon
            -- Check if enemy is within swing range or melee range
            local withinMeleeRange = distance <= 1000

            -- Try predicting demoman shield charge.
            local stop = false
            if (pLocal:InCond(17)) and PlayerClass == 4 or PlayerClass == 8 then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
                stop = true
                dynamicstop = 30
                if (pCmd.forwardmove == 0) then dynamicstop = 30 end -- case if you dont hold w when charging
                if closestDistance <= dynamicstop and PlayerClass == 4 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end
            end
                -- Set attack button if the estimated hit time is within the time ahead limit
                if withinMeleeRange and isMelee and not stop and isWithinHitbox(hitbox_min_trigger, hitbox_max_trigger, pLocalFuture) or distance < swingrange then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end

-- Update last variables
            previousDistance = distance
            prewiousDistancetop = distancetop
            vPlayerOriginLast = vPlayerOrigin
            pLocalOriginLast = pLocalOrigin
        ::continue::
    end
    
-- ent_fire !picker Addoutput "health 99"
local myfont = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
--[[ Code called every frame ]]--
local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end

    local pLocal = entities.GetLocalPlayer()
    if debug:GetValue() == true then
        draw.SetFont( myfont )
        draw.Color( 255, 255, 255, 255 )
        local w, h = draw.GetScreenSize()
        local screenPos = { w / 2 - 15, h / 2 + 35}
        
        local screenPos = client.WorldToScreen(vPlayerOriginvector)
        if screenPos ~= nil then
            draw.Line( screenPos[1], screenPos[2] + 20, screenPos[1], screenPos[2] - 20)
        end
        if vPlayerFuture ~= nil and pLocalFuture ~= nil then
            local screenPos = client.WorldToScreen(pLocalFuture)
            if screenPos ~= nil then
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
            end
            local screenPos = client.WorldToScreen(vPlayerFuture)
            if screenPos ~= nil then
                local screenPos1 = client.WorldToScreen(vPlayerOriginvector)
                if screenPos1 ~= nil then
                    draw.Line( screenPos1[1], screenPos1[2], screenPos[1], screenPos[2])
                end
            end
            -- Draw box around trigger hitbox        
            if vPlayerFuture ~= nil then
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
                draw.Line(vertices[1][1], vertices[1][2], vertices[5][1], vertices[5][2])
                draw.Line(vertices[2][1], vertices[2][2], vertices[6][1], vertices[6][2])
                draw.Line(vertices[3][1], vertices[3][2], vertices[7][1], vertices[7][2])
                draw.Line(vertices[4][1], vertices[4][2], vertices[8][1], vertices[8][2])
            end
            -- text

            str2 = string.format("%.2f", distance)
            draw.TextShadow(screenPos[1], screenPos[2], str2)
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