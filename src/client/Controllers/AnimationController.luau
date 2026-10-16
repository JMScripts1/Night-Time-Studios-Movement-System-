--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Anims)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Movement.Context)

type Ctx = Context.Ctx

local DASH: { [Types.DashDir]: Types.AnimName } = { F = "DashF", B = "DashB", L = "DashL", R = "DashR" }

-- these states outlast their one shot, so the fall loop takes over when it runs out
local THEN_FALL: { [Types.AnimName]: true } = {
	Jump = true,
	DoubleJump = true,
	SlideJump = true,
	WallLeapLeft = true,
	WallLeapRight = true,
	WallBoost = true,
}

local AnimationController = {}

local animations: { [Types.AnimName]: Animation } = {}
local tracks: { [Types.AnimName]: AnimationTrack } = {}
local current: AnimationTrack? = nil

for name: Types.AnimName, id in Anims do
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	animations[name] = anim
end

local function start(name: Types.AnimName)
	local track = tracks[name]
	if track == current then
		return
	end
	if current then
		current:Stop(Config.ANIM_FADE)
	end
	current = track
	if track then
		track:Play(Config.ANIM_FADE)
	end
end

function AnimationController.load(c: Ctx)
	local animator = c.hum:WaitForChild("Animator") :: Animator
	table.clear(tracks)
	current = nil

	for name: Types.AnimName, anim in animations do
		local track = animator:LoadAnimation(anim)
		tracks[name] = track
		if THEN_FALL[name] then
			c.trove:Connect(track.Stopped, function()
				if current == track then
					start("Fall")
				end
			end)
		end
	end

	c.trove:Add(function()
		table.clear(tracks)
		current = nil
	end)
end

function AnimationController.play(c: Ctx)
	-- a leap keeps the wall it left, so its side is the run's side
	local isLeft = c.wall ~= nil and c.wall.side == "Left"
	if c.state == "WallRun" then
		start(if isLeft then "WallRunLeft" else "WallRunRight")
	elseif c.state == "WallLeap" then
		start(if isLeft then "WallLeapLeft" else "WallLeapRight")
	else
		start(c.state)
	end
end

-- on top of the state track, which keeps playing underneath
function AnimationController.dash(dir: Types.DashDir)
	local track = tracks[DASH[dir]]
	if track then
		track:Play(Config.ANIM_FADE)
	end
end

return AnimationController
