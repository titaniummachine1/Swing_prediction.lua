local Simulation = require("Simulation")

local ChargeBot  = {}


---@class ChargeBotMenu
---@field Aimbot table
---@field Charge table
local _menu            = nil

local _chargeState     = "idle"       -- "idle" | "charge"
local _attackStartTick = -1000        -- tickcount when IN_ATTACK was pressed; -1000 = not tracking

-- Dynamic turn cap: calculated per tick

-- Shield/boots itemdef indexes
local SHIELD_TARGE     = 131;
local SHIELD_SPLENDID  = 406;
local SHIELD_TIDE      = 1099;
local BOOTIES          = 405;
local BOOTLEGGER       = 608;

-- Returns the effective yaw cap (in degrees per tick) for the current player state
local function GetChargeTurnCap(pLocal)
    if not pLocal or not pLocal:IsValid() then return 17 end -- fallback
    local isCharging = pLocal:InCond(17)
    if not isCharging then return 17 end

    -- Find equipped shield
    local shields = entities.FindByClass("CTFWearableDemoShield")
    local shieldType = nil
    for _, shield in pairs(shields) do
        if shield and shield:IsValid() then
            local owner = shield:GetPropEntity("m_hOwnerEntity")
            if owner == pLocal then
                local defIndex = shield:GetPropInt("m_iItemDefinitionIndex")
                shieldType = defIndex
                break
            end
        end
    end

    -- Find boots
    local hasBoots = false
    local boots = entities.FindByClass("CTFWearable")
    for _, boot in pairs(boots) do
        if boot and boot:IsValid() then
            local owner = boot:GetPropEntity("m_hOwnerEntity")
            if owner == pLocal then
                local defIndex = boot:GetPropInt("m_iItemDefinitionIndex")
                if defIndex == BOOTIES or defIndex == BOOTLEGGER then
                    hasBoots = true
                    break
                end
            end
        end
    end

    -- FPS scaling (frametime)
    local tickrate = globals.TickInterval() > 0 and 1 / globals.TickInterval() or 66.666
    local frametime = globals.FrameTime()
    local scaling = 1.0
    if frametime > 0 then
        local tickInterval = globals.TickInterval()
        local minFT = 0.2 * tickInterval
        local maxFT = 2.0 * tickInterval
        if frametime <= minFT then
            scaling = 0.25
        elseif frametime >= maxFT then
            scaling = 2.0
        else
            scaling = 0.25 + (frametime - minFT) * (2.0 - 0.25) / (maxFT - minFT)
        end
    end

    -- Shield logic
    if shieldType == SHIELD_TIDE then
        return 180       -- full control
    end
    local baseCap = 0.45 -- radians
    if hasBoots then baseCap = baseCap * 3 end
    -- Convert to degrees
    local capDeg = baseCap * (180 / math.pi)
    -- Per-tick
    local perTick = capDeg * scaling * globals.TickInterval()
    return perTick
end

-- Constants for ChargeControl mouse-turn steering
local CHARGE_TURN_MULTIPLIER = 1.0
local CHARGE_SIDE_MOVE_VALUE = 450

-- ─── Init ─────────────────────────────────────────────────────────────────────

function ChargeBot.Init(menuRef)
    assert(menuRef, "ChargeBot.Init: menuRef is nil")
    _menu = menuRef
end

-- ─── State accessors ──────────────────────────────────────────────────────────

function ChargeBot.GetChargeState()
    return _chargeState
end

function ChargeBot.SetChargeState(state)
    assert(state == "idle" or state == "charge", "ChargeBot.SetChargeState: invalid state " .. tostring(state))
    _chargeState = state
end

function ChargeBot.GetAttackStartTick()
    return _attackStartTick
end

function ChargeBot.SetAttackStartTick(t)
    _attackStartTick = t
end

function ChargeBot.ResetAttackTracking()
    _attackStartTick = -1000
end

-- ─── ChargeControl ────────────────────────────────────────────────────────────
---@param pCmd UserCmd
---@param pLocal Entity
function ChargeBot.ChargeControl(pCmd, pLocal)
    if not pCmd or not pLocal then return end
    if not _menu or not _menu.Charge or not _menu.Charge.ChargeControl then return end
    if not pLocal:IsValid() then return end
    local isCharging = pLocal:InCond(17)
    if not isCharging then return end

    -- Check for Tide Turner (full control)
    local shields = entities.FindByClass("CTFWearableDemoShield")
    for _, shield in pairs(shields) do
        if shield and shield:IsValid() then
            local owner = shield:GetPropEntity("m_hOwnerEntity")
            if owner == pLocal then
                local defIndex = shield:GetPropInt("m_iItemDefinitionIndex")
                if defIndex == SHIELD_TIDE then return end
            end
        end
    end

    local mouseDeltaX = -pCmd.mousedx
    if mouseDeltaX == 0 then return end

    local currentAngles = engine.GetViewAngles()
    local m_yaw         = select(2, client.GetConVar("m_yaw"))
    local turnAmount    = mouseDeltaX * m_yaw * CHARGE_TURN_MULTIPLIER

    if turnAmount > 0 then
        pCmd.sidemove = CHARGE_SIDE_MOVE_VALUE
    else
        pCmd.sidemove = -CHARGE_SIDE_MOVE_VALUE
    end

    local maxTurn = GetChargeTurnCap(pLocal)
    turnAmount = Simulation.Clamp(turnAmount, -maxTurn, maxTurn)

    local newYaw = currentAngles.yaw + turnAmount
    newYaw = ((newYaw + 180) % 360) - 180
    engine.SetViewAngles(EulerAngles(currentAngles.pitch, newYaw, currentAngles.roll))
