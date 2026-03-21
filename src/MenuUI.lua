--[[ Imported by: Main ]]
-- Menu rendering and keybind UI handling.

local lnxLib = require("lnxlib")
local ImMenu = require("immenu")

local Input = lnxLib.Utils.Input
local Notify = lnxLib.UI.Notify

local MenuUI = {}

local bindTimer = 0
local bindDelay = 0.25

local function GetPressedkey()
    local pressedKey = Input.GetPressedKey()
    if not pressedKey then
        if input.IsButtonDown(MOUSE_LEFT) then return MOUSE_LEFT end
        if input.IsButtonDown(MOUSE_RIGHT) then return MOUSE_RIGHT end
        if input.IsButtonDown(MOUSE_MIDDLE) then return MOUSE_MIDDLE end

        for i = 1, 10 do
            if input.IsButtonDown(MOUSE_FIRST + i - 1) then return MOUSE_FIRST + i - 1 end
        end
    end
    return pressedKey
end

local function handleKeybind(noKeyText, keybind, keybindName)
    if keybindName ~= "Press The Key" and ImMenu.Button(keybindName or noKeyText) then
        bindTimer = os.clock() + bindDelay
        keybindName = "Press The Key"
    elseif keybindName == "Press The Key" then
        ImMenu.Text("Press the key")
    end

    if keybindName == "Press The Key" and os.clock() >= bindTimer then
        local pressedKey = GetPressedkey()
        if pressedKey then
            if pressedKey == KEY_ESCAPE then
                keybind = 0
                keybindName = "Always On"
                Notify.Simple("Keybind Success", "Bound Key: " .. keybindName, 2)
            else
                keybind = pressedKey
                keybindName = Input.GetKeyName(pressedKey)
                Notify.Simple("Keybind Success", "Bound Key: " .. keybindName, 2)
            end
        end
    end

    return keybind, keybindName
end

