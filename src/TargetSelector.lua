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
    
    local bestTarget = nil
    local bestFOV = 360 -- Initialize with max FOV
    local localAngles = engine.GetViewAngles()
    local myPos = _me:GetAbsOrigin() + _vHeight

    for _, player in pairs(_players) do
        if not player or not player:IsValid() then goto continue end
        
        local isInvalid = not player:IsAlive()
            or player:IsDormant()
            or player:GetIndex() == _me:GetIndex()
            or player:GetTeamNumber() == _me:GetTeamNumber()
            or (gui.GetValue("ignore cloaked") == 1 and player:InCond(4))
        
        if isInvalid then goto continue end

        local playerOrigin = player:GetAbsOrigin()
        local distance = (playerOrigin - _me:GetAbsOrigin()):Length()
        
        -- Range Check: Max effective range (swing + buffer)
        if distance > (_swingRange + 100) and not _me:InCond(17) then
            goto continue
        end

        local pViewPos = playerOrigin + Vector3(0, 0, 75)
        local angles = (pViewPos - myPos):Angles()
        local fov = Math.AngleFov(localAngles, angles)

        if fov < bestFOV then
            if TargetSelector.IsVisible(player, _me) then
                bestFOV = fov
                bestTarget = player
            end
        end

        ::continue::
    end

    _bestTarget = bestTarget
    return bestTarget
end

return TargetSelector
