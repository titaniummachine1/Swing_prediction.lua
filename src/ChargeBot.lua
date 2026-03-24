--[[ Imported by: Main ]]

local Simulation = require("Simulation")

local ChargeBot = {}

-- ─── Constants ───────────────────────────────────────────────────────────────

local MAX_CHARGE_BOT_TURN = 17
local SIDE_MOVE_VALUE = 450
local TURN_MULTIPLIER = 1.0

-- ─── Module state ────────────────────────────────────────────────────────────

local _chargeState = "idle"
local _chargeAimAngles = nil
local _attackStarted = false
local _attackTickCount = 0

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

-- ─── Charge Control ──────────────────────────────────────────────────────────

function ChargeBot.HandleChargeControl(pCmd, pLocal, menuSettings)
    assert(pCmd, "ChargeBot.HandleChargeControl: pCmd missing")
    assert(pLocal, "ChargeBot.HandleChargeControl: pLocal missing")

    if not menuSettings.ChargeControl then return end
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

    turnAmount = Clamp(turnAmount, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
    local newYaw = Simulation.NormalizeYaw(currentAngles.yaw + turnAmount)

    engine.SetViewAngles(EulerAngles(currentAngles.pitch, newYaw, currentAngles.roll))
end

-- ─── Charge Reach & Multi-tick execution ─────────────────────────────────────

function ChargeBot.HandleChargeReach(pCmd, pLocal, menuSettings, targetPos, weaponSmackDelay)
    assert(pCmd, "ChargeBot.HandleChargeReach: pCmd missing")
    assert(pLocal, "ChargeBot.HandleChargeReach: pLocal missing")
    assert(menuSettings, "ChargeBot.HandleChargeReach: menuSettings missing")

    local pLocalClass = pLocal:GetPropInt("m_iClass")
    if pLocalClass ~= 4 then 
        _chargeState = "idle"
        _chargeAimAngles = nil
        return 
    end

    -- State machine logic (from Main.lua)
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

    -- Attack tracking logic
    if (pCmd:GetButtons() & IN_ATTACK) ~= 0 then
        local chargeLeft = pLocal:GetPropFloat("m_flChargeMeter") or 0
        if menuSettings.ChargeReach and chargeLeft >= 100 and not _attackStarted then
            _attackStarted = true
            _attackTickCount = 0
            if targetPos then
                _chargeAimAngles = (targetPos - (pLocal:GetAbsOrigin() + Vector3(0,0,75))):Angles()
            end
        end
    end

    if _attackStarted then
        _attackTickCount = _attackTickCount + 1
        local onGround = (pLocal:GetPropInt("m_fFlags") & FL_ONGROUND) ~= 0

        if menuSettings.ChargeJump and onGround then
            pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
        end

        local delay = weaponSmackDelay or 13
        if _attackTickCount >= (delay - 2) then
            _chargeState = "aim"
            _attackStarted = false
            _attackTickCount = 0
        end
    end
end

-- ─── Charge Steering (Homing) ────────────────────────────────────────────────

function ChargeBot.SteerTowards(pCmd, pLocal, targetPos, menuSettings)
    assert(pCmd, "ChargeBot.SteerTowards: pCmd missing")
    assert(pLocal, "ChargeBot.SteerTowards: pLocal missing")
    if not menuSettings.ChargeBot then return end
    if not targetPos then return end

    local pLocalClass = pLocal:GetPropInt("m_iClass")
    if pLocalClass ~= 4 then return end

    local isCharging = pLocal:InCond(17)
    local chargeLeft = pLocal:GetPropFloat("m_flChargeMeter") or 0
    local isAimbotReady = input.IsButtonDown(MOUSE_RIGHT) -- Parity with Main.lua line 1490

    if isCharging or (chargeLeft >= 100 and isAimbotReady) then
        local pLocalOrigin = pLocal:GetAbsOrigin() + Vector3(0,0,75)
        local trace = engine.TraceHull(pLocalOrigin, targetPos, Vector3(-18,-18,-18), Vector3(18,18,18), MASK_PLAYERSOLID_BRUSHONLY)
        
        if trace.fraction == 1 or (trace.entity and trace.entity:IsPlayer()) then
            local aimAngles = (targetPos - pLocalOrigin):Angles()
            local currentAng = engine.GetViewAngles()
            local yawDiff = Simulation.NormalizeYaw(aimAngles.yaw - currentAng.yaw)
            local limitedYaw = currentAng.yaw + Clamp(yawDiff, -MAX_CHARGE_BOT_TURN, MAX_CHARGE_BOT_TURN)
            engine.SetViewAngles(EulerAngles(currentAng.pitch, limitedYaw, 0))
        end
    end
end

function ChargeBot.Reset()
    _chargeState = "idle"
    _chargeAimAngles = nil
    _attackStarted = false
    _attackTickCount = 0
end

return ChargeBot
