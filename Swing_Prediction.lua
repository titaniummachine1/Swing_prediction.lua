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

local debug = menu:AddComponent(MenuLib.Checkbox("indicator", false))
local Swingpred = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local mtimeahead   = menu:AddComponent(MenuLib.Slider("distance ahead",    0, 300, 250))

-- local mUberWarning  = menu:AddComponent(MenuLib.Checkbox("Uber Warning", false)) -- Medic Uber Warning (currently no way to check)
-- local mRageSpecKill = menu:AddComponent(MenuLib.Checkbox("Rage Spectator Killbind", false)) -- fuck you "pizza pasta", stop spectating me
--local mRemovals     = menu:AddComponent(MenuLib.MultiCombo("Removals", Removals, ItemFlags.FullWidth)) -- Remove RTD and HUD Texts

--[[ Code needed to run 66 times a second ]]--
local function OnCreateMove(pCmd)                    -- Everything within this function will run 66 times a second
    local pLocal = entities.GetLocalPlayer()         -- Immediately set "pLocal" to the local player (entities.GetLocalPlayer)
    if not pLocal then return end                    -- Immediately check if the local player exists. If it doesn't, return.

    --[[ Features that require access to the weapon ]]--
    if pLocal:IsAlive() == false then return end
        local pWeapon         = pLocal:GetPropEntity( "m_hActiveWeapon" )            -- Set "pWeapon" to the local player's active weapon
        local pWeaponDefIndex = pWeapon:GetPropInt( "m_iItemDefinitionIndex" )       -- Set "pWeaponDefIndex" to the "pWeapon"'s item definition index
        local pWeaponDef      = itemschema.GetItemDefinitionByID( pWeaponDefIndex )  -- Set "pWeaponDef" to the local "pWeapon"'s item definition
        local pWeaponName     = pWeaponDef:GetName()                                 -- Set "pWeaponName" to the local "pWeapon"'s actual name
        if not pWeapon then return end                                               -- If "pWeapon" is not set, break
    if (pWeapon == "CTFRocketLauncher") or (pWeapon == "CTFCannon") then        -- If the local player's active weapon is a projectile weapon (this doesn't work for some reason????)
        pUsingProjectileWeapon  = true                                               -- Set "pUsingProjectileWeapon" to true
    else pUsingProjectileWeapon = false end                                          -- Set "pUsingProjectileWeapon" to false



    --[[ Features that need to iterate through all players ]]
    local players = entities.FindByClass("CTFPlayer")                              -- Create a table of all players in the game
    for k, vPlayer in pairs(players) do                                            -- For each player in the game
        if vPlayer:IsValid() == false then goto continue end                       -- Check if each player is valid
    local vWeapon = vPlayer:GetPropEntity("m_hActiveWeapon")                       -- Set "vWeapon" to the player's active weapon
    if vWeapon ~= nil then                                                         -- If "vWeapon" is not nil
        local vWeaponDefIndex = vWeapon:GetPropInt("m_iItemDefinitionIndex")       -- Set "vWeaponDefIndex" to the "vWeapon"'s item definition index
        --local vWeaponDef      = itemschema.GetItemDefinitionByID(vWeaponDefIndex)  -- Set "vWeaponDef" to the local "vWeapon"'s item definition (doesn't work for some reason)
        --local vWeaponName     = vWeaponDef:GetName()                               -- Set "vWeaponName" to the local "vWeapon"'s actual name (doesn't work for some reason)
    end


    local sneakyboy = false                       -- Create a new variable for if we're invisible or not, set it to false
    if pLocal:InCond(4) or pLocal:InCond(2) 
                        or pLocal:InCond(13) 
                        or pLocal:InCond(9) then  -- If we are in a condition that makes us invisible
        sneakyboy = true                          -- Set "sneakyboy" to true
    end


        if vPlayer:IsAlive() == false then goto continue end
        if vPlayer:GetIndex() == pLocal:GetIndex() then goto continue end            -- Code below this line doesn't work if you're the only player in the game.
        if pLocal:IsAlive() == false then goto continue end                          -- If we are not alive, skip the rest of this code

        --if vPlayer:GetTeamNumber() == pLocal:GetTeamNumber() then goto continue end  -- If we are on the same team as the player we are iterating through, skip the rest of this code



    local players = entities.FindByClass("CTFPlayer")  -- Create a table of all players in the game
    local LocalPlayer = entities.GetLocalPlayer()
   -- local added_per_shot, bucket_current, crit_fired
    
    local vPlayerhitbox = 32

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

    if PlayerClass == 8 then
        return
    end

    local closestPlayer = nil
    closestDistance = 1000
    Vhitbox_Height = 85
    
    
    local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    local adjustedHeight = pLocal:GetAbsOrigin() + viewOffset
    viewheight = (adjustedHeight - pLocal:GetAbsOrigin()):Length()

    local hitbox_height = Vector3( 0, 0, Vhitbox_Height )
    local Vheight = Vector3( 0, 0, viewheight )
    -- Find the closest player
    local maxDistance = 700
    for _, vPlayer in ipairs(players) do
        -- Only check distance for alive enemies on the other team within maxDistance
        if vPlayer:IsAlive() and vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber() then
            





            pLocalOrigin = pLocal:GetAbsOrigin() + Vheight
            vPlayerOrigin = vPlayer:GetAbsOrigin()
            
            local distVector = vPlayerOrigin - pLocalOrigin
            distancefeet = distVector:Length() - swingrange

            vPlayerOrigin = vPlayerOrigin + Vheight
            
            local distVector = vPlayerOrigin - pLocalOrigin
            distance = distVector:Length() - swingrange

            vPlayerOrigin = vPlayer:GetAbsOrigin()
            vPlayerOrigin = vPlayerOrigin + hitbox_height
            distancetop = distVector:Length() - swingrange

            -- Update closest player and closest distance
            if distance < closestDistance and distance <= maxDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end
    end
    

    local stop = false
    if (pLocal:InCond(17)) and PlayerClass == 4 or PlayerClass == 8 then -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
        stop = true
        dynamicstop = 45
        if (pCmd.forwardmove == 0) then dynamicstop = 30 end -- case if you dont hold w when charging
        if closestDistance <= dynamicstop and PlayerClass == 4 then
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
        end
    end
    -- Check if there is a valid closest player
    if closestPlayer ~= nil then
        -- Calculate estimated hit time based on the closest player's distance
        local distance = closestDistance
        --local hostile = (closestPlayer:GetTeamNumber() == pLocal:GetTeamNumber())
        
            -- Check if there are enemies in range and predicted hit time is valid
            
            -- Swing Prediction
            local tickRate = 66 -- game tick rate
            local speedPerTick = distance - (previousDistance or 0) -- difference in distance between current and previous tick
            local speedperTickfeet = distancefeet - (previousDistancefeet or 0)
            
            local closingSpeed = -(speedPerTick * tickRate / 1000) -- closing speed in units/ms
            local closingSpeedfeet = -(speedperTickfeet * tickRate / 1000)
            --print(closingSpeed)
            local isMelee = pWeapon:IsMeleeWeapon()
            -- turn input milisecodn value to code
            local timeAhead = mtimeahead:GetValue()
            
            -- Check if enemy is within swing range or melee range
            local withinMeleeRange = distance <= 500
            
            -- Check if relative speed is greater than 2000 units/ms
            if math.abs(closingSpeed) > 3000 then
                closingSpeed = 0
            end
            
            -- Calculate estimated hit time in milliseconds
            estHitTime = 0
            if closingSpeed ~= 0 then
                estHitTime = distance / closingSpeed
            elseif closingSpeedfeet ~= 0 and distance > distancefeet then
                estHitTime = distancefeet / closingSpeedfeet
            end
            
            -- If estimated hit time has not changed since last tick, set it to 0
            if estHitTime == estHitTimeLast then
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
