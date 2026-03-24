--[[ Imported by: Main ]]

local Simulation = require("Simulation")

local Visuals = {}

-- ─── Constants & Assets ──────────────────────────────────────────────────────

local Verdana = draw.CreateFont("Verdana", 16, 800)

local white_texture = draw.CreateTextureRGBA(string.char(
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25,
    0xff, 0xff, 0xff, 25
), 2, 2)

-- ─── Sphere Cache ───────────────────────────────────────────────────────────

local sphere_cache = { vertices = {}, radius = 90, center = Vector3(0, 0, 0) }

function Visuals.SetupSphere(center, radius, segments)
    sphere_cache.center = center
    sphere_cache.radius = radius
    sphere_cache.segments = segments
    sphere_cache.vertices = {}

    local thetaStep = math.pi / segments
    local phiStep = 2 * math.pi / segments

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
                Vector3(math.sin(theta2) * math.cos(phi1), math.sin(theta2) * math.sin(phi1), math.cos(theta2))
            })
        end
    end
end

-- Initialize sphere
Visuals.SetupSphere(Vector3(0, 0, 0), 90, 7)

-- ─── Drawing Primitives ──────────────────────────────────────────────────────

local function drawPolygon(vertices)
    local cords, reverse_cords = {}, {}
    local sizeof = #vertices
    local sum = 0

    local v1x, v1y = vertices[1][1], vertices[1][2]
    local function cross(a, b)
        return (b[1] - a[1]) * (v1y - a[2]) - (b[2] - a[2]) * (v1x - a[1])
    end

    for i, pos in ipairs(vertices) do
        local convertedTbl = { pos[1], pos[2], 0, 0 }
        cords[i], reverse_cords[sizeof - i + 1] = convertedTbl, convertedTbl
        sum = sum + cross(pos, vertices[(i % sizeof) + 1])
    end

    draw.TexturedPolygon(white_texture, (sum < 0) and reverse_cords or cords, true)
end

function Visuals.ArrowPathArrow2(startPos, endPos, width)
    if not (startPos and endPos) then return nil, nil end
    local direction = endPos - startPos
    if direction:Length() == 0 then return nil, nil end
    direction = Simulation.Normalize(direction)

    local perpDir = Vector3(-direction.y, direction.x, 0)
    local leftBase = startPos + perpDir * width
    local rightBase = startPos - perpDir * width

    local sStart = client.WorldToScreen(startPos)
    local sEnd = client.WorldToScreen(endPos)
    local sLeft = client.WorldToScreen(leftBase)
    local sRight = client.WorldToScreen(rightBase)

    if sStart and sEnd and sLeft and sRight then
        draw.Line(sStart[1], sStart[2], sEnd[1], sEnd[2])
        draw.Line(sLeft[1], sLeft[2], sEnd[1], sEnd[2])
        draw.Line(sRight[1], sRight[2], sEnd[1], sEnd[2])
    end
    return leftBase, rightBase
end

function Visuals.ArrowPathArrow(startPos, endPos, arrowWidth)
    if not (startPos and endPos) then return end
    local direction = endPos - startPos
    if direction:Length() == 0 then return end
    direction = Simulation.Normalize(direction)
    local perpendicular = Vector3(-direction.y, direction.x, 0) * arrowWidth
    
    local finPoint1 = startPos + perpendicular
    local finPoint2 = startPos - perpendicular
    
    local sEnd = client.WorldToScreen(endPos)
    local sFin1 = client.WorldToScreen(finPoint1)
    local sFin2 = client.WorldToScreen(finPoint2)
    
    if sEnd and sFin1 and sFin2 then
        draw.Line(sEnd[1], sEnd[2], sFin1[1], sFin1[2])
        draw.Line(sEnd[1], sEnd[2], sFin2[1], sFin2[2])
        draw.Line(sFin1[1], sFin1[2], sFin2[1], sFin2[2])
    end
end

