---
trigger: always_on
---

# Lmaobox Lua Coding Rules

## CRITICAL (Never Break)

### Memory & Callbacks

**NEVER `require()` in callbacks/functions** - causes memory leaks

- All imports at top of file only
- No runtime `require()` in CreateMove, Draw, or any callback

**NEVER `collectgarbage()` in runtime** - masks leaks, doesn't fix them

- Only allowed if user explicitly requests AND you warn about underlying leak

**NEVER unload callbacks inside other callbacks** - causes crashes

- Use dedicated `Unload` callback for cleanup
- Pattern:

```lua
callbacks.Unregister("Unload", "MyUnload")
callbacks.Register("Unload", "MyUnload", function()
    -- Safe cleanup here
end)
```

**Always unregister before registering callbacks**

```lua
callbacks.Unregister("CreateMove", "MyName")
callbacks.Register("CreateMove", "MyName", onCreateMove)

callbacks.Unregister("Draw", "MyName")
callbacks.Register("Draw", "MyName", onDraw)

callbacks.Unregister("Unload", "MyName")
callbacks.Register("Unload", "MyName", onUnload)
```

### MCP Authority

**MCP is source of truth** - ALWAYS use MCP tools:

- `bundle` - Deploy to %LOCALAPPDATA%/lua
- `get_types` - Get API symbol types
- `get_smart_context` - Get curated context
- `trace_bundle_error` - Trace errors to source

FORBIDDEN:

- Guessing API behavior
- Guessing return types
- Guessing side effects

If MCP contradicts intuition → MCP wins
If user overrides → follow user

---

## High Priority

### Zero Trust Protocol

**Trust ONLY locals created in current function**

External = untrusted:

- Function parameters
- Globals (`G.*`, `_G`)
- `self.*`
- Upvalues
- Engine objects
- Returns from any function

Required pattern:

```lua
local function example(param)
    assert(param, "example: param missing")
    local ply = entities.GetLocalPlayer()
    assert(ply and ply.IsAlive, "example: invalid LocalPlayer")
    -- Trusted zone below
end
```

- No silent fallbacks
- No `or default` for external data
- No guessing nilability

### Performance - Zero Allocations

**Per-frame code must allocate NOTHING:**

- No table creation
- No closures
- No string concatenation
- No `require()` calls
- Hoist constants outside callbacks
- Reuse pre-allocated tables

### Code Clarity

**Self-explanatory code > comments**

- Use clear function/variable names
- If code needs comment to explain HOW → rewrite it
- Comments only for: intent, approach, why (never how)

Rule: If you want to comment how code works → simplify the code

---

## Recommended

### File Structure (Strict Order)

```lua
-- 1. IMPORTS (top-level only)
local FastPlayers = require("FastPlayers")

-- 2. CONSTANTS
local MAX_DISTANCE = 1000
local TEAM_RED = 2

-- 3. HELPER FUNCTIONS (pure, no side effects)
local function calculateDistance(a, b)
    return vectorDistance(a, b)
end

-- 4. RUNTIME LOGIC
local cachedPlayers = {}

local function onCreateMove()
    -- Per-frame logic
end

-- 5. CALLBACK REGISTRATION (END OF FILE)
callbacks.Unregister("CreateMove", "MyScript")
callbacks.Register("CreateMove", "MyScript", onCreateMove)
```

### Function Rules

- Named functions only (no anonymous)
- ≤ 40 lines of code
- One responsibility:
  - Decision OR
  - Transformation OR
  - Side effects (never mix)

---

## Lmaobox Specifics

### Entity Iteration

**Use `pairs()` not `ipairs()`** - player lists are non-sequential

```lua
for _, ent in pairs(entities.FindByClass("CTFPlayer")) do
    if ent and ent:IsValid() and ent:IsAlive() then
        -- Process entity
    end
end
```

### Engine Objects

**Engine objects invalid by default** - always validate:

```lua
local ply = entities.GetLocalPlayer()
assert(ply, "LocalPlayer is nil")
assert(ply.IsAlive, "LocalPlayer missing IsAlive")
if not ply:IsAlive() then return end
```

Caching policy:

- Only cache with validity checks
- Prefer `FastPlayers` module when available
- Don't manually cache if `FastPlayers` exists

### Vector Operations

```lua
-- Normalize (direction, not math convenience)
local function normalize(vec)
    return vectorDivide(vec, vectorLength(vec))
end

-- Distance 2D
local function distance2D(a, b)
    return (a - b):Length2D()
end

-- Distance 3D (fastest)
local function distance3D(a, b)
    return vectorDistance(a, b)
end

-- Available methods
local len = vec:Length()
local len2d = vec:Length2D()
local cross = vec1:Cross(vec2)
local dot = vec1:Dot(vec2)
```

