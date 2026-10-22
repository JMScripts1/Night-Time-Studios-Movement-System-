--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)
local Ground = require(script.Parent.Ground)
local Mantle = require(script.Parent.Mantle)

type Ctx = Context.Ctx

-- still going up faster than this means the ground under us is the one we just left
local RISING = 1
local TURN_RATE = math.rad(Config.AIR_TURN_RATE)
local CHARGE_TIME = Config.DOUBLE_JUMP_CHARGE_TIME / Config.DOUBLE_JUMP_CHARGE_SPEED

local CLINGS: { [Types.MoveState]: true } = { WallCling = true, WallBoost = true }

type Launch = { gain: number, power: number, lift: Vector3, time: number }

-- launched along the heading at momentum times power, held against gravity for a moment before the air takes over
local LAUNCHES: { [Types.MoveState]: Launch } = {
	SlideJump = {
		gain = Config.SLIDE_JUMP_GAIN,
		power = Config.SLIDE_JUMP_LAUNCH,
		lift = Vector3.new(0, Config.SLIDE_JUMP_LIFT, 0),
		time = Config.SLIDE_JUMP_LAUNCH_TIME,
	},
	LedgeLeap = {
		gain = Config.LEDGE_LEAP_GAIN,
		power = Config.LEDGE_LEAP_LAUNCH,
		lift = Vector3.new(0, Config.LEDGE_LEAP_LIFT, 0),
		time = Config.LEDGE_LEAP_LAUNCH_TIME,
	},
}

local Air = {}

-- set directly, not left to the humanoid, so the next step can't read the takeoff as a landing
function Air.launch(c: Ctx, power: number)
	local v = c.root.AssemblyLinearVelocity
	c.root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
end

-- fired by the Boost marker in the DoubleJump animation, a charge that was cut short gets nothing
function Air.boost(c: Ctx)
	if c.isCharging then
		c.isCharging = false
		Air.launch(c, Config.DOUBLE_JUMP_POWER)
	end
end

function Air.land(c: Ctx): Types.MoveState?
	if c.root.AssemblyLinearVelocity.Y > RISING or not Probes.ground(c.root) then
		return nil
	end
	if InputController.isDown("Crouch") and Ground.canSlide(c) then
		return "Slide"
	end
	return Ground.pick(c)
end

function Air.wall(c: Ctx): Types.MoveState?
	local hit = Probes.wall(c.root, c.momentum)
	if not hit or hit.part == c.lastWallPart then
		return nil
	end

	local to: Types.MoveState = if hit.kind == "Run" then "WallRun" else "WallCling"
	if not Context.isReady(c, to) then
		return nil
	end
	c.wall = hit
	return to
end

function Air.enter(c: Ctx)
	local state: Types.MoveState = c.state
	-- a dash picks the heading it leaves behind, see Dash.exit
	if not MoveDefs[c.prev].isDash then
		c.heading = Context.travel(c)
	end

	local launch = LAUNCHES[state]
	if launch then
		c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum + launch.gain)
	end
	if state == "Jump" or state == "SlideJump" then
		c.hum:ChangeState(Enum.HumanoidStateType.Jumping)
		Air.launch(c, Config.JUMP_POWER)
	elseif state == "DoubleJump" then
		c.isCharging = true
		-- never slows a jump that's still rising faster
		Air.launch(c, math.max(c.root.AssemblyLinearVelocity.Y, Config.DOUBLE_JUMP_HOP))
	end
end

function Air.update(c: Ctx, dt: number): Types.MoveState?
	local landed: Types.MoveState? = Air.land(c)
	if landed then
		return landed
	end

	local elapsed = os.clock() - c.since
	-- a slide jump that will clear a drop within the window turns into a leap at once, so its own animation never shows
	if c.state == "SlideJump" and elapsed < Config.LEDGE_LEAP_WINDOW then
		local ahead = c.heading * c.momentum * Config.SLIDE_JUMP_LAUNCH * (Config.LEDGE_LEAP_WINDOW - elapsed)
		if Probes.isOverDrop(c.root, ahead) then
			return "LedgeLeap"
		end
	end
	-- the leap lasts as long as whichever animation it plays
	local leapTime = if c.animLength > 0 then c.animLength else Config.LEDGE_LEAP_TIME
	if c.state == "LedgeLeap" and elapsed >= leapTime then
		return "Fall"
	end

	-- the marker comes late or never while a dash animation is still playing out, so the charge has a time limit too
	if c.isCharging and elapsed >= CHARGE_TIME then
		Air.boost(c)
	elseif c.isCharging then
		local v = c.root.AssemblyLinearVelocity
		c.root.AssemblyLinearVelocity = Vector3.new(v.X, math.max(v.Y, -Config.DOUBLE_JUMP_HANG), v.Z)
	end

	local launch = LAUNCHES[c.state]
	if launch then
		if elapsed < launch.time then
			Context.drive(c, c.heading * c.momentum * launch.power + launch.lift)
		else
			c.lv.Enabled = false
		end
	end

	-- a late press just after letting go of a cling or boost still catches the ledge
	local isLetGo = c.state == "Fall" and CLINGS[c.prev] and elapsed < Config.LEDGE_GRACE
	if isLetGo and InputController.take("Mantle") and Mantle.findLedge(c) then
		return "Mantle"
	end

	-- a ledge in reach wins over a wall, and a wall over the air jump
	if InputController.take("Jump") then
		if Mantle.findLedge(c) then
			return "Mantle"
		end
		local wall: Types.MoveState? = Air.wall(c)
		if wall then
			return wall
		elseif c.airJumps < Config.MAX_AIR_JUMPS then
			return "DoubleJump"
		end
	end

	c.momentum = math.max(0, c.momentum - Config.MOMENTUM_AIR_DECAY * dt)

	-- the control script sets MoveDirection every frame before this runs, so this read is the raw input
	local input = c.hum.MoveDirection
	if input.Magnitude > 0 then
		local want = input.Unit
		c.heading = if c.heading == Vector3.zero then want else Context.turn(c.heading, want, TURN_RATE * dt)
	end
	c.hum:Move(c.heading)
	c.hum.WalkSpeed = math.max(c.momentum, Config.WALK_SPEED)
	return nil
end

-- only the launches use the mover in the air, leaving cuts one short
function Air.exit(c: Ctx)
	c.lv.Enabled = false
	c.isCharging = false
end

return Air
