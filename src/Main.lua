--[[ Swing prediction Refactoring v2 ]]
--[[ Author: Terminator ]]

-- Unload if existing
if package.loaded["A_Swing_Prediction"] then
    package.loaded["A_Swing_Prediction"] = nil
end

---- Initialize libraries
local lnxLib                = require("lnxlib")
local Shared                = require("Shared")
local MenuUI                = require("Menu")
local Config                = require("utils.Config")
local DefaultConfig         = require("utils.DefaultConfig")
local Simulation            = require("Simulation")
local TargetSelector        = require("TargetSelector")
local CritManager           = require("CritManager")
local ChargeBot             = require("ChargeBot")
local Visuals               = require("Visuals")
local Input                 = require("Input")
local MathUtils             = require("MathUtils")
local Combat                = require("Combat")
local Profiler              = nil
local _profilerHealthy      = true
local _profilerErrorPrinted = false

local function handleProfilerError(action, err)
    if not _profilerErrorPrinted then
        print(string.format("[Main] Profiler %s failed: %s", action, tostring(err)))
        _profilerErrorPrinted = true
    end
    _profilerHealthy = false
end

local function safeProfilerCall(action, fn, ...)
    if not Profiler or not _profilerHealthy or not fn then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        handleProfilerError(action, result)
        return nil
    end

    return result
end

do
    local ok, profilerModule = pcall(require, "Profiler")
    if ok and profilerModule then
        Profiler = profilerModule
        if Profiler.SetTimingMode then
            safeProfilerCall("SetTimingMode", Profiler.SetTimingMode, "clock")
        end
        safeProfilerCall("SetVisible", Profiler.SetVisible, true)
        printc(100, 255, 200, 255, "[Main] Profiler enabled")
        print("[Main] Profiler timing mode forced to local clock.")
    else
        print("[Main] Profiler module not found, profiling disabled.")
    end
end

local function profilerSetContext(context)
    if not (_menuSettings and _menuSettings.Visuals and _menuSettings.Visuals.Profiler) then
        return
    end
    safeProfilerCall("SetContext", Profiler and Profiler.SetContext, context)
end

local function profilerBegin(name)
    if not (_menuSettings and _menuSettings.Visuals and _menuSettings.Visuals.Profiler) then
        return
    end
    safeProfilerCall("Begin", Profiler and Profiler.Begin, name)
end

local function profilerEnd()
    if not (_menuSettings and _menuSettings.Visuals and _menuSettings.Visuals.Profiler) then
        return
    end
    safeProfilerCall("End", Profiler and Profiler.End)
end

local function profilerDraw()
    if not (_menuSettings and _menuSettings.Visuals and _menuSettings.Visuals.Profiler) then
        return
    end
    safeProfilerCall("Draw", Profiler and Profiler.Draw)
end

local function profilerShutdown()
    safeProfilerCall("SetVisible", Profiler and Profiler.SetVisible, false)
    safeProfilerCall("Shutdown", Profiler and Profiler.Shutdown)
end

printc(100, 255, 200, 255, "[Main] Script starting...")

-- Menu settings loaded from config
local _menuSettings    = Config.LoadCFG(DefaultConfig.Menu, "A_Swing_Prediction")

-- _state is aliased to Shared so all modules can see the same object
local _state           = Shared
_state.vHeight         = Vector3(0, 0, 75)
_state.totalSwingRange = 48


-- --- Initialization ----------------------------------------------------------

Simulation.Init(_menuSettings)
ChargeBot.Init(_menuSettings)
TargetSelector.Init(_menuSettings)
CritManager.Init(_menuSettings)

-- Pre-allocated ring for range circle world-space points (32 slots, no alloc per tick)
local CIRCLE_SEGMENTS = 32
local _circlePoints = {}
local _circleUnitOffsets = {}
for i = 1, CIRCLE_SEGMENTS do _circlePoints[i] = Vector3(0, 0, 0) end
do
    local angleStep = (2 * math.pi) / CIRCLE_SEGMENTS
    for i = 1, CIRCLE_SEGMENTS do
        local angle = angleStep * i
        _circleUnitOffsets[i] = Vector3(math.cos(angle), math.sin(angle), 0)
    end
end

local function applySilentAttackTick(pCmd, aimAngles, settings)
    if not settings.Aimbot.Silent or not aimAngles then return end
    if (pCmd:GetButtons() & IN_ATTACK) == 0 then return end
    pCmd:SetViewAngles(aimAngles.x, aimAngles.y, 0)
end

local function updateRangeCircle(pLocalOrigin, pLocalFuture, totalSwingRange, vHeight)
    local center = pLocalFuture -- feet
    local radius = totalSwingRange
    for i = 1, CIRCLE_SEGMENTS do
        local offset = _circleUnitOffsets[i]
        _circlePoints[i].x = center.x + (offset.x * radius)
        _circlePoints[i].y = center.y + (offset.y * radius)
        _circlePoints[i].z = center.z
    end
