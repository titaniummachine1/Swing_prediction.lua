---@class Entity
---@field IsValid fun(self: Entity): boolean
---@field GetName fun(self: Entity): string
---@field GetClass fun(self: Entity): string
---@field GetIndex fun(self: Entity): integer
---@field GetTeamNumber fun(self: Entity): integer
---@field GetAbsOrigin fun(self: Entity): Vector3
---@field SetAbsOrigin fun(self: Entity, origin: Vector3)
---@field GetAbsAngles fun(self: Entity): EulerAngles
---@field SetAbsAngles fun(self: Entity, angles: Vector3)
---@field GetMins fun(self: Entity): Vector3
---@field GetMaxs fun(self: Entity): Vector3
---@field InCond fun(self: Entity, cond: number): boolean
---@field GetPropInt fun(self: Entity, name: string): number
---@field GetPropFloat fun(self: Entity, name: string): number
---@field EstimateAbsVelocity fun(self: Entity): Vector3
---@field GetWeaponData fun(self: Entity): table
---@field IsAlive fun(self: Entity): boolean
---@field IsDormant fun(self: Entity): boolean



-- Unload the module if it is already loaded
if package.loaded["ImMenu"] then
    package.loaded["ImMenu"] = nil
end

-- Initialize libraries
local lnxLib         = require("lnxlib")
local Config         = require("utils.Config")
local Simulation     = require("Simulation")
local Visuals        = require("Visuals")
local MenuUI         = require("MenuUI")
local ChargeBot      = require("ChargeBot")
local TargetSelector = require("TargetSelector")
local CritManager    = require("CritManager")

local Math           = lnxLib.Utils.Math
local WPlayer        = lnxLib.TF2.WPlayer
local Notify         = lnxLib.UI.Notify

local Menu           = {
    currentTab = 1,
    tabs = { "Aimbot", "Demoknight", "Visuals", "Misc" },

    Aimbot = {
        Aimbot = true,
        Silent = true,
        AimbotFOV = 360,
        SwingTime = 13,
        AlwaysUseMaxSwingTime = false,
        MaxSwingTime = 11,
        ChargeBot = true,
    },

    Charge = {
        ChargeBot = false,
        ChargeControl = false,
        ChargeSensitivity = 1.0,
        ChargeReach = true,
        ChargeJump = true,
        LateCharge = true,
    },

    Visuals = {
        EnableVisuals = true,
        Sphere = false,
        Section = 1,
        Sections = { "Local", "Target", "Experimental" },
        Local = {
            RangeCircle = true,
            path = {
                enable = true,
                Color = { 255, 255, 255, 255 },
                Styles = { "Pavement", "ArrowPath", "Arrows", "L Line", "dashed", "line" },
                Style = 1,
                width = 5,
            },
        },
        Target = {
            path = {
                enable = true,
                Color = { 255, 255, 255, 255 },
                Styles = { "Pavement", "ArrowPath", "Arrows", "L Line", "dashed", "line" },
                Style = 1,
                width = 5,
            },
        },
    },

    Misc = {
        strafePred = true,
        CritRefill = { Active = true, NumCrits = 1 },
        CritMode = 1,
        CritModes = { "Rage", "On Button" },
        InstantAttack = false,
        WarpOnAttack = true,
        TroldierAssist = false,
        advancedHitreg = true,
    },

    Keybind = KEY_NONE,
    KeybindName = "Always On",
}

local Lua__fullPath  = GetScriptName()
local Lua__fileName  = Lua__fullPath:match("([^/\\]+)%.lua$")
if not Lua__fileName or Lua__fileName == "" then
    Lua__fileName = "A_Swing_Prediction"
end

Menu = Config.LoadCFG(Menu, Lua__fileName)

local function CreateCFG(folder_name, cfg)
    return Config.CreateCFG(cfg or Menu, Lua__fileName, folder_name)
end

-- Module init
Simulation.Init(Menu)
ChargeBot.Init(Menu)
TargetSelector.Init(Menu)
CritManager.Init(Menu)

-- Constants
local swingrange            = 48.0
local TotalSwingRange       = 48.0
local SwingHullSize         = 38.0
local SwingHalfhullSize     = SwingHullSize / 2
local Charge_Range          = 128.0
local normalWeaponRange     = 48.0
local normalTotalSwingRange = 48.0
local vHitbox               = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }
local gravity               = client.GetConVar("sv_gravity") or 800
local stepSize              = 18

