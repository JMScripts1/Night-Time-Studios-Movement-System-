--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local AnimationController = require(script.Parent.AnimationController)
local EffectController = require(script.Parent.EffectController)
local InputController = require(script.Parent.InputController)
local Context = require(script.Parent.Movement.Context)
local Dash = require(script.Parent.Movement.Dash)
local Lean = require(script.Parent.Movement.Lean)
local Air = require(script.Parent.Movement.States.Air)
local Ground = require(script.Parent.Movement.States.Ground)
local Mantle = require(script.Parent.Movement.States.Mantle)
local Slide = require(script.Parent.Movement.States.Slide)
local WallCling = require(script.Parent.Movement.States.WallCling)
local WallRun = require(script.Parent.Movement.States.WallRun)

type Ctx = Context.Ctx

type StateModule = {
	enter: ((Ctx) -> ())?,
	update: (Ctx, number) -> Types.MoveState?,
	exit: ((Ctx) -> ())?,
}

local STATES: { [Types.MoveState]: StateModule } = {
	Idle = Ground,
	Walk = Ground,
	Run = Ground,
	CrouchIdle = Ground,
	CrouchWalk = Ground,
	Slide = Slide,
	Mantle = Mantle,
	Jump = Air,
	DoubleJump = Air,
	SlideJump = Air,
	LedgeLeap = Air,
	Fall = Air,
	WallRun = WallRun,
	WallLeap = WallRun,
	WallCling = WallCling,
	WallBoost = WallCling,
	DashF = Dash,
	DashB = Dash,
	DashL = Dash,
	DashR = Dash,
}

local player = Players.LocalPlayer

local MovementController = {}

local ctx: Ctx? = nil
local lastSent: Types.MoveState? = nil

local function blockRegrab(c: Ctx, untilTime: number)
	for state: Types.MoveState, def in MoveDefs do
		if def.isAttached then
			c.cooldownUntil[state] = untilTime
		end
	end
end

local function send(to: Types.MoveState)
	local wire: Types.MoveState = MoveDefs[to].wire
	if wire ~= lastSent then
		lastSent = wire
		Remotes.Move:FireServer(wire)
	end
end

-- same bookkeeping as the server's apply, so it rarely has a reason to deny
local function switch(c: Ctx, to: Types.MoveState)
	local from: Types.MoveState = c.state
	local def = MoveDefs[to]
	local now = os.clock()

	local exit = STATES[from].exit
	if exit then
		exit(c)
	end

	if MoveDefs[from].isAttached then
		blockRegrab(c, now + Config.WALL_REGRAB)
	end
	if def.group == "Grounded" and MoveDefs[from].group ~= "Grounded" then
		c.airJumps = 0
		c.hasAirDashed = false
		c.lastWallPart = nil
		c.landedAt = now
		if STATES[to] == Ground and c.takeoffY - c.root.Position.Y >= Config.ROLL_HEIGHT then
			c.rollUntil = now + Config.ROLL_TIME
			AnimationController.roll()
		end
	elseif MoveDefs[from].group == "Grounded" and def.group ~= "Grounded" then
		c.takeoffY = c.root.Position.Y
	elseif to == "DoubleJump" then
		c.airJumps += 1
	elseif def.isDash then
		c.hasAirDashed = true
	elseif def.isAttached then
		c.lastWallPart = (c.wall :: Types.WallHit).part
		blockRegrab(c, now + (def.duration or 0) + Config.WALL_REGRAB)
	end
	if def.isDashReset then
		c.hasAirDashed = false
	end
	-- the roll only carries on through the walk states
	if STATES[to] ~= Ground then
		c.rollUntil = 0
	end
	if def.cooldown > 0 then
		c.cooldownUntil[to] = now + def.cooldown
		if def.shares then
			c.cooldownUntil[def.shares] = now + def.cooldown
		end
	end

	if Config.DEBUG then
		print("state", from, "->", to)
	end

	c.prev = from
	c.state = to
	c.since = now
	local enter = STATES[to].enter
	if enter then
		enter(c)
	end
	c.animLength = AnimationController.play(c)
	EffectController.play(c)
	send(to)
end

function MovementController.request(to: Types.MoveState): boolean
	local c = ctx
	if not c or not MoveDefs[c.state].to[to] or not Context.isReady(c, to) then
		return false
	end
	switch(c, to)
	return true
end

local function step(c: Ctx, dt: number)
	-- the split cooldowns let a side dash chain into a front one, but only on the ground. the air gets one dash
	if InputController.take("Dash") and not c.hasAirDashed then
		MovementController.request(InputController.dash())
	end

	local nextState: Types.MoveState? = STATES[c.state].update(c, dt)
	if nextState then
		MovementController.request(nextState)
	end
	Lean.update(c, dt)
	InputController.flush()
end

local function onDeny(state: string)
	local c = ctx
	if Config.DEBUG then
		print("denied", state)
	end
	-- a denial that lands after the client moved on is for an intent the newer one replaced, the server judges that one
	if not c or MoveDefs[c.state].wire ~= state then
		return
	end

	-- snap to what the character is really doing, but never resend the state that was just refused
	local back: Types.MoveState = if Ground.isGrounded(c) then Ground.pick(c) else "Fall"
	local wire: Types.MoveState = MoveDefs[back].wire
	lastSent = if wire == state then wire else nil
	if c.state == back then
		send(back)
	else
		switch(c, back)
	end
end

local function stop(c: Ctx)
	if ctx == c then
		ctx = nil
	end
	c.trove:Clean()
end

local function onCharacterAdded(char: Model)
	local c = Context.new(char)
	AnimationController.load(c)
	AnimationController.play(c)
	EffectController.load(c)
	ctx = c
	-- the server starts every character in Walk
	lastSent = "Walk"

	c.trove:Connect(c.hum.Died, function()
		stop(c)
	end)
	c.trove:Connect(RunService.PreSimulation, function(dt: number)
		step(c, dt)
	end)
end

Remotes.MoveDeny.OnClientEvent:Connect(onDeny)

player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(function(char: Model)
	local c = ctx
	if c and c.char == char then
		stop(c)
	end
end)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

return MovementController
