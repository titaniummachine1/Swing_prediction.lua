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
local _maxBacktrackRecords = 80

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
    local pNetChan = clientstate.GetNetChannel()
    if not pNetChan then return end
    local iTick = globals.TickCount()
    local flIncoming = pNetChan:GetLatency(1) or 0
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

        -- Prune stale history and skip duplicate per-tick snapshots.
        if hist[1] and math.abs(hist[1].tick - iTick) >= 660 then
            _targetHistory[idx] = nil
            hist = {}
            _targetHistory[idx] = hist
        end
        if hist[1] and hist[1].tick == iTick then goto continueH end

        local hitboxes    = player:GetHitboxes()
        local aHead       = hitboxes and hitboxes[1]
        local aChest      = hitboxes and hitboxes[4]
        local headCenter  = aHead and ((aHead[1] + aHead[2]) * 0.5) or (player:GetAbsOrigin() + Vector3(0, 0, 75))
        local chestCenter = aChest and ((aChest[1] + aChest[2]) * 0.5) or (player:GetAbsOrigin() + Vector3(0, 0, 50))

        local flags       = player:GetPropInt("m_fFlags") or 0
        local onGround    = (flags & FL_ONGROUND) ~= 0

        table.insert(hist, 1, {
            tick     = iTick,
            simTick  = math.floor(0.5 + ((player:GetPropFloat("m_flSimulationTime") or 0) / globals.TickInterval())),
            pos      = player:GetAbsOrigin(),
            head     = headCenter,
            chest    = chestCenter,
            vel      = player:EstimateAbsVelocity(),
            onGround = onGround,
            latencyTicks = iLatencyTicks
        })

        while #hist > _maxBacktrackRecords do table.remove(hist) end

        ::continueH::
    end
end

-- Returns the valid [oldestTick, latestTick] window for backtrack at swing impact time.
function TargetSelector.GetBacktrackWindow(swingTicks)
    local iTick = globals.TickCount() + (swingTicks or 0)
    local pNetChan = clientstate.GetNetChannel()
    local flIncoming = pNetChan and pNetChan:GetLatency(1) or 0
    local iLatTicks = math.floor(0.5 + flIncoming / globals.TickInterval())
    local maxUnlag = client.GetConVar("sv_maxunlag") or 0.2
    local iMaxBacktrack = math.floor(0.5 + maxUnlag / globals.TickInterval())
    local iCurrent = iTick - iLatTicks
    local iLatest = iCurrent + math.min(iLatTicks, iMaxBacktrack)
    local iOldest = iCurrent - iMaxBacktrack
    return iOldest, iLatest
end

function TargetSelector.GetHistory(entityIndex)
    return _targetHistory[entityIndex]
end

local _engineGhosts = {}

-- Captures an engine-rendered backtrack ghost position.
-- This natively intercepts the engine's backtracking ghost queue.
function TargetSelector.RecordEngineGhost(player, origin, mins, maxs)
    if not player or not player:IsValid() then return end
    local idx = player:GetIndex()
    if not _engineGhosts[idx] then _engineGhosts[idx] = {} end

    local currentTick = globals.TickCount()

    -- Update existing record
    for _, record in ipairs(_engineGhosts[idx]) do
        if (record.pos - origin):Length() < 1.0 then
            record.lastSeen = currentTick
            record.mins = mins
            record.maxs = maxs
            return
        end
    end

    -- Match to manual history to find the tick
    local matchedTick = nil
    local hist = _targetHistory[idx]
    if hist then
        local bestDist = math.huge
        for _, hRec in ipairs(hist) do
            local dist = (hRec.pos - origin):Length()
            if dist < 5.0 and dist < bestDist then
                bestDist = dist
                matchedTick = hRec.tick
            end
        end
    end

    table.insert(_engineGhosts[idx], 1, {
        pos = origin,
        mins = mins,
        maxs = maxs,
        tick = matchedTick,
        lastSeen = currentTick
    })

    while #_engineGhosts[idx] > 20 do
        table.remove(_engineGhosts[idx])
    end
end

function TargetSelector.GetEngineGhosts(entityIndex)
    local ghosts = _engineGhosts[entityIndex]
    if not ghosts then return nil end
    local validGhosts = {}
    local currentTick = globals.TickCount()
    for _, record in ipairs(ghosts) do
        -- Keep ghosts seen recently by the renderer (within ~150ms buffer to smooth over frames)
        if math.abs(currentTick - record.lastSeen) <= 10 then
            table.insert(validGhosts, record)
        end
    end
    _engineGhosts[entityIndex] = validGhosts
    return validGhosts
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
                table.insert(normalCandidates,
                    { player = player, factor = distanceFactor * fovFactor * visibilityFactor })
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