local function UpdateServerCvars()
    gravity = client.GetConVar("sv_gravity") or 800
    Simulation.UpdatePhysics(gravity, stepSize, vHitbox)
end

UpdateServerCvars()

-- Per-tick variables (reset each tick)
local isMelee                 = false
---@type Entity|nil
local pLocal                  = nil
---@type Entity[]|nil
local players                 = nil
local can_attack              = false
local can_charge              = false
local pLocalPath              = {}
local vPlayerPath             = {}
local drawVhitbox             = {}

local pLocalClass             = nil
local pLocalFuture            = nil
local pLocalOrigin            = nil
---@type Entity|nil
local pWeapon                 = nil
local viewheight              = nil
local Vheight                 = nil
local vPlayerFuture           = nil
local vPlayer                 = nil
local vPlayerOrigin           = nil
local chargeLeft              = nil
---@type Entity|nil
local CurrentTarget           = nil
local aimposVis               = nil
local tickCounterrecharge     = 0

-- Track the tick of the last +attack press (user or script)
local lastAttackTick          = -1000

local dashKeyNotBoundNotified = true

-- Silent aim helper
local function applySilentAttackTick(pCmd, aimAngles)
    if not Menu.Aimbot.Silent or not aimAngles then
        return
    end
    if (pCmd:GetButtons() & IN_ATTACK) == 0 then
        return
    end
    pCmd:SetViewAngles(aimAngles.pitch, aimAngles.yaw, 0)
end

-- Visibility (delegates to TargetSelector)
function IsVisible(player, fromEntity)
    return TargetSelector.IsVisible(player, fromEntity)
end

-- Hit-range helpers
local function checkInRange(targetPos, spherePos, sphereRadius)
    local closestPoint        = Simulation.ClosestPointOnHitbox(targetPos, spherePos)
    local distanceAlongVector = (spherePos - closestPoint):Length()

    if sphereRadius <= distanceAlongVector then
        return false, nil
    end

    if Menu.Misc.advancedHitreg then
        local wr = swingrange
        local hh = SwingHalfhullSize
        if not wr or wr <= 0 or not CurrentTarget then
            return false, nil
        end
        if not Simulation.MeleeSwingCanHit(spherePos, closestPoint, CurrentTarget, wr, hh, pLocal) then
            return false, nil
        end
    end

    return true, closestPoint
end

local function checkInRangeSimple(playerIndex, swingRange, weaponParam, cmd)
    local inRange  = false
    local point    = nil

    inRange, point = checkInRange(vPlayerOrigin, pLocalOrigin, swingRange)
    if inRange then
        return inRange, point, false
    end

    local instantAttackReady = Menu.Misc.InstantAttack and warp.CanWarp() and
        warp.GetChargedTicks() >= Menu.Aimbot.SwingTime
    if instantAttackReady then
        return false, nil, false
    end

    inRange, point = checkInRange(vPlayerFuture, pLocalFuture, swingRange)
    if inRange then
        return inRange, point, false
    end

    return false, nil, false
end

