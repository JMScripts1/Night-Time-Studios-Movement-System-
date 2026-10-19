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
local Vault = require(script.Parent.Vault)

type Ctx = Context.Ctx

-- still going up faster than this means the ground under us is the one we just left
local RISING = 1
local TURN_RATE = math.rad(Config.AIR_TURN_RATE)

local CLINGS: { [Types.MoveState]: true } = { WallCling = true, WallBoost = true }

local Air = {}

-- set directly, not left to the humanoid, so the next step can't read the takeoff as a landing
function Air.launch(c: Ctx, power: number)
	local v = c.root.AssemblyLinearVelocity
	c.root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
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
	local state = c.state
	-- a dash never changes where the character was going, see Dash.exit
	if not MoveDefs[c.prev].isDash then
		c.heading = Context.travel(c)
	end

	if state == "SlideJump" then
		c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum + Config.SLIDE_JUMP_GAIN)
	end
	if state == "Jump" or state == "SlideJump" then
		c.hum:ChangeState(Enum.HumanoidStateType.Jumping)
		Air.launch(c, Config.JUMP_POWER)
	elseif state == "DoubleJump" then
		Air.launch(c, Config.DOUBLE_JUMP_POWER)
	end
end

function Air.update(c: Ctx, dt: number): Types.MoveState?
	local landed: Types.MoveState? = Air.land(c)
	if landed then
		return landed
	end

	-- a late press just after letting go of a cling or boost still catches the ledge
	local isLetGo = c.state == "Fall" and CLINGS[c.prev] and os.clock() - c.since < Config.LEDGE_GRACE
	if isLetGo and InputController.take("VaultMid") and Vault.findLedge(c) then
		return "VaultMid"
	end

	-- a ledge in reach wins over a wall, and a wall over the air jump
	if InputController.take("Jump") then
		if Vault.findLedge(c) then
			return "VaultMid"
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

return Air
