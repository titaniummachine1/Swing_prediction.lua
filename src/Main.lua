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

-- --- Helpers -----------------------------------------------------------------

local function applySilentAttackTick(pCmd, aimAngles, settings)
    if not settings.Aimbot.Silent or not aimAngles then return end
    if (pCmd:GetButtons() & IN_ATTACK) == 0 then return end
    -- pCmd:SetViewAngles on some versions expects numbers, not an object
    pCmd:SetViewAngles(aimAngles.x, aimAngles.y, 0)
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

    local swingRange, hullSize = Simulation.ResolveMeleeParams(pWeapon)
    local isCharging = pLocal:InCond(17)
    local chargeMeter = pLocal:GetPropFloat("m_flChargeMeter")
    local pLocalClass = pLocal:GetPropInt("m_iClass")
    local isDemoman = pLocalClass == 4

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
            -- Note: We use exploit range for target selection/aimbot even before charging
            -- because the aimbot will trigger the charge-reach exploit.
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
    local simulateChargeNoTarget = (not isCharging) and isExploitReady and (not menuSettings.Charge.LateCharge) and (target ~= nil)
    local fixedAnglesLocal = nil
    if simulateChargeNoTarget and target then
        local a = (target:GetAbsOrigin() - pLocal:GetAbsOrigin()):Angles()
        fixedAnglesLocal = EulerAngles(a.x, a.y, 0)
    end
    local localPred = Simulation.PredictPlayer(pLocal, swingTicks, 0, simulateChargeNoTarget or isCharging, fixedAnglesLocal, {
        vHeight = _state.vHeight,
        gravity = client.GetConVar("sv_gravity")
    })
    _state.pLocalOrigin = pLocal:GetAbsOrigin()
    _state.pLocalFuture = localPred.pos[swingTicks]
    _state.pLocalPath   = localPred.pos

    if target then
        local vPlayerOrigin = target:GetAbsOrigin()

        -- Predict target
        local targetStrafe = TargetSelector.GetStrafeAngle(target:GetIndex())
        local targetPred = Simulation.PredictPlayer(target, swingTicks, targetStrafe, false, nil, {
            vHeight = _state.vHeight,
            gravity = client.GetConVar("sv_gravity")
        })

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
