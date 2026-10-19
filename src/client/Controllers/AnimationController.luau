--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Anims = require(ReplicatedStorage.Shared.Anims)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Movement.Context)
local Dash = require(script.Parent.Movement.Dash)

type Ctx = Context.Ctx

local BOOST_MARKER = "Boost"

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
local dashing: AnimationTrack? = nil
-- plays over the state track instead of taking over from it, the walk states keep going underneath
local rolling: AnimationTrack? = nil

for name: Types.AnimName, id in Anims do
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	animations[name] = anim
end

-- while a dash plays the state track is only remembered, it starts when the dash ends
local function start(name: Types.AnimName)
	local track = tracks[name]
	-- a running jump keeps the run going slowed down instead of cutting to the jump, landing in Run speeds it back up
	if current and current == tracks.Run and (name == "Jump" or name == "Run") then
		current:AdjustSpeed(if name == "Jump" then Config.RUN_JUMP_ANIM_SPEED else 1)
		return
	end
	if track == current then
		return
	end
	if current then
		current:Stop(Config.ANIM_FADE)
	end
	current = track
	if track and not dashing then
		track:Play(Config.ANIM_FADE)
	end
end

local function stopRoll()
	if rolling then
		rolling:Stop(Config.ANIM_FADE)
		rolling = nil
	end
end

function AnimationController.load(c: Ctx)
	local animator = c.hum:WaitForChild("Animator") :: Animator
	table.clear(tracks)
	current = nil
	dashing = nil
	rolling = nil

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

	for _, name: Types.AnimName in DASH do
		local track = tracks[name]
		if not track then
			continue
		end
		c.trove:Connect(track.Stopped, function()
			if dashing ~= track then
				return
			end
			dashing = nil
			if current then
				current:Play(Config.ANIM_FADE)
			end
		end)
	end

	-- the back dash's burst is keyed to its animation
	local back = tracks.DashB
	if back then
		c.trove:Connect(back:GetMarkerReachedSignal(BOOST_MARKER), function()
			Dash.boost(c)
		end)
	end

	c.trove:Add(function()
		table.clear(tracks)
		current = nil
		dashing = nil
		rolling = nil
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

	-- a vault's path is keyed to its animation, so the animation is stretched to the vault's length
	local run = c.vaulting
	if run and current and current.Length > 0 then
		current:AdjustSpeed(current.Length / run.time)
	end

	if os.clock() >= c.rollUntil then
		stopRoll()
	end
end

function AnimationController.roll()
	local track = tracks.Roll
	rolling = track
	track:Play(Config.ANIM_FADE)
	if track.Length > 0 then
		track:AdjustSpeed(track.Length / Config.ROLL_TIME)
	end
end

function AnimationController.dash(dir: Types.DashDir)
	local track = tracks[DASH[dir]]
	if not track then
		return
	end
	stopRoll()
	if current then
		current:Stop(Config.ANIM_FADE)
	end
	dashing = track
	track:Play(Config.ANIM_FADE)
	if dir == "B" and track.Length > 0 then
		track:AdjustSpeed(track.Length / Config.BACK_DASH_ANIM_TIME)
	end
end

return AnimationController
