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

local Slide = {}

function Slide.enter(c: Ctx)
	local travel = Context.travel(c)
	c.heading = if travel == Vector3.zero then Context.look(c) else travel
	c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum * Config.SLIDE_BOOST)
	Context.glide(c, c.heading * c.momentum)
end

function Slide.update(c: Ctx, dt: number): Types.MoveState?
	if InputController.take("Jump") then
		return "SlideJump"
	elseif not Ground.isGrounded(c) then
		return "Fall"
	end

	c.momentum -= Config.SLIDE_DECAY * dt
	if c.momentum < Config.SLIDE_END_SPEED then
		return Ground.pick(c)
	end
	Context.glide(c, c.heading * c.momentum)
	return nil
end

Slide.exit = Context.release

return Slide
