--[[ Imported by: Main ]]
-- Default Menu configuration table. Returned as-is; Main.lua deep-copies and config-loads before use.

local DefaultConfig = {}

DefaultConfig.Menu = {
    -- Tab management
    currentTab = 1, -- 1 = Aimbot, 2 = Charge, 3 = Visuals, 4 = Misc
    tabs = { "Aimbot", "Demoknight", "Visuals", "Misc" },

    -- Aimbot settings
    Aimbot = {
        Aimbot = true,
        Silent = true,
        AimbotFOV = 360,
        SwingTime = 13,
        AlwaysUseMaxSwingTime = false,
        MaxSwingTime = 11,
        ChargeBot = true,
        Keybind = { key = 0, mode = 0 }, -- Always On
    },

    -- Charge (Demoknight) settings
    Charge = {
        ChargeBot = false,
        ChargeControl = false,
        ChargeSensitivity = 1.0,
        ChargeReach = true,
        ChargeJump = true,
        LateCharge = true,
        Keybind = { key = 0, mode = 0 }, -- Always On
    },

    -- Visuals settings
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

    -- Misc settings
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

}

return DefaultConfig
