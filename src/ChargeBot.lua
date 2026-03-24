--[[ Imported by: Main ]]

local Simulation = require("Simulation")
local MathUtils = require("MathUtils")

local ChargeBot = {}

-- --- Constants --------------------------------------------------------------

local MAX_CHARGE_BOT_TURN = 17
local SIDE_MOVE_VALUE = 450
local TURN_MULTIPLIER = 1.0

-- --- Module state ------------------------------------------------------------

local _menu = nil
local _chargeState = "idle"
local _chargeAimAngles = nil
local _attackStarted = false
local _attackTickCount = 0
local _lastAttackTick = -1000
local _isExploitReady = false

-- --- Initialization ----------------------------------------------------------

function ChargeBot.Init(menu)
    _menu = menu
end

-- --- Logic -------------------------------------------------------------------

function ChargeBot.IsActive()
    if not _menu then return false end
    return _menu.Charge.ChargeBot
end

function ChargeBot.SetLastAttackTick(tick)
    _lastAttackTick = tick
end

function ChargeBot.TickStateMachine(pCmd, pLocalClass)
    if pLocalClass ~= 4 then 
        _chargeState = "idle"
        _chargeAimAngles = nil
        return 
    end

    if _chargeState == "aim" then
        if _chargeAimAngles then
            engine.SetViewAngles(EulerAngles(_chargeAimAngles.pitch, _chargeAimAngles.yaw, 0))
        end
        _chargeState = "charge"
    elseif _chargeState == "charge" then
        pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)
        _chargeState = "idle"
        _chargeAimAngles = nil
    end
end

function ChargeBot.ChargeControl(pCmd, pLocal)
    if not pLocal:InCond(17) then return end

    -- Tide Turner check
    local shields = entities.FindByClass("CTFWearableDemoShield")
    for _, shield in pairs(shields) do
        if shield and shield:IsValid() then
            local owner = shield:GetPropEntity("m_hOwnerEntity")
            if owner and owner:GetIndex() == pLocal:GetIndex() then
                local defIndex = shield:GetPropInt("m_iItemDefinitionIndex")
                if defIndex == 1099 then return end -- Skip Tide Turner
            end
        end
    end

    local mouseDeltaX = -pCmd.mousedx
    if mouseDeltaX == 0 then return end

    local currentAngles = engine.GetViewAngles()
    local m_yaw = select(2, client.GetConVar("m_yaw")) or 0.022
    local turnAmount = mouseDeltaX * m_yaw * TURN_MULTIPLIER

    if turnAmount > 0 then
        pCmd:SetSideMove(SIDE_MOVE_VALUE)
    else
        pCmd:SetSideMove(-SIDE_MOVE_VALUE)
    end

    turnAmount = MathUtils.Clamp(turnAmount, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
    local newYaw = MathUtils.NormalizeYaw(currentAngles.yaw + turnAmount)

    engine.SetViewAngles(EulerAngles(currentAngles.pitch, newYaw, currentAngles.roll))
end

function ChargeBot.GetChargeBotAim(pLocalClass, pLocal, chargeMeter, pLocalOrigin, pLocalFuture, vPlayerFuture, inRangePoint, canAttack, fDistance, vHitbox)
    if not _menu or not _menu.Charge.ChargeBot then return end
    if pLocalClass ~= 4 then return end

    local isCharging = pLocal:InCond(17)
    local isAimbotReady = input.IsButtonDown(MOUSE_RIGHT) -- This should ideally be passed in or use Input module

    if isCharging or (chargeMeter >= 100 and isAimbotReady) then
        local targetPos = inRangePoint or vPlayerFuture
        if not targetPos then return end

        local trace = engine.TraceHull(pLocalOrigin, targetPos, Vector3(-18,-18,-18), Vector3(18,18,18), MASK_PLAYERSOLID_BRUSHONLY)
        
        if trace.fraction == 1 or (trace.entity and trace.entity:IsPlayer()) then
            local aimAngles = (targetPos - pLocalOrigin):Angles()
            local currentAng = engine.GetViewAngles()
            local yawDiff = MathUtils.NormalizeYaw(aimAngles.yaw - currentAng.yaw)
            local limitedYaw = currentAng.yaw + MathUtils.Clamp(yawDiff, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
            engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
        end
    end
end

function ChargeBot.ArmChargeReach(pLocalClass, chargeMeter)
    local isChargeReachEnabled = false
    if _menu and _menu.Charge then
        isChargeReachEnabled = _menu.Charge.ChargeReach
    end

    if pLocalClass == 4 and chargeMeter == 100 and isChargeReachEnabled then
        _isExploitReady = true
    else
        _isExploitReady = false
    end
end

function ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeMeter, pLocalClass, onGround)
    if not _menu or not _menu.Charge.ChargeReach or pLocalClass ~= 4 then return end

    local attackWindowTicks = _menu.Aimbot.MaxSwingTime or 13
    local withinAttackWindow = (globals.TickCount() - _lastAttackTick) <= attackWindowTicks

    if _isExploitReady and withinAttackWindow then
        -- Trigger charge reach state
        _chargeState = "aim"
        -- Optimization: Calculate aim angles here or in GetChargeBotAim
    end

    if _chargeState ~= "idle" then
        ChargeBot.TickStateMachine(pCmd, pLocalClass)
    end

    -- Manual charge jump
    if _menu.Charge.ChargeJump and (pCmd:GetButtons() & IN_ATTACK2) ~= 0 and chargeMeter == 100 and onGround then
        pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
    end
end

function ChargeBot.Reset()
    _chargeState = "idle"
    _chargeAimAngles = nil
    _attackStarted = false
    _attackTickCount = 0
    _isExploitReady = false
end

return ChargeBot
