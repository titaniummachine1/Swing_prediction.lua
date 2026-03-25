--[[ Imported by: Main ]]

local Simulation = require("Simulation")
local Combat = {}

function Combat.TroldierAssist(pCmd, pLocal, menuSettings)
    if not menuSettings.TroldierAssist then return end
    
    local class = pLocal:GetPropInt("m_iClass")
    if class ~= 3 then return end -- TF_CLASS_SOLDIER

    local primaryWeapon = pLocal:GetEntityForLoadoutSlot(0) -- LOADOUT_POSITION_PRIMARY
    if not primaryWeapon or not primaryWeapon:IsValid() then
        menuSettings.TroldierAssist = false
        return
    end

    local meleeWeapon = pLocal:GetEntityForLoadoutSlot(2) -- LOADOUT_POSITION_MELEE
    local holdsMarketGardener = false
    if meleeWeapon and meleeWeapon:IsValid() then
        local itemIndex = meleeWeapon:GetPropInt("m_AttributeManager", "m_Item", "m_iItemDefinitionIndex")
        if itemIndex == 416 then
            holdsMarketGardener = true
        end
    end
    
    if not holdsMarketGardener then return end

    local activeWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    local flags = pLocal:GetPropInt("m_fFlags")
    local airborne = pLocal:InCond(81) -- Parasol/Airborne/BlastJumping cond

    if airborne then
        pCmd:SetButtons(pCmd:GetButtons() | IN_DUCK)
        if activeWeapon and activeWeapon:IsValid() and activeWeapon:GetIndex() ~= meleeWeapon:GetIndex() then
            client.Command("slot3", true) -- Melee
            return
        end

        -- Landing prediction for Market Gardener
        local weaponData = meleeWeapon:GetWeaponData()
        local smackDelay = weaponData and weaponData.smackDelay or (13 * globals.TickInterval())
        local S = math.floor(smackDelay / globals.TickInterval()) + 1
        
        -- Lightweight prediction (only swing duration + 1)
        local localPred = Simulation.PredictPlayer(
            pLocal, S, 0, 0, nil, 
            { gravity = client.GetConVar("sv_gravity") },
            Simulation.BufLocal)
            
        if localPred and localPred.onGround[S] and not localPred.onGround[S-1] then
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
        end
    else
        if activeWeapon and activeWeapon:IsValid() and activeWeapon:GetIndex() ~= primaryWeapon:GetIndex() then
            client.Command("slot1", true) -- Primary
        end
    end
end

function Combat.HandleWarp(pCmd, pLocal, pWeapon, weaponSmackDelay, menuSettings)
    if not (menuSettings.InstantAttack and warp.CanWarp()) then return false end

    local chargedTicks = warp.GetChargedTicks() or 0
    local neededTicks = math.min(weaponSmackDelay or 13, 20)

    if chargedTicks >= neededTicks then
        pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)

        if menuSettings.WarpOnAttack then
            -- Set ConVar for more processed ticks
            client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
            client.SetConVar("sv_maxusrcmdprocessticks", neededTicks)
            
            warp.TriggerWarp()
            return true
        end
    end

    return false
end

return Combat
