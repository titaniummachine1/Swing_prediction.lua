--[[ Imported by: Main ]]

local Combat = {}

function Combat.TroldierAssist(pCmd, pLocal, menuSettings)
    if not menuSettings.TroldierAssist then return end
    
    local flags = pLocal:GetPropInt("m_fFlags")
    local onGround = (flags & FL_ONGROUND) ~= 0
    local airborne = pLocal:InCond(81) -- Parasol/Airborne cond

    if airborne then
        pCmd:SetButtons(pCmd:GetButtons() | IN_DUCK)
    end

    -- Slot switching logic
    if airborne then
        client.Command("slot3", true) -- Melee
    else
        client.Command("slot1", true) -- Primary
    end
end

function Combat.HandleWarp(pCmd, pWeapon, weaponSmackDelay, menuSettings)
    if not menuSettings.InstantAttack then return end
    if not warp.CanWarp() then return end

    local chargedTicks = warp.GetChargedTicks() or 0
    local neededTicks = math.min(weaponSmackDelay or 13, 20)

    if chargedTicks >= neededTicks then
        if menuSettings.WarpOnAttack then
            warp.TriggerWarp()
        end
        return true
    end

    return false
end

return Combat
