--[[ Imported by: Main ]]

local Simulation = require("Simulation")
local MathUtils = require("MathUtils")

local ChargeBot = {}

-- --- Constants --------------------------------------------------------------
-- (Charge turn constants now derived from server flCap math in getChargeTurnCapDeg)

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
            engine.SetViewAngles(_chargeAimAngles)
        end
        _chargeState = "charge"
    elseif _chargeState == "charge" then
        pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK2)
        _chargeState = "idle"
        _chargeAimAngles = nil
    end
end

-- --- Charge Turn Constants (mirrors CalculateChargeCap from tf_player_shared.cpp) ---------------

-- Base yaw cap (radians/tick, pre-frametime scaling) from CalculateChargeCap flCap = 0.45
local CHARGE_YAW_CAP_BASE    = 0.45   -- radians
-- Bootie turn attribute multiplier (+200% = x3 base cap)
local BOOTIE_TURN_MULTIPLIER = 3.0    -- with Ali Baba's / Bootlegger
-- Frametime scaling: RemapValClamped(ft, 0.2*ti, 2.0*ti, 0.25, 2.0)
local SCALE_MIN              = 0.25
local SCALE_MAX              = 2.0
-- Shield def indices that grant full Tide Turner-style control (skip our cap logic)
local TIDE_TURNER_DEFINDEX   = 1099
-- Boots that grant +200% charge_turn_control attribute
local BOOTIES_DEFINDICES     = { [405] = true, [1105] = true }

local function getChargeTurnCapDeg(pLocal)
    -- Detect shield equipped on local player
    local hasTideTurner = false
    local hasBooties    = false
    local shields = entities.FindByClass("CTFWearableDemoShield")
    for _, shield in pairs(shields) do
        if shield and shield:IsValid() then
            local owner = shield:GetPropEntity("m_hOwnerEntity")
            if owner and owner:IsValid() and owner:GetIndex() == pLocal:GetIndex() then
                local defIndex = shield:GetPropInt("m_iItemDefinitionIndex")
                if defIndex == TIDE_TURNER_DEFINDEX then
                    hasTideTurner = true
                end
            end
        end
    end

    -- Check wearable boots on local (slot 8 items, wearable class)
    local wearables = entities.FindByClass("CTFWearable")
    for _, w in pairs(wearables) do
        if w and w:IsValid() then
            local owner = w:GetPropEntity("m_hOwnerEntity")
            if owner and owner:IsValid() and owner:GetIndex() == pLocal:GetIndex() then
                local defIndex = w:GetPropInt("m_iItemDefinitionIndex")
                if BOOTIES_DEFINDICES[defIndex] then
                    hasBooties = true
                end
            end
        end
    end

    if hasTideTurner then
        return nil, true -- nil = use full mouse, true = is Turner
    end

    -- flCap calculation
    local flCap = CHARGE_YAW_CAP_BASE
    if hasBooties then
        flCap = flCap * BOOTIE_TURN_MULTIPLIER
    end

    -- Frametime scaling: clamp frametime to [0.2*ti, 2.0*ti], remap to [0.25, 2.0]
    local ti = globals.TickInterval()
    local ft = globals.FrameTime()
    local ftMin = 0.2 * ti
    local ftMax = 2.0 * ti
    local ftClamped = math.max(ftMin, math.min(ftMax, ft))
    local scale = SCALE_MIN + (SCALE_MAX - SCALE_MIN) * ((ftClamped - ftMin) / (ftMax - ftMin))

    -- Final cap in radians for this tick, then convert to degrees
    local capRad = flCap * scale
    local capDeg = math.deg(capRad)
    return capDeg, false
end

function ChargeBot.ChargeControl(pCmd, pLocal)
    if not pLocal:InCond(17) then return end

    local capDeg, isTideTurner = getChargeTurnCapDeg(pLocal)

    -- Tide Turner: has native full control, no capping needed
    if isTideTurner then return end

    local mouseDeltaX = -pCmd.mousedx
    if mouseDeltaX == 0 then return end

    local currentAngles = engine.GetViewAngles()
    local m_yaw = select(2, client.GetConVar("m_yaw")) or 0.022
    local wantedTurn = mouseDeltaX * m_yaw

    -- Clamp to the server's per-tick cap (squeeze every degree allowed)
    local actualTurn
    if wantedTurn > 0 then
        actualTurn = math.min(wantedTurn, capDeg)
        -- Commit sidemove in turn direction so client prediction matches server move
        pCmd:SetSideMove(450)
    else
        actualTurn = math.max(wantedTurn, -capDeg)
        pCmd:SetSideMove(-450)
    end

    local newYaw = MathUtils.NormalizeYaw(currentAngles.y + actualTurn)
    engine.SetViewAngles(EulerAngles(currentAngles.x, newYaw, currentAngles.z))
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
            local yawDiff = MathUtils.NormalizeYaw(aimAngles.y - currentAng.y)

            -- Use actual server turn cap for smooth non-rubberband steering
            local turnCapDeg = 17 -- fallback for when not charging but about to charge
            if isCharging then
                local capFromServer = getChargeTurnCapDeg(pLocal)
                if capFromServer then turnCapDeg = capFromServer end
            end

            local limitedYaw = currentAng.y + MathUtils.Clamp(yawDiff, -turnCapDeg, turnCapDeg)
            engine.SetViewAngles(EulerAngles(currentAng.x, limitedYaw, 0))
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

function ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeMeter, pLocalClass, onGround, inRangePoint, vPlayerFuture, pLocalOrigin)
    if not _menu or not _menu.Charge.ChargeReach or pLocalClass ~= 4 then 
        _chargeState = "idle"
        _attackStarted = false
        return 
    end

    -- Update last attack tick if IN_ATTACK is set
    if (pCmd:GetButtons() & IN_ATTACK) ~= 0 then
        _lastAttackTick = globals.TickCount()
        
        -- Start tracking attack ticks for charge reach exploit
        if chargeMeter == 100 and not _attackStarted then
            _attackStarted = true
            _attackTickCount = 0
            
            -- Store aim direction to target future position so charge travels correctly
            if inRangePoint then
                _chargeAimAngles = (inRangePoint - pLocalOrigin):Angles()
            elseif vPlayerFuture then
                _chargeAimAngles = (vPlayerFuture - pLocalOrigin):Angles()
            end
        end
    end

    -- Track attack ticks and execute charge at right moment
    if _attackStarted then
        _attackTickCount = _attackTickCount + 1

        -- Get weapon smack delay (when the weapon will hit)
        local weaponData = pWeapon and pWeapon:GetWeaponData()
        local weaponSmackDelay = 13 -- fallback
        if weaponData and weaponData.smackDelay then
             weaponSmackDelay = math.floor(weaponData.smackDelay / globals.TickInterval())
        end

        -- If charge-jump enabled issue jump together with charge
        if _menu.Charge.ChargeJump and onGround then
            pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
        end

        -- Execute charge exactly 2 ticks before the hit registers
        if _attackTickCount >= (weaponSmackDelay - 2) then
            _chargeState = "aim" -- next TickStateMachine call will trigger aim/charge
            _attackStarted = false
            _attackTickCount = 0
        end
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
