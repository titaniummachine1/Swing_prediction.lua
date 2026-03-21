--[[ Imported by: Main ]]
-- Visual draw primitives and frame render.

local Simulation = require("Simulation")

local Visuals = {}

-- ─── Constants / assets ───────────────────────────────────────────────────────

local Verdana = draw.CreateFont("Verdana", 16, 800)
draw.SetFont(Verdana)

local white_texture = draw.CreateTextureRGBA(string.char(
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25
), 2, 2)

-- ─── Sphere cache ─────────────────────────────────────────────────────────────

local sphere_cache = { vertices = {}, radius = 90, center = Vector3(0, 0, 0) }

local function setup_sphere(center, radius, segments)
    sphere_cache.center   = center
    sphere_cache.radius   = radius
    sphere_cache.segments = segments
    sphere_cache.vertices = {}

    local thetaStep       = math.pi / segments
    local phiStep         = 2 * math.pi / segments

    for i = 0, segments - 1 do
        local theta1 = thetaStep * i
        local theta2 = thetaStep * (i + 1)
        for j = 0, segments - 1 do
            local phi1 = phiStep * j
            local phi2 = phiStep * (j + 1)
            table.insert(sphere_cache.vertices, {
                Vector3(math.sin(theta1) * math.cos(phi1), math.sin(theta1) * math.sin(phi1), math.cos(theta1)),
                Vector3(math.sin(theta1) * math.cos(phi2), math.sin(theta1) * math.sin(phi2), math.cos(theta1)),
                Vector3(math.sin(theta2) * math.cos(phi2), math.sin(theta2) * math.sin(phi2), math.cos(theta2)),
                Vector3(math.sin(theta2) * math.cos(phi1), math.sin(theta2) * math.sin(phi1), math.cos(theta2)),
            })
        end
    end
end

setup_sphere(Vector3(0, 0, 0), 90, 7)

-- ─── Textured polygon ─────────────────────────────────────────────────────────

local drawPolygon = (function()
    local v1x, v1y = 0, 0
    local function cross(a, b)
        return (b[1] - a[1]) * (v1y - a[2]) - (b[2] - a[2]) * (v1x - a[1])
    end
    local TexturedPolygon = draw.TexturedPolygon
    return function(vertices)
        local cords, reverse_cords = {}, {}
        local sizeof               = #vertices
        local sum                  = 0
        v1x, v1y                   = vertices[1][1], vertices[1][2]
        for i, pos in ipairs(vertices) do
            local t = { pos[1], pos[2], 0, 0 }
            cords[i], reverse_cords[sizeof - i + 1] = t, t
            sum = sum + cross(pos, vertices[(i % sizeof) + 1])
        end
        TexturedPolygon(white_texture, (sum < 0) and reverse_cords or cords, true)
    end
end)()

-- ─── Path draw primitives ─────────────────────────────────────────────────────

local function arrowPathArrow2(startPos, endPos, width)
    if not (startPos and endPos) then return nil, nil end
    local direction = endPos - startPos
    if direction:Length() == 0 then return nil, nil end
    direction       = Simulation.Normalize(direction)

    local perpDir   = Vector3(-direction.y, direction.x, 0)
    local leftBase  = startPos + perpDir * width
    local rightBase = startPos - perpDir * width

    local sStart    = client.WorldToScreen(startPos)
    local sEnd      = client.WorldToScreen(endPos)
    local sLeft     = client.WorldToScreen(leftBase)
    local sRight    = client.WorldToScreen(rightBase)

    if sStart and sEnd and sLeft and sRight then
        draw.Line(sStart[1], sStart[2], sEnd[1], sEnd[2])
        draw.Line(sLeft[1], sLeft[2], sEnd[1], sEnd[2])
        draw.Line(sRight[1], sRight[2], sEnd[1], sEnd[2])
    end

    return leftBase, rightBase
end

local function arrowPathArrow(startPos, endPos, arrowWidth)
    if not startPos or not endPos then return end
    local direction = endPos - startPos
    if direction:Length() == 0 then return end
    direction           = Simulation.Normalize(direction)

    local perpendicular = Vector3(-direction.y, direction.x, 0) * arrowWidth
    local finPoint1     = startPos + perpendicular
    local finPoint2     = startPos - perpendicular

    local sEnd          = client.WorldToScreen(endPos)
    local sFin1         = client.WorldToScreen(finPoint1)
    local sFin2         = client.WorldToScreen(finPoint2)

    if sEnd and sFin1 and sFin2 then
        draw.Line(sEnd[1], sEnd[2], sFin1[1], sFin1[2])
        draw.Line(sEnd[1], sEnd[2], sFin2[1], sFin2[2])
        draw.Line(sFin1[1], sFin1[2], sFin2[1], sFin2[2])
    end