-- OnCreateMove
local function OnCreateMove(pCmd)
    -- Reset per-tick entity references
    pLocal        = nil
    pWeapon       = nil
    players       = nil
    CurrentTarget = nil
    vPlayer       = nil
    pLocalClass   = nil
    pLocalFuture  = nil
    pLocalOrigin  = nil
    vPlayerFuture = nil
    vPlayerOrigin = nil
    chargeLeft    = nil
    aimposVis     = nil
    viewheight    = nil
    Vheight       = nil

    pLocalPath    = {}
    vPlayerPath   = {}
    drawVhitbox   = {}

    isMelee       = false
    can_attack    = false
    can_charge    = false

    pLocal        = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        goto continue
    end

    -- Refresh physics constants
    stepSize = pLocal:GetPropFloat("m_flStepSize") or 18
    Simulation.UpdatePhysics(gravity, stepSize, vHitbox)

    -- Track last +attack tick for charge-reach logic
    if (pCmd:GetButtons() & IN_ATTACK) ~= 0 then
        lastAttackTick = globals.TickCount()
        Simulation.SetLastAttackTick(lastAttackTick)
    end

    pLocalClass = pLocal:GetPropInt("m_iClass")
    chargeLeft  = pLocal:GetPropFloat("m_flChargeMeter")

    -- Charge-reach state machine (Demoman only)
    ChargeBot.TickStateMachine(pCmd, pLocalClass)

    -- Notify if instant attack is on but dash key not bound
    if Menu.Misc.InstantAttack and gui.GetValue("dash move key") == 0 and not dashKeyNotBoundNotified then
        Notify.Simple("Instant Attack Warning", "Dash key is not bound. Instant Attack will not work properly.", 4)
        dashKeyNotBoundNotified = true
    elseif (not Menu.Misc.InstantAttack or gui.GetValue("dash move key") ~= 0) and dashKeyNotBoundNotified then
        dashKeyNotBoundNotified = false
    end

    -- Skip Spy or unclassed
    pLocalClass = pLocal:GetPropInt("m_iClass")
    if pLocalClass == nil or pLocalClass == 8 then
        goto continue
    end

    -- Require active weapon
    pWeapon = pLocal:GetPropEntity("m_hActiveWeapon")
    if not pWeapon then
        goto continue
    end

    do
        local flags           = pLocal:GetPropInt("m_fFlags")
        local airbone         = pLocal:InCond(81)
        chargeLeft            = pLocal:GetPropFloat("m_flChargeMeter")
        chargeLeft            = math.floor(chargeLeft)

        local pWeaponData     = pWeapon:GetWeaponData()
        local pWeaponDefIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex")
        local pWeaponDef      = itemschema.GetItemDefinitionByID(pWeaponDefIndex)

        -- Troldier assist
        if Menu.Misc.TroldierAssist then
            local state = airbone and "slot3" or "slot1"
            if airbone then
                pCmd:SetButtons(pCmd.buttons | IN_DUCK)
            end
            client.Command(state, true)
        end

        -- Only continue for melee weapons
        isMelee = pWeapon:IsMeleeWeapon()
        if not isMelee then
            goto continue
        end

        -- Eye position
        local viewOffset                       = pLocal:GetPropVector("localdata", "m_vecViewOffset[0]")
        local adjustedHeight                   = pLocal:GetAbsOrigin() + viewOffset
        viewheight                             = (adjustedHeight - pLocal:GetAbsOrigin()):Length()
        Vheight                                = Vector3(0, 0, viewheight)
        pLocalOrigin                           = pLocal:GetAbsOrigin() + Vheight

        -- Swing range
        local weaponSwingRange, weaponHullSize = Simulation.ResolveMeleeParams(pWeapon, pWeaponDef)
        swingrange                             = weaponSwingRange
        SwingHullSize                          = weaponHullSize
        SwingHalfhullSize                      = SwingHullSize / 2

        local isCurrentlyCharging              = pLocal:InCond(17)
        if not isCurrentlyCharging then
            normalWeaponRange     = swingrange or normalWeaponRange
            normalTotalSwingRange = swingrange + (SwingHullSize / 2)
        end

        local hasFullCharge     = chargeLeft == 100
        local isDemoman         = pLocalClass == 4
        local isExploitReady    = Menu.Charge.ChargeReach and hasFullCharge and isDemoman
        local attackWindowTicks = Menu.Aimbot.MaxSwingTime or 13
        if pWeaponData and pWeaponData.smackDelay then
            attackWindowTicks = Simulation.smackDelayToTicks(pWeaponData.smackDelay)
        end
        local withinAttackWindow = (globals.TickCount() - lastAttackTick) <= attackWindowTicks

        if isCurrentlyCharging then
            local isDoingExploit = Menu.Charge.ChargeReach and withinAttackWindow
            if isDoingExploit then
                swingrange      = Charge_Range
                TotalSwingRange = Charge_Range + (SwingHullSize / 2)
            else
                swingrange      = normalWeaponRange or swingrange
                TotalSwingRange = normalTotalSwingRange
            end
        else
            if isExploitReady then
                swingrange      = Charge_Range
                TotalSwingRange = Charge_Range + (SwingHullSize / 2)
            else
                TotalSwingRange = swingrange + (SwingHullSize / 2)
            end
        end

        -- ChargeControl (mouse steering while charging)
        if Menu.Charge.ChargeControl and pLocal:InCond(17) then
            ChargeBot.ChargeControl(pCmd, pLocal)
        end

        -- Target selection
        local keybind = Menu.Keybind
        players = entities.FindByClass("CTFPlayer")

        TargetSelector.SetTickState(players, pLocal, Vheight or Vector3(0, 0, 72), TotalSwingRange)
        TargetSelector.CalcStrafe()

        if keybind == 0 then
            CurrentTarget = TargetSelector.GetBestTarget(pLocal)
            vPlayer       = CurrentTarget
        elseif input.IsButtonDown(keybind) then
            CurrentTarget = TargetSelector.GetBestTarget(pLocal)
            vPlayer       = CurrentTarget
        else
            CurrentTarget = nil
            vPlayer       = nil
        end

        -- Crit refill
        CritManager.Tick(pCmd, pWeapon, CurrentTarget ~= nil)

        local OnGround = (flags & FL_ONGROUND) ~= 0
        can_attack = false

        -- Charge-jump (manual with right-click)
        if Menu.Charge.ChargeJump and pLocalClass == 4 then
            if (pCmd:GetButtons() & IN_ATTACK2) ~= 0 and chargeLeft == 100 and OnGround then
                pCmd:SetButtons(pCmd:GetButtons() | IN_JUMP)
            end
        end

        -- Refresh physics before prediction
        gravity                  = client.GetConVar("sv_gravity") or 800
        stepSize                 = pLocal:GetPropFloat("m_flStepSize") or stepSize

        -- Prediction setup
        local instantAttackReady = Menu.Misc.InstantAttack and warp.CanWarp() and
            warp.GetChargedTicks() >= Menu.Aimbot.SwingTime
        local simulateCharge     = (not isCurrentlyCharging) and isExploitReady and (not Menu.Charge.LateCharge)
        local simTicks           = Menu.Aimbot.SwingTime
        if not instantAttackReady and not simulateCharge then
            local remSwing = Simulation.getMeleeSwingTicksRemaining(pWeapon)
            if remSwing then
                simTicks = math.max(remSwing, 1)
            end
        end

        -- Local player prediction (deferred for charge case until target is known)
        local chargeNeedsPrediction = simulateCharge
        local velIsZero = pLocal:EstimateAbsVelocity():Length() < 1
        if velIsZero then
            pLocalFuture          = pLocalOrigin
            chargeNeedsPrediction = false
        elseif not chargeNeedsPrediction then
            local player        = WPlayer.FromEntity(pLocal)
            local useStrafePred = Menu.Misc.strafePred and not (instantAttackReady and Menu.Misc.WarpOnAttack)
            local strafeAngle   = useStrafePred and TargetSelector.GetStrafeAngle(pLocal:GetIndex()) or 0

            local predData      = Simulation.PredictPlayer(player, simTicks, strafeAngle, false, nil)
            if not predData then return end

            pLocalPath   = predData.pos
            pLocalFuture = predData.pos[simTicks] + viewOffset
        end

        -- Stop if no target
        if CurrentTarget == nil then
            return
        end

        if not (CurrentTarget and CurrentTarget:IsValid() and CurrentTarget:IsAlive() and not CurrentTarget:IsDormant()) then
            return
        end

        vPlayerOrigin = CurrentTarget:GetAbsOrigin()

        -- Deferred charge prediction: use aimbot yaw toward target
        if chargeNeedsPrediction then
            local player        = WPlayer.FromEntity(pLocal)
            local useStrafePred = Menu.Misc.strafePred and not (instantAttackReady and Menu.Misc.WarpOnAttack)
            local strafeAngle   = useStrafePred and TargetSelector.GetStrafeAngle(pLocal:GetIndex()) or 0

            local targetEyePos  = vPlayerOrigin + Vheight
            local aimYaw        = Math.PositionAngles(pLocalOrigin, targetEyePos).yaw
            local fixedAngles   = EulerAngles(0, aimYaw, 0)

            local predData      = Simulation.PredictPlayer(player, simTicks, strafeAngle, true, fixedAngles)
            if not predData then return end

            pLocalPath   = predData.pos
            pLocalFuture = predData.pos[simTicks] + viewOffset
        end

        -- Adjust hitbox for ducking target
        local VpFlags = CurrentTarget:GetPropInt("m_fFlags")
        local DUCKING = (VpFlags & FL_DUCKING) ~= 0
        if DUCKING then
            vHitbox[2].z = 62
        else
            vHitbox[2].z = 82
        end

        -- Enemy prediction
        if not instantAttackReady then
            local player = WPlayer.FromEntity(CurrentTarget)
            local strafeAngle = TargetSelector.GetStrafeAngle(CurrentTarget:GetIndex())
            local predData = Simulation.PredictPlayer(player, simTicks, strafeAngle, false, nil)
            if not predData then return end

            vPlayerPath    = predData.pos
            vPlayerFuture  = predData.pos[simTicks]
            drawVhitbox[1] = vPlayerFuture + vHitbox[1]
            drawVhitbox[2] = vPlayerFuture + vHitbox[2]
        else
            vPlayerFuture  = CurrentTarget:GetAbsOrigin()
            drawVhitbox[1] = vPlayerFuture + vHitbox[1]
            drawVhitbox[2] = vPlayerFuture + vHitbox[2]
        end

        -- Distance check
        local fDistance = (vPlayerFuture - pLocalFuture):Length()

        -- Range check
        local inRangePoint
        do
            local inR, iRP, chg = false, nil, false
            if CurrentTarget and CurrentTarget.GetIndex then
                inR, iRP, chg = checkInRangeSimple(CurrentTarget:GetIndex(), TotalSwingRange, pWeapon, pCmd)
                do
                    local inR, iRP, chg = checkInRangeSimple(CurrentTarget:GetIndex(), TotalSwingRange, pWeapon, pCmd)
                    inRangePoint        = iRP
                    can_attack          = inR
                    can_charge          = chg
                end
                local aim_angles = nil
                if inRangePoint then
                    aimposVis  = inRangePoint
                    aim_angles = Math.PositionAngles(pLocalOrigin, inRangePoint)
                end

                -- ChargeBot steering (modifies engine angles directly, does not return aim_angles)
                ChargeBot.GetChargeBotAim(
                    pLocalClass,
                    pLocal,
                    chargeLeft,
                    pLocalOrigin or Vector3(0, 0, 0),
                    pLocalFuture or Vector3(0, 0, 0),
                    vPlayerFuture or Vector3(0, 0, 0),
                    inRangePoint or Vector3(0, 0, 0),
                    can_attack,
                    fDistance,
                    vHitbox
                )

                -- Normal silent/overt aim when in range
                if can_attack and aim_angles and aim_angles.pitch and aim_angles.yaw then
                    if not Menu.Aimbot.Silent then
                        engine.SetViewAngles(EulerAngles(aim_angles.pitch, aim_angles.yaw, 0))
                    end
                end
            end

            -- Attack logic
            local weaponSmackDelay = 13
            if can_attack then
                ::continue::
                return
            end
            if pWeapon and pWeapon:GetWeaponData() then
                local weaponData = pWeapon:GetWeaponData()
                if weaponData and weaponData.smackDelay then
                    weaponSmackDelay = Simulation.smackDelayToTicks(weaponData.smackDelay)

                    if Menu.Aimbot.SwingTime ~= weaponSmackDelay then
                        local oldValue = Menu.Aimbot.SwingTime or 13
                        if Menu.Aimbot.AlwaysUseMaxSwingTime or oldValue >= (Menu.Aimbot.MaxSwingTime or 13) then
                            Menu.Aimbot.SwingTime = weaponSmackDelay
                        end
                        Menu.Aimbot.MaxSwingTime = weaponSmackDelay

                        local pWDef              = itemschema.GetItemDefinitionByID(pWeapon:GetPropInt(
                            "m_iItemDefinitionIndex"))
                        local pWName             = (pWDef and pWDef:GetName()) or "Unknown"
                        Notify.Simple(string.format(
                            "Updated SwingTime for %s:\n - Old: %d ticks\n - New: %d ticks\n - Delay: %.2f s",
                            pWName, oldValue, Menu.Aimbot.SwingTime or weaponSmackDelay, weaponData.smackDelay
                        ))
                    end
                end
            end

            local scheduledAimAngles
            if inRangePoint then
                scheduledAimAngles = Math.PositionAngles(pLocalOrigin, inRangePoint)
            else
                scheduledAimAngles = Math.PositionAngles(pLocalOrigin, vPlayerFuture)
            end

            if Menu.Misc.InstantAttack and instantAttackReady and Menu.Misc.WarpOnAttack then
                local velocity = pLocal:EstimateAbsVelocity()
                local oppositePoint
                if velocity:Length() > 10 then
                    oppositePoint = pLocal:GetAbsOrigin() - velocity
                else
                    local angles  = engine.GetViewAngles()
                    local forward = angles:Forward()
                    oppositePoint = pLocal:GetAbsOrigin() + forward * 20
                end
                if oppositePoint and (oppositePoint - pLocal:GetAbsOrigin()):Length() < 300 then
                    Simulation.WalkTo(pCmd, pLocal, oppositePoint)
                end

                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                applySilentAttackTick(pCmd, scheduledAimAngles)

                client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
                local safeTickValue = math.min(weaponSmackDelay, 20)
                client.SetConVar("sv_maxusrcmdprocessticks", safeTickValue)

                local chargedTicks = warp.GetChargedTicks() or 0
                if chargedTicks >= safeTickValue then
                    warp.TriggerWarp()
                else
                    client.ChatPrintf("[Debug] Instant Attack: Not enough ticks (" ..
                        chargedTicks .. "/" .. safeTickValue .. "), normal attack")
                end
                can_attack = false
            elseif Menu.Misc.InstantAttack and instantAttackReady and not Menu.Misc.WarpOnAttack then
                client.ChatPrintf("[Debug] Instant Attack: Warp disabled, using normal attack")
                local normalAttackTicks = math.min(weaponSmackDelay, 24)
                client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
                client.SetConVar("sv_maxusrcmdprocessticks", normalAttackTicks)
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                applySilentAttackTick(pCmd, scheduledAimAngles)
                can_attack = false
            else
                local normalAttackTicks = math.min(weaponSmackDelay, 24)
                client.RemoveConVarProtection("sv_maxusrcmdprocessticks")
                client.SetConVar("sv_maxusrcmdprocessticks", normalAttackTicks)
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
                applySilentAttackTick(pCmd, scheduledAimAngles)

                -- Arm charge-reach exploit
                ChargeBot.ArmChargeReach(pLocalClass, chargeLeft)
                can_attack = false
            end

            -- Fire charge-reach IN_ATTACK2 when timing window is met
            ChargeBot.UpdateChargeReach(pCmd, pWeapon, chargeLeft, pLocalClass, OnGround)
        end

        vHitbox[2].z = 82
    end

    ::continue::
