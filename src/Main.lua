--[[ Swing prediction Refactoring v2 ]]
--[[ Author: Terminator ]]

-- Unload if existing
if package.loaded["A_Swing_Prediction"] then
    package.loaded["A_Swing_Prediction"] = nil
end

---- Initialize libraries
local lnxLib         = require("lnxlib")
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

-- Shared State
local _menuSettings  = Config.LoadCFG(DefaultConfig.Menu, "A_Swing_Prediction")
local _state         = {
    pLocalOrigin = nil,
    pLocalFuture = nil,
    pLocalPath = nil,
    vPlayerOrigin = nil,
    vPlayerFuture = nil,
    vPlayerPath = nil,
    currentTarget = nil,
    aimposVis = nil,
    drawVhitbox = nil,
    vHeight = Vector3(0, 0, 75),
    totalSwingRange = 48,
    lastAttackTick = -1000
}

-- --- Initialization ----------------------------------------------------------

Simulation.Init(_menuSettings)
ChargeBot.Init(_menuSettings)
TargetSelector.Init(_menuSettings)
CritManager.Init(_menuSettings)

-- --- Helpers -----------------------------------------------------------------

local function applySilentAttackTick(pCmd, aimAngles, settings)
    if not settings.Aimbot.Silent or not aimAngles then return end
    if (pCmd:GetButtons() & IN_ATTACK) == 0 then return end
    pCmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
end

-- --- Main Logic --------------------------------------------------------------

local function OnCreateMove(pCmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        ChargeBot.Reset()
        return
    end

    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon then return end

    local menuSettings = _menuSettings
    if not menuSettings.Aimbot.Aimbot then return end

    -- 1. Updates & State
    local players = entities.FindByClass("CTFPlayer")
    _state.vHeight = Vector3(0, 0, pLocal:GetPropVector("localdata", "m_vecViewOffset[0]").z)

    local swingRange, hullSize = Simulation.ResolveMeleeParams(pWeapon)
    _state.totalSwingRange = swingRange + (hullSize / 2)

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
    local smackDelay = pWeapon:GetPropFloat("m_flNextPrimaryAttack") - globals.CurTime()
    local swingTicks = Simulation.smackDelayToTicks(smackDelay > 0 and smackDelay or 0.2)

    if target then
        local pLocalOrigin = pLocal:GetAbsOrigin() + _state.vHeight
        local vPlayerOrigin = target:GetAbsOrigin()

        -- Predict target
        local targetStrafe = TargetSelector.GetStrafeAngle(target:GetIndex())
        local targetPred = Simulation.PredictPlayer(target, swingTicks, targetStrafe, false, nil, {
            vHeight = _state.vHeight,
            gravity = client.GetConVar("sv_gravity")
        })

        -- ... rest of target prediction ...
        _state.vPlayerOrigin = vPlayerOrigin
        _state.vPlayerFuture = targetPred.pos[swingTicks]
        _state.vPlayerPath = targetPred.pos

        -- Predict local
        local isCharging = pLocal:InCond(17)
        local localPred = Simulation.PredictPlayer(pLocal, swingTicks, 0, isCharging, nil, {
            vHeight = _state.vHeight,
            gravity = client.GetConVar("sv_gravity")
        })
        _state.pLocalOrigin = pLocal:GetAbsOrigin()
        _state.pLocalFuture = localPred.pos[swingTicks]
        _state.pLocalPath = localPred.pos

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

            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            applySilentAttackTick(pCmd, aimAngles, menuSettings)
            if not menuSettings.Aimbot.Silent then
                engine.SetViewAngles(EulerAngles(aimAngles.pitch, aimAngles.yaw, 0))
            end
        end

        -- ChargeBot Steering
        ChargeBot.GetChargeBotAim(
            pLocal:GetPropInt("m_iClass"), pLocal, pLocal:GetPropFloat("m_flChargeMeter"),
            pLocalOrigin, _state.pLocalFuture, _state.vPlayerFuture, point, inRange,
            (vPlayerOrigin - pLocalOrigin):Length(), { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
        )
    end

    -- 6. Charge Control & Reach
    if chargeActive then
        ChargeBot.ChargeControl(pCmd, pLocal)
    end
    ChargeBot.UpdateChargeReach(pCmd, pWeapon, pLocal:GetPropFloat("m_flChargeMeter"), pLocal:GetPropInt("m_iClass"),
        (pLocal:GetPropInt("m_fFlags") & FL_ONGROUND) ~= 0)

    -- 7. Crit Management
    CritManager.Tick(pCmd, pWeapon, target ~= nil, menuSettings.Misc)
end

local function OnDraw()
    local menuSettings = _menuSettings
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
