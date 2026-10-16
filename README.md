# Night Time Studios Movement System

Momentum based movement for an R6 RPG: sprint, slide, jumps, wall movement, vaults and a directional dash. The client moves its own character, the server checks it and keeps its own record of what each player is allowed to be doing.

**Status:** design only. Nothing here is implemented yet, and every number is an untested starting value. All of them live in `Config.luau` and get tuned by playing at real ping.

Combat is covered in its own document. The two share one server module, `StateService` (section 7.1).

References like C5 or C20 point at sections of `CONVENTIONS.md`, the rulebook for all code in this project.

## Contents

1. [Overview](#1-overview)
2. [States](#2-states)
3. [Transitions](#3-transitions)
4. [Momentum](#4-momentum)
5. [Probes](#5-probes)
6. [Vault](#6-vault)
7. [Server](#7-server)
8. [Remotes](#8-remotes)
9. [Client](#9-client)
10. [Layout](#10-layout)
11. [Config](#11-config)
12. [Packages](#12-packages)
13. [Server Authority](#13-server-authority)
14. [Decisions and open questions](#14-decisions-and-open-questions)
15. [Build order](#15-build-order)

---

## 1. Overview

Fixed decisions the rest of the document builds on.

- **R6 only.** No `RigType` branching, no R15 part names (C18).
- **The client moves its own character.** The server never prevents movement. It checks it and records it (C20).
- **The server trusts no client claim.** It never reads a client `WalkSpeed`, a position claim or an "I am running" flag to decide anything.
- **Humanoid stays as the character body.** Ground and air physics come from the Humanoid. Special states (slide, wall states, leaps) use movers on `HumanoidRootPart`.
- **Not built on Roblox Server Authority** (section 13). All input goes through one controller so a later move is cheap.
- **End times, not timers.** `endsAt`, `cooldownUntil` and `dodgeUntil` are compared against the clock. No `task.delay` chains flipping state.
- **Dash is an overlay action, not a state** (section 3.1).

---

## 2. States

16 states in three groups. **Wire** is the name the client sends to the server. Idle and CrouchIdle are never sent on their own, they ride on Walk and CrouchWalk, so Idle <-> Walk changes cost no traffic.

| State | Group | Wire | Timed | Notes |
|---|---|---|---|---|
| Idle | Grounded | Walk | no | |
| Walk | Grounded | Walk | no | |
| Run | Grounded | Run | no | Sprint, builds momentum |
| Slide | Grounded | Slide | until speed drops | Run plus crouch key only. Ends in CrouchWalk if there is no headroom to stand |
| CrouchIdle | Grounded | CrouchWalk | no | |
| CrouchWalk | Grounded | CrouchWalk | no | |
| VaultLow | Grounded | VaultLow | `VAULT_LOW_TIME` | Run into a vaultable obstacle, automatic (section 6) |
| Jump | Airborne | Jump | no | |
| DoubleJump | Airborne | DoubleJump | no | One air jump per airtime |
| SlideJump | Airborne | SlideJump | no | Jump out of Slide, keeps and adds momentum |
| Fall | Airborne | Fall | no | No key. Entered on walking off a ledge, or when a leap or boost ends |
| WallRun | Wall | WallRun | `WALLRUN_MAX_TIME` | Jump pressed in the air at a wall, side on to it |
| WallLeap | Wall | WallLeap | `LEAP_TIME` | Jump pressed in a wall run. Arcs away from the wall, then Fall |
| WallCling | Wall | WallCling | `CLING_MAX_TIME` | Jump pressed in the air at a wall, facing it |
| WallBoost | Wall | WallBoost | `BOOST_TIME` | Jump pressed in a cling. Vertical launch up the wall, then Fall |
| VaultMid | Wall | VaultMid | `VAULT_MID_TIME` | F near a ledge from WallCling or WallBoost (section 6) |

**Timed states.** The server stores `endsAt` and resolves an expired state to its `after` state the next time it is read. No timer fires.

**Landing is not a state.** It is whichever grounded state the input and momentum call for at the moment of ground contact: Run if sprint is held, Slide if crouch is held and speed is high enough, otherwise Walk, Idle or CrouchWalk. Momentum survives a landing for `LAND_GRACE` seconds (section 4).

---

## 3. Transitions

Rows use wire names, so Idle shares the Walk row and CrouchIdle shares the CrouchWalk row. "Land" means any grounded state, and the server only accepts it if its own ground probe hits (section 7.2).

```
Walk        -> Run, CrouchWalk, Jump, Fall, VaultLow
Run         -> Walk, Slide, Jump, Fall, VaultLow
Slide       -> Run, Walk, CrouchWalk, SlideJump, Fall
CrouchWalk  -> Walk, Run, Jump, Fall
VaultLow    -> Run, Walk, Fall
VaultMid    -> Walk, Fall
Jump        -> DoubleJump, Fall, WallRun, WallCling, Land
DoubleJump  -> Fall, WallRun, WallCling, Land
SlideJump   -> DoubleJump, Fall, WallRun, WallCling, Land
Fall        -> DoubleJump, WallRun, WallCling, Land
WallRun     -> WallLeap, Fall, Land
WallLeap    -> Fall, WallRun, WallCling, Land
WallCling   -> WallBoost, VaultMid, Fall, Land
WallBoost   -> VaultMid, Fall, WallRun, WallCling, Land
```

Rules on top of the table:

- **Wall states start in the air only.** Pressing Jump in the air with a valid wall probe starts WallRun or WallCling, whichever the facing says (section 5.1), and wins over DoubleJump. Jump in a WallRun is WallLeap, Jump in a WallCling is WallBoost.
- **No regrabbing the same wall.** After leaving a wall, `WALL_REGRAB` seconds must pass, and the server remembers `lastWallPart` and refuses that part until the player has landed. Chaining only works onto a different part. This is one check in `MovementService`, easy to change.
- **Air jumps.** DoubleJump needs `airJumps < MAX_AIR_JUMPS`, and the counter only resets on landing. Wall states neither refund nor spend it, so an unused air jump is still there after a WallLeap or WallBoost ends in Fall.
- **VaultMid starts from WallCling or WallBoost only.** Nothing vaults in mid air.
- **Nothing starts while Stunned, Downed or Attacking.** The server asks `StateService` (section 7.1), not combat internals.

### 3.1 Dash

Dash is an overlay action, not a state. The player can be in any allowed grounded or airborne state and dash in one of four directions relative to the character: Forward, Back, Left, Right. It does not change the move state. It records `dashUntil`, and `dodgeUntil` for iframes, because the dash is the dodge.

- **Allowed from:** Idle, Walk, Run, CrouchWalk, Jump, DoubleJump, SlideJump, Fall. **Not from:** Slide, VaultLow, VaultMid and the wall states. Refused while Stunned or Downed.
- **Direction** comes from the movement keys held when the dash key is pressed. No key held dashes Forward.
- **Cost:** works in the air, cooldown only (`DASH_COOLDOWN`). No charges and no stamina cost for now.
- **Movement:** a short `LinearVelocity` burst on `HumanoidRootPart` for `DASH_TIME` at `DASH_SPEED`. It does not change momentum, speed returns to what it was before the dash.
- **Server record:** `dashUntil`, `dodgeUntil` and `dashCooldownUntil`. It raises the speed window cap while `dashUntil` is in the future and tells the other clients with `DashFx`.

---

## 4. Momentum

Momentum is one number: carried horizontal speed in studs per second. It lives on the client, in the movement controller. The server never trusts it, it only bounds it (section 7.4).

| Event | Effect |
|---|---|
| Run | Holds momentum at `RUN_SPEED` or above, builds slowly while running straight |
| Walk, Crouch | Momentum decays to the state's speed at `MOMENTUM_GROUND_DECAY` |
| Slide start | Momentum x `SLIDE_BOOST`, then decays at `SLIDE_DECAY`. Ends under `SLIDE_END_SPEED` |
| SlideJump | Keeps momentum, adds `SLIDE_JUMP_GAIN` |
| Air | Decays slowly at `MOMENTUM_AIR_DECAY`. Steering turns the velocity direction (`AIR_TURN_RATE`), it does not add speed |
| WallRun | Holds momentum, decays at `WALLRUN_DECAY`, falls at `WALLRUN_FALL_SPEED` |
| WallLeap | Momentum becomes velocity along the wall plus `LEAP_OUT` away from the wall plus `LEAP_UP`, adds `LEAP_GAIN` |
| WallCling | Horizontal momentum is dropped, slides down the wall at `CLING_SLIDE_SPEED` |
| WallBoost | Vertical launch up the wall (`BOOST_UP`), no push away from it |
| VaultLow | Momentum x `VAULT_BOOST`, capped at `MOMENTUM_MAX` |
| VaultMid | Momentum unchanged |
| Dash | No change, speed returns to what it was before the dash |
| Landing | Momentum is kept if a state that carries it (Run, Slide) is entered within `LAND_GRACE`, otherwise it decays as normal |
| Hard cap | `MOMENTUM_MAX`, nothing exceeds it |

### How it is applied on R6

- **Ground and air walking:** the controller sets `Humanoid.WalkSpeed` from momentum each step. That is the client's own value and the server ignores it.
- **Slide, WallRun, WallLeap, WallBoost:** a `LinearVelocity` on `HumanoidRootPart`, created once per character and enabled per state. Plane mode lets gravity keep working on the axis the plane leaves free. Slide uses the ground plane, WallRun uses the wall plane.
- **Facing the wall in WallCling:** an `AlignOrientation` on `HumanoidRootPart`, also created once.
- **Dash:** the same `LinearVelocity`, a short burst at `DASH_SPEED` in the chosen direction.
- **VaultLow and VaultMid:** an `AlignPosition` moves `HumanoidRootPart` along a short path built from the probe, and a `NoCollisionConstraint` between the character and the obstacle part stays for the length of the vault. Both are created per vault and destroyed when it ends.
- **During wall states** `Humanoid.AutoRotate = false`. Humanoid states the game does not use are turned off with `SetStateEnabled`.
- No `BodyVelocity` and friends (C16). Forces and movers go on `HumanoidRootPart` (C18).

---

## 5. Probes

`Probes` is a shared, stateless module. The client uses it to decide and the server uses it to verify, each with its own positions.

R6 facts: every character is the same size, so all of these are constants. `HumanoidRootPart` is 2x2x1 and its centre sits about 3 studs above the floor. Check this in Studio before trusting `GROUND_RAY`.

Raycast params are built once with `CollisionGroup = "MoveProbe"`, which collides with Default and not with Characters. Decorative parts have `CanQuery = false` (C23).

### 5.1 Wall probe

Runs when Jump is pressed in the air on the client, and once per Move intent on the server.

The origin is the `HumanoidRootPart` position. Three rays of length `WALL_REACH` are cast: forward (look vector), right and left. Each hit is rejected if:

- `math.abs(normal.Y) > WALL_MAX_NORMAL_Y` (floor, ceiling or slope).
- The part is not `Anchored` or has the attribute `NoWall`. An exploiter owns and can place unanchored parts near themselves.
- It fails the span check: the ray is repeated at the `WALL_SPAN_OFFSETS` heights (head and feet), and the centre plus at least one other must hit the same part. This keeps a ledge corner from counting as a wall.

**Classification** uses the character's facing against the wall, flattened to the horizontal plane. `L` is the look vector and `N` the wall normal, so `facing = -L:Dot(N)`, where 1 means looking straight at the wall.

| Facing | Result |
|---|---|
| `facing >= FACING_SPLIT` (0.7, about 45 degrees off head on) | WallCling |
| anything lower | WallRun. Side from `RightVector:Dot(-N)`: above 0 is Right, otherwise Left |

There is no dead zone because the choice is made once, on the key press, so nothing can flicker. A wall works from any facing angle. The probe only casts forward, right and left, so a wall directly behind the character is not found. Add a back ray if that should count.

**WallRun speed condition:** horizontal speed must be at least `WALLRUN_MIN_SPEED`. Below it the probe returns nothing for a WallRun and Jump stays a DoubleJump. WallCling has no speed condition. On the client the speed is its own, on the server it is the speed measured between samples.

Returns `{ kind: "Run" | "Cling", side: "Left" | "Right"?, normal: Vector3, part: BasePart }?`.

### 5.2 Ground probe

One ray straight down from `HumanoidRootPart`, length `GROUND_RAY`, same params. The server uses it for Jump and Land checks and the client uses it for landing.

### 5.3 Vault probe

`Probes.vault` returns a Low or a Mid hit. See section 6.

---

## 6. Vault

Two vaults, two states.

| | VaultLow | VaultMid |
|---|---|---|
| Trigger | Automatic when moving into a vaultable obstacle | F while in WallCling or WallBoost near a ledge |
| Allowed from | Walk, Run. Not Slide, not mid air | WallCling, WallBoost |
| Minimum speed | none | none |
| Momentum | x `VAULT_BOOST`, capped at `MOMENTUM_MAX` | unchanged |
| Ends in | Run if Shift is held, otherwise Walk | Walk, standing on the ledge |
| Animation | VaultLow | VaultMid (latch and pull up) |
| Duration | `VAULT_LOW_TIME` | `VAULT_MID_TIME` |

### Marking

A part is vaultable only if it, or the model it sits in, has the attribute `Vaultable = true`. Geometry alone is never enough.

In a large RPG, "any anchored part in a height range" would vault over trim, props, fences, NPC colliders and half the map by accident, and every level change could silently add or remove vaults. A flag on the part makes a vault a level design decision. The server check is a cheap attribute read, and an exploiter cannot make anything vaultable. The cost is that level builders tag each obstacle, one attribute per part. The height check still runs on top, so a tagged part that is too tall or too short is ignored.

### VaultLow probe

Runs on the client every step while moving in Walk or Run (one ray first, the rest only when it hits), and once per intent on the server.

1. A forward ray from knee height, length `VAULT_REACH`, hits an anchored `Vaultable` part with a near vertical normal, and the character is moving toward it.
2. The top is found with a ray straight down from just past the hit point, starting well above the obstacle. Its height above the floor is between `VAULT_LOW_MIN_H` and `VAULT_LOW_MAX_H` and its normal points up.
3. Headroom: a forward ray at character height above the top surface is clear.

Returns `{ kind = "Low", part, topY, normal }?`.

### VaultMid probe

Runs when F is pressed in WallCling or WallBoost.

1. A forward ray at head height hits an anchored `Vaultable` wall within `LEDGE_REACH`.
2. A forward ray from `LEDGE_MIN_UP` to `LEDGE_MAX_UP` above the head is clear at its top, so the lip is within reach.
3. A ray straight down from `LEDGE_DEPTH` past the wall face, starting above the lip, finds a surface with an upward normal. Headroom above it is checked like VaultLow.

Returns `{ kind = "Mid", part, topY, normal }?`.

### How a vault moves

The client moves `HumanoidRootPart` along a short path built from the probe (start, over or up, end) and ignores collision with the obstacle part for the length of the vault (section 4). The server does not follow the path. It checks that the probe is valid at the start and that `VAULT_COOLDOWN` has passed, and the normal speed check covers the rest.

---

## 7. Server

### 7.1 StateService

Shared with combat. One table per character, created on spawn and removed on `PlayerRemoving` and character removal.

```
move:    state, since, endsAt, airJumps, lastWallPart, cooldownUntil: { [MoveState]: number }
dash:    dashUntil, dodgeUntil, dashCooldownUntil   (movement writes, combat reads dodgeUntil)
speed:   windowCap, lastGoodCFrame, bucket, exemptUntil
combat:  stunnedUntil, parryUntil, downed           (combat fills these)
stamina: value, stamp                               (value is computed from stamp and regen when read)
```

Public functions only, other services never reach into the table:

| Function | Purpose |
|---|---|
| `get` | Returns the character's state table |
| `current(char)` | Returns the move state, resolving expired timed states |
| `canMove(char)` | False while stunned, downed or attacking |
| `exempt(char, seconds)` | Called by knockback, teleports and cutscenes before they move a player |

### 7.2 Move intent

Handled in the order from C5:

1. **Rate limit.** Token bucket per player (`MOVE_BURST`, `MOVE_REFILL`).
2. **Type and existence.** `typeof(state) == "string"`, a length cap, and `MoveDefs[state]` exists.
3. **Character.** Alive and has `StateService` data.
4. **Permission.** `canMove` passes, the transition is in the `to` set of the recorded state, and the state's cooldown and stamina allow it.
5. **Context probes**, from server positions:
   - Grounded to Airborne (Jump): the ground probe hits, or the player was grounded within `COYOTE` seconds.
   - Airborne or Wall to Grounded (Land): the ground probe must hit. This stops a client from sending Walk in the air to reset air jumps or lower its speed cap tracking.
   - Wall states: the shared wall probe returns a hit of the right kind on an anchored part, not tagged `NoWall`, and not `lastWallPart` unless the player has landed since.
   - VaultLow: the recorded state is Walk or Run, the ground probe hits, and the vault probe returns a Low hit. The moving toward it check is skipped on the server.
   - VaultMid: the recorded state is WallCling or WallBoost, and the vault probe returns a Mid hit.
6. **Apply.** Write `state`, `since`, `endsAt` for timed states, `cooldownUntil`, the stamina cost, and reset or spend `airJumps`.
7. **Replicate.** Set the `MoveState` attribute on the character so other clients can read it for effects, and nothing else. A denied intent fires `MoveDeny` to that player only.

Fail closed: if a probe cannot decide, deny.

### 7.3 Dash intent

Same order as 7.2.

1. Rate limit (`DASH_BURST`, `DASH_REFILL`).
2. `typeof(dir) == "string"` and `dir` is one of `"F"`, `"B"`, `"L"`, `"R"`.
3. `canMove`, the recorded state is in the allowed list (section 3.1), and `dashCooldownUntil` has passed.
4. Apply: `dashUntil = now + DASH_TIME`, `dodgeUntil = now + DODGE_TIME`, `dashCooldownUntil = now + DASH_COOLDOWN`, raise `windowCap` to `DASH_SPEED`.
5. Fire `DashFx`. A denied dash fires `MoveDeny` with `"Dash"`.

The server does not check the direction against anything, it only passes it on for the effect. It never reads where the client actually went.

### 7.4 Speed check

Runs every `SPEED_SAMPLE_INTERVAL` seconds per character, never per frame (C20).

- **Distance** is horizontal only (X and Z), between the current and the last sampled `HumanoidRootPart` position, divided by the real time between samples.
- **Allowed speed** is `windowCap * SPEED_TOLERANCE`, plus `SPEED_LAG_STUDS` spread over the interval. `windowCap` is the largest `cap` of any state recorded during the interval, so a fast state that ended mid interval still counts. It resets to the current state's cap after each sample.
- **Caps** come from `MoveDefs`. Walk is `WALK_SPEED`, CrouchWalk is `CROUCH_SPEED`, every other state is `MOMENTUM_MAX`. This is loose on purpose for v1. The cap is one function in `MoveDefs`, so a momentum estimate built from recorded states can replace it later without touching anything else. While `dashUntil` is in the future the cap is at least `DASH_SPEED`.
- **Over the limit** adds the excess ratio to a bucket that drains at `SPEED_BUCKET_DRAIN` per second. A lag spike is forgiven, sustained speed is not. At `SPEED_BUCKET_MAX` the character is put back at `lastGoodCFrame` with `PivotTo`, quietly. `lastGoodCFrame` only updates on a passing sample.
- **Skipped** while `exemptUntil` is in the future. Spawn and respawn exempt `SPAWN_EXEMPT` seconds.
- **Not checked in v1:** vertical speed. A fly check (airborne, not in a jump or wall state, not falling) is a later detection add.

### 7.5 Detection hooks (later)

All server side (C24). Speed bucket hits, denied intents per minute, and a honeypot remote nobody legitimately fires each add to a per player score. One signal proves nothing, several have to agree before anything visible happens.

Ladder: log, rubber band, restrict, kick, ban. The evidence is logged even when nothing visible happens.

---

## 8. Remotes

Defined in the shared `Remotes` module. All are reliable `RemoteEvent`s.

| Remote | Direction | Args | Notes |
|---|---|---|---|
| `Move` | Client to server | `state: string` | Every wire state change. Never sends position, speed, momentum or wall data |
| `MoveDeny` | Server to client | `state: string` | The client cancels the predicted state and falls back to Fall or the grounded state it is really in. `state` is `"Dash"` for a refused dash |
| `Dash` | Client to server | `dir: string` | `"F"`, `"B"`, `"L"` or `"R"`. Never sends a position or speed |
| `DashFx` | Server to clients | `char: Model, dir: string` | Other clients play the dash effect and animation cues |

- The server shows state and the Stamina value to other clients through attributes it sets on the character, never the other way round.
- A dropped `Move` would leave the server on the wrong cap and cause false speed flags. The rate limit bucket is generous, and the client sends a state change only when the wire state differs from the last one it sent.
- Nothing is sent per frame. Effects (dust, sparks, camera) are made on each client from the `MoveState` attribute and the definitions. The server creates no effect parts.

---

## 9. Client

One entry point, `init.client.luau`, requires and starts the controllers.

### Controllers

| Module | Job |
|---|---|
| `InputController` | The only module that reads input. Turns keys from `Config.KEYS` into named actions (`Sprint`, `Crouch`, `Jump`, `Dash`, `VaultMid`) and hands them to the movement controller. Sprint is held, not toggled. Movement direction comes from `Humanoid.MoveDirection` for now. If Server Authority is ever adopted, this is the module that moves to the Input Action System |
| `MovementController` | The state machine, momentum and movers. One update per step (`RunService.PreSimulation`) and one `request(to)` function. `request` checks `MoveDefs[current].to[to]` and the local cooldown, switches at once, and sends `Move` when the wire state changed. On `MoveDeny` it cancels |
| `AnimationController` | Loads every R6 track once per character through the `Animator` the server made (`WaitForChild("Animator")`) and keeps them. Plays by state |
| `EffectController` | Later. Dust, wall sparks and FOV scaling with momentum, driven by the `MoveState` attribute |

### State modules

One per family, each with `enter(ctx)`, `update(ctx, dt) -> MoveState?` and `exit(ctx)`. `update` returns the next state, or nil.

| Module | States |
|---|---|
| `Ground` | Idle, Walk, Run, CrouchIdle, CrouchWalk |
| `Slide` | Slide |
| `Vault` | VaultLow, VaultMid |
| `Air` | Jump, DoubleJump, SlideJump, Fall |
| `WallRun` | WallRun, WallLeap |
| `WallCling` | WallCling, WallBoost |

Dash lives in `Movement/Dash.luau`. It is not a state. It picks the direction from the keys held, runs the burst, sends `Dash` and cancels on `MoveDeny`.

### Context table

The table passed to states holds the character, humanoid, root, animator, probe params, movers and current momentum, plus a Trove for that character's connections. The Trove is cleaned when the character dies.

### Controls

| Action | Key | Config |
|---|---|---|
| Sprint (hold) | Left Shift | `KEYS.SPRINT` |
| Crouch | Left Control | `KEYS.CROUCH` |
| Jump | Space | `KEYS.JUMP` |
| Dash | Q | `KEYS.DASH` |
| Vault (VaultMid) | F | `KEYS.VAULT_MID` |

### Animations

All tracks are R6 animations. Priority is set in the animation editor, not in script.

| Priority | Animations |
|---|---|
| Idle | Idle, Fall |
| Movement | Walk, Run |
| Action | Slide, VaultLow, VaultMid, Dash, wall states, jumps |

R6 animations cannot be mirrored at runtime, so WallRun needs a Left and a Right animation and Dash needs four (F, B, L, R). An empty `Animate` LocalScript in `StarterCharacterScripts` replaces the default one so it does not fight these tracks.

---

## 10. Layout

```
src/
  shared/
    Types.luau          MoveState, MoveGroup, MoveDef, WallHit, VaultHit, DashDir
    Config.luau         every constant in section 11
    Remotes.luau
    MoveDefs.luau       the 16 states: group, wire, cap, cost, cooldown, duration, after, anim, to
    Probes.luau         wall, ground, vault
  server/
    init.server.luau
    RateLimit.luau
    Services/
      StateService.luau
      MovementService.luau   intent handling, speed check, spawn setup, collision groups
  client/
    init.client.luau
    Controllers/
      InputController.luau
      MovementController.luau
      AnimationController.luau
      EffectController.luau
      Movement/States/       Ground, Slide, Vault, Air, WallRun, WallCling
      Movement/Dash.luau
  character/
    Animate.client.luau      empty, replaces the default Animate
Packages/                    third party, synced to ReplicatedStorage.Packages
```

`src/character` and the repo root `Packages/` folder follow C2.

### Rojo project

```json
{
	"name": "Game",
	"tree": {
		"$className": "DataModel",
		"ReplicatedStorage": {
			"Shared": { "$path": "src/shared" },
			"Packages": { "$path": "Packages" }
		},
		"ServerScriptService": {
			"Server": { "$path": "src/server" }
		},
		"StarterPlayer": {
			"StarterPlayerScripts": {
				"Client": { "$path": "src/client" }
			},
			"StarterCharacterScripts": {
				"$path": "src/character"
			}
		}
	}
}
```

### Studio settings

Rojo does not set these:

- Avatar type: **R6**
- StreamingEnabled: **on** (C23)
- `Workspace.PlayerCharacterDestroyBehavior`: **enabled**

The collision groups `Characters` and `MoveProbe` are registered by the server in `MovementService` on start, and every character part is put in `Characters` on spawn.

---

## 11. Config

All values are untested starting points. Studs and seconds unless noted.

```lua
--!strict
return table.freeze({
	DEBUG = false,

	WALK_SPEED = 14,
	CROUCH_SPEED = 7,
	RUN_SPEED = 22,
	MOMENTUM_MAX = 44,
	MOMENTUM_GROUND_DECAY = 30,
	MOMENTUM_AIR_DECAY = 1.5,
	LAND_GRACE = 0.15,
	AIR_TURN_RATE = 120,

	JUMP_POWER = 50,
	DOUBLE_JUMP_POWER = 45,
	MAX_AIR_JUMPS = 1,
	COYOTE = 0.15,

	SLIDE_MIN_SPEED = 18,
	SLIDE_BOOST = 1.1,
	SLIDE_DECAY = 8,
	SLIDE_END_SPEED = 10,
	SLIDE_COOLDOWN = 0.6,
	SLIDE_JUMP_GAIN = 4,

	WALL_REACH = 2.5,
	WALL_SPAN_OFFSETS = { 1.5, -1.5 },
	WALL_MAX_NORMAL_Y = 0.2,
	FACING_SPLIT = 0.7,
	WALL_REGRAB = 0.4,
	WALLRUN_MIN_SPEED = 16,
	WALLRUN_MAX_TIME = 2.5,
	WALLRUN_FALL_SPEED = 3,
	WALLRUN_DECAY = 2,
	CLING_MAX_TIME = 3,
	CLING_SLIDE_SPEED = 2,
	LEAP_OUT = 28,
	LEAP_UP = 40,
	LEAP_TIME = 0.35,
	LEAP_GAIN = 6,
	BOOST_UP = 55,
	BOOST_TIME = 0.4,

	VAULT_REACH = 2.5,
	VAULT_LOW_MIN_H = 2,
	VAULT_LOW_MAX_H = 4.5,
	VAULT_LOW_TIME = 0.5,
	VAULT_BOOST = 1.1,
	VAULT_COOLDOWN = 0.4,
	LEDGE_REACH = 2.5,
	LEDGE_MIN_UP = 1,
	LEDGE_MAX_UP = 5,
	LEDGE_DEPTH = 1.5,
	VAULT_MID_TIME = 0.8,

	DASH_SPEED = 55,
	DASH_TIME = 0.2,
	DODGE_TIME = 0.15,
	DASH_COOLDOWN = 1.2,
	DASH_BURST = 3,
	DASH_REFILL = 1,

	KEYS = {
		SPRINT = Enum.KeyCode.LeftShift,
		CROUCH = Enum.KeyCode.LeftControl,
		JUMP = Enum.KeyCode.Space,
		DASH = Enum.KeyCode.Q,
		VAULT_MID = Enum.KeyCode.F,
	},

	GROUND_RAY = 4,

	MOVE_BURST = 10,
	MOVE_REFILL = 8,
	SPEED_SAMPLE_INTERVAL = 0.25,
	SPEED_TOLERANCE = 1.25,
	SPEED_LAG_STUDS = 4,
	SPEED_BUCKET_MAX = 6,
	SPEED_BUCKET_DRAIN = 1.5,
	SPAWN_EXEMPT = 1.5,

	STAMINA_MAX = 100,
	STAMINA_REGEN = 15,
})
```

Stamina costs and cooldowns per state live in `MoveDefs`. All costs are 0 for now, no state costs stamina.

---

## 12. Packages

**Toolchain** (Rokit, pinned in `rokit.toml`): Rojo, StyLua, Selene, luau-lsp, plus Wally and wally-package-types if Wally is the package manager. Pin versions when running `rokit add`.

**Package manager.** Wally is the most used and what most Roblox packages are published on, but it needs `wally-package-types` after each install or strict types break on its link modules. pesde is actively developed, has its own registry, and can pull Wally packages and git repos. Forest is a newer registry that claims to fix the types problem, but it is too new to rely on. Recommendation: Wally with wally-package-types. If the group prefers pesde, nothing else in this document changes.

| Package | Verdict | Why |
|---|---|---|
| Trove (sleitnick/RbxUtil) | Add now | C6.4 requires a cleanup helper. One per character and one per controller. Check the registry for the exact package name when installing |
| Signal library (GoodSignal or LemonSignal) | Not yet | Internal state changes are a plain function call. Add when a second listener appears |
| Blink or Zap (IDL, buffer networking) | Not yet | `Move` sends one short string a few times a second, so a plain `RemoteEvent` is fine. Revisit for combat or if the Network tab shows cost. Community benchmarks lean Blink and Zap over runtime serializers like ByteNet, but treat that as opinion. The handler still does its own rate limit and permission checks |
| Chickynoid | No | Replaces Humanoid with a fixed box character and its own physics, which conflicts with R6 plus Humanoid and with the client moving its own character. Last push was in 2024 and a forum reply calls it discontinued. Read it for ideas only |
| Roblox Server Authority | No | See section 13 |

Everything under `Packages/` is excluded from StyLua and Selene.

---

## 13. Server Authority

Roblox posted a "Full Release" announcement for Server Authority on July 9, 2026, but it is opt-in. It needs StreamingEnabled, NextGenerationReplication (still labelled Beta), `UseFixedSimulation`, deferred signals and the Input Action System, and games with custom movement have to adapt their scripts to `BindToSimulation`.

The same post lists known issues that touch this project: eight playing tracks per Animator, 64 attributes per instance, and remote events not synchronised with the simulation timeline. Constraint based movers (`LinearVelocity`, `AlignOrientation`) are also called out by developers as needing rework.

This design keeps to the brief and does not build on it. To keep a later move cheap it uses one input module, one `update(dt)` entry point for movement, no per frame remotes, and no reliance on the character's network owner.

Whether to build on Server Authority now that Roblox calls it released is a decision for the group. It would change sections 4, 7.4 and 9.

---

## 14. Decisions and open questions

### Settled

- Wall activation and boost
- No double jump refund
- Slide trigger
- Dash as the dodge, with iframes
- Dash Forward with no key held, usable in the air
- No stamina costs
- Loose speed caps
- Shift to sprint, Control to crouch, Q to dash
- Both vaults. VaultMid is one latch and pull up animation from WallCling and WallBoost with no boost, and may change later
- Whether Slide can pass under low gaps is tested first, and a smaller collision hull is only added if needed (section 15)

### Open

Each has the default assumed until answered.

1. Is a dash refused from Slide, VaultLow, VaultMid and the wall states? Assumed yes (section 3.1).
2. Fall damage or a hard landing stun belongs to combat. Out of scope here.

---

## 15. Build order

Each layer must pass the C10 checklist before the next one starts.

1. **Types, Config, MoveDefs, Probes.**
   Done when the transition table has no state without a row, the wall probe classifies a head on wall and a side on wall correctly in a test place, and the vault probes accept a tagged obstacle and ignore an untagged one.
2. **StateService, RateLimit, spawn setup** (collision groups, exemptions).
   Done when state tables are created and removed with no leftover entries after 50 respawns.
3. **Server movement checks:** move and dash intent handling, and the speed check.
   Done when garbage args (nil, NaN, huge numbers, wrong types, unknown states, unknown dash directions) from the command bar do nothing, and a scripted speed hack is rubber banded while normal play and a dash are not.
4. **Remotes and their wiring.**
   Done when spamming `Move` and `Dash` at a high rate is dropped without errors.
5. **Client:** `InputController`, `MovementController`, then states in this order: Ground, Air, Slide, WallRun, WallCling, VaultLow, VaultMid, then Dash. When Slide is in, test in Studio whether the slide animation lets the character pass under a low gap. If it does not, add a smaller collision hull before moving on.
   Done when every transition in section 3 can be played, a denied intent snaps back, and there is no memory growth after repeating the main actions 50 times.
6. **AnimationController, then EffectController.**

---

## Sources

- Server Authority full release post: https://devforum.roblox.com/t/full-release-ship-fair-and-competitive-games-with-server-authority/4727993
- Server Authority how to begin: https://devforum.roblox.com/t/server-authority-how-to-begin/4139185
- Wall movement threads (raycast and LinearVelocity approach): https://devforum.roblox.com/t/making-a-wall-jumpwall-slide/3962464 and https://devforum.roblox.com/t/wallrun-system-not-working/2778389
- Chickynoid: https://github.com/easy-games/chickynoid
- Zap: https://github.com/red-blox/zap
- Blink: https://github.com/ccrossedheart/blink
- ByteNet: https://github.com/ffrostfall/ByteNet
- pesde: https://github.com/pesde-pkg/pesde
- Forest package manager thread: https://devforum.roblox.com/t/forest-package-manager-the-modern-package-platform-for-roblox/4766024
- Trove, Janitor and signal module origins: https://devforum.roblox.com/t/maid-signal-original-posts/3003357