function Visuals.DrawPavement(startPos, endPos, width)
    if not (startPos and endPos) then return nil, nil end
    local direction = endPos - startPos
    if direction:Length() == 0 then return nil, nil end
    direction = Simulation.Normalize(direction)
    
    local perpDir = Vector3(-direction.y, direction.x, 0)
    local leftBase = startPos + perpDir * width
    local rightBase = startPos - perpDir * width
    
    local sStart = client.WorldToScreen(startPos)
    local sEnd = client.WorldToScreen(endPos)
    local sLeft = client.WorldToScreen(leftBase)
    local sRight = client.WorldToScreen(rightBase)
    
    if sStart and sEnd and sLeft and sRight then
        draw.Line(sStart[1], sStart[2], sEnd[1], sEnd[2])
        draw.Line(sStart[1], sStart[2], sLeft[1], sLeft[2])
        draw.Line(sStart[1], sStart[2], sRight[1], sRight[2])
    end
    return leftBase, rightBase
end

function Visuals.LLine(startPos, endPos, secondaryLineSize)
    if not (startPos and endPos) then return end
    local direction = endPos - startPos
    if direction:Length() == 0 then return end
    local normDir = Simulation.Normalize(direction)
    local perpendicular = Vector3(normDir.y, -normDir.x, 0) * secondaryLineSize
    
    local sStart = client.WorldToScreen(startPos)
    local sEnd = client.WorldToScreen(endPos)
    if not (sStart and sEnd) then return end
    
    local sSecondary = client.WorldToScreen(startPos + perpendicular)
    if sSecondary then
        draw.Line(sStart[1], sStart[2], sEnd[1], sEnd[2])
        draw.Line(sStart[1], sStart[2], sSecondary[1], sSecondary[2])
    end
end

-- ─── Style Dispatcher ────────────────────────────────────────────────────────

