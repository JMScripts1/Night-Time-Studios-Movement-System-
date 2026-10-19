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

	c.dash = {
		dir = dir,
		startedAt = now,
		isAir = MoveDefs[c.state].group == "Airborne",
		back = if dir == "B" then -Context.look(c) else nil,
	}
	c.dashCooldownUntil = now + Config.DASH_COOLDOWN
	Remotes.Dash:FireServer(dir)
	return true
end

-- fired by the Boost marker in the DashB animation, a backstep that already ran out gets nothing
function Dash.boost(c: Ctx)
	local run = c.dash
	if run and run.back and not run.boostedAt then
		run.boostedAt = os.clock()
	end
end

-- a slow backstep, then a burst at the marker. in the air it holds its height the whole way
local function updateBack(c: Ctx, run: Context.DashRun, back: Vector3)
	local now = os.clock()
	local boostedAt = run.boostedAt
	local isOver = if boostedAt
		then now - boostedAt >= Config.BACK_DASH_BOOST_TIME
		else now - run.startedAt >= Config.BACK_DASH_TIME
	if isOver then
		Dash.finish(c)
		return
	end

	local speed = Config.BACK_DASH_SPEED * (if boostedAt then Config.BACK_DASH_BOOST else Config.BACK_DASH_DRIFT)
	if run.isAir then
		Context.drive(c, back * speed)
	else
		Context.glide(c, back * speed)
	end
end

function Dash.update(c: Ctx, run: Context.DashRun)
	local back = run.back
	if back then
		updateBack(c, run, back)
		return
	end

	local elapsed = os.clock() - run.startedAt
	if elapsed >= Config.DASH_TIME then
		Dash.finish(c)
		return
	end

	-- never slower than the momentum it started from, and the tail lands back on it, so a dash adds no speed
	local fade = math.max(0, elapsed - HOLD) / (Config.DASH_TIME - HOLD)
	local peak = math.max(Config.DASH_SPEED, c.momentum)
	local speed = peak + (c.momentum - peak) * fade
	Context.glide(c, direction(c, run.dir) * speed)

	if run.isAir and elapsed < Config.DASH_AIR_HOLD then
		local v = c.root.AssemblyLinearVelocity
		c.root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
	end
end

function Dash.finish(c: Ctx)
	c.dash = nil
	c.lv.Enabled = false
end

return Dash
