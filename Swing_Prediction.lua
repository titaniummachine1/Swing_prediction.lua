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

local debug = menu:AddComponent(MenuLib.Checkbox("indicator", false))
local Swingpred = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local mtimeahead   = menu:AddComponent(MenuLib.Slider("distance ahead",    150, 300, 250))

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


local function GetClosingSpeed(mDistance, mPastdistance)
    if (mDistance or mPastdistance) ~= nil then
    local speedPerTick = mDistance - (mPastdistance or 0)
    local closingSpeed = -(speedPerTick * tickRate / 1000) -- closing speed in units/ms
    return (closingSpeed or 0) -- difference in distance between current and previous tick
    end
end

function GetClosestPlayer(pLocal, players, maxDistance, swingrange)
    local closestPlayer = nil
    local closestDistance = maxDistance
    local pLocalOrigin = GetPlayerOrigin(pLocal, GetAdjustedHeight(pLocal))
    local hitbox_height = Vector3(0, 0, 85)
    local enemy = (vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber())

    for _, vPlayer in ipairs(players) do
        if vPlayer == nil then
            goto continue
        end
        -- Only check distance for alive enemies on the other team within maxDistance
        if enemy and vPlayer:IsAlive() then
            local vPlayerOrigin = GetPlayerOrigin(vPlayer, GetAdjustedHeight(vPlayer))
            local distVector = vPlayerOrigin - pLocalOrigin
            local distance = distVector:Length() - swingrange

            if distance < closestDistance and distance <= maxDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end

        ::continue::
    end

    if closestPlayer ~= nil then
        return {
            origin = GetPlayerOrigin(closestPlayer, GetAdjustedHeight(closestPlayer)),
            topOrigin = GetPlayerOrigin(closestPlayer, Vhitbox_Height),
        }
    end

    return nil
end


--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd, gameData)
    gameData = GameData()  -- Update gameData with latest information

    local pLocal, pWeapon = gameData.pLocal, gameData.pWeapon
    -- Use pLocal, pWeapon, pWeaponDefIndex, etc. as needed

    if not pLocal then return end                    -- Immediately check if the local player exists. If it doesn't, return.


       
        --if vPlayer:GetTeamNumber() == pLocal:GetTeamNumber() then goto continue end  -- If we are on the same team as the player we are iterating through, skip the rest of this code



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
            pLocalOrigin = pLocal:GetAbsOrigin() + Vheight
        
        if PlayerClass == nil then goto continue end

        if PlayerClass == 8 then
            return
        end

        --test1
        
if not Swingpred:GetValue() then goto continue end
    for _, vPlayer in ipairs(players) do
        if vPlayer == nil then goto continue end            -- Code below this line doesn't work if you're the only player in the game.
        if not Swingpred:GetValue() then goto continue end
        local enemy = (vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber())
            -- Only check distance for alive enemies on the other team within maxDistance
        if enemy and vPlayer:IsAlive() then

                if vPlayer ~= nil then
                vPlayerOrigin = (vPlayer:GetAbsOrigin() + Vheight)
                else
                    local vPlayer = Vector3( 0, 0, 0 )
                end



                distVector = vPlayerOrigin - pLocalOrigin
                local distance = distVector:Length() - swingrange
                if distance < closestDistance and distance <= maxDistance then
                    closestPlayer = vPlayer
                    closestDistance = distance
                end
                if closestPlayer ~= nil then
                vPlayerOriginvector = closestPlayer:GetAbsOrigin() + Vheight
                vPlayerOriginvectortop = closestPlayer:GetAbsOrigin() + hitbox_height
                end
            end
        end

            distance = closestDistance

                if distVector ~= nil and vPlayerOriginvector ~= nil then
                    distance = distVector:Length() - swingrange
                end
            

    -- Check if there is a valid closest player
    if closestPlayer ~= nil then



        --local hostile = (closestPlayer:GetTeamNumber() == pLocal:GetTeamNumber())
            -- Check if there are enemies in range and predicted hit time is valid

            local isMelee = pWeapon:IsMeleeWeapon() -- check if using melee weapon
            -- turn input milisecodn value to code
            local timeAhead = mtimeahead:GetValue() -- check timeahead set in menu

            --[[-----------------------------Swing Prediction--------------------------------]]

            --calculating eyelevel closing speed
                local mDistance = distance
                local mPastdistance = previousDistance
                closingSpeed = GetClosingSpeed(mDistance, mPastdistance)
            -- calculating toplevel closing speed towards our eyes
                local mDistance = distancetop
                local mPastdistance = previousDistancetop
                closingSpeedtop = GetClosingSpeed(mDistance, mPastdistance)
                --print(closingSpeed)
            
            -- Check if enemy is within swing range or melee range
            local withinMeleeRange = distance <= 1200
            --[[ Check if relative speed is greater than 2000 units/ms
            if math.abs(closingSpeed) > 3000 then
                closingSpeed = 0
            end]]
            if distance < 0 then
                distance = 0
            end

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
            estHitTime = 0
            if closestDistance > 0 and distance < 600 then
                estHitTime = distance / closingSpeed
            end

            previousDistance = distance    -- Update previous distance and estimated hit time
            prewiousDistancetop = distancetop

                        -- Calculate estimated hit time in milliseconds
            -- Check if estimated hit time is within range, enemy is not on the same team, and within melee distance
            if withinMeleeRange then
                --debugging
                if isMelee and not stop and estHitTime > 0 and estHitTime < 10000 then
                    estHitTime1 = estHitTime
                end
                -- Set attack button if the estimated hit time is within the time ahead limit
                if isMelee and not stop and estHitTime > 0 and estHitTime <= timeAhead then
                    estHitTime1 = estHitTime
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                    --print("Estimated hit time:", estHitTime, "ms")
                    
                end
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

        draw.SetFont( myfont )
        draw.Color( 255, 255, 255, 255 )
        local estHitTime2 = estHitTime1
        if debug:GetValue() == true then
            --if pLocal ~= nil then
            if estHitTime2 ~= nil and distance ~= nil then
                str1 = string.format("%.2f", estHitTime2)
                str2 = string.format("%.2f", distance)
            end
     
                        local screenPos = client.WorldToScreen(vPlayerOriginvector)
                        if screenPos ~= nil then
                            draw.Text( screenPos[1], screenPos[2], "⎯⎯⎯⎯⎯")
                        end

                local w, h = draw.GetScreenSize()
                local screenPos = { w / 2 - 15, h / 2 + 20}
                draw.TextShadow(screenPos[1], screenPos[2], str1)
                local screenPos = { w / 2 - 15, h / 2 + 35}
                draw.TextShadow(screenPos[1], screenPos[2], str2)
            end
        end
    --end

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