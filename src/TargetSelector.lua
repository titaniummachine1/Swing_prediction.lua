--[[ Imported by: Main ]]

local lnxLib = require("lnxlib")
local Simulation = require("Simulation")

local TargetSelector = {}

local Math = lnxLib.Utils.Math
local Helpers = lnxLib.TF2.Helpers

-- --- Module state ------------------------------------------------------------

local _players = nil
local _me = nil
local _vHeight = nil
local _swingRange = nil
local _bestTarget = nil

-- --- Initialization ----------------------------------------------------------

function TargetSelector.Init(menu)
    -- TargetSelector currently doesn't need specific menu initialization but kept for parity
end

-- --- Logic -------------------------------------------------------------------

function TargetSelector.SetTickState(players, me, vHeight, swingRange)
    _players = players
    _me = me
    _vHeight = vHeight or Vector3(0, 0, 72)
    _swingRange = swingRange or 48
    _bestTarget = nil
end

function TargetSelector.CalcStrafe()
    if not _players or not _me then return end
    Simulation.CalcStrafe(_players, _me)
end

function TargetSelector.GetStrafeAngle(entityIndex)
    return Simulation.GetStrafeAngle(entityIndex)
end

function TargetSelector.IsVisible(player, fromEntity)
    if not player or not fromEntity then return false end
    return Simulation.IsVisible(player, fromEntity, _vHeight)
end

function TargetSelector.GetBestTarget(me)
    if not _players or not _me then return nil end
    
    local normalCandidates = {}
    local meleeCandidates = {}
    local foundTargetInMeleeRange = false
    
    local myAngles = engine.GetViewAngles()
    local myPos = _me:GetAbsOrigin() + _vHeight
    local meleeRangeThreshold = _swingRange + 50

    for _, player in pairs(_players) do
        if not player or not player:IsValid() then goto continue end
        
        local isInvalid = not player:IsAlive()
            or player:IsDormant()
            or player:GetIndex() == _me:GetIndex()
            or player:GetTeamNumber() == _me:GetTeamNumber()
            or (gui.GetValue("ignore cloaked") == 1 and player:InCond(4))
            or (_me:InCond(17) and (player:GetAbsOrigin().z - _me:GetAbsOrigin().z) > 17)
        
        if isInvalid then goto continue end

        local playerOrigin = player:GetAbsOrigin()
        local distance = (playerOrigin - _me:GetAbsOrigin()):Length()
        
        -- Range Check: Max effective range (swing + buffer)
        if distance > (_swingRange + 100) and not _me:InCond(17) then
            goto continue
        end

        local pViewPos = playerOrigin + Vector3(0, 0, 75)
        local angles = (pViewPos - myPos):Angles()
        local fov = Math.AngleFov(myAngles, angles)

        -- FOV check (using a fixed max FOV for now, could be passed from menu)
        if fov > 360 then goto continue end

        if TargetSelector.IsVisible(player, _me) then
            local visibilityFactor = 1.0
            
            if distance <= meleeRangeThreshold then
                foundTargetInMeleeRange = true
                local fovFactor = Math.RemapValClamped(fov, 0, 360, 1, 0.7)
                table.insert(meleeCandidates, { player = player, factor = fovFactor * visibilityFactor })
            elseif distance <= 770 then
                local distanceFactor = Math.RemapValClamped(distance, 0, 770, 1, 0.9)
                local fovFactor = Math.RemapValClamped(fov, 0, 360, 1, 0.1)
                table.insert(normalCandidates, { player = player, factor = distanceFactor * fovFactor * visibilityFactor })
            end
        end

        ::continue::
    end

    local function chooseBest(cands)
        if #cands == 0 then return nil end
        if #cands > 1 then
            for _, c in ipairs(cands) do
                local p = c.player
                local hp = p:GetHealth() or 0
                local maxhp = p:GetPropInt("m_iMaxHealth") or hp
                local missing = (maxhp > 0) and ((maxhp - hp) / maxhp) or 0
                c.factor = c.factor * (1 + missing)
            end
        end
        local best = cands[1]
        for i = 2, #cands do
            if cands[i].factor > best.factor then best = cands[i] end
        end
        return best.player
    end

    local result = foundTargetInMeleeRange and chooseBest(meleeCandidates) or chooseBest(normalCandidates)
    _bestTarget = result
    return result
end

return TargetSelector
