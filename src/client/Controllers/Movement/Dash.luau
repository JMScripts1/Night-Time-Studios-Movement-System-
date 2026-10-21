--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Context)
local Ground = require(script.Parent.States.Ground)

type Ctx = Context.Ctx

local HOLD = Config.DASH_TIME * (1 - Config.DASH_TAIL)

local Dash = {}

-- re-read every step, so turning mid dash bends the path
local function direction(c: Ctx): Vector3
	local look = Context.look(c)
	if c.state == "DashF" then
		return look
	end
	local right = look:Cross(Vector3.yAxis)
	return if c.state == "DashR" then right else -right
end

-- fired by the Boost marker in the DashB animation, a backstep that already ran out gets nothing
function Dash.boost(c: Ctx)
	local run = c.dash
	if run and run.back and not run.boostedAt then
		run.boostedAt = os.clock()
	end
end

-- a slow backstep, then a burst at the marker. no height hold, through the windup it reads as a stall
local function updateBack(c: Ctx, run: Context.DashRun, back: Vector3): boolean
	local now = os.clock()
	local boostedAt = run.boostedAt
	local isOver = if boostedAt
		then now - boostedAt >= Config.BACK_DASH_BOOST_TIME
		else now - c.since >= Config.BACK_DASH_TIME
	if isOver then
		return true
	end

	local speed = Config.BACK_DASH_SPEED * (if boostedAt then Config.BACK_DASH_BOOST else Config.BACK_DASH_DRIFT)
	Context.glide(c, back * speed)
	return false
end

local function updateBurst(c: Ctx, run: Context.DashRun): boolean
	local elapsed = os.clock() - c.since
	if elapsed >= Config.DASH_TIME then
		return true
	end

	-- the tail brakes back onto momentum. the air dash has none, it lets go at full speed and the air bleeds it off
	local fade = if run.isAirDash then 0 else math.max(0, elapsed - HOLD) / (Config.DASH_TIME - HOLD)
	local peak = math.max(if run.isAirDash then Config.AIR_DASH_SPEED else Config.DASH_SPEED, c.momentum)
	local speed = peak + (c.momentum - peak) * fade
	Context.glide(c, direction(c) * speed)

	if run.isAir and elapsed < Config.DASH_AIR_HOLD then
		local v = c.root.AssemblyLinearVelocity
		c.root.AssemblyLinearVelocity = Vector3.new(v.X, if run.isAirDash then Config.AIR_DASH_LIFT else 0, v.Z)
	end
	return false
end

function Dash.enter(c: Ctx)
	local isAir = MoveDefs[c.prev].group == "Airborne"
	local isAirDash = isAir and c.state == "DashF"
	if isAirDash then
		c.momentum = math.min(Config.MOMENTUM_MAX, math.max(c.momentum + Config.AIR_DASH_GAIN, Config.AIR_DASH_EXIT))
	end
	c.dash = {
		isAir = isAir,
		isAirDash = isAirDash,
		back = if c.state == "DashB" then -Context.look(c) else nil,
	}
end

function Dash.update(c: Ctx): Types.MoveState?
	local run = c.dash :: Context.DashRun
	local back = run.back
	local isOver = if back then updateBack(c, run, back) else updateBurst(c, run)
	if not isOver then
		return nil
	end
	return if Ground.isGrounded(c) then Ground.pick(c) else "Fall"
end

function Dash.exit(c: Ctx)
	-- Air keeps whatever heading a dash leaves. the air dash leaves its own, side and back dashes in the air the old one
	local run = c.dash :: Context.DashRun
	if not run.isAir or run.isAirDash then
		c.heading = Context.travel(c)
	end
	c.dash = nil
	c.lv.Enabled = false
end

return Dash
