--[[ Swing prediction Refactoring v2 ]]
--[[ Author: Terminator ]]

-- Unload if existing
if package.loaded["A_Swing_Prediction"] then
    package.loaded["A_Swing_Prediction"] = nil
end

---- Initialize libraries
local lnxLib         = require("lnxlib")
local Shared         = require("Shared")
local MenuUI         = require("Menu")
local Config         = require("utils.Config")
local DefaultConfig  = require("utils.DefaultConfig")
local Simulation     = require("Simulation")
local TargetSelector = require("TargetSelector")
local CritManager    = require("CritManager")
local ChargeBot      = require("ChargeBot")
local Visuals        = require("Visuals")
local Input          = require("Input")
local MathUtils      = require("MathUtils")
local Combat         = require("Combat")

printc(100, 255, 200, 255, "[Main] Script starting...")

-- Menu settings loaded from config
local _menuSettings = Config.LoadCFG(DefaultConfig.Menu, "A_Swing_Prediction")

-- _state is aliased to Shared so all modules can see the same object
local _state = Shared
_state.vHeight        = Vector3(0, 0, 75)
_state.totalSwingRange = 48


-- --- Initialization ----------------------------------------------------------

Simulation.Init(_menuSettings)
ChargeBot.Init(_menuSettings)
TargetSelector.Init(_menuSettings)
CritManager.Init(_menuSettings)

-- Pre-allocated ring for range circle world-space points (32 slots, no alloc per tick)
local CIRCLE_SEGMENTS = 32
local _circlePoints = {}
for _i = 1, CIRCLE_SEGMENTS do _circlePoints[_i] = nil end

local function applySilentAttackTick(pCmd, aimAngles, settings)
    if not settings.Aimbot.Silent or not aimAngles then return end
    if (pCmd:GetButtons() & IN_ATTACK) == 0 then return end
    pCmd:SetViewAngles(aimAngles.x, aimAngles.y, 0)
end

local function updateRangeCircle(pLocalOrigin, pLocalFuture, totalSwingRange, vHeight)
    local eyePos = pLocalOrigin + vHeight
    local center = pLocalFuture  -- feet
    local radius = totalSwingRange
    local angleStep = (2 * math.pi) / CIRCLE_SEGMENTS
    for i = 1, CIRCLE_SEGMENTS do
        local angle = angleStep * i
        local circlePoint = center + Vector3(math.cos(angle), math.sin(angle), 0) * radius
        local trace = engine.TraceLine(eyePos, circlePoint, MASK_SHOT_HULL)
        _circlePoints[i] = trace.fraction < 1.0 and trace.endpos or circlePoint
    end
end

-- --- Main Logic --------------------------------------------------------------

