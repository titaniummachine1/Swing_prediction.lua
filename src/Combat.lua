--[[ Combat module for Swing prediction ]]
--
--[[ Handles attack and charge logic ]]
--

local lnxLib = require("lnxlib")
local Math = lnxLib.Utils.Math
local MathUtils = require("MathUtils")

local Combat = {}

-- Constants for charge movement
local CHARGE_CONSTANTS = {
    SIDE_MOVE_VALUE = 450, -- A/D key movement speed
    MAX_TURN_RATE = 73.04, -- Maximum turn per frame in degrees
    ACCELERATION = 750, -- Charge acceleration
}

-- Walk to position helper
local function WalkTo(pCmd, pLocal, targetPos)
    if not targetPos then
        return
    end

    local currentPos = pLocal:GetAbsOrigin()
    local direction = (targetPos - currentPos)
    direction.z = 0 -- Keep horizontal movement only

    if direction:Length() > 0 then
        direction = MathUtils.Normalize(direction)
        local angles = direction:Angles()

        -- Set forward movement
        pCmd.forwardmove = 450

        -- Set view angles to face target
        if not Menu.Aimbot.Silent then
            engine.SetViewAngles(EulerAngles(angles.pitch, angles.yaw, 0))
        else
            pCmd:SetViewAngles(angles.pitch, angles.yaw, 0)
        end
    end
end

-- Handle charge bot turning logic
function Combat.HandleChargeBot(pCmd, pLocal, aim_angles, Menu)
    local MAX_CHARGE_BOT_TURN = 17

    if not aim_angles or not aim_angles.pitch or not aim_angles.yaw then
        return
    end

    local currentAngles = engine.GetViewAngles()
    local yawDiff = MathUtils.NormalizeYaw(aim_angles.yaw - currentAngles.yaw)
    local turnAmount = yawDiff

    -- Apply side movement based on turning direction
    if turnAmount > 0 then
        -- Turning left, simulate pressing D (right strafe)
        pCmd.sidemove = CHARGE_CONSTANTS.SIDE_MOVE_VALUE
    else
        -- Turning right, simulate pressing A (left strafe)
        pCmd.sidemove = -CHARGE_CONSTANTS.SIDE_MOVE_VALUE
    end

    -- Limit maximum turn per frame
    turnAmount = MathUtils.Clamp(turnAmount, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)

    -- Calculate new yaw angle
    local newYaw = currentAngles.yaw + turnAmount

    -- Handle -180/180 degree boundary crossing
    newYaw = newYaw % 360
    if newYaw > 180 then
        newYaw = newYaw - 360
    elseif newYaw < -180 then
        newYaw = newYaw + 360
    end

    -- Set the new view angles
    if Menu.Aimbot.Silent then
        pCmd:SetViewAngles(currentAngles.pitch, newYaw, 0)
    else
        engine.SetViewAngles(EulerAngles(currentAngles.pitch, newYaw, 0))
    end
end

-- Handle instant attack with warp
function Combat.HandleInstantAttack(pCmd, pLocal, weaponSmackDelay, Menu)
    if not Menu.Misc.WarpOnAttack then
        pCmd:SetButtons(pCmd:GetButtons() + IN_ATTACK)
        return
    end

    local velocity = pLocal:EstimateAbsVelocity()
    local oppositePoint

    -- Calculate opposite point for movement
    if velocity:Length() > 10 then
        oppositePoint = pLocal:GetAbsOrigin() - velocity
    else
        local angles = engine.GetViewAngles()
        local forward = angles:Forward()
        oppositePoint = pLocal:GetAbsOrigin() + forward * 20
    end

    -- Move to opposite point for better warp positioning
    if oppositePoint and (oppositePoint - pLocal:GetAbsOrigin()):Length() < 300 then
        WalkTo(pCmd, pLocal, oppositePoint)
    end

    -- Set up the attack and warp
    pCmd:SetButtons(pCmd:GetButtons() + IN_ATTACK)

    client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
    local safeTickValue = math.min(weaponSmackDelay, 20)
    client.SetConVar("sv_maxusrcmdprocessticks", safeTickValue)

    -- Trigger the warp
    local chargedTicks = warp.GetChargedTicks() or 0
    if chargedTicks >= safeTickValue then
        warp.TriggerWarp(safeTickValue)
        client.ChatPrintf("[Debug] Instant Attack: Warping with " .. chargedTicks .. " ticks")
    else
        client.ChatPrintf(
            "[Debug] Instant Attack: Not enough ticks (" .. chargedTicks .. "/" .. safeTickValue .. "), normal attack"
        )
    end
end

-- Handle charge jump exploit
function Combat.HandleChargeJump(pCmd, pLocal, targetPos, Menu)
    if not Menu.Charge.ChargeJump then
        return
    end

    -- Calculate jump trajectory
    local currentPos = pLocal:GetAbsOrigin()
    local direction = (targetPos - currentPos)
    direction.z = 0 -- Keep horizontal for now

    local distance = direction:Length()
    if distance > 0 then
        direction = MathUtils.Normalize(direction)

        -- Add upward component for jump
        direction.z = 0.5 -- Adjust jump angle
        direction = MathUtils.Normalize(direction)

        -- Set jump and forward movement
        pCmd:SetButtons(pCmd:GetButtons() + IN_JUMP + IN_ATTACK)
        pCmd.forwardmove = 450

        -- Aim slightly upward for jump
        local angles = direction:Angles()
        if Menu.Aimbot.Silent then
            pCmd:SetViewAngles(angles.pitch, angles.yaw, 0)
        else
            engine.SetViewAngles(EulerAngles(angles.pitch, angles.yaw, 0))
        end
    end
end


-- Update weapon swing time based on current weapon
function Combat.UpdateWeaponSwingTime(Menu, pWeapon)
    if not pWeapon or not pWeapon:GetWeaponData() then
        return
    end

    local weaponData = pWeapon:GetWeaponData()
    if not weaponData or not weaponData.smackDelay then
        return
    end

    -- Convert smackDelay time to ticks (rounded up)
    local weaponSmackDelay = math.floor(weaponData.smackDelay / globals.TickInterval())
    weaponSmackDelay = math.max(weaponSmackDelay, 5) -- Ensure minimum viable value

    -- Update the menu's SwingTime setting
    if Menu.Aimbot.SwingTime ~= weaponSmackDelay then
        local oldValue = Menu.Aimbot.SwingTime or 13

        if Menu.Aimbot.AlwaysUseMaxSwingTime or oldValue >= (Menu.Aimbot.MaxSwingTime or 13) then
            Menu.Aimbot.SwingTime = weaponSmackDelay
        end

        -- Update the maximum swing time value
        Menu.Aimbot.MaxSwingTime = weaponSmackDelay

        -- Get weapon name for notification
        local pWeaponName = "Unknown"
        pcall(function()
            local pWeaponDefIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
            local pWeaponDef = itemschema.GetItemDefinitionByID(pWeaponDefIndex)
            pWeaponName = pWeaponDef and pWeaponDef:GetName() or "Unknown"
        end)

        -- Display notification
        local Notify = require("immenu").Notify or lnxLib.UI.Notify
        Notify.Simple(
            string.format(
                "Updated SwingTime for %s:\n - Old value: %d ticks\n - New value: %d ticks\n - Actual delay: %.2f seconds",
                pWeaponName,
                oldValue,
                Menu.Aimbot.SwingTime or weaponSmackDelay,
                weaponData.smackDelay
            )
        )
    end

    return weaponSmackDelay
end

return Combat