local function renderPathStyle(path, style, width)
    if not path or #path < 2 then return end

    if style == 1 then -- Pavement
        local lastLeft, lastRight = nil, nil
        for i = 1, #path - 1 do
            local left, right = Visuals.DrawPavement(path[i], path[i+1], width)
            if left and right then
                local sL = client.WorldToScreen(left)
                local sR = client.WorldToScreen(right)
                if sL and sR then
                    if lastLeft and lastRight then
                        draw.Line(lastLeft[1], lastLeft[2], sL[1], sL[2])
                        draw.Line(lastRight[1], lastRight[2], sR[1], sR[2])
                    end
                    lastLeft, lastRight = sL, sR
                end
            end
        end
        if lastLeft and lastRight then
            local sFinal = client.WorldToScreen(path[#path])
            if sFinal then
                draw.Line(lastLeft[1], lastLeft[2], sFinal[1], sFinal[2])
                draw.Line(lastRight[1], lastRight[2], sFinal[1], sFinal[2])
            end
        end
    elseif style == 2 then -- ArrowPath
        local lastLeft, lastRight = nil, nil
        for i = 2, #path - 1 do
            local left, right = Visuals.ArrowPathArrow2(path[i], path[i+1], width)
            if left and right then
                local sL = client.WorldToScreen(left)
                local sR = client.WorldToScreen(right)
                if sL and sR then
                    if lastLeft and lastRight then
                        draw.Line(lastLeft[1], lastLeft[2], sL[1], sL[2])
                        draw.Line(lastRight[1], lastRight[2], sR[1], sR[2])
                    end
                    lastLeft, lastRight = sL, sR
                end
            end
        end
    elseif style == 3 then -- Arrows
        for i = 1, #path - 1 do
            Visuals.ArrowPathArrow(path[i], path[i+1], width)
        end
    elseif style == 4 then -- L Line
        for i = 1, #path - 1 do
            Visuals.LLine(path[i], path[i+1], width)
        end
    elseif style == 5 then -- Dashed
        for i = 1, #path - 1 do
            local s1 = client.WorldToScreen(path[i])
            local s2 = client.WorldToScreen(path[i+1])
            if s1 and s2 and i % 2 == 1 then
                draw.Line(s1[1], s1[2], s2[1], s2[2])
            end
        end
    elseif style == 6 then -- Line
        for i = 1, #path - 1 do
            local s1 = client.WorldToScreen(path[i])
            local s2 = client.WorldToScreen(path[i+1])
            if s1 and s2 then
                draw.Line(s1[1], s1[2], s2[1], s2[2])
            end
        end
    end
end

-- ─── Main Render Dispatch ────────────────────────────────────────────────────

function Visuals.Render(menu, state)
    assert(menu, "Visuals.Render: menu settings missing")
    assert(state, "Visuals.Render: state missing")

    if not menu.Visuals or not menu.Visuals.EnableVisuals then return end

    local w, h = draw.GetScreenSize()
    draw.SetFont(Verdana)

    -- 1. HUD: Warp Status
    if menu.Misc and menu.Misc.InstantAttack then
        local warpLib = rawget(_G, "warp")
        local charged = (warpLib and warpLib.GetChargedTicks()) or 0
        local maxTicks = 24
        local canWarp = (warpLib and warpLib.CanWarp())
        local isWarping = (warpLib and warpLib.IsWarping())

        local warpText = string.format("Warp: %d/%d", charged, maxTicks)
        local statusText = string.format("CanWarp: %s | Warping: %s", tostring(canWarp), tostring(isWarping))
        local warpOnAttackText = string.format("WarpOnAttack: %s", tostring(menu.Misc.WarpOnAttack))

        if isWarping then draw.Color(255, 100, 100, 255)
        elseif canWarp and charged >= 13 then draw.Color(100, 255, 100, 255)
        elseif canWarp then draw.Color(255, 255, 100, 255)
        else draw.Color(255, 255, 255, 255) end

        local tw = draw.GetTextSize(warpText)
        draw.Text(w - tw - 10, 100, warpText)
        draw.Color(255, 255, 255, 255)
        local sw = draw.GetTextSize(statusText)
        draw.Text(w - sw - 10, 120, statusText)
        local wow = draw.GetTextSize(warpOnAttackText)
        draw.Text(w - wow - 10, 140, warpOnAttackText)
    end

    -- 2. Range Circle (Local)
    if menu.Visuals.Local.RangeCircle and state.pLocalFuture and state.pLocalOrigin and state.vHeight then
        local viewPos = state.pLocalOrigin
        local center = state.pLocalFuture - state.vHeight
        local radius = state.totalSwingRange or 48
        local segments = 32
        local angleStep = (2 * math.pi) / segments

        local circleColor = state.currentTarget and {0, 255, 0, 255} or {255, 255, 255, 255}
        draw.Color(table.unpack(circleColor))

        local vertices = {}
        for i = 1, segments do
            local angle = angleStep * i
            local circlePoint = center + Vector3(math.cos(angle), math.sin(angle), 0) * radius
            local trace = engine.TraceLine(viewPos, circlePoint, MASK_SHOT_HULL)
            local endPoint = trace.fraction < 1.0 and trace.endpos or circlePoint
            vertices[i] = client.WorldToScreen(endPoint)
        end

        for i = 1, segments do
            local j = (i % segments) + 1
            if vertices[i] and vertices[j] then
                draw.Line(vertices[i][1], vertices[i][2], vertices[j][1], vertices[j][2])
            end
        end
    end

    -- 3. Path (Local)
    if menu.Visuals.Local.path.enable and state.pLocalPath then
        draw.Color(table.unpack(menu.Visuals.Local.path.Color))
        renderPathStyle(state.pLocalPath, menu.Visuals.Local.path.Style, menu.Visuals.Local.path.width)
    end

    -- 4. Range Sphere (Experimental)
    if menu.Visuals.Sphere and state.pLocalOrigin then
        local playerYaw = engine.GetViewAngles().yaw
        local cosY = math.cos(math.rad(playerYaw))
        local sinY = math.sin(math.rad(playerYaw))
        local playerForward = Vector3(-cosY, -sinY, 0)

        sphere_cache.center = state.pLocalOrigin
        sphere_cache.radius = state.totalSwingRange or 48

        draw.Color(255, 255, 255, 25)
        for _, vertex in ipairs(sphere_cache.vertices) do
            local function rotateV(v)
                return Vector3(-v.x * cosY + v.y * sinY, -v.x * sinY - v.y * cosY, v.z)
            end
            local rv1 = rotateV(vertex[1])
            local rv2 = rotateV(vertex[2])
            local rv3 = rotateV(vertex[3])
            local rv4 = rotateV(vertex[4])

            local hs = Vector3(18, 18, 18)
            local function traceV(rv)
                local wp = sphere_cache.center + rv * sphere_cache.radius
                local tr = engine.TraceHull(sphere_cache.center, wp, -hs, hs, MASK_SHOT_HULL)
                return tr.fraction < 1.0 and tr.endpos or wp
            end

            local ep1, ep2, ep3, ep4 = traceV(rv1), traceV(rv2), traceV(rv3), traceV(rv4)
            local sp1, sp2, sp3, sp4 = client.WorldToScreen(ep1), client.WorldToScreen(ep2), client.WorldToScreen(ep3), client.WorldToScreen(ep4)

            local normal = Simulation.Normalize(rv2 - rv1):Cross(rv3 - rv1)
            if normal:Dot(playerForward) > 0.1 then
                if sp1 and sp2 and sp3 and sp4 then
                    draw.Color(255, 255, 255, 25)
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

    -- 5. Path (Target)
    if menu.Visuals.Target.path.enable and state.vPlayerPath then
        draw.Color(table.unpack(menu.Visuals.Target.path.Color))
        renderPathStyle(state.vPlayerPath, menu.Visuals.Target.path.Style, menu.Visuals.Target.path.width)
    end

    -- 6. Aim Cross (Target)
    if state.aimposVis then
        local sAim = client.WorldToScreen(state.aimposVis)
        if sAim then
            draw.Color(255, 255, 255, 255)
            draw.Line(sAim[1] + 10, sAim[2], sAim[1] - 10, sAim[2])
            draw.Line(sAim[1], sAim[2] - 10, sAim[1], sAim[2] + 10)
        end
    end

    -- 7. Hitbox Box (Target)
    if state.drawVhitbox and state.drawVhitbox[1] and state.drawVhitbox[2] then
        local mn, mx = state.drawVhitbox[1], state.drawVhitbox[2]
        local pts = {
            Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mn.y, mn.z),
            Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z)
        }
        local s = {}
        for i, p in ipairs(pts) do s[i] = client.WorldToScreen(p) end
        if s[1] and s[2] and s[3] and s[4] and s[5] and s[6] and s[7] and s[8] then
            draw.Color(255, 255, 255, 255)
            draw.Line(s[1][1], s[1][2], s[2][1], s[2][2]) draw.Line(s[2][1], s[2][2], s[3][1], s[3][2])
            draw.Line(s[3][1], s[3][2], s[4][1], s[4][2]) draw.Line(s[4][1], s[4][2], s[1][1], s[1][2])
            draw.Line(s[5][1], s[5][2], s[6][1], s[6][2]) draw.Line(s[6][1], s[6][2], s[7][1], s[7][2])
            draw.Line(s[7][1], s[7][2], s[8][1], s[8][2]) draw.Line(s[8][1], s[8][2], s[5][1], s[5][2])
            draw.Line(s[1][1], s[1][2], s[5][1], s[5][2]) draw.Line(s[2][1], s[2][2], s[6][1], s[6][2])
            draw.Line(s[3][1], s[3][2], s[7][1], s[7][2]) draw.Line(s[4][1], s[4][2], s[8][1], s[8][2])
        end
    end
end

return Visuals
