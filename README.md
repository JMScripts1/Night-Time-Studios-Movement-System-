# Night Time Studios Movement System

Momentum based movement for an R6 RPG: sprint, slide, jumps, a ledge leap, wall movement, mantling, a directional dash and a landing roll. The client moves its own character, the server checks it and keeps its own record of what each player is allowed to be doing.

**Status:** implemented and playtested in Studio. Every number lives in `Config.luau` and is tuned by playing at real ping.

Combat is covered in its own document. The two share one server module, `StateService` (section 7.1).

References like C5 or C20 point at sections of `CONVENTIONS.md`, the rulebook for all code in this project.

## Contents

1. [Overview](#1-overview)
2. [States](#2-states)
3. [Transitions](#3-transitions)
4. [Momentum](#4-momentum)
5. [Probes](#5-probes)
6. [Mantle](#6-mantle)
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
- **Dash is a state like any other** (section 3.1). Nothing interrupts it, and it ends in whatever the character is doing.

---

## 2. States

20 states in three groups. **Wire** is the name the client sends to the server. Idle and CrouchIdle are never sent on their own, they ride on Walk and CrouchWalk, so Idle <-> Walk changes cost no traffic.

| State | Group | Wire | Timed | Notes |
|---|---|---|---|---|
| Idle | Grounded | Walk | no | |
| Walk | Grounded | Walk | no | |
| Run | Grounded | Run | no | Sprint, builds momentum |
| Slide | Grounded | Slide | until speed drops | Run plus crouch key only. Ends in CrouchWalk if there is no headroom to stand |
| CrouchIdle | Grounded | CrouchWalk | no | |
| CrouchWalk | Grounded | CrouchWalk | no | |
| Jump | Airborne | Jump | no | |
| DoubleJump | Airborne | DoubleJump | no | One air jump per airtime |
| SlideJump | Airborne | SlideJump | no | Jump out of Slide. Keeps and adds momentum, then a short launch (section 4) |
| LedgeLeap | Airborne | LedgeLeap | its animation's length, at most `LEDGE_LEAP_TIME` | A slide jump that clears a drop just after takeoff. A stronger launch that adds momentum |
| Fall | Airborne | Fall | no | No key. Entered on walking off a ledge, or when a wall leap, ledge leap, boost or dash in the air ends |
| DashF, DashB, DashL, DashR | Airborne | same | `DASH_TIME`, back dash up to `BACK_DASH_TIME + BACK_DASH_BOOST_TIME` | Q, one state per direction (section 3.1) |
| WallRun | Wall | WallRun | `WALLRUN_MAX_TIME` | Jump pressed in the air at a wall, side on to it |
| WallLeap | Wall | WallLeap | `LEAP_TIME` | Jump pressed in a wall run. Arcs away from the wall, then Fall |
| WallCling | Wall | WallCling | `CLING_MAX_TIME` | Jump pressed in the air at a wall, facing it |
| WallBoost | Wall | WallBoost | `BOOST_TIME` | Jump pressed in a cling. Vertical launch up the wall, then Fall |
| Mantle | Wall | Mantle | `MANTLE_TIME` | Space or F near a ledge, from the air or a wall (section 6) |

**Timed states.** The server stores `endsAt` and resolves an expired state to its `after` state the next time it is read. No timer fires.

**Landing is not a state.** It is whichever grounded state the input and momentum call for at the moment of ground contact: Run if sprint is held, Slide if crouch is on and speed is high enough, otherwise Walk, Idle or CrouchWalk. Momentum survives a landing for `LAND_GRACE` seconds (section 4). A big enough drop lands in a roll, which is only an animation and a short push (section 4).

---

## 3. Transitions

Rows use wire names, so Idle shares the Walk row and CrouchIdle shares the CrouchWalk row. "Land" means any grounded state, and the server only accepts it if its own ground probe hits (section 7.2). "Dash" means any of DashF, DashB, DashL and DashR.

```
Walk        -> Run, CrouchWalk, Jump, Fall, Dash
Run         -> Walk, Slide, Jump, Fall, Dash
Slide       -> Run, Walk, CrouchWalk, SlideJump, Fall
CrouchWalk  -> Walk, Run, Jump, Fall
Mantle      -> Walk, Fall
Jump        -> DoubleJump, Fall, WallRun, WallCling, Mantle, Land, Dash
DoubleJump  -> Fall, WallRun, WallCling, Mantle, Land, Dash
SlideJump   -> LedgeLeap, DoubleJump, Fall, WallRun, WallCling, Mantle, Land, Dash
LedgeLeap   -> DoubleJump, Fall, WallRun, WallCling, Mantle, Land, Dash
Fall        -> DoubleJump, WallRun, WallCling, Mantle, Land, Dash
WallRun     -> WallLeap, Fall, Land
WallLeap    -> Fall, WallRun, WallCling, Land
WallCling   -> WallBoost, Mantle, Fall, Land
WallBoost   -> Mantle, Fall, WallRun, WallCling, Land
Dash        -> Walk, Run, CrouchWalk, Fall
```

Rules on top of the table:

- **Jump in the air** checks for a ledge first (Mantle, section 6), then a wall, then the air jump. A wall probe hit starts WallRun or WallCling, whichever the facing says (section 5.1). Jump in a WallRun is WallLeap, Jump in a WallCling is WallBoost, unless a ledge is in reach.
- **Wall states start in the air only.**
- **No regrabbing the same wall.** After leaving a wall, `WALL_REGRAB` seconds must pass, and the server remembers `lastWallPart` and refuses that part until the player has landed. Chaining only works onto a different part. This is one check in `MovementService`, easy to change.
- **Air jumps.** DoubleJump needs `airJumps < MAX_AIR_JUMPS`, and the counter only resets on landing. Wall states neither refund nor spend it, so an unused air jump is still there after a WallLeap or WallBoost ends in Fall.
- **Mantle starts from the air states, WallCling and WallBoost**, and only when the ledge probe finds a ledge in reach.
- **LedgeLeap starts from SlideJump only**, when the character will clear a drop of at least `LEDGE_LEAP_DROP` within `LEDGE_LEAP_WINDOW` of takeoff. The client looks ahead as far as the launch carries it in what is left of the window, so the leap starts at once and the SlideJump animation never shows. It ends when its animation does.
- **Nothing starts during a dash.** It runs to its end first.
- **Nothing starts while Stunned, Downed or Attacking.** The server asks `StateService` (section 7.1), not combat internals.

### 3.1 Dash

Dash is four states, DashF, DashB, DashL and DashR, one per direction relative to the character. Entering one records `dodgeUntil` on the server for iframes, because the dash is the dodge.

- **Allowed from:** Idle, Walk, Run, Jump, DoubleJump, SlideJump, Fall. **Not from:** crouching, Slide, Mantle and the wall states. Refused while Stunned or Downed. This is only the `to` lists in `MoveDefs`, so the client and the server agree by construction.
- **Nothing cuts a dash short.** Jumps, slides, wall grabs and other dashes wait until it ends. Then it hands over to what the character is doing: a grounded state on the ground, Fall in the air.
- **Direction** comes from the movement keys held when Q is pressed, the first of W, A, S, D wins. No key held dashes Back.
- **Cooldowns:** front and back share one `DASH_COOLDOWN`, left and right share another (the `shares` field in `MoveDefs`). A side dash can follow a front dash, two of the same kind can't. In the air there is one dash until landing, so the chain only works on the ground (`hasAirDashed`, reset on landing like the air jump). A WallRun or WallBoost gives it back, a cling on its own doesn't, and a dash started on the ground doesn't count. No charges and no stamina cost.
- **Front and side dashes:** a `LinearVelocity` burst on `HumanoidRootPart` for `DASH_TIME` at `max(DASH_SPEED, momentum)`, fading back to momentum over the last `DASH_TAIL` of it. The direction is re-read against the character's facing every step, so turning bends the path. In the air the vertical speed is held at zero for `DASH_AIR_HOLD`, then gravity takes over.
- **Back dash:** a slow backstep at `BACK_DASH_SPEED * BACK_DASH_DRIFT` until the DashB animation reaches its `Boost` marker, then a burst at `BACK_DASH_SPEED * BACK_DASH_BOOST` for `BACK_DASH_BOOST_TIME`. Its direction is fixed when it starts. In the air it has no height hold, gravity keeps working, so the longer windup doesn't stall the character mid air. If the marker never fires it ends after `BACK_DASH_TIME`.
- **Air dash:** a front dash started from an airborne state. It bursts like any front dash but at `AIR_DASH_SPEED` and with no `DASH_TAIL`: it lets go at full speed, like the slide jump and ledge leap launches, and the Humanoid's air control bleeds it down onto momentum plus `AIR_DASH_GAIN`, never less than `AIR_DASH_EXIT` (capped at `MOMENTUM_MAX`). So it carries the character from a standstill jump and still adds speed when already fast. Instead of holding its height it rises at `AIR_DASH_LIFT` for `DASH_AIR_HOLD`, enough to reach a platform a little above. When it ends the character keeps going the way it dashed. It is still DashF on the wire, so it shares the front and back cooldown and gives the same iframes. Back and side dashes in the air are plain dashes.
- **Momentum** is unchanged by every other dash, and back and side dashes in the air keep the heading the jump had.
- **Airborne group,** so a dash off the ground is a takeoff and its end is a landing, both checked like any other.

---

## 4. Momentum

Momentum is one number: carried horizontal speed in studs per second. It lives on the client, in the movement controller. The server never trusts it, it only bounds it (section 7.4).

| Event | Effect |
|---|---|
| Run | Holds momentum at `RUN_SPEED` or above, builds slowly while running straight |
| Walk, Crouch | Momentum decays to the state's speed at `MOMENTUM_GROUND_DECAY` |
| Slide start | Momentum x `SLIDE_BOOST`, then decays at `SLIDE_DECAY`. Ends under `SLIDE_END_SPEED` |
| SlideJump | Keeps momentum, adds `SLIDE_JUMP_GAIN`. Launches along the heading at momentum x `SLIDE_JUMP_LAUNCH` plus `SLIDE_JUMP_LIFT` up, held for `SLIDE_JUMP_LAUNCH_TIME`, then the air takes over |
| LedgeLeap | Adds `LEDGE_LEAP_GAIN`, capped at `MOMENTUM_MAX`. The same kind of launch with `LEDGE_LEAP_LAUNCH`, `LEDGE_LEAP_LIFT` and `LEDGE_LEAP_LAUNCH_TIME` |
| Air | Decays slowly at `MOMENTUM_AIR_DECAY`. Steering turns the velocity direction (`AIR_TURN_RATE`), it does not add speed |
| WallRun | Holds momentum, decays at `WALLRUN_DECAY`, falls at `WALLRUN_FALL_SPEED` |
| WallLeap | Momentum becomes velocity along the wall plus `LEAP_OUT` away from the wall plus `LEAP_UP`, adds `LEAP_GAIN` |
| WallCling | Horizontal momentum is dropped, slides down the wall at `CLING_SLIDE_SPEED` |
| WallBoost | Vertical launch up the wall (`BOOST_UP`), no push away from it |
| Mantle | Momentum unchanged |
| Dash | No change, speed returns to what it was before the dash |
| Air dash | Adds `AIR_DASH_GAIN`, at least `AIR_DASH_EXIT`, capped at `MOMENTUM_MAX`. The burst lets go at full speed and the air bleeds it onto the new momentum, along the dash |
| Landing | Momentum is kept if a state that carries it (Run, Slide) is entered within `LAND_GRACE`, otherwise it decays as normal |
| Landing roll | A landing at least `ROLL_HEIGHT` below where the ground was left plays the Roll animation and carries the character forward at `max(ROLL_SPEED, momentum)` for `ROLL_TIME`, even with no keys held. Not a state. Jumping, sliding or dashing cuts it short |
| Hard cap | `MOMENTUM_MAX`, nothing exceeds it |

### How it is applied on R6

- **Ground and air walking:** the controller sets `Humanoid.WalkSpeed` from momentum each step. That is the client's own value and the server ignores it.
- **Slide, WallRun, WallLeap, WallBoost:** a `LinearVelocity` on `HumanoidRootPart`, created once per character and enabled per state. Plane mode lets gravity keep working on the axis the plane leaves free. Slide uses the ground plane, WallRun uses the wall plane.
- **Facing the wall in WallCling:** an `AlignOrientation` on `HumanoidRootPart`, also created once.
- **Dash:** the same `LinearVelocity`, a short burst in the chosen direction (section 3.1).
- **SlideJump and LedgeLeap launches:** the same `LinearVelocity` in vector mode, so it holds against gravity, for the launch time only. One `LAUNCHES` table in `Air` holds both.
- **Landing roll:** no mover. The Ground state calls `Humanoid:Move` along the facing and raises `WalkSpeed` to at least `ROLL_SPEED` until the roll ends.
- **Mantle:** an `AlignPosition` moves `HumanoidRootPart` along a short path built from the probe, and a `NoCollisionConstraint` between the character and the ledge part stays for the length of the mantle. Both are created per mantle and destroyed when it ends.
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
- The part is not `Anchored` or has the tag `NoWall`. An exploiter owns and can place unanchored parts near themselves.
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

### 5.3 Ledge probe

`Probes.ledge` finds a ledge to mantle onto. See section 6.

---

## 6. Mantle

Mantling pulls the character up onto a ledge that is just in reach. It is one state, Mantle.

- **Trigger:** Space near a ledge in the air or on a wall. F in WallCling, WallBoost, or within `LEDGE_GRACE` of letting go of one.
- **Allowed from:** Jump, DoubleJump, SlideJump, LedgeLeap, Fall, WallCling, WallBoost.
- **Momentum:** unchanged.
- **Ends in:** Walk, standing on the ledge.
- **Animation:** Mantle (latch and pull up).
- **Duration:** `MANTLE_TIME`, then `MANTLE_COOLDOWN` before the next one.

### Marking

A part can be mantled only if it, or the model it sits in, has the tag `Mantleable`. Geometry alone is never enough.

In a large RPG, "any anchored part with a lip in reach" would mantle onto trim, props, fences, NPC colliders and half the map by accident, and every level change could silently add or remove ledges. A flag on the part makes a mantle a level design decision. The server check is a cheap tag check, and an exploiter cannot make anything mantleable. The cost is that level builders tag each ledge, one tag per part. The lip window still applies on top, so a tagged part whose top is out of reach is ignored.

### Ledge probe

`Probes.ledge` runs when Space is pressed in the air or on a wall, and when F is pressed where it is allowed, and once per intent on the server. It is meant for being just under a ledge and pulling up onto it.

1. A forward ray from `LEDGE_LOW` below the root (just above the feet) hits an anchored `Mantleable` wall within `LEDGE_REACH`.
2. A ray straight down, `LEDGE_DEPTH` past the wall face and starting `LEDGE_HIGH` above the root, finds the top of that part with an upward normal. So any lip between the feet and well over the head counts.
3. Headroom: a forward ray at character height above the top is clear.

Returns `{ part, point, normal }?`.

### How a mantle moves

The client moves `HumanoidRootPart` along a short curve built from the probe (start, the lip where the animation plants its hands, standing on top) and ignores collision with the ledge part for the length of the mantle (section 4). The server does not follow the path. It checks that the probe is valid at the start and that `MANTLE_COOLDOWN` has passed, and the normal speed check covers the rest.

---

## 7. Server

### 7.1 StateService

Shared with combat. One table per character, created on spawn and removed on `PlayerRemoving` and character removal.

```
move:    state, since, endsAt, airJumps, hasAirDashed, lastWallPart, groundedAt, cooldownUntil: { [MoveState]: number }
dash:    dodgeUntil                                         (movement writes, combat reads)
speed:   windowCap, lastGoodCFrame, bucket, exemptUntil, lastPos, sampledAt, measured
combat:  stunnedUntil, attackUntil, parryUntil, downed      (combat fills these)
stamina: value, stamp                                       (value is computed from stamp and regen when read)
```

Public functions only, other services never reach into the table:

| Function | Purpose |
|---|---|
| `get` | Returns the character's state table |
| `current(char)` | Returns the move state, resolving expired timed states |
| `canMove(char)` | False while stunned, downed or attacking |
| `land(char, at)` | Resets air jumps and the last wall part on landing |
| `spend(char, cost)` | Takes stamina if there is enough |
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
   - Mantle: the ledge probe returns a hit.
   - LedgeLeap: within `LEDGE_LEAP_WINDOW` of the SlideJump, and a ray straight down finds no floor within `LEDGE_LEAP_DROP` under the feet. The server's copy is still behind the edge, so it also casts from a point ahead along the direction of travel, as far as the lag slack plus the launch distance over the window.
   - Dash: no probe, only the transition table, the cooldown, and one dash per airtime.
   - **Lag slack.** The server's copy of a character trails the client by roughly speed times ping, so probes get `PROBE_SLACK` plus the measured flat speed times `PROBE_LAG`. Landing and Mantle also add the vertical speed times `PROBE_LAG`, capped at `BOOST_UP`, because after a fast fall or a boost the server's copy is still well above or below the client.
6. **Apply.** Write `state`, `since`, `endsAt` for timed states, `cooldownUntil` (and the state it `shares` a cooldown with), `dodgeUntil` for a dash, the stamina cost, and reset or spend `airJumps`.
7. **Replicate.** Set the `MoveState` attribute on the character so other clients can read it for effects, and nothing else. A denied intent fires `MoveDeny` to that player only.

Fail closed: if a probe cannot decide, deny.

### 7.3 Dash intent

There is no separate one. A dash is a `Move` intent for one of the four dash states and goes through 7.2 like everything else. The server never reads where the client actually went.

### 7.4 Speed check

Runs every `SPEED_SAMPLE_INTERVAL` seconds per character, never per frame (C20).

- **Distance** is horizontal only (X and Z), between the current and the last sampled `HumanoidRootPart` position, divided by the real time between samples.
- **Allowed speed** is `windowCap * SPEED_TOLERANCE`, plus `SPEED_LAG_STUDS` spread over the interval. `windowCap` is the largest `cap` of any state recorded during the interval, so a fast state that ended mid interval still counts. It resets to the current state's cap after each sample.
- **Caps** come from `MoveDefs`. Walk is `WALK_SPEED`, CrouchWalk is `CROUCH_SPEED`, WallLeap is `MOMENTUM_MAX + LEAP_GAIN + LEAP_OUT`, SlideJump and LedgeLeap are `MOMENTUM_MAX` times their launch, the dash states are the fastest any dash can go (the back dash burst, `DASH_SPEED`, `AIR_DASH_SPEED` or `MOMENTUM_MAX`), and every other state is `MOMENTUM_MAX`. After a fast state ends the cap falls at `MOMENTUM_GROUND_DECAY` per second instead of dropping at once, because the client bleeds its speed off the same way. This is loose on purpose for v1. The cap is one function in `MoveDefs`, so a momentum estimate built from recorded states can replace it later without touching anything else.
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
| `Move` | Client to server | `state: string` | Every wire state change, dashes included. Never sends position, speed, momentum or wall data |
| `MoveDeny` | Server to client | `state: string` | The client cancels the predicted state and falls back to Fall or the grounded state it is really in. A denial for a state the client has already left is ignored, the newer state it sent gets its own answer |

- The server shows state and the Stamina value to other clients through attributes it sets on the character, never the other way round. Other clients see a dash in the `MoveState` attribute.
- A dropped `Move` would leave the server on the wrong cap and cause false speed flags. The rate limit bucket is generous, and the client sends a state change only when the wire state differs from the last one it sent.
- Nothing is sent per frame. Effects (dust, sparks, camera) are made on each client from the `MoveState` attribute and the definitions. The server creates no effect parts.

---

## 9. Client

One entry point, `init.client.luau`, requires and starts the controllers.

### Controllers

| Module | Job |
|---|---|
| `InputController` | The only module that reads input. Turns keys from `Config.KEYS` into named actions (`Sprint`, `Crouch`, `Jump`, `Dash`, `Mantle`) and hands them to the movement controller. Sprint is a double tap of W, held for as long as W stays down. W is read without being sunk so it still walks, and Shift is left free for shift lock. Crouch is a toggle, and jumping or starting a sprint turns it off. Movement direction comes from `Humanoid.MoveDirection` for now. If Server Authority is ever adopted, this is the module that moves to the Input Action System |
| `MovementController` | The state machine, momentum and movers. One update per step (`RunService.PreSimulation`) and one `request(to)` function. `request` checks `MoveDefs[current].to[to]` and the local cooldown, switches at once, and sends `Move` when the wire state changed. On `MoveDeny` it snaps back, unless it has already left the denied state. It also starts the landing roll |
| `AnimationController` | Loads every R6 track once per character through the `Animator` the server made (`WaitForChild("Animator")`) and keeps them. Plays by state. A running jump keeps the run animation going at `RUN_JUMP_ANIM_SPEED` instead of cutting to the jump. A dash animation takes over from the state animation and plays to its end. The jump, leap and boost one shots also play to their end when the state moves on to Fall, then hand over to the fall loop. The landing roll plays on top of the walk states. `play` returns the length of the animation it started, so LedgeLeap can last exactly as long as whichever of its animations plays, and those alternate |
| `EffectController` | Later. Dust, wall sparks and FOV scaling with momentum, driven by the `MoveState` attribute |

### State modules

One per family, each with `enter(ctx)`, `update(ctx, dt) -> MoveState?` and `exit(ctx)`. `update` returns the next state, or nil.

| Module | States |
|---|---|
| `Ground` | Idle, Walk, Run, CrouchIdle, CrouchWalk |
| `Slide` | Slide |
| `Mantle` | Mantle |
| `Air` | Jump, DoubleJump, SlideJump, LedgeLeap, Fall |
| `WallRun` | WallRun, WallLeap |
| `WallCling` | WallCling, WallBoost |
| `Dash` | DashF, DashB, DashL, DashR |

`Dash` lives in `Movement/Dash.luau` rather than `Movement/States/`, next to `Lean.luau`, which tilts the body by `RootJoint.Transform` on top of the animated pose.

### Context table

The table passed to states holds the character, humanoid, root, animator, probe params, movers and current momentum, plus a Trove for that character's connections. The Trove is cleaned when the character dies.

### Controls

| Action | Key | Config |
|---|---|---|
| Sprint | Double tap W, hold | `KEYS.SPRINT`, `DOUBLE_TAP` |
| Crouch | Left Control, toggle | `KEYS.CROUCH` |
| Jump | Space | `KEYS.JUMP` |
| Dash | Q | `KEYS.DASH` |
| Mantle | Space or F near a ledge | `KEYS.JUMP`, `KEYS.MANTLE` |

### Animations

All tracks are R6 animations, with their asset ids in `Anims.luau`, which asserts every name on load. Priority is set in the animation editor, not in script.

| Priority | Animations |
|---|---|
| Idle | Idle, Fall |
| Movement | Walk, Run |
| Action | Slide, Mantle, the dashes, Roll, LedgeLeap, wall states, jumps |

R6 animations cannot be mirrored at runtime, so WallRun and WallLeap need a Left and a Right animation and Dash needs four (F, B, L, R). The air dash plays its own `AirDash` animation in place of DashF. The DashB animation needs a keyframe marker named `Boost` where the burst starts. LedgeLeap has two animations, `LedgeLeap` and `LedgeLeap2`, listed in `LEAPS` in `AnimationController`, and `LEDGE_LEAP_TIME` must be at least as long as the longest. An empty `Animate` LocalScript in `StarterCharacterScripts` replaces the default one so it does not fight these tracks.

---

## 10. Layout

```
src/
  shared/
    Types.luau          MoveState, MoveGroup, AnimName, MoveDef, WallHit, LedgeHit
    Config.luau         every constant in section 11
    Remotes.luau
    MoveDefs.luau       the 20 states: group, wire, cap, cost, cooldown, shares, duration, after, to
    Probes.luau         wall, ground, ledge
    Anims.luau          animation asset ids by name
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
      EffectController.luau  later
      Movement/Context.luau  the per character context table and mover helpers
      Movement/States/       Ground, Slide, Mantle, Air, WallRun, WallCling
      Movement/Dash.luau     the four dash states
      Movement/Lean.luau     body lean
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

Every tunable lives in `src/shared/Config.luau`, which is the source of truth. The values there have been tuned by playtesting, so they are not repeated here. Studs and seconds unless noted. The file is grouped as:

| Group | Covers |
|---|---|
| Ground and momentum | Walk, crouch and run speeds, `RUN_BUILD`, `MOMENTUM_MAX`, decay rates, `LAND_GRACE`, `AIR_TURN_RATE` |
| Jumps and landing | Jump and double jump power, `COYOTE`, and the landing roll (`ROLL_HEIGHT`, `ROLL_SPEED`, `ROLL_TIME`) |
| Slide | Entry speed, boost, decay, end speed, cooldown, jump gain, turn rate, the slide jump launch (`SLIDE_JUMP_*`) and the ledge leap (`LEDGE_LEAP_*`) |
| Wall states | Wall probe reach and spans, `FACING_SPLIT`, regrab time, wall run, cling, leap and boost numbers |
| Mantle | Lip window (`LEDGE_LOW`, `LEDGE_HIGH`, `LEDGE_DEPTH`), the path keyed to its animation, `LEDGE_GRACE`, `MANTLE_TIME`, `MANTLE_COOLDOWN` |
| Dash | `DASH_SPEED`, `DASH_TIME`, `DASH_TAIL`, `DASH_AIR_HOLD`, `DASH_COOLDOWN`, `DODGE_TIME`, the back dash (`BACK_DASH_*`) and the air dash (`AIR_DASH_*`) |
| Feel and animation | Body lean, `ANIM_FADE`, `RUN_JUMP_ANIM_SPEED`, the hurt speed penalty |
| Input | `KEYS`, `DOUBLE_TAP` |
| R6 offsets | `ROOT_HEIGHT`, `KNEE_Y`, `GROUND_RAY`, `STAND_RAY` |
| Server checks | Move rate limit, speed check sampling, tolerance and bucket, `SPAWN_EXEMPT`, and the lag slack (`COOLDOWN_TOLERANCE`, `LAND_SLACK`, `PROBE_SLACK`, `PROBE_LAG`) |
| Stamina | `STAMINA_MAX`, `STAMINA_REGEN` |

`DEBUG` prints every state change and denial. Turn it off outside of testing.

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
- Dash Back with no key held, usable in the air
- Dash is a state, so nothing stacks on it. Refused from crouching, Slide, Mantle and the wall states
- Front and back dashes share a cooldown, side dashes share another, so the two kinds chain
- The back dash is a backstep and a burst keyed to its animation's `Boost` marker
- A front dash in the air is the air dash: a full dash burst that hands a carry speed to momentum and keeps going where it went. It is not a separate state or key
- No stamina costs
- Loose speed caps
- Double tap W to sprint (Shift stays shift lock), Control to toggle crouch, Q to dash
- Mantle (once called VaultMid) is one latch and pull up animation, started by Space or F when just under a ledge, with no boost
- No low vault. It only added a speed boost the other moves already give
- A landing roll after a drop of `ROLL_HEIGHT` or more, visual plus a short forward push, not a state
- A running jump keeps the run animation, slowed, instead of the jump animation
- A slide jump launches, and one that clears a drop just after takeoff becomes a ledge leap, a stronger launch that adds momentum and lasts as long as its animation
- Whether Slide can pass under low gaps is tested first, and a smaller collision hull is only added if needed (section 15)

### Open

1. Fall damage or a hard landing stun belongs to combat. Out of scope here.
2. A Q press during a dash is dropped. Buffering it for the moment the dash ends would make chaining easier.

---

## 15. Build order

All six layers are built. The list is kept as the order things were built and checked in. Each layer had to pass the C10 checklist before the next one started.

1. **Types, Config, MoveDefs, Probes.**
   Done when the transition table has no state without a row, the wall probe classifies a head on wall and a side on wall correctly in a test place, and the ledge probe accepts a tagged ledge and ignores an untagged one.
2. **StateService, RateLimit, spawn setup** (collision groups, exemptions).
   Done when state tables are created and removed with no leftover entries after 50 respawns.
3. **Server movement checks:** move and dash intent handling, and the speed check.
   Done when garbage args (nil, NaN, huge numbers, wrong types, unknown states, unknown dash directions) from the command bar do nothing, and a scripted speed hack is rubber banded while normal play and a dash are not.
4. **Remotes and their wiring.**
   Done when spamming `Move` and `Dash` at a high rate is dropped without errors.
5. **Client:** `InputController`, `MovementController`, then states in this order: Ground, Air, Slide, WallRun, WallCling, Mantle, then Dash. When Slide is in, test in Studio whether the slide animation lets the character pass under a low gap. If it does not, add a smaller collision hull before moving on.
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
