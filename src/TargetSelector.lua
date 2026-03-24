--[[ Imported by: Main ]]

local lnxLib = require("lnxlib")
local Simulation = require("Simulation")

local TargetSelector = {}

local Math = lnxLib.Utils.Math
local Helpers = lnxLib.TF2.Helpers

-- ─── Target Selection ────────────────────────────────────────────────────────

function TargetSelector.GetBestTarget(me, players, menuSettings, params)
    assert(me, "TargetSelector.GetBestTarget: me missing")
    assert(players, "TargetSelector.GetBestTarget: players list missing")
    assert(menuSettings, "TargetSelector.GetBestTarget: menuSettings missing")
    assert(params, "TargetSelector.GetBestTarget: params missing")

    local normalCandidates = {}
    local meleeCandidates = {}

    local totalSwingRange = params.totalSwingRange or 48
    local meleeRangeThreshold = totalSwingRange + 50
    local foundTargetInMeleeRange = false

    local localPlayerViewAngles = engine.GetViewAngles()
    local localPlayerOrigin = me:GetAbsOrigin()
    local localPlayerEyePos = localPlayerOrigin + (params.vHeight or Vector3(0, 0, 75))

    local effectiveFOV = menuSettings.AimbotFOV or 360

    for _, player in pairs(players) do
        if not player or not player:IsValid() then goto continue end
        
        local isInvalid = not player:IsAlive()
            or player:IsDormant()
            or player:GetIndex() == me:GetIndex()
            or player:GetTeamNumber() == me:GetTeamNumber()
            or (gui.GetValue("ignore cloaked") == 1 and player:InCond(4))
            or (me:InCond(17) and (player:GetAbsOrigin().z - me:GetAbsOrigin().z) > 17)
            or not Simulation.IsVisible(player, me, params.vHeight or Vector3(0, 0, 75))
        
        if isInvalid then
            goto continue
        end

        local playerOrigin = player:GetAbsOrigin()
        local distance = (playerOrigin - localPlayerOrigin):Length()
        local pViewOffset = player:GetPropVector("localdata", "m_vecViewOffset[0]")
        local pViewPos = playerOrigin + pViewOffset

        local angles = Math.PositionAngles(localPlayerOrigin, pViewPos)
        local fov = Math.AngleFov(localPlayerViewAngles, angles)
        if fov > effectiveFOV then
            goto continue
        end

        local isVisible = Helpers.VisPos(player, localPlayerEyePos, playerOrigin + Vector3(0, 0, 75))
        local visibilityFactor = isVisible and 1 or 0.1

        if distance <= meleeRangeThreshold then
            foundTargetInMeleeRange = true
            local meleeFovFactor = Math.RemapValClamped(fov, 0, effectiveFOV, 1, 0.7)
            local factor = meleeFovFactor * visibilityFactor
            table.insert(meleeCandidates, { player = player, factor = factor })
        elseif distance <= 770 then
            local distanceFactor = Math.RemapValClamped(distance, 0, 770, 1, 0.9)
            local fovFactor = Math.RemapValClamped(fov, 0, effectiveFOV, 1, 0.1)
            local factor = distanceFactor * fovFactor * visibilityFactor
            table.insert(normalCandidates, { player = player, factor = factor })
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