end

local function drawPavement(startPos, endPos, width)
    if not (startPos and endPos) then return nil, nil end
    local direction = endPos - startPos
    if direction:Length() == 0 then return nil, nil end
    direction       = Simulation.Normalize(direction)

    local perpDir   = Vector3(-direction.y, direction.x, 0)
    local leftBase  = startPos + perpDir * width
    local rightBase = startPos - perpDir * width

    local sStart    = client.WorldToScreen(startPos)
    local sEnd      = client.WorldToScreen(endPos)
    local sLeft     = client.WorldToScreen(leftBase)
    local sRight    = client.WorldToScreen(rightBase)

    if sStart and sEnd and sLeft and sRight then
        draw.Line(sStart[1], sStart[2], sEnd[1], sEnd[2])
        draw.Line(sStart[1], sStart[2], sLeft[1], sLeft[2])
        draw.Line(sStart[1], sStart[2], sRight[1], sRight[2])
    end

    return leftBase, rightBase
end

local function L_line(startPos, endPos, secondary_line_size)
    if not (startPos and endPos) then return end
    local direction = endPos - startPos
    if direction:Length() == 0 then return end

    local normDir       = Simulation.Normalize(direction)
    local perpendicular = Vector3(normDir.y, -normDir.x, 0) * secondary_line_size

    local sStart        = client.WorldToScreen(startPos)
    local sEnd          = client.WorldToScreen(endPos)
    if not (sStart and sEnd) then return end

    local sSecondary = client.WorldToScreen(startPos + perpendicular)
    if sSecondary then
        draw.Line(sStart[1], sStart[2], sEnd[1], sEnd[2])
        draw.Line(sStart[1], sStart[2], sSecondary[1], sSecondary[2])
    end
end

-- ─── Path rendering helpers (factored per-style for local and target paths) ──

