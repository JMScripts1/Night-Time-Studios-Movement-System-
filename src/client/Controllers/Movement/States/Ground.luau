--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)

type Ctx = Context.Ctx

local SPEEDS: { [Types.MoveState]: number } = {
	Idle = Config.WALK_SPEED,
	Walk = Config.WALK_SPEED,
	CrouchIdle = Config.CROUCH_SPEED,
	CrouchWalk = Config.CROUCH_SPEED,
}

local LOW: { [Types.MoveState]: true } = { Slide = true, CrouchIdle = true, CrouchWalk = true }

local Ground = {}

-- either one seeing floor is enough, so a bump or a slope at speed doesn't drop into Fall for a frame
function Ground.isGrounded(c: Ctx): boolean
	return c.hum.FloorMaterial ~= Enum.Material.Air or Probes.ground(c.root) ~= nil
end

function Ground.canSlide(c: Ctx): boolean
	return c.momentum >= Config.SLIDE_MIN_SPEED and Context.isReady(c, "Slide")
end

function Ground.pick(c: Ctx): Types.MoveState
	local isMoving = c.hum.MoveDirection.Magnitude > 0
	local isStuck = LOW[c.state] and Probes.ceiling(c.root) ~= nil
	if InputController.isDown("Crouch") or isStuck then
		return if isMoving then "CrouchWalk" else "CrouchIdle"
	elseif isMoving and InputController.isDown("Sprint") then
		return "Run"
	end
	return if isMoving then "Walk" else "Idle"
end

function Ground.update(c: Ctx, dt: number): Types.MoveState?
	local state: Types.MoveState = c.state
	local hum = c.hum

	if state == "Run" then
		c.momentum = math.max(c.momentum, Config.RUN_SPEED)
		c.runTime += dt
		if hum.MoveDirection:Dot(c.root.CFrame.LookVector) >= Config.RUN_STRAIGHT then
			local ease = math.clamp((c.runTime - Config.RUN_BUILD_DELAY) / Config.RUN_BUILD_EASE, 0, 1)
			c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum + Config.RUN_BUILD * ease * dt)
		end
	else
		-- walking and crouching drop to their own speed at once, a landing holds on so it can still go into a run or slide
		local target = SPEEDS[state]
		if c.momentum < target or os.clock() - c.landedAt > Config.LAND_GRACE then
			c.momentum = target
			c.runTime = 0
		end
	end

	local isHurt = hum.Health <= hum.MaxHealth * Config.HURT_THRESHOLD
	hum.WalkSpeed = if state == "Run" and isHurt then c.momentum - Config.HURT_SPEED_PENALTY else c.momentum
	-- the landing roll carries on forward with no keys held
	if os.clock() < c.rollUntil then
		hum:Move(Context.look(c))
		hum.WalkSpeed = math.max(hum.WalkSpeed, Config.ROLL_SPEED)
	end

	local isCrouched = state == "CrouchIdle" or state == "CrouchWalk"
	if not Ground.isGrounded(c) then
		return "Fall"
	elseif InputController.take("Jump") and not isCrouched then
		-- from a crouch the press only stands up, it already turned crouch off and the pick below does the rest
		return "Jump"
	elseif state == "Run" and InputController.isDown("Crouch") then
		-- Run can't go straight to CrouchWalk, so a slide on cooldown stands up for one step first
		return if Ground.canSlide(c) then "Slide" else "Walk"
	end

	local nextState: Types.MoveState = Ground.pick(c)
	return if nextState ~= state then nextState else nil
end

return Ground