end

-- --- Main Logic --------------------------------------------------------------

local function OnCreateMove(pCmd)
    profilerSetContext("tick")

    profilerBegin("Tick.Setup")
    -- Reset transient per-tick visual state
    _state.aimposVis     = nil
    _state.currentTarget = nil
    _state.drawVhitbox   = nil

    local pLocal         = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        ChargeBot.Reset()
        profilerEnd()
        return
    end

    local menuSettings = _menuSettings
    local aimbotEnabled = menuSettings.Aimbot and menuSettings.Aimbot.Aimbot

    -- 3. Troldier & Combat Assists (Call before melee check to allow switching)
    Combat.TroldierAssist(pCmd, pLocal, menuSettings.Misc)

    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or not pWeapon:IsMeleeWeapon() then
        profilerEnd()
        return
    end
    local troldierSwingAssist = Combat.ShouldUseTroldierSwingAssist(pLocal, pWeapon, menuSettings.Misc)

    -- 1. Updates & State
    local players = entities.FindByClass("CTFPlayer")
    local viewOffset = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
    _state.vHeight = Vector3(0, 0, viewOffset.z)

    -- Cache equipment once per tick (avoids FindByClass spam in ChargeControl/GetChargeBotAim)
    local pLocalClass = pLocal:GetPropInt("m_iClass")
    local isDemoman = pLocalClass == 4
    if isDemoman then ChargeBot.CacheEquipment(pLocal) end
    profilerEnd()

    profilerBegin("Tick.TimingRange")
    local swingRange, hullSize = Simulation.ResolveMeleeParams(pWeapon)
    local isCharging = pLocal:InCond(17)
    local chargeMeter = pLocal:GetPropFloat("m_flChargeMeter")
    -- Dynamic Prediction Timing (Remaining ticks for active swings)
    local weaponData = pWeapon:GetWeaponData()
    local baseSwingTicks = menuSettings.Aimbot.SwingTime or 13
    local smackDelay = weaponData and weaponData.smackDelay or (baseSwingTicks * globals.TickInterval())
    local timeFireDelay = weaponData and weaponData.timeFireDelay or 0.8
    local swingTicks = math.floor(smackDelay / globals.TickInterval())

    local curTime = pLocal:GetPropInt("m_nTickBase") * globals.TickInterval()
    local nextPrimary = pWeapon:GetPropFloat("m_flNextPrimaryAttack") or 0
    local isMidSwing = false

    if nextPrimary > curTime then
        local swingStartTime = nextPrimary - timeFireDelay
        local smackTime = swingStartTime + smackDelay
        local remainingTime = smackTime - curTime
        if remainingTime > 0 and remainingTime <= smackDelay then
            local remainingTicks = math.floor(remainingTime / globals.TickInterval())
            swingTicks = math.max(1, math.min(swingTicks, remainingTicks))
            isMidSwing = true
        end
    end

    -- Charge Reach Range Logic
    local Charge_Range = 128
    local isExploitReady = menuSettings.Charge.ChargeReach and chargeMeter == 100 and isDemoman
    local lastAttackTick = ChargeBot.GetLastAttackTick()
    local withinAttackWindow = isMidSwing or ((globals.TickCount() - lastAttackTick) <= swingTicks)
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
    profilerEnd()

    profilerBegin("Tick.HistoryAndStrafe")
    TargetSelector.SetTickState(players, pLocal, _state.vHeight, _state.totalSwingRange)
    TargetSelector.UpdateHistory(players, pCmd)
    TargetSelector.CalcStrafe()
    profilerEnd()

    -- 2. Activation Check
    profilerBegin("Tick.Targeting")
    local aimActive = aimbotEnabled and Input.IsKeybindActive(menuSettings.Aimbot.Keybind)
    local chargeActive = Input.IsKeybindActive(menuSettings.Charge.Keybind)
    local chargeBotActive = isDemoman and menuSettings.Charge.ChargeBot and chargeActive
    local chargeControlActive = isDemoman and menuSettings.Charge.ChargeControl
    local chargeReachActive = isDemoman and menuSettings.Charge.ChargeReach
    local demoknightTargetingActive = chargeBotActive or chargeReachActive
    local targetingEnabled = aimActive or demoknightTargetingActive

    -- 4. Target Selection
    local potentialTarget = nil
    if targetingEnabled then
        potentialTarget = TargetSelector.GetBestTarget(pLocal)
    end
    local target = targetingEnabled and potentialTarget or nil
    _state.currentTarget = target -- Locked target for green visuals

    -- 4.5. Combat Distance Check (for CritManager Refill)
    local inCombat = false
    if potentialTarget then
        -- AABB sphere collision check to see if target is within 5x our attack range (including charge reach)
        local pLocalOrigin = pLocal:GetAbsOrigin() + _state.vHeight
        local pTargetOrigin = potentialTarget:GetAbsOrigin()
        local closestPoint = Simulation.ClosestPointOnHitbox(pTargetOrigin, pLocalOrigin,
            { Vector3(-24, -24, 0), Vector3(24, 24, 82) })
        local distance = (closestPoint - pLocalOrigin):Length()

        if distance <= (_state.totalSwingRange * 5) then
            inCombat = true
        end
    end
    profilerEnd()

    -- 5. Prediction & Aimbot
    -- (swingTicks is now computed dynamically at the start of the tick for mid-swing accuracy)

    -- Always predict local player (needed for range circle even without a target)
    profilerBegin("Tick.LocalPredict")
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

    local useStrafePred     = menuSettings.Misc.strafePred
    -- Could add warp/instant attack conditions here if required, but for basic strafe pred:
    local localStrafe       = useStrafePred and TargetSelector.GetStrafeAngle(pLocal:GetIndex()) or 0
    local gravity           = client.GetConVar("sv_gravity")
    local localPredictTicks = swingTicks
    if troldierSwingAssist and not isMidSwing then
        localPredictTicks = math.min(swingTicks + 1, 32)
    end

    local localPred        = Simulation.PredictPlayer(
        pLocal, localPredictTicks, localStrafe, chargeModeLocal, fixedAnglesLocal,
        { gravity = gravity },
        Simulation.BufLocal)
    _state.pLocalOrigin    = pLocal:GetAbsOrigin()
    _state.pLocalFuture    = localPred.pos[swingTicks] or pLocal:GetAbsOrigin()
    _state.pLocalPath      = localPred.pos
    _state.pLocalPathCount = swingTicks

    if Combat.ShouldTroldierPreSwing(troldierSwingAssist, localPred, swingTicks, isMidSwing, pCmd, menuSettings.Misc) then
        pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
    end

    -- Amalgam-style Backtrack logic
    local btOldest, btLatest = TargetSelector.GetBacktrackWindow(swingTicks)

    -- Pre-compute range circle world positions once per tick (tick-rate, not frame-rate)
    if menuSettings.Visuals and menuSettings.Visuals.Local and menuSettings.Visuals.Local.RangeCircle then
        updateRangeCircle(pLocal:GetAbsOrigin(), _state.pLocalFuture, _state.totalSwingRange, _state.vHeight)
        _state.rangeCirclePoints = _circlePoints
    else
        _state.rangeCirclePoints = nil
    end
    profilerEnd()

    -- Always show white AABB box at simulated future target position
    -- Predict the nearest target using full simulation so the visual box always shows exactly where we will aim
    local targetPred = nil
    local targetPredEntityIndex = nil
    profilerBegin("Tick.VisualTarget")
    if potentialTarget then
        local vVisOrigin = potentialTarget:GetAbsOrigin()
        targetPredEntityIndex = potentialTarget:GetIndex()

        local potStrafe = TargetSelector.GetStrafeAngle(potentialTarget:GetIndex())
        targetPred = Simulation.PredictPlayer(
            potentialTarget, swingTicks, potStrafe, 0, nil,
            { gravity = gravity },
            Simulation.BufTarget)

        _state.vTargetHitboxPos = targetPred.pos[swingTicks] or vVisOrigin
        -- vTargetAimPos starts as the same as HitboxPos; overridden during attack
        _state.vTargetAimPos = _state.vTargetHitboxPos
        _state.aimBacktrack = false
    else
        _state.vTargetHitboxPos = nil
        _state.vTargetAimPos = nil
        _state.aimBacktrack = false
    end
    profilerEnd()

    profilerBegin("Tick.AimSolve")
    if target then
        local vPlayerOrigin = target:GetAbsOrigin()

        if not targetPred or targetPredEntityIndex ~= target:GetIndex() then
            -- Predict target (targets never use charge physics)
            local targetStrafe = TargetSelector.GetStrafeAngle(target:GetIndex())
            targetPred = Simulation.PredictPlayer(
                target, swingTicks, targetStrafe, 0, nil,
                { gravity = gravity },
                Simulation.BufTarget)
            targetPredEntityIndex = target:GetIndex()
        end

        _state.vPlayerOrigin = vPlayerOrigin
        _state.vPlayerFuture = targetPred.pos[swingTicks]
        _state.vPlayerPath = targetPred.pos
        _state.vPlayerPathCount = swingTicks

        local TargetSelector = package.loaded["TargetSelector"] or _G["TargetSelector"]
        local historyBuffer = TargetSelector and TargetSelector.GetHistory(target:GetIndex()) or nil
        local engineGhosts = TargetSelector and TargetSelector.GetEngineGhosts(target:GetIndex()) or nil

        local inRange, point, bTick = Simulation.CheckInRangeSimple(
            target:GetIndex(), _state.totalSwingRange, pLocalOrigin, _state.pLocalFuture + _state.vHeight,
            _state.vPlayerOrigin, _state.vPlayerFuture, target, {
                advancedHitreg = menuSettings.Misc.advancedHitreg,
                vHitbox = { Vector3(-24, -24, 0), Vector3(24, 24, 82) },
                swingTicks = swingTicks,
                history = historyBuffer,
                ghostHistory = engineGhosts,
                btOldest = btOldest,
                btLatest = btLatest
            }
        )

        if inRange then
            _state.aimposVis = point
            if bTick then
                pCmd.tick_count = bTick
                _state.aimBacktrack = true
                -- Show green box at the backtrack record's origin
                if historyBuffer then
                    for _, record in pairs(historyBuffer) do
                        if record.tick == bTick or record.simTick == bTick then
                            _state.vTargetAimPos = record.pos
                            break
                        end
                    end
                end
                if not _state.vTargetAimPos and engineGhosts then
                    for _, record in pairs(engineGhosts) do
                        if record.tick == bTick or record.simTick == bTick then
                            _state.vTargetAimPos = record.pos
                            break
                        end
                    end
                end
            else
                _state.aimBacktrack = false
                _state.vTargetAimPos = _state.vPlayerFuture or _state.vPlayerOrigin
            end
            if aimActive then
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
        else
            _state.aimBacktrack = false
            _state.vTargetAimPos = _state.vPlayerFuture or _state.vPlayerOrigin
        end

        if chargeBotActive then
            -- ChargeBot steering/aim assist is gated by ChargeBot enable + keybind.
            ChargeBot.GetChargeBotAim(
                pLocalClass, pLocal, chargeMeter,
                pLocalOrigin, _state.pLocalFuture, _state.vPlayerFuture, point, inRange,
                (vPlayerOrigin - pLocalOrigin):Length(), { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
            )
        end
    else
        _state.vPlayerFuture    = nil
        _state.vPlayerPath      = nil
        _state.vPlayerPathCount = 0
        -- Note: vTargetHitboxPos is kept from potentialTarget block above for AABB visuals
    end
    profilerEnd()

    -- 6. Charge Control & Reach
    profilerBegin("Tick.Charge")
    if chargeControlActive then
        ChargeBot.ChargeControl(pCmd, pLocal)
    end
    ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeMeter, pLocalClass,
        (pLocal:GetPropInt("m_fFlags") & FL_ONGROUND) ~= 0,
        _state.aimposVis, _state.vPlayerFuture, pLocal:GetAbsOrigin() + _state.vHeight,
        CritManager.IsRefilling())
    profilerEnd()

    -- 7. Crit Management
    profilerBegin("Tick.Crit")
    CritManager.Tick(pCmd, pWeapon, inCombat, isCharging, menuSettings.Misc)
    profilerEnd()