local function renderPathStyle(path, style, width)
    if style == 1 then
        -- Pavement
        local lastLeft, lastRight = nil, nil
        for i = 1, #path - 1 do
            local leftBase, rightBase = drawPavement(path[i], path[i + 1], width)
            if leftBase and rightBase then
                local sLeft  = client.WorldToScreen(leftBase)
                local sRight = client.WorldToScreen(rightBase)
                if sLeft and sRight then
                    if lastLeft and lastRight then
                        draw.Line(lastLeft[1], lastLeft[2], sLeft[1], sLeft[2])
                        draw.Line(lastRight[1], lastRight[2], sRight[1], sRight[2])
                    end
                    lastLeft, lastRight = sLeft, sRight
                end
            end
        end
        if lastLeft and lastRight and #path > 0 then
            local sFinal = client.WorldToScreen(path[#path])
            if sFinal then
                draw.Line(lastLeft[1], lastLeft[2], sFinal[1], sFinal[2])
                draw.Line(lastRight[1], lastRight[2], sFinal[1], sFinal[2])
            end
        end
    elseif style == 2 then
        -- ArrowPath
        local lastLeft, lastRight = nil, nil
        for i = 2, #path - 1 do
            local leftBase, rightBase = arrowPathArrow2(path[i], path[i + 1], width)
            if leftBase and rightBase then
                local sLeft  = client.WorldToScreen(leftBase)
                local sRight = client.WorldToScreen(rightBase)
                if sLeft and sRight then
                    if lastLeft and lastRight then
                        draw.Line(lastLeft[1], lastLeft[2], sLeft[1], sLeft[2])
                        draw.Line(lastRight[1], lastRight[2], sRight[1], sRight[2])
                    end
                    lastLeft, lastRight = sLeft, sRight
                end
            end
        end
    elseif style == 3 then
        -- Arrows
        for i = 1, #path - 1 do
            arrowPathArrow(path[i], path[i + 1], width)
        end
    elseif style == 4 then
        -- L Line
        for i = 1, #path - 1 do
            L_line(path[i], path[i + 1], width)
        end
    elseif style == 5 then
        -- Dashed
        for i = 1, #path - 1 do
            local s1 = client.WorldToScreen(path[i])
            local s2 = client.WorldToScreen(path[i + 1])
            if s1 and s2 and i % 2 == 1 then
                draw.Line(s1[1], s1[2], s2[1], s2[2])
            end
        end
    elseif style == 6 then
        -- Line
        for i = 1, #path - 1 do
            local s1 = client.WorldToScreen(path[i])
            local s2 = client.WorldToScreen(path[i + 1])
            if s1 and s2 then
                draw.Line(s1[1], s1[2], s2[1], s2[2])
            end
        end
    end
end

-- ─── Frame render ─────────────────────────────────────────────────────────────

-- Call from doDraw when the local player is alive and holds a melee weapon.
-- state fields: pLocalFuture, pLocalOrigin, Vheight, TotalSwingRange,
--               pLocalPath, vPlayerPath, vPlayerFuture, CurrentTarget,
--               drawVhitbox, aimposVis
function Visuals.Render(menu, state)
    assert(menu, "Visuals.Render: menu is nil")
    assert(state, "Visuals.Render: state is nil")

    local w, h = draw.GetScreenSize()
    draw.Color(255, 255, 255, 255)

    -- Warp status HUD
    if menu.Misc.InstantAttack then
        local warpLib          = rawget(_G, "warp")
        local charged          = warpLib and warpLib.GetChargedTicks() or 0
        local maxTicks         = 24
        local isWarping        = warpLib and warpLib.IsWarping() or false
        local canWarp          = warpLib and warpLib.CanWarp() or false

        local warpText         = string.format("Warp: %d/%d", charged, maxTicks)
        local statusText       = string.format("CanWarp: %s | Warping: %s", tostring(canWarp), tostring(isWarping))
        local warpOnAttackText = string.format("WarpOnAttack: %s", tostring(menu.Misc.WarpOnAttack))

        if isWarping then
            draw.Color(255, 100, 100, 255)
        elseif canWarp and charged >= 13 then
            draw.Color(100, 255, 100, 255)
        elseif canWarp then
            draw.Color(255, 255, 100, 255)
        else
            draw.Color(255, 255, 255, 255)
        end

        draw.SetFont(Verdana)
        local textW = draw.GetTextSize(warpText)
        draw.Text(w - textW - 10, 100, warpText)

        draw.Color(255, 255, 255, 255)
        local statusW = draw.GetTextSize(statusText)
        draw.Text(w - statusW - 10, 120, statusText)
        local warpOnW = draw.GetTextSize(warpOnAttackText)
        draw.Text(w - warpOnW - 10, 140, warpOnAttackText)
    end

    draw.Color(255, 255, 255, 255)

    -- Range circle
    local pLocalFuture    = state.pLocalFuture
    local pLocalOrigin    = state.pLocalOrigin
    local Vheight         = state.Vheight
    local TotalSwingRange = state.TotalSwingRange
    local CurrentTarget   = state.CurrentTarget

    if menu.Visuals.Local.RangeCircle and pLocalFuture and pLocalOrigin and Vheight then
        local viewPos     = pLocalOrigin
        local center      = pLocalFuture - Vheight
        local radius      = TotalSwingRange
        local segments    = 32
        local angleStep   = (2 * math.pi) / segments

        local circleColor = CurrentTarget and { 0, 255, 0, 255 } or { 255, 255, 255, 255 }
        draw.Color(table.unpack(circleColor))

        local vertices = {}
        for i = 1, segments do
            local angle       = angleStep * i
            local circlePoint = center + Vector3(math.cos(angle), math.sin(angle), 0) * radius
            local trace       = engine.TraceLine(viewPos, circlePoint, MASK_SHOT_HULL)
            local endPoint    = trace.fraction < 1.0 and trace.endpos or circlePoint
            vertices[i]       = client.WorldToScreen(endPoint)
        end

        for i = 1, segments do
            local j = (i % segments) + 1
            if vertices[i] and vertices[j] then
                draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
            end
        end
    end

    -- Local player path
    local pLocalPath = state.pLocalPath
    if menu.Visuals.Local.path.enable and pLocalFuture and pLocalPath then
        draw.Color(table.unpack(menu.Visuals.Local.path.Color))
        renderPathStyle(pLocalPath, menu.Visuals.Local.path.Style, menu.Visuals.Local.path.width)
    end

    -- Range sphere (experimental)
    if menu.Visuals.Sphere and pLocalOrigin then
        local playerYaw     = engine.GetViewAngles().yaw
        local cosYaw        = math.cos(math.rad(playerYaw))
        local sinYaw        = math.sin(math.rad(playerYaw))
        local playerForward = Vector3(-cosYaw, -sinYaw, 0)

        sphere_cache.center = pLocalOrigin
        sphere_cache.radius = TotalSwingRange

        for _, vertex in ipairs(sphere_cache.vertices) do
            local function rotateVert(v)
                return Vector3(-v.x * cosYaw + v.y * sinYaw, -v.x * sinYaw - v.y * cosYaw, v.z)
            end
            local rv1 = rotateVert(vertex[1])
            local rv2 = rotateVert(vertex[2])
            local rv3 = rotateVert(vertex[3])
            local rv4 = rotateVert(vertex[4])

            local hullSize = Vector3(18, 18, 18)
            local function traceVert(rv)
                local worldPos = sphere_cache.center + rv * sphere_cache.radius
                local tr       = engine.TraceHull(sphere_cache.center, worldPos, -hullSize, hullSize, MASK_SHOT_HULL)
                return tr.fraction < 1.0 and tr.endpos or worldPos
            end

            local ep1 = traceVert(rv1)
            local ep2 = traceVert(rv2)
            local ep3 = traceVert(rv3)
            local ep4 = traceVert(rv4)

            local sp1 = client.WorldToScreen(ep1)
            local sp2 = client.WorldToScreen(ep2)
            local sp3 = client.WorldToScreen(ep3)
            local sp4 = client.WorldToScreen(ep4)

            local normal = Simulation.Normalize(rv2 - rv1):Cross(rv3 - rv1)
            if normal:Dot(playerForward) > 0.1 then
                if sp1 and sp2 and sp3 and sp4 then
                    drawPolygon({ sp1, sp2, sp3, sp4 })
                    draw.Color(255, 255, 255, 25)
                    draw.Line(sp1[1], sp1[2], sp2[1], sp2[2])
                    draw.Line(sp2[1], sp2[2], sp3[1], sp3[2])
                    draw.Line(sp3[1], sp3[2], sp4[1], sp4[2])
                    draw.Line(sp4[1], sp4[2], sp1[1], sp1[2])
                end
            end
        end
    end

    -- Target path, aim cross, and AABB box
    local vPlayerFuture = state.vPlayerFuture
    local vPlayerPath   = state.vPlayerPath
    local aimposVis     = state.aimposVis
    local drawVhitbox   = state.drawVhitbox

    if vPlayerFuture then
        draw.Color(255, 255, 255, 255)

        if menu.Visuals.Target.path.enable and vPlayerPath then
            renderPathStyle(vPlayerPath, menu.Visuals.Target.path.Style, menu.Visuals.Target.path.width)
        end

        if aimposVis then
            local sAim = client.WorldToScreen(aimposVis)
            if sAim then
                draw.Line(sAim[1] + 10, sAim[2], sAim[1] - 10, sAim[2])
                draw.Line(sAim[1], sAim[2] - 10, sAim[1], sAim[2] + 10)
            end
        end

        if drawVhitbox and drawVhitbox[1] and drawVhitbox[2] then
            local mn = drawVhitbox[1]
            local mx = drawVhitbox[2]
            local verts3d = {
                Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z),
                Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mn.y, mn.z),
                Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z),
                Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z),
            }
            local v = {}
            for i, pt in ipairs(verts3d) do
                v[i] = client.WorldToScreen(pt)
            end
            if v[1] and v[2] and v[3] and v[4] and v[5] and v[6] and v[7] and v[8] then
                -- Bottom face
                draw.Line(v[1][1], v[1][2], v[2][1], v[2][2])
                draw.Line(v[2][1], v[2][2], v[3][1], v[3][2])
                draw.Line(v[3][1], v[3][2], v[4][1], v[4][2])
                draw.Line(v[4][1], v[4][2], v[1][1], v[1][2])
                -- Top face
                draw.Line(v[5][1], v[5][2], v[6][1], v[6][2])
                draw.Line(v[6][1], v[6][2], v[7][1], v[7][2])
                draw.Line(v[7][1], v[7][2], v[8][1], v[8][2])
                draw.Line(v[8][1], v[8][2], v[5][1], v[5][2])
                -- Connecting edges
                draw.Line(v[1][1], v[1][2], v[5][1], v[5][2])
                draw.Line(v[2][1], v[2][2], v[6][1], v[6][2])
                draw.Line(v[3][1], v[3][2], v[7][1], v[7][2])
                draw.Line(v[4][1], v[4][2], v[8][1], v[8][2])
            end
        end
    end
end

return Visuals
