--[[ Imported by: Main ]]
-- Menu rendering and keybind UI handling.


local lnxLib = require("lnxlib")
local TimMenu = require("TimMenu")


local Input = lnxLib.Utils.Input
local Notify = lnxLib.UI.Notify

local MenuUI = {}


local activationModes = { "Always On", "Hold", "On Release", "Toggle" }
local activationModeValues = { 0, 1, 3, 2 }
local bindCaptureState = {
    activeId = nil,
    waitingRelease = false,
}

local function keyToLabel(key)
    local resolvedKey = tonumber(key) or 0
    if resolvedKey == 0 then
        return "NONE"
    end

    if resolvedKey == MOUSE_LEFT then
        return "MOUSE1"
    end
    if resolvedKey == MOUSE_RIGHT then
        return "MOUSE2"
    end

    local keyName = nil
    if Input and Input.GetKeyName then
        keyName = Input.GetKeyName(resolvedKey)
    end

    if type(keyName) == "string" and keyName ~= "" and keyName ~= "UNKNOWN" then
        return keyName
    end

    return tostring(resolvedKey)
end

local function modeToSelectorIndex(mode)
    local normalizedMode = tonumber(mode) or 0
    for index, modeValue in ipairs(activationModeValues) do
        if modeValue == normalizedMode then
            return index
        end
    end
    return 1
end

local function selectorIndexToMode(index)
    local resolved = activationModeValues[tonumber(index) or 1]
    if resolved == nil then
        return 0
    end
    return resolved
end

local function normalizeKeybind(bind, defaultMode)
    local fallbackMode = tonumber(defaultMode) or 0
    if fallbackMode < 0 or fallbackMode > 3 then
        fallbackMode = 0
    end

    if type(bind) == "table" then
        local key = bind.key
        local mode = bind.mode
        local id = bind.id

        if type(key) == "table" then
            if mode == nil then
                mode = key.mode
            end
            key = key.key
        end

        key = tonumber(key) or 0
        mode = tonumber(mode)
        if mode == nil or mode < 0 or mode > 3 then
            mode = fallbackMode
        end

        if key == 0 then
            mode = 0
        end

        return { key = key, mode = mode, id = id }
    end

    local normalizedKey = tonumber(bind) or 0
    if normalizedKey == 0 then
        return { key = normalizedKey, mode = 0, id = nil }
    end
    return { key = normalizedKey, mode = fallbackMode, id = nil }
end

local function applyKeybindResult(existingBind, result)
    local normalized = normalizeKeybind(existingBind, 0)
    if type(result) == "table" then
        return normalizeKeybind(result, normalized.mode)
    end

    normalized.key = tonumber(result) or 0
    if normalized.key == 0 then
        normalized.mode = 0
    end
    return normalized
end

local function renderKeybindControls(label, bind)
    local updatedBind = normalizeKeybind(bind, 0)
    local bindId = tostring(updatedBind.id or label)
    local isCapturing = bindCaptureState.activeId == bindId

    local buttonLabel = label .. ": [" .. keyToLabel(updatedBind.key) .. "]"
    if isCapturing then
        buttonLabel = label .. ": [PRESS KEY]"
    end

    if (not isCapturing) and TimMenu.Button(buttonLabel) then
        bindCaptureState.activeId = bindId
        bindCaptureState.waitingRelease = true
    elseif isCapturing then
        TimMenu.Button(buttonLabel)
    end
    TimMenu.NextLine()

    if isCapturing then
        if bindCaptureState.waitingRelease then
            if not input.IsButtonDown(MOUSE_LEFT) then
                bindCaptureState.waitingRelease = false
            end
        else
            if input.IsButtonPressed(MOUSE_LEFT) then
                updatedBind.key = MOUSE_LEFT
                bindCaptureState.activeId = nil
                bindCaptureState.waitingRelease = false
            end

            for code = 1, 255 do
                if bindCaptureState.activeId == nil then
                    break
                end

                if input.IsButtonPressed(code) then
                    if code == KEY_ESCAPE then
                        updatedBind.key = 0
                        updatedBind.mode = 0
                    else
                        updatedBind.key = code
                    end
                    bindCaptureState.activeId = nil
                    bindCaptureState.waitingRelease = false
                    break
                end
            end
        end
    end

    local selectorIndex = modeToSelectorIndex(updatedBind.mode)
    local nextSelectorIndex = TimMenu.Selector(label .. " Mode", selectorIndex, activationModes)
    updatedBind.mode = selectorIndexToMode(nextSelectorIndex)
    if updatedBind.key == 0 then
        updatedBind.mode = 0
    end

    return normalizeKeybind(updatedBind, 0)
end


function MenuUI.Render(menu)
    assert(menu, "MenuUI.Render: menu is nil")

    if type(menu.Charge) ~= "table" then
        menu.Charge = {}
    end
    local rawChargeBotFOV = tonumber(menu.Charge.ChargeBotFOV)
    if not rawChargeBotFOV then
        rawChargeBotFOV = 90
    end
    menu.Charge.ChargeBotFOV = math.max(1, math.min(180, rawChargeBotFOV))
    menu.Aimbot.Keybind = normalizeKeybind(menu.Aimbot.Keybind, 0)
    menu.Charge.Keybind = normalizeKeybind(menu.Charge.Keybind, 0)

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
        menu.Aimbot.Keybind.id = "aimbot"
        menu.Aimbot.Keybind = renderKeybindControls("Aimbot Keybind", menu.Aimbot.Keybind)
        TimMenu.NextLine()
        TimMenu.EndSector()
    end


    if menu.currentTab == "Demoknight" or menu.currentTab == 2 then
        TimMenu.BeginSector("Demoknight")
        menu.Charge.ChargeBot = TimMenu.Checkbox("Charge Bot", menu.Charge.ChargeBot)
        TimMenu.NextLine()
        if menu.Charge.ChargeBot then
            menu.Charge.ChargeBotFOV = TimMenu.Slider("ChargeBot FOV", menu.Charge.ChargeBotFOV or 90, 1, 180, 1)
            TimMenu.NextLine()
            menu.Charge.Keybind.id = "chargebot"
            menu.Charge.Keybind = renderKeybindControls("ChargeBot Keybind", menu.Charge.Keybind)
            TimMenu.NextLine()
        end
        menu.Charge.ChargeControl = TimMenu.Checkbox("Charge Control", menu.Charge.ChargeControl)
        TimMenu.NextLine()
        menu.Charge.ChargeReach = TimMenu.Checkbox("Charge Reach", menu.Charge.ChargeReach)
        TimMenu.NextLine()
        if menu.Charge.ChargeReach then
            menu.Charge.LateCharge = TimMenu.Checkbox("Late Charge", menu.Charge.LateCharge)
            TimMenu.NextLine()
        end
        menu.Charge.ChargeJump = TimMenu.Checkbox("Charge Jump", menu.Charge.ChargeJump)
        TimMenu.NextLine()
        TimMenu.EndSector()
    end

    if menu.currentTab == "Visuals" or menu.currentTab == 3 then
        TimMenu.BeginSector("Visuals")
        menu.Visuals.EnableVisuals = TimMenu.Checkbox("Enable", menu.Visuals.EnableVisuals)
        TimMenu.NextLine()
        menu.Visuals.Profiler = TimMenu.Checkbox("Profiler", menu.Visuals.Profiler)
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