Rule: Only normalize when you need **direction**, not as math shortcut

---

## FastPlayers Pattern

```lua
local FastPlayers = {}

-- Pre-allocated tables
local cachedAllPlayers = {}
local cachedEnemies = {}
local cachedTeammates = {}

-- State
local cachedLocal = nil
local cachedLocalTeam = nil
local lastHighestIndex = -1

local function onCreateMove()
    local currentHighestIndex = entities.GetHighestEntityIndex()
    if currentHighestIndex ~= lastHighestIndex then
        lastHighestIndex = currentHighestIndex
        FastPlayers.Update()
    end
end

local function onPlayerEvent(event)
    local eventName = event:GetName()
    if eventName == "player_death"
        or eventName == "player_spawn"
        or eventName == "player_team" then
        FastPlayers.Update()
    end
end

function FastPlayers.Update()
    cachedLocal = entities.GetLocalPlayer()
    local newTeam = cachedLocal and cachedLocal:GetTeamNumber() or nil

    if newTeam ~= cachedLocalTeam then
        cachedLocalTeam = newTeam
    end

    -- Clear arrays
    for i = 1, globals.MaxClients() do
        cachedAllPlayers[i] = nil
        cachedEnemies[i] = nil
        cachedTeammates[i] = nil
    end

    -- Repopulate
    local writeIdx = 0
    local enemyIdx = 0
    local teamIdx = 0

    for _, ent in pairs(entities.FindByClass("CTFPlayer")) do
        if ent and ent:IsValid() and ent:IsAlive() and not ent:IsDormant() then
            writeIdx = writeIdx + 1
            cachedAllPlayers[writeIdx] = ent

            if cachedLocalTeam then
                if ent:GetTeamNumber() == cachedLocalTeam then
                    teamIdx = teamIdx + 1
                    cachedTeammates[teamIdx] = ent
                else
                    enemyIdx = enemyIdx + 1
                    cachedEnemies[enemyIdx] = ent
                end
            end
        end
    end
end

function FastPlayers.GetAll() return cachedAllPlayers end
function FastPlayers.GetEnemies() return cachedEnemies end
function FastPlayers.GetTeammates() return cachedTeammates end
function FastPlayers.GetLocal() return cachedLocal end

-- Callback registration at END
callbacks.Unregister("FireGameEvent", "FastPlayers_Events")
callbacks.Unregister("CreateMove", "FastPlayers_Update")
callbacks.Register("FireGameEvent", "FastPlayers_Events", onPlayerEvent)
callbacks.Register("CreateMove", "FastPlayers_Update", onCreateMove)

return FastPlayers
```

---

## Forbidden Patterns

### Tables & State

- No mixed tables (data + behavior)
- No logic stored in state tables
- No mutation during iteration

### Globals

- May write at init
- May update in controlled runtime paths
- Never ad-hoc modification

### Lua Features (Use Sparingly)

- **Metatables:** Only with explicit justification
- **Clever one-liners:** Forbidden
- **`and/or` flow tricks:** Forbidden
- **Implicit returns:** Forbidden

---

## Pre-Deployment Checklist

- [ ] All external data asserted
- [ ] No guessed APIs (used MCP)
- [ ] No `require()` inside functions/callbacks
- [ ] No `collectgarbage()` calls
- [ ] Per-frame paths allocate nothing
- [ ] Callbacks registered at END
- [ ] Names express intent without comments
- [ ] Used MCP `bundle` for deployment

---

## Error Handling

**Assert + hard crash when:**

- Undefined behavior would occur
- Input violates assumptions

**No silent recovery**

```lua
local function process(data)
    assert(type(data) == "table", "process: data must be table")
    assert(data.x and data.y, "process: missing x or y")
    -- Safe to use data.x and data.y
end
```

---

## Deployment

**Always use MCP `bundle`**

- Never simulate deploy manually
- Bundling is atomic
- Don't bundle during debug unless requested

Use MCP tool: bundle
Path: folder containing Main.lua or main.lua

---

## AI Guardrails (Immediate Rewrite If Detected)

- Runtime `require()` calls
- `collectgarbage()` usage without user override
- Implicit globals
- Guessed APIs
- Reused names with different meaning
- Abstraction at 2 uses (wait for 3+)
- Silent nil handling
- Unnamed magic numbers
- Unclear math intent
