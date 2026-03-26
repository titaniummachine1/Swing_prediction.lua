--[[ Imported by: Main ]]

local CritManager = {}

-- --- Initialization ----------------------------------------------------------

function CritManager.Init(menu)
    -- CritManager handles its own state in Tick
end

-- --- Module state ------------------------------------------------------------

local _originalCritHackKey = 0
local _originalMeleeCritHack = 0
local _menuWasOpen = false
local _critRefillActive = false

-- --- Tick --------------------------------------------------------------------

function CritManager.Tick(pCmd, pWeapon, hasTarget, isCharging, menuSettings)
    assert(pCmd, "CritManager.Tick: pCmd missing")
    assert(pWeapon, "CritManager.Tick: pWeapon missing")
    assert(menuSettings, "CritManager.Tick: menuSettings missing")

    local menuIsOpen = gui.IsMenuOpen()

    -- If menu just opened, update our stored values
    if menuIsOpen and not _menuWasOpen then
        _originalCritHackKey = gui.GetValue("Crit Hack Key")
        _originalMeleeCritHack = gui.GetValue("Melee Crit Hack")
    end

    _menuWasOpen = menuIsOpen

    -- Only proceed with crit refill logic when menu is closed
    if not menuIsOpen then
        local critRefillSettings = menuSettings.CritRefill
        if not critRefillSettings then return end

        local critValue = 39 -- Base value for crit token bucket calculation
        local critBucket = pWeapon:GetCritTokenBucket()
        local numCrits = critValue * (critRefillSettings.NumCrits or 1)

        -- Cap numCrits to ensure critBucket does not exceed 1000
        if numCrits < 27 then numCrits = 27 end
        if numCrits > 1000 then numCrits = 1000 end

        if not hasTarget and not isCharging and critRefillSettings.Active then
            -- Check if we need to refill the crit bucket
            if critBucket < numCrits then
                -- Start crit refill mode if not already active
                if not _critRefillActive then
                    gui.SetValue("Crit Hack Key", 0)   -- Disable crit hack key
                    gui.SetValue("Melee Crit Hack", 2) -- Set to "Stop" mode to store crits
                    _critRefillActive = true
                end

                -- Keep attacking to build crits
                pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
            else
                -- Crit bucket is full, restore user settings
                if _critRefillActive then
                    gui.SetValue("Crit Hack Key", _originalCritHackKey)
                    gui.SetValue("Melee Crit Hack", menuSettings.CritMode or 0)
                    _critRefillActive = false
                end
            end
        else
            -- We have a target or refill is disabled, restore settings if needed
            if _critRefillActive then
                gui.SetValue("Crit Hack Key", _originalCritHackKey)
                gui.SetValue("Melee Crit Hack", menuSettings.CritMode or 0)
                _critRefillActive = false
            end
        end
    end
end

function CritManager.IsRefilling()
    return _critRefillActive
end

return CritManager
