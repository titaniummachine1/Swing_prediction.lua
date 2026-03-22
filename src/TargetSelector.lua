local Simulation       = require("Simulation")

local TargetSelector   = {}

-- ─── Module state ──────────────────────────────────────────────────────────────

---@class MenuAimbot
---@field AimbotFOV number

---@class Menu
---@field Aimbot MenuAimbot

---@type Menu|nil
local _menu            = nil

-- Strafe-deviation tracking tables (per-entity, keyed by entity index)
local _lastAngles      = {} ---@type table<number, EulerAngles>
local _lastDeltas      = {} ---@type table<number, number>
local _avgDeltas       = {} ---@type table<number, number>
local _strafeAngles    = {} ---@type table<number, number>
local _inaccuracy      = {} ---@type table<number, number>
local _pastPositions   = {}
local _maxPositions    = 4

---@class TargetSelectorMenu
---@field Aimbot table
local _players         = nil
local _pLocal          = nil
local _Vheight         = nil
local _TotalSwingRange = 48.0
local _settings        = { MinDistance = 0, MaxDistance = 770, MinFOV = 0, MaxFOV = 360 }

-- ─── Init ─────────────────────────────────────────────────────────────────────

function TargetSelector.Init(menuRef)
    assert(menuRef, "TargetSelector.Init: menuRef is nil")
    _menu = menuRef
end

---@param players      table
---@param pLocal       Entity
---@param Vheight      Vector3
---@param TotalSwingRange number
function TargetSelector.SetTickState(players, pLocal, Vheight, TotalSwingRange)
    assert(players, "TargetSelector.SetTickState: players is nil")
    assert(pLocal, "TargetSelector.SetTickState: pLocal is nil")
    assert(Vheight, "TargetSelector.SetTickState: Vheight is nil")
    assert(TotalSwingRange, "TargetSelector.SetTickState: TotalSwingRange is nil")
    _players         = players
    _pLocal          = pLocal
    _Vheight         = Vheight
    _TotalSwingRange = TotalSwingRange
    if _menu and _menu.Aimbot then
        _settings.MaxFOV = _menu.Aimbot.AimbotFOV
    end
end

-- ─── Strafe angle read-back ───────────────────────────────────────────────────

function TargetSelector.GetStrafeAngle(entityIndex)
    return _strafeAngles[entityIndex] or 0
end

-- ─── Visibility helpers ───────────────────────────────────────────────────────

local function VisPos(target, from, to)
    local trace = engine.TraceLine(from, to, MASK_SHOT | CONTENTS_GRATE)
    return (trace.entity == target) or (trace.fraction > 0.99)
end

local function IsVisible(player, fromEntity)
    assert(player, "TargetSelector.IsVisible: player is nil")
    assert(fromEntity, "TargetSelector.IsVisible: fromEntity is nil")
    local from = fromEntity:GetAbsOrigin() + _Vheight
    local to   = player:GetAbsOrigin() + _Vheight
    return VisPos(player, from, to)
end

-- Exported so Main/other modules can call it if needed
function TargetSelector.IsVisible(player, fromEntity)
    return IsVisible(player, fromEntity)
end

-- ─── CalcStrafe ───────────────────────────────────────────────────────────────
-- Updates _strafeAngles for all players. Call once per tick after SetTickState.

function TargetSelector.CalcStrafe()
    assert(_players, "TargetSelector.CalcStrafe: call SetTickState first")
    assert(_pLocal, "TargetSelector.CalcStrafe: call SetTickState first")

    local autostrafe = gui.GetValue("Auto Strafe")
    local flags      = _pLocal:GetPropInt("m_fFlags")
    local OnGround   = (flags & FL_ONGROUND) ~= 0

    for _, entity in pairs(_players) do
        local entityIndex = entity:GetIndex()

        if entity:IsDormant() or not entity:IsAlive() then
            _lastAngles[entityIndex]   = nil
            _lastDeltas[entityIndex]   = nil
            _avgDeltas[entityIndex]    = nil
            _strafeAngles[entityIndex] = nil
            _inaccuracy[entityIndex]   = nil
            goto continue
        end

        local v = entity:EstimateAbsVelocity()
        if entity == _pLocal then
            table.insert(_pastPositions, 1, entity:GetAbsOrigin())
            if #_pastPositions > _maxPositions then
                table.remove(_pastPositions)
            end

            if not OnGround and autostrafe == 2 and #_pastPositions >= _maxPositions then
                v = Vector3(0, 0, 0)
                for i = 1, #_pastPositions - 1 do
                    v = v + (_pastPositions[i] - _pastPositions[i + 1])
                end
                v = v / (_maxPositions - 1)
            else
                v = entity:EstimateAbsVelocity()
            end
        end

        local angle = v:Angles()

        if _lastAngles[entityIndex] == nil then
            _lastAngles[entityIndex] = angle
            goto continue
        end

        local delta                = angle.y - _lastAngles[entityIndex].y
        local smoothingFactor      = 0.2
        local avgDelta             = (_lastDeltas[entityIndex] or delta) * (1 - smoothingFactor) +
            delta * smoothingFactor

        _avgDeltas[entityIndex]    = avgDelta

        local vector1              = Vector3(1, 0, 0)
        local vector2              = Vector3(1, 0, 0)

        local ang1                 = vector1:Angles()
        ang1.y                     = ang1.y + (_lastDeltas[entityIndex] or delta)
        vector1                    = ang1:Forward() * vector1:Length()

        local ang2                 = vector2:Angles()
        ang2.y                     = ang2.y + avgDelta
        vector2                    = ang2:Forward() * vector2:Length()

        local distance             = (vector1 - vector2):Length()
        _strafeAngles[entityIndex] = avgDelta
        _inaccuracy[entityIndex]   = distance
        _lastDeltas[entityIndex]   = delta
        _lastAngles[entityIndex]   = angle

        ::continue::
    end
