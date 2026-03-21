--[[ Imported by: Main ]]
-- Demoknight charge-reach state machine, ChargeControl, and ChargeJump logic.

local Simulation             = require("Simulation")

local ChargeBot              = {}

-- ─── Module state ──────────────────────────────────────────────────────────────

-- Reference to the shared Menu table (set via Init)
local _menu                  = nil

-- Charge-reach state machine
local _chargeState           = "idle" -- "idle" | "charge"
local _attackStartTick       = -1000 -- tickcount when IN_ATTACK was pressed; -1000 = not tracking

-- Max turn rate for ChargeBot yaw clamping (degrees per tick)
local MAX_CHARGE_BOT_TURN    = 17

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

function ChargeBot.GetMaxChargeBotTurn()
    return MAX_CHARGE_BOT_TURN
end

-- ─── ChargeControl ────────────────────────────────────────────────────────────
-- Simulates A/D key strafe while charging to allow mouse-steered turning.
-- Call inside OnCreateMove when the local player is a Demoman.
---@param pCmd userdata  CUserCmd
---@param pLocal userdata  local player entity
function ChargeBot.ChargeControl(pCmd, pLocal)
    assert(pCmd, "ChargeBot.ChargeControl: pCmd is nil")
    assert(pLocal, "ChargeBot.ChargeControl: pLocal is nil")

    if not _menu.Charge.ChargeControl then
        return
    end

    local isLocalValid = pLocal:IsValid()
    assert(isLocalValid, "ChargeBot.ChargeControl: pLocal invalid")

    local isCharging = pLocal:InCond(17)
    if not isCharging then
        return
    end

    -- Check if any equipped shield is a Tide Turner (disable control for it)
    local shields = entities.FindByClass("CTFWearableDemoShield")
    for _, shield in pairs(shields) do
        if shield and shield:IsValid() then
            local owner  = shield:GetPropEntity("m_hOwnerEntity")
            local isMine = owner == pLocal
            if isMine then
                local defIndex = shield:GetPropInt("m_iItemDefinitionIndex")
                local isTideTurner = defIndex == 1099
                if isTideTurner then
                    return
                end
            end
        end
    end

    local mouseDeltaX = -pCmd.mousedx
    if mouseDeltaX == 0 then
        return
    end

    local currentAngles = engine.GetViewAngles()
    local m_yaw         = select(2, client.GetConVar("m_yaw"))
    local turnAmount    = mouseDeltaX * m_yaw * CHARGE_TURN_MULTIPLIER

    if turnAmount > 0 then
        pCmd.sidemove = CHARGE_SIDE_MOVE_VALUE
    else
        pCmd.sidemove = -CHARGE_SIDE_MOVE_VALUE
    end

    turnAmount   = Simulation.Clamp(turnAmount, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)

    local newYaw = currentAngles.yaw + turnAmount
    newYaw       = newYaw % 360
    if newYaw > 180 then
        newYaw = newYaw - 360
    elseif newYaw < -180 then
        newYaw = newYaw + 360
    end

    engine.SetViewAngles(EulerAngles(currentAngles.pitch, newYaw, currentAngles.roll))
end

-- ─── State machine tick ───────────────────────────────────────────────────────
-- Call early in OnCreateMove (Demoman only, before target selection).
-- Drives: inject IN_ATTACK2 one tick after chargeState is set to "charge".
---@param pCmd userdata  CUserCmd
---@param pLocalClass integer  local player class ID
function ChargeBot.TickStateMachine(pCmd, pLocalClass)
    assert(pCmd, "ChargeBot.TickStateMachine: pCmd is nil")

    if pLocalClass == 4 then
        if _chargeState == "charge" then
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)
            _chargeState = "idle"
        end
    else
        _chargeState     = "idle"
        _attackStartTick = -1000
    end
end

-- ─── Charge-reach fire logic ──────────────────────────────────────────────────
-- Call after IN_ATTACK is pressed (can_attack block) to arm and fire the charge.
-- Returns true if IN_ATTACK2 was scheduled (chargeState set to "charge").
---@param pCmd     userdata
---@param pWeapon  userdata
---@param chargeLeft  number  (0–100)
---@param pLocalClass integer
---@param OnGround    boolean
---@return boolean  fired
function ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeLeft, pLocalClass, OnGround)
    assert(pCmd, "ChargeBot.UpdateChargeReach: pCmd is nil")
    assert(pLocalClass, "ChargeBot.UpdateChargeReach: pLocalClass is nil")

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
-- Steers toward target while charging toward enemy (not can_attack).
-- Returns aim_angles or nil if not steering.
---@param pLocalClass   integer
---@param pLocal        userdata
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
        local trace = engine.TraceHull(pLocalOrigin, aimPosTarget, vHitbox[1], vHitbox[2],
            MASK_PLAYERSOLID_BRUSHONLY)
        if trace.fraction == 1 or trace.entity ~= nil then
            local aimAngles  = Math.PositionAngles(pLocalOrigin, aimPosTarget)
            local currentAng = engine.GetViewAngles()
            local yawDiff    = Simulation.NormalizeYaw(aimAngles.yaw - currentAng.yaw)
            local limitedYaw = currentAng.yaw + Simulation.Clamp(yawDiff, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
            engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
        end
        return nil
    end

    -- Full-charge pre-charge steering (charge meter 100, right-mouse held, not in range)
    if _menu.Aimbot.ChargeBot and chargeLeft == 100 and input.IsButtonDown(MOUSE_RIGHT) and not can_attack and fDistance < 750 then
        local aimPosTarget = inRangePoint or vPlayerFuture
        if not aimPosTarget then return nil end
        local trace = engine.TraceHull(pLocalFuture, aimPosTarget, vHitbox[1], vHitbox[2],
            MASK_PLAYERSOLID_BRUSHONLY)
        if trace.fraction == 1 or trace.entity ~= nil then
            local aimAngles  = Math.PositionAngles(pLocalOrigin, aimPosTarget)
            local currentAng = engine.GetViewAngles()
            local yawDiff    = Simulation.NormalizeYaw(aimAngles.yaw - currentAng.yaw)
            local limitedYaw = currentAng.yaw + Simulation.Clamp(yawDiff, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
            engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
        end
        return nil
    end

    return nil
end

return ChargeBot
