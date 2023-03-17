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
end, ItemFlags.FullWidth))
]]

local Swingpred = menu:AddComponent(MenuLib.Checkbox("Enable", true))
local mswingdist   = menu:AddComponent(MenuLib.Slider("Miliseconds ahead",    10, 1000, 250))
-- local mUberWarning  = menu:AddComponent(MenuLib.Checkbox("Uber Warning", false)) -- Medic Uber Warning (currently no way to check)
-- local mRageSpecKill = menu:AddComponent(MenuLib.Checkbox("Rage Spectator Killbind", false)) -- fuck you "pizza pasta", stop spectating me
--local mRemovals     = menu:AddComponent(MenuLib.MultiCombo("Removals", Removals, ItemFlags.FullWidth)) -- Remove RTD and HUD Texts

local myfont = draw.CreateFont("Verdana", 16, 800)

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
    local is_melee                  = pWeapon:IsMeleeWeapon()
    local cond_Melee

    --local primaryWeapon = pLocal:GetEntityForLoadoutSlot( LOADOUT_POSITION_PRIMARY )
    --local secondaryWeapon = pLocal:GetEntityForLoadoutSlot( LOADOUT_POSITION_SECONDARY )
    --local meleeWeapon = pLocal:GetEntityForLoadoutSlot( LOADOUT_POSITION_MELEE )
   --local Localclass = pLocal:GetTeamNumber()
    --local touching = 69
    --swingrange = 69
    local swingrange = pWeapon:GetSwingRange()

    --local shouldmelee = true
    --local safe = true
    --local incombat = false
    --local safemode = true
    


if sneakyboy then return end

-- Initialize closest distance and closest player
if Swingpred:GetValue() then
    local closestPlayer = nil
    local closestDistance = 99999
    
    -- Find the closest player
    for _, vPlayer in ipairs(players) do
        -- Only check distance for alive enemies on the other team
        if vPlayer:IsAlive() and vPlayer:GetTeamNumber() ~= pLocal:GetTeamNumber() then
            local distVector = vPlayer:GetAbsOrigin() - pLocal:GetAbsOrigin()    -- Set "distVector" to the distance between us and the player we are iterating through
            local distance = distVector:Length() - swingrange -- Subtract swingrange to get distance to hit the target
            
            -- Update closest player and closest distance
            if distance < closestDistance then
                closestPlayer = vPlayer
                closestDistance = distance
            end
        end
    end
    
    -- Check if there is a valid closest player
    if closestPlayer ~= nil then
        -- Calculate estimated hit time based on the closest player's distance
        local distance = closestDistance
        local hostle = (closestPlayer:GetTeamNumber() == pLocal:GetTeamNumber())
        
        -- Check if there are enemies in range and predicted hit time is valid
        if not hostle and distance < 500 then
            -- Swing Prediction
            
            -- Calculate closing speed in units/ms
            local tickRate = 66
            local speedPerTick = distance - (previousDistance or 0)
            local closingSpeed = speedPerTick * tickRate / 1000
            local relativeSpeed = -closingSpeed
            local PlayerClass = LocalPlayer:GetPropInt("m_iClass")
                        -- Convert time ahead from seconds to milliseconds
            local timeahead = mswingdist:GetValue()
            local swingdist = distance <= swingrange
            local meleedist = distance <= 350

            -- Check if relative speed is greater than 2000 units/ms
            if math.abs(relativeSpeed) > 2 then
                relativeSpeed = 0
            end

            local charge = false
            if PlayerClass == 4 and (pLocal:InCond(17)) then
                charge = true                                        -- If we are charging (17 is TF_COND_SHIELD_CHARGE)
                if distance < 30 then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                end
            end
            -- Calculate estimated hit time in milliseconds
            local estime = 0
            if relativeSpeed ~= 0 then
                estime = distance / relativeSpeed
            end

            estime = estime - swingrange -- Subtract swingrange to get the estimated hit time when within range

            if estime == estimelast then
                estime = 0
            end

            -- Set estimated hit time to 0 if negative
            if estime < 0 then
                estime = 0
            end

            

            

            
            estimedraw = estime
            -- Check if estimated hit time is within range, enemy is not on the same team, and within melee distance
            if meleedist then
                -- Set attack button if the estimated hit time is within the time ahead limit
                if charge == false and estime > 0 and estime <= timeahead and is_melee then
                    pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                    print("Estimated hit time:", estime, "ms")
                    estimedraw = estime
                end
            end
            
            -- Update previous distance and estimated hit time
            previousDistance = distance
            estimelast = estime
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

        if (mfTimer > 12 * 66) then                                                                                                            -- Remove the cross after 12 seconds (isn't this fps-based? on 144hz monitors, 66 = 5.5 seconds. In that case, this may show longer than it should for others)
            mfTimer = 0
        end

        local players = entities.FindByClass("CTFPlayer")
        local pLocal = entities.GetLocalPlayer()
        
        if pLocal ~= nil then
            local w, h = draw.GetScreenSize()
            local screenPos = { w / 2 + 10, h / 2 }
        
            if estimedraw ~= nil and estimedraw ~= 0 then
                str1 = string.format("%.2f", estimedraw)
            else
                str1 = "0" -- or whatever message you want to display if relativeSpeed is zero or nil
            end
        
            draw.SetFont(myfont)
            draw.Color(255, 255, 255, 255)
            draw.TextShadow(screenPos[1], screenPos[2], str1)
        
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
