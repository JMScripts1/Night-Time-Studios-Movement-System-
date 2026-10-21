--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RateLimit = require(script.Parent.Parent.RateLimit)
local StateService = require(script.Parent.StateService)

type CharState = StateService.CharState

local CHAR_GROUP = "Characters"
local PROBE_GROUP = "MoveProbe"
local MAX_STATE_LEN = 16
-- groundedAt is only stamped once per sample, so a fresh one can be a whole interval old
local COYOTE_WINDOW = Config.COYOTE + Config.SPEED_SAMPLE_INTERVAL
-- long enough to skip the sample after a snap, the client's old position can still arrive
local SNAP_EXEMPT = Config.SPEED_SAMPLE_INTERVAL * 2
local GROUND_REACH = Config.GROUND_RAY + Config.LAND_SLACK
-- facing and speed are the client's call, the server only needs a real wall
local ANY_SPEED = math.huge

-- the slide jump that opens it reached the server about as late as the leap does
local LEAP_WINDOW = Config.LEDGE_LEAP_WINDOW + Config.COOLDOWN_TOLERANCE

-- the client only ever sends wire names
local WIRE: { [string]: Types.MoveState } = {}
for state: Types.MoveState, def in MoveDefs do
	if def.wire == state then
		WIRE[state] = state
	end
end

local MovementService = {}

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = CHAR_GROUP
	end
end

-- the owner can delete parts of its own character, so nothing in it is assumed
local function liveRoot(char: Model): BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if hum and hum.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function onGround(root: BasePart): boolean
	return Probes.ground(root, GROUND_REACH) ~= nil
end

-- the server's copy of the character trails the client by speed times ping
local function reach(st: CharState, base: number): number
	return base + Config.PROBE_SLACK + st.speed.measured * Config.PROBE_LAG
end

-- the measured speed is flat only, so jumps and falls trail by their own vertical speed, capped so it can't be inflated
local function verticalLag(root: BasePart): number
	return math.min(math.abs(root.AssemblyLinearVelocity.Y), Config.BOOST_UP) * Config.PROBE_LAG
end

local function blockRegrab(st: CharState, untilTime: number)
	for state: Types.MoveState, def in MoveDefs do
		if def.isAttached then
			st.move.cooldownUntil[state] = untilTime
		end
	end
end

local function canEnter(
	char: Model,
	st: CharState,
	root: BasePart,
	from: Types.MoveState,
	to: Types.MoveState,
	now: number
): (boolean, BasePart?)
	local move = st.move
	local fromGroup = MoveDefs[from].group
	local toGroup = MoveDefs[to].group
	local isTakeoff = fromGroup == "Grounded" and toGroup == "Airborne" and to ~= "Fall"

	local cooldownUntil = move.cooldownUntil[to] or 0
	if
		not StateService.canMove(char)
		or not MoveDefs[from].to[to]
		or now + Config.COOLDOWN_TOLERANCE < cooldownUntil
	then
		return false
	end

	if toGroup == "Grounded" and fromGroup ~= "Grounded" then
		return Probes.ground(root, GROUND_REACH + verticalLag(root)) ~= nil
	elseif isTakeoff then
		return onGround(root) or now - move.groundedAt <= COYOTE_WINDOW
	elseif to == "DoubleJump" then
		return move.airJumps < Config.MAX_AIR_JUMPS
	elseif MoveDefs[to].isDash then
		return not move.hasAirDashed
	elseif MoveDefs[to].isAttached then
		local hit = Probes.wall(root, ANY_SPEED, reach(st, Config.WALL_REACH))
		if hit and hit.part ~= move.lastWallPart then
			return true, hit.part
		end
		return false
	elseif to == "Mantle" then
		return Probes.ledge(root, reach(st, verticalLag(root))) ~= nil
	elseif to == "LedgeLeap" then
		-- the client looks as far ahead as its launch carries it in the window, and the server's copy trails behind that
		local v = root.AssemblyLinearVelocity
		local flat = Vector3.new(v.X, 0, v.Z)
		local launch = st.speed.measured * Config.SLIDE_JUMP_LAUNCH * Config.LEDGE_LEAP_WINDOW
		local ahead = if flat.Magnitude > 0 then flat.Unit * reach(st, launch) else nil
		return now - move.since <= LEAP_WINDOW and Probes.isOverDrop(root, ahead)
	end
	return true
end

