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

-- Rolling buffer for backtrack: _targetHistory[idx] = { {pos = Vector3, tick = number}, ... }
local _targetHistory = {}
local _maxBacktrackRecords = 14

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

function TargetSelector.UpdateHistory(players, pCmd)
    if not players then return end
    local iTick    = globals.TickCount()
    local pNetChan = clientstate.GetNetChannel()
    local flIncoming    = pNetChan and pNetChan:GetLatency(1) or 0
    local iLatencyTicks = math.floor(0.5 + flIncoming / globals.TickInterval())

    for _, player in pairs(players) do
        if not player or not player:IsValid() then goto continueH end
        local idx = player:GetIndex()

        if not player:IsAlive() or player:IsDormant() then
            _targetHistory[idx] = nil
            goto continueH
        end

        if not _targetHistory[idx] then _targetHistory[idx] = {} end
        local hist = _targetHistory[idx]

        -- Prune stale history (older than 660 ticks, same as reference)
        if hist[1] and math.abs(hist[1].tick - iTick) >= 660 then
            _targetHistory[idx] = nil
            goto continueH
        end

        -- Capture actual hitbox centers for precision aim
        local hitboxes = player:GetHitboxes()
        local aHead  = hitboxes and hitboxes[1]
        local aChest = hitboxes and hitboxes[4]
        local headCenter  = aHead  and ((aHead[1]  + aHead[2])  * 0.5) or (player:GetAbsOrigin() + Vector3(0, 0, 75))
        local chestCenter = aChest and ((aChest[1] + aChest[2]) * 0.5) or (player:GetAbsOrigin() + Vector3(0, 0, 50))

        local flags = player:GetPropInt("m_fFlags") or 0
        local onGround = (flags & FL_ONGROUND) ~= 0

        table.insert(hist, 1, {
            tick  = iTick,
            pos   = player:GetAbsOrigin(),  -- feet origin for AABB range check
            head  = headCenter,
            chest = chestCenter,
            latencyTicks = iLatencyTicks,
            vel   = player:EstimateAbsVelocity(),
            onGround = onGround
        })

        -- Keep max 80 records
        while #hist > 80 do
            table.remove(hist)
        end

        ::continueH::
    end
end

-- Returns the valid [oldestTick, latestTick] window for backtrack,
-- based on current server-estimated latency, mirroring reference implementation logic.
function TargetSelector.GetBacktrackWindow()
    local iTick       = globals.TickCount()
    local pNetChan    = clientstate.GetNetChannel()
    local flIncoming  = pNetChan and pNetChan:GetLatency(1) or 0
    local iLatTicks   = math.floor(0.5 + flIncoming / globals.TickInterval())
    local maxBT       = math.floor(0.5 + 0.2 / globals.TickInterval())  -- 200 ms in ticks
    local iCurrent    = iTick - iLatTicks
    local iLatest     = iCurrent + math.min(iLatTicks, maxBT)
    local iOldest     = iCurrent - maxBT
    return iOldest, iLatest
end

function TargetSelector.GetHistory(entityIndex)
    return _targetHistory[entityIndex]
end

function TargetSelector.CalcStrafe()
    if not _players or not _me then return end
    Simulation.CalcStrafe(_players, _me, TargetSelector.GetHistory)
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
        
        -- Range Check: Expand to 4x swing range so far targets stay tracked for backtrack history
        local maxRange = _swingRange * 4
        if distance > maxRange and not _me:InCond(17) then
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
            else
                -- Far candidate - tracked but lower priority (for backtrack + visuals)
                local distanceFactor = Math.RemapValClamped(distance, 0, maxRange, 1, 0.5)
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
