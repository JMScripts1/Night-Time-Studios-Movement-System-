--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)
local Air = require(script.Parent.Air)

type Ctx = Context.Ctx

local FALL = Vector3.new(0, -Config.WALLRUN_FALL_SPEED, 0)

local WallRun = {}

function WallRun.enter(c: Ctx)
	local wall = c.wall :: Types.WallHit

	if c.state == "WallRun" then
		local along = wall.normal:Cross(Vector3.yAxis)
		local travel = Context.travel(c)
		local ref = if travel == Vector3.zero then Context.look(c) else travel
		c.heading = if along:Dot(ref) >= 0 then along else -along
		Context.face(c, c.heading)
		Context.drive(c, c.heading * c.momentum + FALL)
		return
	end

	-- heading is still the run direction along the wall
	local out = c.heading * (c.momentum + Config.LEAP_GAIN) + wall.normal * Config.LEAP_OUT
	c.momentum = math.min(Config.MOMENTUM_MAX, out.Magnitude)
	c.heading = out.Unit
	Context.glide(c, c.heading * c.momentum)
	Air.launch(c, Config.LEAP_UP)
end

function WallRun.update(c: Ctx, dt: number): Types.MoveState?
	local landed: Types.MoveState? = Air.land(c)
	if landed then
		return landed
	end
	local elapsed = os.clock() - c.since

	if c.state == "WallRun" then
		if InputController.take("Jump") then
			return "WallLeap"
		elseif elapsed >= Config.WALLRUN_MAX_TIME or not Probes.wall(c.root, math.huge) then
			return "Fall"
		end
		c.momentum = math.max(0, c.momentum - Config.WALLRUN_DECAY * dt)
		Context.drive(c, c.heading * c.momentum + FALL)
		return nil
	end

	if InputController.take("Jump") then
		local wall: Types.MoveState? = Air.wall(c)
		if wall then
			return wall
		end
	end
	return if elapsed >= Config.LEAP_TIME then "Fall" else nil
end

WallRun.exit = Context.release

return WallRun
