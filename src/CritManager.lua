---@class Entity
---@field IsDormant fun(self: Entity): boolean

---@class MenuMisc
---@field CritRefill table
---@field CritMode number

---@class Menu
---@field Misc MenuMisc


local CritManager            = {}

-- ─── Module state ──────────────────────────────────────────────────────────────

---@class CritManagerMenu
---@field Misc table
local _menu                  = nil

local _originalCritHackKey   = 0
local _originalMeleeCritHack = 0
local _menuWasOpen           = false
local _critRefillActive      = false

-- ─── Init ─────────────────────────────────────────────────────────────────────

function CritManager.Init(menuRef)
    assert(menuRef, "CritManager.Init: menuRef is nil")
    _menu = menuRef
end

-- ─── Tick ─────────────────────────────────────────────────────────────────────
---@param pCmd       UserCmd  CUserCmd
---@param pWeapon    Entity   active melee weapon
---@param hasTarget  boolean   whether a CurrentTarget exists
function CritManager.Tick(pCmd, pWeapon, hasTarget)
    assert(pCmd, "CritManager.Tick: pCmd is nil")
    assert(pWeapon, "CritManager.Tick: pWeapon is nil")

    local menuIsOpen = gui.IsMenuOpen()

    if menuIsOpen and not _menuWasOpen then
        _originalCritHackKey   = gui.GetValue("Crit Hack Key")
        _originalMeleeCritHack = gui.GetValue("Melee Crit Hack")
    end
    _menuWasOpen = menuIsOpen

    if menuIsOpen then
        return
    end

    local CritValue  = 39
    local CritBucket = pWeapon:GetCritTokenBucket()
    local NumCrits   = CritValue * _menu.Misc.CritRefill.NumCrits

    -- Clamp to safe range
    if NumCrits < 27 then NumCrits = 27 end
    if NumCrits > 1000 then NumCrits = 1000 end

    if not hasTarget and _menu.Misc.CritRefill.Active then
        if CritBucket < NumCrits then
            if not _critRefillActive then
                gui.SetValue("Crit Hack Key", 0)
                gui.SetValue("Melee Crit Hack", 2)
                _critRefillActive = true
            end
            pCmd:SetButtons(pCmd:GetButtons() | IN_ATTACK)
        else
            if _critRefillActive then
                gui.SetValue("Crit Hack Key", _originalCritHackKey)
                gui.SetValue("Melee Crit Hack", _menu.Misc.CritMode)
                _critRefillActive = false
            end
        end
    else
        if _critRefillActive then
            gui.SetValue("Crit Hack Key", _originalCritHackKey)
            gui.SetValue("Melee Crit Hack", _menu.Misc.CritMode)
            _critRefillActive = false
        end
    end
end

return CritManager
