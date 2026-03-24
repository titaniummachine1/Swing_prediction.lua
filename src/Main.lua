--[[ Imported by: Global ]]

local lnxLib = require("lnxlib")
local Menu = require("Menu")
local Config = require("Config")
local Simulation = require("Simulation")
local TargetSelector = require("TargetSelector")
local CritManager = require("CritManager")
local ChargeBot = require("ChargeBot")
local Visuals = require("Visuals")

-- ─── Constants ───────────────────────────────────────────────────────────────

local MASK_SHOT_HULL = 10067459
local MAX_SPEED = 770

-- ─── Shared State ────────────────────────────────────────────────────────────

if not rawget(_G, "G") then _G.G = {} end
G.IsUpdating = false

local _state = {
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
    totalSwingRange = 48
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function GetWeaponSmackDelay(weapon)
    local defIndex = weapon:GetPropInt("m_iItemDefinitionIndex")
    if defIndex == 43 or defIndex == 239 or defIndex == 1084 or defIndex == 1100 then return 1 -- Gloves
    elseif defIndex == 307 then return 1 -- Caber
    elseif defIndex == 132 or defIndex == 172 or defIndex == 327 or defIndex == 404 or defIndex == 482 then return 18 -- Swords
    end
    return 13 -- Default
end

-- ─── Main Logic ──────────────────────────────────────────────────────────────

local function OnCreateMove(pCmd)
    if G.IsUpdating then return end

    local pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then 
        ChargeBot.Reset()
        return 
    end

    local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon or not pWeapon:IsMeleeWeapon() then return end

    local menuSettings = Menu.GetSettings()
    if not menuSettings.AimbotEnabled then return end

    -- 1. Updates
    local players = entities.GetPlayers()
    Simulation.CalcStrafe(players, pLocal)

    -- 2. Local Prediction
    local swingTime = GetWeaponSmackDelay(pWeapon)
    local isCharging = pLocal:InCond(17)
    local simCharge = isCharging or (pLocal:GetPropFloat("m_flChargeMeter") >= 100)
    
    local simParams = {
        vHeight = _state.vHeight,
        chargeJump = input.IsButtonDown(KEY_SPACE),
        isChargeReachEnabled = menuSettings.ChargeReach
    }

    local localPred = Simulation.PredictPlayer(pLocal, swingTime, 0, simCharge, nil, simParams)
    _state.pLocalOrigin = pLocal:GetAbsOrigin()
    _state.pLocalFuture = localPred.pos[swingTime]
    _state.pLocalPath = localPred.pos
    _state.totalSwingRange = (pLocal:GetPropInt("m_iClass") == 4 and 72 or 48)

    -- 3. Target Selection
    local target = TargetSelector.GetBestTarget(pLocal, players, menuSettings, {
        vHeight = _state.vHeight,
        totalSwingRange = _state.totalSwingRange
    })

    _state.currentTarget = target
    _state.aimposVis = nil
    _state.vPlayerPath = nil

    if target then
        -- 4. Target Prediction
        local targetStrafe = Simulation.GetStrafeAngle(target:GetIndex())
        local targetPred = Simulation.PredictPlayer(target, swingTime, targetStrafe, false, nil, simParams)
        _state.vPlayerOrigin = target:GetAbsOrigin()
        _state.vPlayerFuture = targetPred.pos[swingTime]
        _state.vPlayerPath = targetPred.pos
        
        -- 5. Range Check & Aimbot
        local inRange, point = Simulation.CheckInRangeSimple(
            target:GetIndex(), _state.totalSwingRange, _state.pLocalOrigin, _state.pLocalFuture,
            _state.vPlayerOrigin, _state.vPlayerFuture, target, simParams
        )

        if inRange then
            _state.aimposVis = point
            _state.drawVhitbox = { Vector3(-24,-24,0), Vector3(24,24,82) }
            
            -- Set Angles
            local aimAngles = (point - (_state.pLocalOrigin + _state.vHeight)):Angles()
            pCmd:SetViewAngles(aimAngles)
            if not menuSettings.Silent then
                engine.SetViewAngles(aimAngles)
            end

            -- Attack
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
        end

        -- 6. Charge Steering
        ChargeBot.SteerTowards(pCmd, pLocal, _state.vPlayerOrigin + _state.vHeight, menuSettings)
    end

    -- 7. Crit Management
    CritManager.Tick(pCmd, pWeapon, target ~= nil, menuSettings)

    -- 8. Charge Bot Control
    ChargeBot.HandleChargeControl(pCmd, pLocal, menuSettings)
    ChargeBot.HandleChargeReach(pCmd, pLocal, menuSettings, target and target:GetAbsOrigin(), swingTime)
end

local function OnDraw()
    local menuSettings = Menu.GetSettings()
    Visuals.Render(menuSettings, _state)
end

-- ─── Initialization ──────────────────────────────────────────────────────────

local function Init()
    callbacks.Unregister("CreateMove", "Tim_CreateMove")
    callbacks.Unregister("Draw", "Tim_Draw")
    
    callbacks.Register("CreateMove", "Tim_CreateMove", OnCreateMove)
    callbacks.Register("Draw", "Tim_Draw", OnDraw)
    
    print("Swing Prediction Refactored Loaded!")
end

Init()