end

-- ─── GetBestTarget ────────────────────────────────────────────────────────────
---@param me Entity  local player entity
---@return Entity|nil
function TargetSelector.GetBestTarget(me)
    assert(me, "TargetSelector.GetBestTarget: me is nil")
    assert(_players, "TargetSelector.GetBestTarget: call SetTickState first")

    local lnxLib                  = require("lnxLib")
    local Math                    = lnxLib.Utils.Math
    local Helpers                 = lnxLib.TF2.Helpers

    local normalCandidates        = {}
    local meleeCandidates         = {}

    local meleeRangeThreshold     = _TotalSwingRange + 50
    local foundTargetInMeleeRange = false

    local localPlayerViewAngles   = engine.GetViewAngles()
    local localPlayerOrigin       = me:GetAbsOrigin()
    local localPlayerEyePos       = localPlayerOrigin + Vector3(0, 0, 75)
    local effectiveFOV            = 360
    if _menu and _menu.Aimbot and _menu.Aimbot.AimbotFOV then
        effectiveFOV = _menu.Aimbot.AimbotFOV
    end

    for _, player in pairs(_players) do
        local isInvalid = player == nil
            or not player:IsValid()
            or not player:IsAlive()
            or player:IsDormant()
            or player == me
            or player:GetTeamNumber() == me:GetTeamNumber()
            or (gui.GetValue("ignore cloaked") == 1 and player:InCond(4))
            or (me:InCond(17) and (player:GetAbsOrigin().z - me:GetAbsOrigin().z) > 17)
            or not IsVisible(player, me)
        if isInvalid then
            goto continue
        end

        local playerOrigin = player:GetAbsOrigin()
        local distance     = (playerOrigin - localPlayerOrigin):Length()
        local Pviewoffset  = player:GetPropVector("localdata", "m_vecViewOffset[0]")
        local Pviewpos     = playerOrigin + Pviewoffset

        local angles       = Math.PositionAngles(localPlayerOrigin, Pviewpos)
        local fov          = Math.AngleFov(localPlayerViewAngles, angles)
        if fov > effectiveFOV then
            goto continue
        end

        local isVisible        = Helpers.VisPos(player, localPlayerEyePos, playerOrigin + Vector3(0, 0, 75))
        local visibilityFactor = isVisible and 1 or 0.1

        if distance <= meleeRangeThreshold then
            foundTargetInMeleeRange = true
            local meleeFovFactor    = Math.RemapValClamped(fov, 0, effectiveFOV, 1, 0.7)
            local factor            = meleeFovFactor * visibilityFactor
            table.insert(meleeCandidates, { player = player, factor = factor })
        elseif distance <= 770 then
            local distanceFactor = Math.RemapValClamped(distance, _settings.MinDistance, _settings.MaxDistance, 1, 0.9)
            local fovFactor      = Math.RemapValClamped(fov, 0, effectiveFOV, 1, 0.1)
            local factor         = distanceFactor * fovFactor * visibilityFactor
            table.insert(normalCandidates, { player = player, factor = factor })
        end

        ::continue::
    end

    local function chooseBest(cands)
        if #cands == 0 then return nil end
        if #cands > 1 then
            for _, c in pairs(cands) do
                local p       = c.player
                local hp      = p:GetHealth() or 0
                local maxhp   = p:GetPropInt("m_iMaxHealth") or hp
                local missing = (maxhp > 0) and ((maxhp - hp) / maxhp) or 0
                c.factor      = c.factor * (1 + missing)
            end
        end
        local best = cands[1]
        for i = 2, #cands do
            if cands[i].factor > best.factor then
                best = cands[i]
            end
        end
        return best.player
    end

    if foundTargetInMeleeRange then
        return chooseBest(meleeCandidates)
    else
        return chooseBest(normalCandidates)
    end
end

return TargetSelector