end

-- Draw
local function doDraw()
    MenuUI.Render(Menu)

    if not (engine.Con_IsVisible() or engine.IsGameUIVisible()) and Menu.Visuals.EnableVisuals then
        local drawPLocal = entities.GetLocalPlayer()
        if drawPLocal and drawPLocal:IsAlive() then
            local drawPWeapon = drawPLocal:GetPropEntity("m_hActiveWeapon")
            if drawPWeapon and drawPWeapon:IsMeleeWeapon() then
                Visuals.Render(Menu, {
                    pLocalFuture    = pLocalFuture,
                    pLocalOrigin    = pLocalOrigin,
                    Vheight         = Vheight,
                    TotalSwingRange = TotalSwingRange,
                    pLocalPath      = pLocalPath,
                    vPlayerPath     = vPlayerPath,
                    vPlayerFuture   = vPlayerFuture,
                    CurrentTarget   = CurrentTarget,
                    drawVhitbox     = drawVhitbox,
                    aimposVis       = aimposVis,
                })
            end
        end
    end
end

-- Unload
local function OnUnload()
    local unloadLib = rawget(_G, "UnloadLib")
    if type(unloadLib) == "function" then
        unloadLib()
    end
    CreateCFG(string.format([[Lua %s]], Lua__fileName), Menu)
    client.Command('play "ui/buttonclickrelease"', true)
