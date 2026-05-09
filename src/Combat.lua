--[[ Imported by: Main ]]

local Simulation = require("Simulation")
local Combat = {}

local function isBlastJumping(pLocal)
    if not pLocal or not pLocal:IsValid() then
        return false
    end

    if pLocal:InCond(81) then
        return true
    end

    local ok, value = pcall(function()
        return pLocal:GetPropBool("m_Shared", "m_bBlastJumping")
    end)

    return ok and value == true
end

local function hasMarketGardener(pLocal)
    if not pLocal or not pLocal:IsValid() then
        return false
    end

    local meleeWeapon = pLocal:GetEntityForLoadoutSlot(2)
    if not meleeWeapon or not meleeWeapon:IsValid() then
        return false
    end

    local itemIndex = meleeWeapon:GetPropInt("m_AttributeManager", "m_Item", "m_iItemDefinitionIndex")
    return itemIndex == 416
end

function Combat.TroldierAssist(pCmd, pLocal, menuSettings)
    if not menuSettings.TroldierAssist then return false end
    
    local class = pLocal:GetPropInt("m_iClass")
    if class ~= 3 then return false end -- TF_CLASS_SOLDIER

    local primaryWeapon = pLocal:GetEntityForLoadoutSlot(0) -- LOADOUT_POSITION_PRIMARY
    if not primaryWeapon or not primaryWeapon:IsValid() then
        menuSettings.TroldierAssist = false
        return false
    end

    local meleeWeapon = pLocal:GetEntityForLoadoutSlot(2) -- LOADOUT_POSITION_MELEE
    local holdsMarketGardener = false
    if meleeWeapon and meleeWeapon:IsValid() then
        local itemIndex = meleeWeapon:GetPropInt("m_AttributeManager", "m_Item", "m_iItemDefinitionIndex")
        if itemIndex == 416 then
            holdsMarketGardener = true
        end
    end
    
    if not holdsMarketGardener then return false end

    local activeWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    local blastJumping = isBlastJumping(pLocal)

    if blastJumping then
        pCmd:SetButtons(pCmd:GetButtons() | IN_DUCK)
        if activeWeapon and activeWeapon:IsValid() and activeWeapon:GetIndex() ~= meleeWeapon:GetIndex() then
            client.Command("slot3", true) -- Melee
        end
        return true
    else
        if activeWeapon and activeWeapon:IsValid() and activeWeapon:GetIndex() ~= primaryWeapon:GetIndex() then
            client.Command("slot1", true) -- Primary
        end
        return false
    end
end

function Combat.ShouldUseTroldierSwingAssist(pLocal, pWeapon, menuSettings)
    if not menuSettings or not menuSettings.TroldierAssist then
        return false
    end

    if not pLocal or not pLocal:IsValid() or not pWeapon or not pWeapon:IsValid() then
        return false
    end

    if pLocal:GetPropInt("m_iClass") ~= 3 then
        return false
    end

    return pWeapon:IsMeleeWeapon() and hasMarketGardener(pLocal) and isBlastJumping(pLocal)
end

function Combat.ShouldTroldierPreSwing(localPred, swingTicks, isMidSwing, pCmd, menuSettings)
    if not menuSettings or not menuSettings.TroldierAssist then
        return false
    end

    if not localPred or not swingTicks or isMidSwing then
        return false
    end

    if not pCmd or (pCmd:GetButtons() & IN_ATTACK) ~= 0 then
        return false
    end

    return localPred.onGround[swingTicks + 1] == true
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
