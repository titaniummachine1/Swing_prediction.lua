--[[ Imported by: Main ]]

local Simulation             = require("Simulation")
local MathUtils              = require("MathUtils")

local ChargeBot              = {}

-- --- Module state ------------------------------------------------------------

local _menu                  = nil
local _chargeState           = "idle"
local _chargeAimAngles       = nil
local _attackStarted         = false
local _attackTickCount       = 0
local _lastAttackTick        = -1000
local _isExploitReady        = false

-- Cached once per tick by CacheEquipment()
local _hasTideTurner         = false
local _hasBooties            = false

-- --- Charge Turn Constants ---------------------------------------------------
local CHARGE_YAW_CAP_BASE    = 0.45
local BOOTIE_TURN_MULTIPLIER = 3.0
local SCALE_MIN              = 0.25
local SCALE_MAX              = 2.0
local TIDE_TURNER_DEFINDEX   = 1099
local BOOTIES_DEFINDICES     = { [405] = true, [1105] = true }

-- --- Initialization ----------------------------------------------------------

function ChargeBot.Init(menu)
    _menu = menu
end

function ChargeBot.CacheEquipment(pLocal)
    assert(pLocal, "ChargeBot.CacheEquipment: pLocal missing")
    _hasTideTurner = false
    _hasBooties    = false

    local shields  = entities.FindByClass("CTFWearableDemoShield")
    for _, shield in pairs(shields) do
        if shield and shield:IsValid() then
            local owner = shield:GetPropEntity("m_hOwnerEntity")
            if owner and owner:IsValid() and owner:GetIndex() == pLocal:GetIndex() then
                if shield:GetPropInt("m_iItemDefinitionIndex") == TIDE_TURNER_DEFINDEX then
                    _hasTideTurner = true
                end
            end
        end
    end

    local wearables = entities.FindByClass("CTFWearable")
    for _, w in pairs(wearables) do
        if w and w:IsValid() then
            local owner = w:GetPropEntity("m_hOwnerEntity")
            if owner and owner:IsValid() and owner:GetIndex() == pLocal:GetIndex() then
                if BOOTIES_DEFINDICES[w:GetPropInt("m_iItemDefinitionIndex")] then
                    _hasBooties = true
                end
            end
        end
    end
end

-- --- Logic -------------------------------------------------------------------

function ChargeBot.IsActive()
    if not _menu then return false end
    return _menu.Charge.ChargeBot
end

function ChargeBot.SetLastAttackTick(tick)
    _lastAttackTick = tick
end

function ChargeBot.GetLastAttackTick()
    return _lastAttackTick
end

function ChargeBot.TickStateMachine(pCmd, pLocalClass)
    if pLocalClass ~= 4 then
        _chargeState = "idle"
        _chargeAimAngles = nil
        return
    end

    if _chargeState == "aim" then
        if _chargeAimAngles then
            engine.SetViewAngles(EulerAngles(_chargeAimAngles.x, _chargeAimAngles.y, 0))
        end
        _chargeState = "charge"
    elseif _chargeState == "charge" then
        pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)
        _chargeState = "idle"
        _chargeAimAngles = nil
    end
end

-- --- Math compliance ---------------------------------------------------------

local function getChargeTurnCapDeg()
    if _hasTideTurner then
        return nil, true
    end

    local flCap = CHARGE_YAW_CAP_BASE
    if _hasBooties then
        flCap = flCap * BOOTIE_TURN_MULTIPLIER
    end

    -- SERVER STRICT COMPLIANCE: Use TickInterval to prevent FPS-based desyncs
    local ti = globals.TickInterval()
    local ft = ti
    local ftMin = 0.2 * ti
    local ftMax = 2.0 * ti

    local ftClamped = math.max(ftMin, math.min(ftMax, ft))
    local scale = SCALE_MIN + (SCALE_MAX - SCALE_MIN) * ((ftClamped - ftMin) / (ftMax - ftMin))

    local capRad = flCap * scale
    -- 2% safety buffer to absorb minor floating point math differences
    local capDeg = math.deg(capRad) * 0.98

    return capDeg, false
end