end

-- Events
local function damageLogger(event)
    UpdateServerCvars()
    if event:GetName() ~= 'player_hurt' then return end

    local victim      = entities.GetByUserID(event:GetInt("userid"))
    local attacker    = entities.GetByUserID(event:GetInt("attacker"))
    local localPlayer = entities.GetLocalPlayer()

    if attacker == nil or not localPlayer or localPlayer:GetName() ~= attacker:GetName() then
        return
    end
    local damage = event:GetInt("damageamount")
    if not victim then return end
    if damage <= victim:GetHealth() then return end

    if Menu.Misc.InstantAttack and warp.GetChargedTicks() < 13 and not warp.IsWarping() then
        warp.TriggerCharge()
        tickCounterrecharge = 0
    end
end

-- Callbacks
callbacks.Unregister("CreateMove", "MCT_CreateMove")
callbacks.Unregister("FireGameEvent", "adaamaXDgeLogger")
callbacks.Unregister("Unload", "MCT_Unload")
callbacks.Unregister("Draw", "MCT_Draw")

callbacks.Register("CreateMove", "MCT_CreateMove", OnCreateMove)
callbacks.Register("FireGameEvent", "adaamaXDgeLogger", damageLogger)
callbacks.Register("Unload", "MCT_Unload", OnUnload)
callbacks.Register("Draw", "MCT_Draw", doDraw)

client.Command('play "ui/buttonclick"', true)
