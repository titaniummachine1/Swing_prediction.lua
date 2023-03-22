--[[                                ]]--
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


--[[ Varibles used for looping ]]--
local LastExtenFreeze = 0  -- Spectator Mode
local prTimer = 0          -- Timer for Random Ping
local flTimer = 0          -- Timer for Fake Latency
local c2Timer = 0          -- Timer for Battle CryoWeaponmAutoweapon raytracing
local c2Timer2 = 0         -- Timer for ^ to prevent spamming
local mfTimer = 0          -- Timer for Medic Finder
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

local debug = menu:AddComponent(MenuLib.Checkbox("indicator", true))
local Swingpred = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local mtimeahead   = menu:AddComponent(MenuLib.Slider("distance ahead",    0, 300, 250))

-- local mUberWarning  = menu:AddComponent(MenuLib.Checkbox("Uber Warning", false)) -- Medic Uber Warning (currently no way to check)
-- local mRageSpecKill = menu:AddComponent(MenuLib.Checkbox("Rage Spectator Killbind", false)) -- fuck you "pizza pasta", stop spectating me
--local mRemovals     = menu:AddComponent(MenuLib.MultiCombo("Removals", Removals, ItemFlags.FullWidth)) -- Remove RTD and HUD Texts

function GameData()
    local data = {}

    -- Get local player data
    data.pLocal = entities.GetLocalPlayer()     -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
    data.pWeapon = data.pLocal:GetPropEntity("m_hActiveWeapon")
    data.pWeaponDefIndex = data.pWeapon:GetPropInt("m_iItemDefinitionIndex")
    data.pWeaponDef = itemschema.GetItemDefinitionByID(data.pWeaponDefIndex)
    data.pWeaponName = data.pWeaponDef:GetName()
    data.pUsingProjectileWeapon = (data.pWeaponName == "CTFRocketLauncher" or data.pWeaponName == "CTFCannon")
    -- Get player data for all players in the game

    -- Check if local player is invisible
    data.sneakyboy = (data.pLocal:InCond(4) or data.pLocal:InCond(2) or data.pLocal:InCond(13) or data.pLocal:InCond(9))

    return data
end


local function GetClosingSpeed(mDistance, mPastdistance)
    local speedPerTick = mDistance - (mPastdistance or 0)
    local closingSpeed = -(speedPerTick * tickRate / 1000) -- closing speed in units/ms
    return (closingSpeed or 0) -- difference in distance between current and previous tick
end



--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd, gameData)
    gameData = GameData()  -- Update gameData with latest information

    local pLocal, pWeapon, pWeaponDefIndex = gameData.pLocal, gameData.pWeapon, gameData.pWeaponDefIndex
    -- Use pLocal, pWeapon, pWeaponDefIndex, etc. as needed

    if not pLocal then return end                    -- Immediately check if the local player exists. If it doesn't, return.


       
        --if vPlayer:GetTeamNumber() == pLocal:GetTeamNumber() then goto continue end  -- If we are on the same team as the player we are iterating through, skip the rest of this code



    local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game
    local LocalPlayer = entities.GetLocalPlayer()
   -- local added_per_shot, bucket_current, crit_fired
    
    local vPlayerhitbox = 0

    local swingrange = pWeapon:GetSwingRange()
    if swingrange ~= nil then
        swingrange = swingrange + vPlayerhitbox
    end

    if swingrange == nil then
        swingrange = 0
    end

if sneakyboy then return end

