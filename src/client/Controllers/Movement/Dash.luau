--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Context)

type Ctx = Context.Ctx

-- the server's list plus CrouchIdle, which it never sees because it rides on CrouchWalk
local FROM: { [Types.MoveState]: true } = table.freeze({
	Idle = true,
	Walk = true,
	Run = true,
	CrouchIdle = true,
	CrouchWalk = true,
	Jump = true,
	DoubleJump = true,
	SlideJump = true,
	Fall = true,
})

local HOLD = Config.DASH_TIME * (1 - Config.DASH_TAIL)
-- the tail fades to the speed handed to momentum, so the dash never ends in a sudden drop
local EXIT = math.min(Config.DASH_EXIT_SPEED, Config.MOMENTUM_MAX)

local Dash = {}

Dash.FROM = FROM

-- re-read every step, so turning mid dash bends the path
local function direction(c: Ctx, dir: Types.DashDir): Vector3
	local look = Context.look(c)
	if dir == "F" then
		return look
	elseif dir == "B" then
		return -look
	end
	local right = look:Cross(Vector3.yAxis)
	return if dir == "R" then right else -right
end

function Dash.start(c: Ctx, dir: Types.DashDir): boolean
	local now = os.clock()
	if c.dash or now < c.dashCooldownUntil or not FROM[c.state] then
		return false
	end

	c.dash = { dir = dir, startedAt = now, isAir = MoveDefs[c.state].group == "Airborne" }
	c.dashCooldownUntil = now + Config.DASH_COOLDOWN
	Remotes.Dash:FireServer(dir)
	return true
end

function Dash.update(c: Ctx, run: Context.DashRun)
	local elapsed = os.clock() - run.startedAt
	if elapsed >= Config.DASH_TIME then
		Dash.finish(c)
		return
	end

	local fade = math.max(0, elapsed - HOLD) / (Config.DASH_TIME - HOLD)
	local speed = Config.DASH_SPEED + (EXIT - Config.DASH_SPEED) * fade
	Context.glide(c, direction(c, run.dir) * speed)

	if run.isAir and elapsed < Config.DASH_AIR_HOLD then
		local v = c.root.AssemblyLinearVelocity
		c.root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end
end

function Dash.finish(c: Ctx)
	c.dash = nil
	c.lv.Enabled = false
	c.momentum = math.max(c.momentum, EXIT)
end

function Dash.cancel(c: Ctx)
	c.dash = nil
	c.lv.Enabled = false
end

return Dash