function MenuUI.Render(menu)
    assert(menu, "MenuUI.Render: menu is nil")

    if not (gui.IsMenuOpen() and ImMenu and ImMenu.Begin("Swing Prediction")) then
        return
    end

    ImMenu.BeginFrame(1)
    menu.currentTab = ImMenu.TabControl(menu.tabs, menu.currentTab)
    ImMenu.EndFrame()

    if menu.currentTab == 1 then
        ImMenu.BeginFrame(1)
        menu.Aimbot.Aimbot = ImMenu.Checkbox("Enable", menu.Aimbot.Aimbot)
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        menu.Aimbot.Silent = ImMenu.Checkbox("Silent Aim", menu.Aimbot.Silent)
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        menu.Aimbot.AimbotFOV = ImMenu.Slider("Fov", menu.Aimbot.AimbotFOV, 1, 360)
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        local swingTimeMaxDisplay = menu.Aimbot.MaxSwingTime or 13
        local swingTimeLabel = string.format("Swing Time (max: %d)", swingTimeMaxDisplay)
        menu.Aimbot.SwingTime = ImMenu.Slider(swingTimeLabel, menu.Aimbot.SwingTime, 1, swingTimeMaxDisplay)
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        menu.Aimbot.AlwaysUseMaxSwingTime = ImMenu.Checkbox("Always Use Max Swing Time",
            menu.Aimbot.AlwaysUseMaxSwingTime)
        if menu.Aimbot.AlwaysUseMaxSwingTime then
            menu.Aimbot.SwingTime = menu.Aimbot.MaxSwingTime or 13
        end
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        ImMenu.Text("Keybind: ")
        menu.Keybind, menu.KeybindName = handleKeybind("Always On", menu.Keybind, menu.KeybindName)
        ImMenu.EndFrame()
    end

    if menu.currentTab == 2 then
        ImMenu.BeginFrame(1)
        local oldValue = menu.Charge.ChargeBot
        menu.Charge.ChargeBot = ImMenu.Checkbox("Charge Bot", menu.Charge.ChargeBot)
        if oldValue ~= menu.Charge.ChargeBot then
            menu.Aimbot.ChargeBot = menu.Charge.ChargeBot
        end
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        local oldChargeControl = menu.Charge.ChargeControl
        menu.Charge.ChargeControl = ImMenu.Checkbox("Charge Control", menu.Charge.ChargeControl)
        if oldChargeControl ~= menu.Charge.ChargeControl then
            menu.Misc.ChargeControl = menu.Charge.ChargeControl
        end
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        local oldChargeReach = menu.Charge.ChargeReach
        menu.Charge.ChargeReach = ImMenu.Checkbox("Charge Reach", menu.Charge.ChargeReach)
        if oldChargeReach ~= menu.Charge.ChargeReach then
            menu.Misc.ChargeReach = menu.Charge.ChargeReach
        end
        if menu.Charge.ChargeReach then
            menu.Charge.LateCharge = ImMenu.Checkbox("Late Charge", menu.Charge.LateCharge)
        end
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        local oldChargeJump = menu.Charge.ChargeJump
        menu.Charge.ChargeJump = ImMenu.Checkbox("Charge Jump", menu.Charge.ChargeJump)
        if oldChargeJump ~= menu.Charge.ChargeJump then
            menu.Misc.ChargeJump = menu.Charge.ChargeJump
        end
        ImMenu.EndFrame()
    end

    if menu.currentTab == 4 then
        ImMenu.BeginFrame()
        menu.Misc.InstantAttack = ImMenu.Checkbox("Instant Attack", menu.Misc.InstantAttack)
        if menu.Misc.InstantAttack then
            menu.Misc.WarpOnAttack = ImMenu.Checkbox("Warp On Attack", menu.Misc.WarpOnAttack)
        end
        menu.Misc.advancedHitreg = ImMenu.Checkbox("Advanced Hitreg", menu.Misc.advancedHitreg)
        menu.Misc.TroldierAssist = ImMenu.Checkbox("Troldier Assist", menu.Misc.TroldierAssist)
        ImMenu.EndFrame()

        ImMenu.BeginFrame()
        menu.Misc.CritRefill.Active = ImMenu.Checkbox("Auto Crit refill", menu.Misc.CritRefill.Active)
        if menu.Misc.CritRefill.Active then
            menu.Misc.CritRefill.NumCrits = ImMenu.Slider("Crit Number", menu.Misc.CritRefill.NumCrits, 1, 25)
        end
        ImMenu.EndFrame()

        ImMenu.BeginFrame()
        if menu.Misc.CritRefill.Active then
            menu.Misc.CritMode = ImMenu.Option(menu.Misc.CritMode, menu.Misc.CritModes)
        end
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        menu.Misc.strafePred = ImMenu.Checkbox("Local Strafe Pred", menu.Misc.strafePred)
        ImMenu.EndFrame()
    end

    if menu.currentTab == 3 then
        ImMenu.BeginFrame(1)
        menu.Visuals.EnableVisuals = ImMenu.Checkbox("Enable", menu.Visuals.EnableVisuals)
        ImMenu.EndFrame()

        ImMenu.BeginFrame(1)
        menu.Visuals.Section = ImMenu.Option(menu.Visuals.Section, menu.Visuals.Sections)
        ImMenu.EndFrame()

        if menu.Visuals.Section == 1 then
            menu.Visuals.Local.RangeCircle = ImMenu.Checkbox("Range Circle", menu.Visuals.Local.RangeCircle)
            menu.Visuals.Local.path.enable = ImMenu.Checkbox("Local Path", menu.Visuals.Local.path.enable)
            menu.Visuals.Local.path.Style = ImMenu.Option(menu.Visuals.Local.path.Style, menu.Visuals.Local.path.Styles)
            menu.Visuals.Local.path.width = ImMenu.Slider("Width", menu.Visuals.Local.path.width, 1, 20, 0.1)
        end

        if menu.Visuals.Section == 2 then
            menu.Visuals.Target.path.enable = ImMenu.Checkbox("Target Path", menu.Visuals.Target.path.enable)
            menu.Visuals.Target.path.Style = ImMenu.Option(menu.Visuals.Target.path.Style,
                menu.Visuals.Target.path.Styles)
            menu.Visuals.Target.path.width = ImMenu.Slider("Width", menu.Visuals.Target.path.width, 1, 20, 0.1)
        end

        if menu.Visuals.Section == 3 then
            ImMenu.BeginFrame(1)
            ImMenu.Text("Experimental")
            menu.Visuals.Sphere = ImMenu.Checkbox("Range Shield", menu.Visuals.Sphere)
            ImMenu.EndFrame()
        end
    end

    ImMenu.End()
end

return MenuUI
