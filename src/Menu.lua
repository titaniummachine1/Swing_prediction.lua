--[[ Imported by: Main ]]
-- Menu rendering and keybind UI handling.


local lnxLib = require("lnxlib")
local TimMenu = require("TimMenu")


local Input = lnxLib.Utils.Input
local Notify = lnxLib.UI.Notify

local MenuUI = {}


local activationModes = { "Always", "Hold", "Toggle", "Release" }


function MenuUI.Render(menu)
    assert(menu, "MenuUI.Render: menu is nil")

    if not (gui.IsMenuOpen() and TimMenu.Begin("Swing Prediction")) then
        return
    end

    local tabs = { "Aimbot", "Demoknight", "Visuals", "Misc" }
    menu.currentTab = TimMenu.TabControl("swing_tabs", tabs, menu.currentTab or 1)
    TimMenu.NextLine()


    if menu.currentTab == "Aimbot" or menu.currentTab == 1 then
        TimMenu.BeginSector("Aimbot")
        menu.Aimbot.Aimbot = TimMenu.Checkbox("Enable", menu.Aimbot.Aimbot)
        TimMenu.NextLine()
        menu.Aimbot.Silent = TimMenu.Checkbox("Silent Aim", menu.Aimbot.Silent)
        TimMenu.NextLine()
        menu.Aimbot.AimbotFOV = TimMenu.Slider("Fov", menu.Aimbot.AimbotFOV, 1, 360, 1)
        TimMenu.NextLine()
        local swingTimeMaxDisplay = menu.Aimbot.MaxSwingTime or 13
        local swingTimeLabel = string.format("Swing Time (max: %d)", swingTimeMaxDisplay)
        menu.Aimbot.SwingTime = TimMenu.Slider(swingTimeLabel, menu.Aimbot.SwingTime, 1, swingTimeMaxDisplay, 1)
        TimMenu.NextLine()
        menu.Aimbot.AlwaysUseMaxSwingTime = TimMenu.Checkbox("Always Use Max Swing Time",
            menu.Aimbot.AlwaysUseMaxSwingTime)
        TimMenu.NextLine()
        if menu.Aimbot.AlwaysUseMaxSwingTime then
            menu.Aimbot.SwingTime = menu.Aimbot.MaxSwingTime or 13
        end
        local currentKey = menu.Aimbot.Keybind
        if type(currentKey) == "table" then currentKey = currentKey.key end
        local newKey = TimMenu.Keybind("Aimbot Keybind", currentKey or 0)
        if type(menu.Aimbot.Keybind) == "table" then
            menu.Aimbot.Keybind.key = newKey
        else
            menu.Aimbot.Keybind = { key = newKey, mode = 1 } -- Migrate to table
        end
        TimMenu.NextLine()
        TimMenu.EndSector()
    end


    if menu.currentTab == "Demoknight" or menu.currentTab == 2 then
        TimMenu.BeginSector("Demoknight")
        local oldValue = menu.Charge.ChargeBot
        menu.Charge.ChargeBot = TimMenu.Checkbox("Charge Bot", menu.Charge.ChargeBot)
        TimMenu.NextLine()
        if oldValue ~= menu.Charge.ChargeBot then
            menu.Aimbot.ChargeBot = menu.Charge.ChargeBot
        end
        menu.Charge.ChargeBotFOV = TimMenu.Slider("ChargeBot FOV", menu.Charge.ChargeBotFOV or 90, 1, 180, 1)
        TimMenu.NextLine()
        local currentKey = menu.Charge.Keybind
        if type(currentKey) == "table" then currentKey = currentKey.key end
        local newKey = TimMenu.Keybind("ChargeBot Keybind", currentKey or 0)
        if type(menu.Charge.Keybind) == "table" then
            menu.Charge.Keybind.key = newKey
        else
            menu.Charge.Keybind = { key = newKey, mode = 1 } -- Migrate to table
        end
        TimMenu.NextLine()
        local oldChargeControl = menu.Charge.ChargeControl
        menu.Charge.ChargeControl = TimMenu.Checkbox("Charge Control", menu.Charge.ChargeControl)
        TimMenu.NextLine()
        if oldChargeControl ~= menu.Charge.ChargeControl then
            menu.Misc.ChargeControl = menu.Charge.ChargeControl
        end
        local oldChargeReach = menu.Charge.ChargeReach
        menu.Charge.ChargeReach = TimMenu.Checkbox("Charge Reach", menu.Charge.ChargeReach)
        TimMenu.NextLine()
        if oldChargeReach ~= menu.Charge.ChargeReach then
            menu.Misc.ChargeReach = menu.Charge.ChargeReach
        end
        if menu.Charge.ChargeReach then
            menu.Charge.LateCharge = TimMenu.Checkbox("Late Charge", menu.Charge.LateCharge)
            TimMenu.NextLine()
        end
        local oldChargeJump = menu.Charge.ChargeJump
        menu.Charge.ChargeJump = TimMenu.Checkbox("Charge Jump", menu.Charge.ChargeJump)
        TimMenu.NextLine()
        if oldChargeJump ~= menu.Charge.ChargeJump then
            menu.Misc.ChargeJump = menu.Charge.ChargeJump
        end
        TimMenu.EndSector()
    end

    if menu.currentTab == "Visuals" or menu.currentTab == 3 then
        TimMenu.BeginSector("Visuals")
        menu.Visuals.EnableVisuals = TimMenu.Checkbox("Enable", menu.Visuals.EnableVisuals)
        TimMenu.NextLine()
        menu.Visuals.Section = TimMenu.Selector("Section", menu.Visuals.Section, menu.Visuals.Sections)
        TimMenu.NextLine()
        if menu.Visuals.Section == 1 then
            menu.Visuals.Local.RangeCircle = TimMenu.Checkbox("Range Circle", menu.Visuals.Local.RangeCircle)
            TimMenu.NextLine()
            menu.Visuals.Local.path.enable = TimMenu.Checkbox("Local Path", menu.Visuals.Local.path.enable)
            TimMenu.NextLine()
            menu.Visuals.Local.path.Style = TimMenu.Selector("Path Style", menu.Visuals.Local.path.Style,
                menu.Visuals.Local.path.Styles)
            TimMenu.NextLine()
            menu.Visuals.Local.path.width = TimMenu.Slider("Width", menu.Visuals.Local.path.width, 1, 20, 0.1)
            TimMenu.NextLine()
        end
        if menu.Visuals.Section == 2 then
            menu.Visuals.Target.path.enable = TimMenu.Checkbox("Target Path", menu.Visuals.Target.path.enable)
            TimMenu.NextLine()
            menu.Visuals.Target.path.Style = TimMenu.Selector("Path Style", menu.Visuals.Target.path.Style,
                menu.Visuals.Target.path.Styles)
            TimMenu.NextLine()
            menu.Visuals.Target.path.width = TimMenu.Slider("Width", menu.Visuals.Target.path.width, 1, 20, 0.1)
            TimMenu.NextLine()
        end
        if menu.Visuals.Section == 3 then
            TimMenu.Text("Experimental")
            menu.Visuals.Sphere = TimMenu.Checkbox("Range Shield", menu.Visuals.Sphere)
            TimMenu.NextLine()
        end
        TimMenu.EndSector()
    end

    if menu.currentTab == "Misc" or menu.currentTab == 4 then
        TimMenu.BeginSector("Misc")
        menu.Misc.InstantAttack = TimMenu.Checkbox("Instant Attack", menu.Misc.InstantAttack)
        TimMenu.NextLine()
        if menu.Misc.InstantAttack then
            menu.Misc.WarpOnAttack = TimMenu.Checkbox("Warp On Attack", menu.Misc.WarpOnAttack)
            TimMenu.NextLine()
        end
        menu.Misc.advancedHitreg = TimMenu.Checkbox("Advanced Hitreg", menu.Misc.advancedHitreg)
        TimMenu.NextLine()
        menu.Misc.TroldierAssist = TimMenu.Checkbox("Troldier Assist", menu.Misc.TroldierAssist)
        TimMenu.NextLine()
        menu.Misc.CritRefill.Active = TimMenu.Checkbox("Auto Crit refill", menu.Misc.CritRefill.Active)
        TimMenu.NextLine()
        if menu.Misc.CritRefill.Active then
            menu.Misc.CritRefill.NumCrits = TimMenu.Slider("Crit Number", menu.Misc.CritRefill.NumCrits, 1, 25, 1)
            TimMenu.NextLine()
            menu.Misc.CritMode = TimMenu.Selector("Crit Mode", menu.Misc.CritMode, menu.Misc.CritModes)
            TimMenu.NextLine()
        end
        menu.Misc.strafePred = TimMenu.Checkbox("Local Strafe Pred", menu.Misc.strafePred)
        TimMenu.NextLine()
        TimMenu.EndSector()
    end

    TimMenu.End()
end

return MenuUI
