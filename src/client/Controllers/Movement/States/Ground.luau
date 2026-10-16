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

local function findVault(c: Ctx): boolean
	local dir = c.hum.MoveDirection
	if dir.Magnitude == 0 or not Context.isReady(c, "VaultLow") then
		return false
	end

	local hit = Probes.vaultLow(c.root)
	if not hit or dir:Dot(-hit.normal) < Config.VAULT_TOWARD then
		return false
	end
	c.vault = hit
	return true
end

function Ground.update(c: Ctx, dt: number): Types.MoveState?
	local state: Types.MoveState = c.state
	local hum = c.hum

	if state == "Run" then
		c.momentum = math.max(c.momentum, Config.RUN_SPEED)
		if hum.MoveDirection:Dot(c.root.CFrame.LookVector) >= Config.RUN_STRAIGHT then
			c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum + Config.RUN_BUILD * dt)
		end
	else
		local target = SPEEDS[state]
		if c.momentum < target then
			c.momentum = target
		elseif os.clock() - c.landedAt > Config.LAND_GRACE then
			c.momentum = math.max(target, c.momentum - Config.MOMENTUM_GROUND_DECAY * dt)
		end
	end

	local isHurt = hum.Health <= hum.MaxHealth * Config.HURT_THRESHOLD
	hum.WalkSpeed = if state == "Run" and isHurt then c.momentum - Config.HURT_SPEED_PENALTY else c.momentum

	if not Ground.isGrounded(c) then
		return "Fall"
	elseif InputController.take("Jump") then
		return "Jump"
	elseif state == "Run" and InputController.isDown("Crouch") then
		-- Run can't go straight to CrouchWalk, so a slide on cooldown stands up for one step first
		return if Ground.canSlide(c) then "Slide" else "Walk"
	elseif (state == "Walk" or state == "Run") and findVault(c) then
		return "VaultLow"
	end

	local nextState: Types.MoveState = Ground.pick(c)
	return if nextState ~= state then nextState else nil
end

return Ground