end

local function OnDrawModel(ctx)
    profilerSetContext("frame")
    if not ctx:IsDrawingBackTrack() then return end
    local ent = ctx:GetEntity()
    if not ent or not ent:IsPlayer() then return end

    -- Record the actual rendered position and dynamic bounding box of the backtrack ghost
    profilerBegin("Frame.Ghosts")
    TargetSelector.RecordEngineGhost(ent, ent:GetAbsOrigin(), ent:GetMins(), ent:GetMaxs())
    profilerEnd()
end

local function OnDraw()
    local menuSettings = _menuSettings
    if Profiler and _profilerHealthy and Profiler.SetVisible then
        local showProfiler = menuSettings and menuSettings.Visuals and menuSettings.Visuals.Profiler or false
        safeProfilerCall("SetVisible", Profiler.SetVisible, showProfiler)
    end

    profilerSetContext("frame")
    MenuUI.Render(menuSettings)
    Visuals.Render(menuSettings, _state)
    profilerDraw()
end

local function OnUnload()
    Config.CreateCFG(_menuSettings, "A_Swing_Prediction")
    profilerShutdown()
end

-- --- Initialization ----------------------------------------------------------

local function Init()
    callbacks.Unregister("CreateMove", "Swing_CreateMove")
    callbacks.Unregister("Draw", "Swing_Draw")
    callbacks.Unregister("DrawModel", "Swing_DrawModel")
    callbacks.Unregister("Unload", "Swing_Unload")

    callbacks.Register("CreateMove", "Swing_CreateMove", OnCreateMove)
    callbacks.Register("Draw", "Swing_Draw", OnDraw)
    callbacks.Register("DrawModel", "Swing_DrawModel", OnDrawModel)
    callbacks.Register("Unload", "Swing_Unload", OnUnload)

    print("Swing Prediction v2 Modular Loaded!")
end

Init()