local function OnCreateMove(pCmd)
    -- Reset transient per-tick visual state
    _state.aimposVis     = nil
    _state.currentTarget  = nil
    _state.drawVhitbox    = nil

    local pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        ChargeBot.Reset()
        return
    end

    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or not pWeapon:IsMeleeWeapon() then return end

    local menuSettings = _menuSettings
    if not menuSettings.Aimbot.Aimbot then return end

    -- 1. Updates & State
    local players = entities.FindByClass("CTFPlayer")
    local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    _state.vHeight = Vector3(0, 0, viewOffset.z)

    -- Cache equipment once per tick (avoids FindByClass spam in ChargeControl/GetChargeBotAim)
    local pLocalClass = pLocal:GetPropInt("m_iClass")
    local isDemoman = pLocalClass == 4
    if isDemoman then ChargeBot.CacheEquipment(pLocal) end

    local swingRange, hullSize = Simulation.ResolveMeleeParams(pWeapon)
    local isCharging = pLocal:InCond(17)
    local chargeMeter = pLocal:GetPropFloat("m_flChargeMeter")

    -- Charge Reach Range Logic
    local Charge_Range = 128
    local isExploitReady = menuSettings.Charge.ChargeReach and chargeMeter == 100 and isDemoman
    local lastAttackTick = ChargeBot.GetLastAttackTick()
    local withinAttackWindow = (globals.TickCount() - lastAttackTick) <= 13

    if isCharging then
        local isDoingExploit = menuSettings.Charge.ChargeReach and withinAttackWindow
        if isDoingExploit then
            _state.totalSwingRange = Charge_Range + (hullSize / 2)
        else
            _state.totalSwingRange = swingRange + (hullSize / 2)
        end
    else
        if isExploitReady then
            _state.totalSwingRange = Charge_Range + (hullSize / 2)
        else
            _state.totalSwingRange = swingRange + (hullSize / 2)
        end
    end

    TargetSelector.SetTickState(players, pLocal, _state.vHeight, _state.totalSwingRange)
    TargetSelector.CalcStrafe()

    -- 2. Activation Check
    local aimActive = Input.IsKeybindActive(menuSettings.Aimbot.Keybind)
    local chargeActive = Input.IsKeybindActive(menuSettings.Charge.Keybind)

    -- 3. Troldier & Combat Assists
    Combat.TroldierAssist(pCmd, pLocal, menuSettings.Misc)

    -- 4. Target Selection
    local target = aimActive and TargetSelector.GetBestTarget(pLocal) or nil
    _state.currentTarget = target

    -- 5. Prediction & Aimbot
    local weaponData = pWeapon:GetWeaponData()
    local swingTicks = menuSettings.Aimbot.SwingTime or 13
    if weaponData and weaponData.smackDelay then
        swingTicks = math.floor(weaponData.smackDelay / globals.TickInterval())
    end

    -- Always predict local player (needed for range circle even without a target)
    local pLocalOrigin = pLocal:GetAbsOrigin() + _state.vHeight
    local chargeModeLocal = 0
    if isCharging then
        local isDoingExploit = menuSettings.Charge.ChargeReach and withinAttackWindow
        if isDoingExploit then chargeModeLocal = 1 end
    elseif isExploitReady and not menuSettings.Charge.LateCharge then
        chargeModeLocal = 2
    end

    local fixedAnglesLocal = nil
    if chargeModeLocal == 2 and target then
        local a = (target:GetAbsOrigin() - pLocal:GetAbsOrigin()):Angles()
        fixedAnglesLocal = EulerAngles(a.x, a.y, 0)
    end

    local localPred = Simulation.PredictPlayer(
        pLocal, swingTicks, 0, chargeModeLocal, fixedAnglesLocal,
        { gravity = client.GetConVar("sv_gravity") },
        Simulation.BufLocal)
    _state.pLocalOrigin = pLocal:GetAbsOrigin()
    _state.pLocalFuture = localPred.pos[swingTicks]
    _state.pLocalPath   = localPred.pos

    -- Pre-compute range circle world positions once per tick (tick-rate, not frame-rate)
    if menuSettings.Visuals and menuSettings.Visuals.Local and menuSettings.Visuals.Local.RangeCircle then
        updateRangeCircle(pLocal:GetAbsOrigin(), _state.pLocalFuture, _state.totalSwingRange, _state.vHeight)
        _state.rangeCirclePoints = _circlePoints
    else
        _state.rangeCirclePoints = nil
    end

    if target then
        local vPlayerOrigin = target:GetAbsOrigin()

        -- Predict target (targets never use charge physics)
        local targetStrafe = TargetSelector.GetStrafeAngle(target:GetIndex())
        local targetPred = Simulation.PredictPlayer(
            target, swingTicks, targetStrafe, 0, nil,
            { gravity = client.GetConVar("sv_gravity") },
            Simulation.BufTarget)

        _state.vPlayerOrigin = vPlayerOrigin
        _state.vPlayerFuture = targetPred.pos[swingTicks]
        _state.vPlayerPath = targetPred.pos

        -- Range & Attack
        local inRange, point = Simulation.CheckInRangeSimple(
            target:GetIndex(), _state.totalSwingRange, pLocalOrigin, _state.pLocalFuture + _state.vHeight,
            _state.vPlayerOrigin, _state.vPlayerFuture, target, {
                advancedHitreg = menuSettings.Misc.advancedHitreg,
                vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
            }
        )

        if inRange then
            _state.aimposVis = point
            local aimAngles = (point - pLocalOrigin):Angles()

            local handledWarp = Combat.HandleWarp(pCmd, pLocal, pWeapon, swingTicks, menuSettings.Misc)
            if not handledWarp then
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            end

            applySilentAttackTick(pCmd, aimAngles, menuSettings)
            if not menuSettings.Aimbot.Silent then
                engine.SetViewAngles(EulerAngles(aimAngles.x, aimAngles.y, 0))
            end
        end

        -- ChargeBot Steering
        ChargeBot.GetChargeBotAim(
            pLocalClass, pLocal, chargeMeter,
            pLocalOrigin, _state.pLocalFuture, _state.vPlayerFuture, point, inRange,
            (vPlayerOrigin - pLocalOrigin):Length(), { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
        )
    else
        _state.vPlayerFuture = nil
        _state.vPlayerPath   = nil
    end

    -- 6. Charge Control & Reach
    if chargeActive then
        ChargeBot.ChargeControl(pCmd, pLocal)
    end
    ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeMeter, pLocalClass, 
        (pLocal:GetPropInt("m_fFlags") & FL_ONGROUND) ~= 0, 
        _state.aimposVis, _state.vPlayerFuture, pLocal:GetAbsOrigin() + _state.vHeight)

    -- 7. Crit Management
    CritManager.Tick(pCmd, pWeapon, target ~= nil, menuSettings.Misc)
end

local function OnDraw()
    local menuSettings = _menuSettings
    MenuUI.Render(menuSettings)
    Visuals.Render(menuSettings, _state)
end

local function OnUnload()
    Config.CreateCFG(_menuSettings, "A_Swing_Prediction")
end

-- --- Initialization ----------------------------------------------------------

local function Init()
    callbacks.Unregister("CreateMove", "Swing_CreateMove")
    callbacks.Unregister("Draw", "Swing_Draw")
    callbacks.Unregister("Unload", "Swing_Unload")

    callbacks.Register("CreateMove", "Swing_CreateMove", OnCreateMove)
    callbacks.Register("Draw", "Swing_Draw", OnDraw)
    callbacks.Register("Unload", "Swing_Unload", OnUnload)

    print("Swing Prediction v2 Modular Loaded!")
end

Init()
