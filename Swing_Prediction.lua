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
local mtime          = menu:AddComponent(MenuLib.Slider("movement ahead", 100 ,375 ,350 ))

-- local mUberWarning  = menu:AddComponent(MenuLib.Checkbox("Uber Warning", false)) -- Medic Uber Warning (currently no way to check)
-- local mRageSpecKill = menu:AddComponent(MenuLib.Checkbox("Rage Spectator Killbind", false)) -- fuck you "pizza pasta", stop spectating me
--local mRemovals     = menu:AddComponent(MenuLib.MultiCombo("Removals", Removals, ItemFlags.FullWidth)) -- Remove RTD and HUD Texts

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
        local maxDistance = 1200

    --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
            local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
            local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
            viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()

        -- set heightvector to later add to obsorigin.
            local hitbox_height = Vector3( 0, 0, Vhitbox_Height )
            local Vheight = Vector3( 0, 0, viewheight )
        
        if PlayerClass == nil then goto continue end

        if PlayerClass == 8 then
            return
        end
if not Swingpred:GetValue() then goto continue end
    for _, vPlayer in ipairs(players) do
        if vPlayer == nil then goto continue end
        if not Swingpred:GetValue() then goto continue end
        local enemy = (vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber())
        if enemy and vPlayer:IsAlive() then
            local vPlayerOrigin = (vPlayer:GetAbsOrigin() + Vheight)
            local distVector = vPlayerOrigin - pLocalOrigin
            local distance = distVector:Length()
            if distance < closestDistance and distance <= maxDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end
    end

if closestPlayer ~= nil then

--[[position prediction]]--
        vPlayerOrigin = closestPlayer:GetAbsOrigin() + Vheight
        pLocalOrigin = pLocal:GetAbsOrigin() + Vheight
        vPlayerOriginvector = vPlayerOrigin
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
        local pLocalSpeedVec = Vector3(pLocalSpeedX * tickRate * time, pLocalSpeedY * tickRate * time, pLocalSpeedZ * tickRate * time)
        local vPlayerSpeedVec = Vector3(vPlayerSpeedX * tickRate * time, vPlayerSpeedY * tickRate * time, vPlayerSpeedZ * tickRate * time)

        
        pLocalFuture = pLocalOrigin + pLocalSpeedVec
        vPlayerFuture = vPlayerOrigin + vPlayerSpeedVec
--[[position prediction]]--

        -- Calculate distance between future positions (temporary)
        distance = (pLocalFuture - vPlayerFuture):Length()
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

            previousDistance = distance    -- Update previous distance and estimated hit time
            prewiousDistancetop = distancetop
            vPlayerOriginLast = vPlayerOrigin
            pLocalOriginLast = pLocalOrigin

                        -- Calculate estimated hit time in milliseconds
            -- Check if estimated hit time is within range, enemy is not on the same team, and within melee distance
            if withinMeleeRange then
                -- Set attack button if the estimated hit time is within the time ahead limit
                if isMelee and not stop and distance < swingrange then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                    --print("Estimated hit time:", EstHitTime, "ms")
                end
            end
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
                draw.Line( screenPos[1] + 10, screenPos[2], screenPos[1] - 10, screenPos[2])
                draw.Line( screenPos[1], screenPos[2] - 10, screenPos[1], screenPos[2] + 10)
                local screenPos1 = client.WorldToScreen(vPlayerOriginvector)
                if screenPos1 ~= nil then
                    draw.Line( screenPos1[1], screenPos1[2], screenPos[1], screenPos[2])
                end
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