function ChargeBot.ChargeControl(pCmd, pLocal)
    if not pLocal:InCond(17) then return end

    local capDeg, isTideTurner = getChargeTurnCapDeg()

    -- Tide Turner gets native full control, no clamping necessary.
    if isTideTurner then return end

    local mouseDeltaX = -pCmd.mousedx
    if mouseDeltaX == 0 then return end

    local currentAngles = engine.GetViewAngles()
    local m_yaw = select(2, client.GetConVar("m_yaw")) or 0.022
    local wantedTurn = mouseDeltaX * m_yaw

    -- Mimic free mouse rotation up to the absolute server limit
    local actualTurn = MathUtils.Clamp(wantedTurn, -capDeg, capDeg)

    -- Sync the client's movement prediction when riding the edge of the cap
    if actualTurn > 0 and actualTurn >= capDeg then
        pCmd:SetSideMove(450)
    elseif actualTurn < 0 and actualTurn <= -capDeg then
        pCmd:SetSideMove(-450)
    end

    local newYaw = MathUtils.NormalizeYaw(currentAngles.y + actualTurn)
    engine.SetViewAngles(EulerAngles(currentAngles.x, newYaw, currentAngles.z))

    -- CRITICAL: Nullify raw mouse input to prevent double-rotation rubberbanding
    pCmd.mousedx = 0
end

function ChargeBot.GetChargeBotAim(pLocalClass, pLocal, chargeMeter, pLocalOrigin, pLocalFuture, vPlayerFuture,
                                   inRangePoint, canAttack, fDistance, vHitbox)
    if not _menu or not _menu.Charge.ChargeBot then return end
    if pLocalClass ~= 4 then return end

    local chargeBotFOV = tonumber(_menu.Charge.ChargeBotFOV) or 90
    chargeBotFOV = MathUtils.Clamp(chargeBotFOV, 1, 180)
    local halfFOV = chargeBotFOV * 0.5

    local isCharging = pLocal:InCond(17)
    local isAimbotReady = input.IsButtonDown(MOUSE_RIGHT)

    if isCharging or (chargeMeter >= 100 and isAimbotReady) then
        local targetPos = inRangePoint or vPlayerFuture
        if not targetPos then return end

        local trace = engine.TraceHull(pLocalOrigin, targetPos, Vector3(-18, -18, -18), Vector3(18, 18, 18),
            MASK_PLAYERSOLID_BRUSHONLY)

        if trace.fraction == 1 or (trace.entity and trace.entity:IsPlayer()) then
            local aimAngles = (targetPos - pLocalOrigin):Angles()
            local currentAng = engine.GetViewAngles()
            local yawDiff = MathUtils.NormalizeYaw(aimAngles.y - currentAng.y)

            -- Respect ChargeBot FOV for activation/steering.
            if math.abs(yawDiff) > halfFOV then
                return
            end

            -- Safe fallback for the exact tick the charge initiates
            local turnCapDeg = 1.5
            local hasFullControl = _hasTideTurner

            if isCharging then
                local capFromServer, tide = getChargeTurnCapDeg()
                if tide then
                    hasFullControl = true
                elseif capFromServer then
                    turnCapDeg = capFromServer
                end
            end

            local limitedYaw
            if hasFullControl then
                -- Instant aim if we have a Tide Turner
                limitedYaw = aimAngles.y
            else
                -- Maximize angle change toward target using exact server limit
                local actualTurn = MathUtils.Clamp(yawDiff, -turnCapDeg, turnCapDeg)
                limitedYaw = currentAng.y + actualTurn
            end

            engine.SetViewAngles(EulerAngles(currentAng.x, MathUtils.NormalizeYaw(limitedYaw), 0))
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

function ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeMeter, pLocalClass, onGround, inRangePoint, vPlayerFuture,
                                     pLocalOrigin, isRefilling)
    if not _menu or not _menu.Charge.ChargeReach or pLocalClass ~= 4 then
        _chargeState = "idle"
        _attackStarted = false
        return
    end

    if (pCmd:GetButtons() & IN_ATTACK) ~= 0 and not isRefilling then
        _lastAttackTick = globals.TickCount()

        if chargeMeter == 100 and not _attackStarted and inRangePoint then
            _attackStarted = true
            _attackTickCount = 0

            local a = (inRangePoint - pLocalOrigin):Angles()
            _chargeAimAngles = EulerAngles(a.x, a.y, 0)
        end
    end

    if _attackStarted then
        _attackTickCount = _attackTickCount + 1

        local weaponData = pWeapon and pWeapon:GetWeaponData()
        local weaponSmackDelay = 13
        if weaponData and weaponData.smackDelay then
            weaponSmackDelay = math.floor(weaponData.smackDelay / globals.TickInterval())
        end

        if _menu.Charge.ChargeJump and onGround then
            pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
        end

        if _attackTickCount >= (weaponSmackDelay - 2) then
            _chargeState = "aim"
            _attackStarted = false
            _attackTickCount = 0
        end
    end

    if _chargeState ~= "idle" then
        ChargeBot.TickStateMachine(pCmd, pLocalClass)
    end

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