end

-- ─── State machine tick ───────────────────────────────────────────────────────
-- Call early in OnCreateMove (Demoman only, before target selection).
---@param pCmd UserCmd
---@param pLocalClass integer  local player class ID
function ChargeBot.TickStateMachine(pCmd, pLocalClass)
    if not pCmd or not pLocalClass then
        return
    end

    if pLocalClass == 4 then
        if _chargeState == "charge" then
            local buttons = pCmd:GetButtons() or 0
            pCmd:SetButtons(buttons | IN_ATTACK2)
            _chargeState = "idle"
        end
    else
        _chargeState     = "idle"
        _attackStartTick = -1000
    end
end

-- ─── Charge-reach fire logic ──────────────────────────────────────────────────
-- Call after IN_ATTACK is pressed (can_attack block) to arm and fire the charge.
---@param pCmd UserCmd
---@param pWeapon Entity
---@param chargeLeft number  (0–100)
---@param pLocalClass integer
---@param OnGround boolean
---@return boolean fired
function ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeLeft, pLocalClass, OnGround)
    if not pCmd or not pLocalClass then
        return false
    end

    if _attackStartTick < 0 then
        return false
    end

    local weaponSmackDelayTicks = _menu.Aimbot.MaxSwingTime or 13
    local wd = pWeapon and pWeapon:GetWeaponData()
    if wd and wd.smackDelay then
        weaponSmackDelayTicks = Simulation.smackDelayToTicks(wd.smackDelay)
    end

    if _menu.Charge.ChargeJump and OnGround then
        pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
    end

    local chargeWindow       = Simulation.getChargeReachWindowTicks()
    local damageRegisterTick = _attackStartTick + weaponSmackDelayTicks
    local ticksToSmack       = damageRegisterTick - globals.TickCount()

    if ticksToSmack <= chargeWindow then
        _chargeState     = "charge"
        _attackStartTick = -1000
        return true
    end

    return false
end

-- ─── Arm charge reach ─────────────────────────────────────────────────────────
-- Call when IN_ATTACK fires and conditions are met to arm the reach exploit.
---@param pLocalClass integer
---@param chargeLeft  number
function ChargeBot.ArmChargeReach(pLocalClass, chargeLeft)
    local isDemoman     = pLocalClass == 4
    local hasFullCharge = chargeLeft == 100
    local isEnabled     = _menu.Charge.ChargeReach

    if isDemoman and isEnabled and hasFullCharge and _attackStartTick < 0 then
        _attackStartTick = globals.TickCount()
    end
end

-- ─── ChargeBot steering (pre-attack) ─────────────────────────────────────────
---@param pLocalClass   integer
---@param pLocal        Entity
---@param chargeLeft    number
---@param pLocalOrigin  Vector3   eye origin of local player
---@param pLocalFuture  Vector3   predicted eye origin of local player
---@param vPlayerFuture Vector3   predicted origin of target
---@param inRangePoint  Vector3|nil
---@param can_attack    boolean
---@param fDistance     number
---@param vHitbox       table
---@return EulerAngles|nil
function ChargeBot.GetChargeBotAim(pLocalClass, pLocal, chargeLeft, pLocalOrigin, pLocalFuture, vPlayerFuture,
                                   inRangePoint, can_attack, fDistance, vHitbox)
    assert(pLocalClass, "ChargeBot.GetChargeBotAim: pLocalClass is nil")
    assert(pLocal, "ChargeBot.GetChargeBotAim: pLocal is nil")

    if pLocalClass ~= 4 then
        return nil
    end

    local Math = require("lnxLib").Utils.Math

    -- Actively charging toward enemy (not in swing range yet)
    local isCharging = pLocal:InCond(17)
    if _menu.Aimbot.ChargeBot and isCharging and not can_attack then
        local aimPosTarget = inRangePoint or vPlayerFuture
        if not aimPosTarget then return nil end
        local trace = engine.TraceHull(pLocalOrigin, aimPosTarget, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
        if trace.fraction == 1 or trace.entity ~= nil then
            local aimAngles  = Math.PositionAngles(pLocalOrigin, aimPosTarget)
            local currentAng = engine.GetViewAngles()
            local yawDiff    = Simulation.NormalizeYaw(aimAngles.yaw - currentAng.yaw)
            local maxTurn    = GetChargeTurnCap(pLocal)
            local limitedYaw = currentAng.yaw + Simulation.Clamp(yawDiff, -maxTurn, maxTurn)
            engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
        end
        return nil
    end

    -- Full-charge pre-charge steering (charge meter 100, right-mouse held, not in range)
    if _menu.Aimbot.ChargeBot and chargeLeft == 100 and input.IsButtonDown(MOUSE_RIGHT) and not can_attack and fDistance < 750 then
        local aimPosTarget = inRangePoint or vPlayerFuture
        if not aimPosTarget then return nil end
        local trace = engine.TraceHull(pLocalFuture, aimPosTarget, vHitbox[1], vHitbox[2], MASK_PLAYERSOLID_BRUSHONLY)
        if trace.fraction == 1 or trace.entity ~= nil then
            local aimAngles  = Math.PositionAngles(pLocalOrigin, aimPosTarget)
            local currentAng = engine.GetViewAngles()
            local yawDiff    = Simulation.NormalizeYaw(aimAngles.yaw - currentAng.yaw)
            local maxTurn    = GetChargeTurnCap(pLocal)
            local limitedYaw = currentAng.yaw + Simulation.Clamp(yawDiff, -maxTurn, maxTurn)
            engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
        end
        return nil
    end

    return nil
end

return ChargeBot
