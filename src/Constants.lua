--[[ Constants module for Swing prediction ]]
--
--[[ Game constants and definitions ]]
--

local Constants = {}

-- Entity-independent constants
Constants.SWING_RANGE = 48
Constants.TOTAL_SWING_RANGE = 48
Constants.SWING_HULL_SIZE = 38
Constants.SWING_HALF_HULL_SIZE = Constants.SWING_HULL_SIZE / 2
Constants.CHARGE_RANGE = 128
Constants.NORMAL_WEAPON_RANGE = 48
Constants.NORMAL_TOTAL_SWING_RANGE = 48
Constants.STEP_SIZE = 18

-- Hitbox dimensions
Constants.V_HITBOX = { Vector3(-24, -24, 0), Vector3(24, 24, 82) }

-- Class maximum speeds
Constants.CLASS_MAX_SPEEDS = {
    [1] = 400, -- Scout
    [2] = 300, -- Sniper
    [3] = 240, -- Soldier
    [4] = 280, -- Demoman
    [5] = 320, -- Medic
    [6] = 240, -- Heavy
    [7] = 300, -- Pyro
    [8] = 280, -- Spy
    [9] = 240, -- Engineer
}

-- Charge movement constants
Constants.CHARGE_CONSTANTS = {
    SIDE_MOVE_VALUE = 450, -- A/D key movement speed
    MAX_TURN_RATE = 73.04, -- Maximum turn per frame in degrees
    ACCELERATION = 750, -- Charge acceleration
}

-- Trace masks
Constants.MASK_SHOT_HULL = 1170801955
Constants.MASK_PLAYERSOLID = 1179647935
Constants.MASK_PLAYERSOLID_BRUSHONLY = 1179647935

-- Input constants
Constants.MOUSE_LEFT = 107
Constants.MOUSE_RIGHT = 108
Constants.MOUSE_MIDDLE = 109
Constants.MOUSE_FIRST = 107
Constants.KEY_SPACE = 32
Constants.KEY_ESCAPE = 27

-- Button constants
Constants.IN_ATTACK = 1
Constants.IN_ATTACK2 = 2
Constants.IN_JUMP = 2

-- Condition flags
Constants.FL_DUCKING = 2

return Constants
