--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)
local Ground = require(script.Parent.Ground)

type Ctx = Context.Ctx

local TURN_RATE = math.rad(Config.SLIDE_TURN_RATE)

local Slide = {}

function Slide.enter(c: Ctx)
	local travel = Context.travel(c)
	c.heading = if travel == Vector3.zero then Context.look(c) else travel
	c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum * Config.SLIDE_BOOST)
	Context.face(c, c.heading)
	Context.glide(c, c.heading * c.momentum)
end

function Slide.update(c: Ctx, dt: number): Types.MoveState?
	if InputController.take("Jump") then
		return "SlideJump"
	elseif not Ground.isGrounded(c) then
		return "Fall"
	end

	-- the slide slows down on its own speed, momentum comes out of it untouched
	local speed = c.momentum - Config.SLIDE_DECAY * (os.clock() - c.since)
	if speed < Config.SLIDE_END_SPEED then
		return Ground.pick(c)
	end

	-- the default camera stops short of straight down, so the flat look is never zero
	local look = workspace.CurrentCamera.CFrame.LookVector
	c.heading = Context.turn(c.heading, Vector3.new(look.X, 0, look.Z).Unit, TURN_RATE * dt)
	Context.face(c, c.heading)
	Context.glide(c, c.heading * speed)
	return nil
end

Slide.exit = Context.release

return Slide