local function apply(
	char: Model,
	st: CharState,
	from: Types.MoveState,
	to: Types.MoveState,
	now: number,
	wall: BasePart?
)
	local move = st.move
	local def = MoveDefs[to]

	if MoveDefs[from].isAttached then
		blockRegrab(st, now + Config.WALL_REGRAB)
	end

	if def.group == "Grounded" and MoveDefs[from].group ~= "Grounded" then
		StateService.land(char, now)
	elseif to == "DoubleJump" then
		move.airJumps += 1
	elseif def.isDash and MoveDefs[from].group ~= "Grounded" then
		move.hasAirDashed = true
	elseif wall then
		move.lastWallPart = wall
		-- covers the state running out on its own, leaving early overwrites it above
		blockRegrab(st, now + (def.duration or 0) + Config.WALL_REGRAB)
	end
	if def.isDashReset then
		move.hasAirDashed = false
	end

	if def.cooldown > 0 then
		move.cooldownUntil[to] = now + def.cooldown
		if def.shares then
			move.cooldownUntil[def.shares] = now + def.cooldown
		end
	end
	if def.isDash then
		st.dash.dodgeUntil = now + Config.DODGE_TIME
	end

	move.state = to
	move.since = now
	move.endsAt = if def.duration then now + def.duration else nil
	st.speed.windowCap = math.max(st.speed.windowCap, def.cap)
	char:SetAttribute("MoveState", to)
end

local function onMove(plr: Player, state: unknown)
	if not RateLimit.check(plr, "Move") then
		return
	end
	if typeof(state) ~= "string" or #state > MAX_STATE_LEN then
		return
	end

	local to: Types.MoveState? = WIRE[state]
	local char = plr.Character
	local st = if char then StateService.get(char) else nil
	local root = if char then liveRoot(char) else nil
	if not to or not char or not st or not root then
		return
	end

	-- a timed state the server already ran out, the client is just catching up
	local from: Types.MoveState = StateService.current(char)
	if to == from then
		return
	end

	local now = workspace:GetServerTimeNow()
	local ok, wall = canEnter(char, st, root, from, to, now)
	if ok and StateService.spend(char, MoveDefs[to].cost) then
		apply(char, st, from, to, now, wall)
	else
		Remotes.MoveDeny:FireClient(plr, to)
	end
end

local function sample(char: Model, st: CharState, now: number)
	local root = liveRoot(char)
	if not root then
		return
	end

	local speed = st.speed
	local dt = now - speed.sampledAt
	local pos = root.Position
	speed.measured = Vector3.new(pos.X - speed.lastPos.X, 0, pos.Z - speed.lastPos.Z).Magnitude / dt
	speed.lastPos = pos
	speed.sampledAt = now
	speed.bucket = math.max(0, speed.bucket - dt * Config.SPEED_BUCKET_DRAIN)
	if onGround(root) then
		st.move.groundedAt = now
	end

	if now >= speed.exemptUntil then
		local allowed = speed.windowCap * Config.SPEED_TOLERANCE + Config.SPEED_LAG_STUDS / dt
		if speed.measured <= allowed then
			speed.lastGoodCFrame = char:GetPivot()
		else
			speed.bucket += speed.measured / allowed - 1
			if speed.bucket >= Config.SPEED_BUCKET_MAX then
				StateService.exempt(char, SNAP_EXEMPT)
				char:PivotTo(speed.lastGoodCFrame)
				speed.lastPos = speed.lastGoodCFrame.Position
				speed.bucket = 0
				if Config.DEBUG then
					print("rubber band", char.Name)
				end
			end
		end
	end

	-- the cap falls instead of dropping at once, the body takes a moment to slow down and the server sees it late
	local state: Types.MoveState = StateService.current(char)
	speed.windowCap = math.max(MoveDefs[state].cap, speed.windowCap - Config.MOMENTUM_GROUND_DECAY * dt)
	char:SetAttribute("MoveState", state)
end

local function onCharacterAdded(char: Model)
	StateService.add(char)
	StateService.exempt(char, Config.SPAWN_EXEMPT)
	char:SetAttribute("MoveState", StateService.current(char))

	for _, part in char:GetDescendants() do
		setGroup(part)
	end
	-- accessories and tools arrive after spawn
	char.DescendantAdded:Connect(setGroup)
end

local function onPlayerAdded(plr: Player)
	plr.CharacterAdded:Connect(onCharacterAdded)
	plr.CharacterRemoving:Connect(StateService.remove)

	local char = plr.Character
	if char then
		onCharacterAdded(char)
	end
end

-- the place file may already have them from the collision group editor
for _, name in { CHAR_GROUP, PROBE_GROUP } do
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end
PhysicsService:CollisionGroupSetCollidable(PROBE_GROUP, CHAR_GROUP, false)

Remotes.Move.OnServerEvent:Connect(onMove)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(plr)
	local char = plr.Character
	if char then
		StateService.remove(char)
	end
end)
for _, plr in Players:GetPlayers() do
	onPlayerAdded(plr)
end

task.spawn(function()
	while true do
		task.wait(Config.SPEED_SAMPLE_INTERVAL)
		local now = workspace:GetServerTimeNow()
		for _, plr in Players:GetPlayers() do
			local char = plr.Character
			local st = if char then StateService.get(char) else nil
			if not char or not st then
				continue
			end
			sample(char, st, now)
		end
	end
end)

return MovementService