-- Initialize closest distance and closest player
if Swingpred:GetValue() then
        local PlayerClass = LocalPlayer:GetPropInt("m_iClass")
        local closestPlayer = nil
        closestDistance = 1000
        Vhitbox_Height = 85
        local maxDistance = 700

    --get pLocal eye level and set vector at our eye level to ensure we cehck distance from eyes
            local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
            local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
            viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()

        -- set heightvector to later add to obsorigin.
            local hitbox_height = Vector3( 0, 0, Vhitbox_Height )
            local Vheight = Vector3( 0, 0, viewheight )


        if PlayerClass == 8 then
            return
        end
    
    for _, vPlayer in ipairs(players) do
        local enemy = (vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber())
        -- Only check distance for alive enemies on the other team within maxDistance
        if enemy then

            if vPlayer:GetIndex() == pLocal:GetIndex() then goto continue end            -- Code below this line doesn't work if you're the only player in the game.
            if pLocal:IsAlive() == false then goto continue end                          -- If we are not alive, skip the rest of this code
    
            if vPlayer:IsValid() then
                local vWeapon = vPlayer:GetPropEntity("m_hActiveWeapon")
                if vWeapon ~= nil then
                    local vWeaponDefIndex = vWeapon:GetPropInt("m_iItemDefinitionIndex")
                    --local vWeaponDef = itemschema.GetItemDefinitionByID(vWeaponDefIndex)
                    --local vWeaponName = vWeaponDef:GetName()
                end
            end

            pLocalOrigin = pLocal:GetAbsOrigin() + Vheight
            vPlayerOrigin = vPlayer:GetAbsOrigin()
            
            local distVector = vPlayerOrigin - pLocalOrigin
            distancefeet = distVector:Length() - swingrange

            vPlayerOrigin = vPlayerOrigin + Vheight
            
            local distVector = vPlayerOrigin - pLocalOrigin
            distance = distVector:Length() - swingrange

            

            --distancetop = distVector:Length() - swingrange

            -- Update closest player and closest distance
            if distance < closestDistance and distance <= maxDistance and  vPlayer:IsAlive() == true then
                closestPlayer = vPlayer
                closestDistance = distance
            end
            distance = closestDistance

            -- Trace towards enemy hitbox
            local trace = engine.TraceLine(pLocalOrigin, vPlayerOrigin, MASK_SHOT_HULL)

            -- Check if hitbox was hit
            if trace == vPlayer then
                -- Get closest point on hitbox
                local closestPoint = trace.entity:GetHitboxPosition(0)
                local hitboxdistance = closestPoint - pLocalOrigin
                local hitboxdistance = hitboxdistance:Length()
                print("Distance to enemy hitbox: " .. hitboxdistance)
            end
            
            if hitboxdistance ~= nil then
                print(hitboxdistance)
            end
        end
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

            -- calculating feetlevel closing speed towards our eyes
                local mDistance = distancefeet
                local mPastdistance = previousDistancefeet
                closingSpeedfeet = GetClosingSpeed(mDistance, mPastdistance)
            
                --print(closingSpeed)
            
            -- Check if enemy is within swing range or melee range
            local withinMeleeRange = distance <= 500
            
            --[[ Check if relative speed is greater than 2000 units/ms
            if math.abs(closingSpeed) > 3000 then
                closingSpeed = 0
            end]]
            
            -- Calculate estimated hit time in milliseconds
            estHitTime = 0

            -- Try predicting demoman shield charge.
            local stop = false
            if (pLocal:InCond(17)) and PlayerClass == 4 or PlayerClass == 8 then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
                stop = true
                dynamicstop = 45
                if (pCmd.forwardmove == 0) then dynamicstop = 30 end -- case if you dont hold w when charging
                if closestDistance <= dynamicstop and PlayerClass == 4 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end
            end

            if closingSpeed ~= 0.00 and closingspeed ~= nil then
                estHitTime = distance / closingSpeed
            elseif closingSpeed ~= nil and closingSpeedfeet ~= 0.00 and distance > distancefeet then
                estHitTime = distancefeet / closingSpeedfeet
            end
            
            -- If estimated hit time has not changed since last tick, set it to 0
            if estHitTime == estHitTimeLast or stop then
                estHitTime = 0
            end

            -- Update previous distance and estimated hit time
            previousDistance = distance
            prewiousDistancefeet = distancefeet
            -- Check if estimated hit time is within range, enemy is not on the same team, and within melee distance
            if withinMeleeRange then
                -- Set attack button if the estimated hit time is within the time ahead limit
                if isMelee and not stop and estHitTime > 0 and estHitTime <= timeAhead then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                    --print("Estimated hit time:", estHitTime, "ms")
                    estHitTime1 = estHitTime
                end
            end
        end
        ::continue::
    end
end

-- ent_fire !picker Addoutput "health 99"
local myfont = draw.CreateFont( "Verdana", 16, 800 ) -- Create a font for doDraw
--[[ Code called every frame ]]--
local function doDraw()
    if engine.Con_IsVisible() or engine.IsGameUIVisible() then
        return
    end
    local players = entities.FindByClass("CTFPlayer")
    local vPlayerOriginvector = vPlayerOrigin

        local pLocal = entities.GetLocalPlayer()
        if (mfTimer > 12 * 66) then                                 --[]                                                                           -- Remove the cross after 12 seconds (isn't this fps-based? on 144hz monitors, 66 = 5.5 seconds. In that case, this may show longer than it should for others)
            mfTimer = 0
        end

        if pLocal ~= nil and debug ~= nil then
            if debug:GetValue() == true then

            local screenPos = client.WorldToScreen(vPlayerOriginvector)

                for i, p in ipairs( players ) do
                    if p:IsAlive() and not p:IsDormant() then
                        
                        local screenPos = client.WorldToScreen(vPlayerOrigin)
                        if screenPos ~= nil then
                            draw.SetFont( myfont )
                            draw.Color( 255, 255, 255, 255 )
                            draw.Text( screenPos[1], screenPos[2], string.format("%.2f", estHitTime1))
                        end
                    end
                end

                local w, h = draw.GetScreenSize()
                local screenPos = { w / 2 - 15, h / 2 + 20}
                local str1 = 0
                if estime ~= nil then
                    str1 = string.format("%.2f", estHitTime1)
                end
            
                draw.SetFont(myfont)
                draw.Color(255, 255, 255, 255)
                draw.TextShadow(screenPos[1], screenPos[2], str1)
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
