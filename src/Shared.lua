--[[ Imported by: Main, ChargeBot, CritManager, Visuals ]]
-- Shared script-wide state table. Avoids _G pollution.
-- Modules get this table and read/write fields here instead of using globals.

local Shared = {
    -- Per-tick state written by Main, read by modules
    pLocalOrigin = nil,
    pLocalFuture = nil,
    pLocalPath   = nil,

    vPlayerOrigin = nil,
    vPlayerFuture = nil,
    vPlayerPath   = nil,

    currentTarget = nil,
    aimposVis     = nil,
    drawVhitbox   = nil,

    vHeight        = nil, -- Vector3, set each tick
    totalSwingRange = 48,
}

return Shared
