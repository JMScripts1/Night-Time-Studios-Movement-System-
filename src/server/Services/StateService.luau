--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)

export type CharState = {
	move: {
		state: Types.MoveState,
		prev: Types.MoveState,
		since: number,
		endsAt: number?,
		airJumps: number,
		lastWallPart: BasePart?,
		groundedAt: number,
		cooldownUntil: { [Types.MoveState]: number },
	},
	dash: {
		dashUntil: number,
		dodgeUntil: number,
		dashCooldownUntil: number,
	},
	speed: {
		windowCap: number,
		lastGoodCFrame: CFrame,
		bucket: number,
		exemptUntil: number,
		lastPos: Vector3,
		sampledAt: number,
		measured: number,
	},
	combat: {
		stunnedUntil: number,
		attackUntil: number,
		parryUntil: number,
		downed: boolean,
	},
	stamina: {
		value: number,
		stamp: number,
	},
}

local SPAWN_STATE: Types.MoveState = "Walk"

local StateService = {}

local states: { [Model]: CharState } = {}

function StateService.add(char: Model)
	local now = workspace:GetServerTimeNow()
	local pivot = char:GetPivot()
	states[char] = {
		move = {
			state = SPAWN_STATE,
			prev = SPAWN_STATE,
			since = now,
			airJumps = 0,
			groundedAt = 0,
			cooldownUntil = {},
		},
		dash = { dashUntil = 0, dodgeUntil = 0, dashCooldownUntil = 0 },
		speed = {
			windowCap = MoveDefs[SPAWN_STATE].cap,
			lastGoodCFrame = pivot,
			bucket = 0,
			exemptUntil = 0,
			lastPos = pivot.Position,
			sampledAt = now,
			measured = 0,
		},
		combat = { stunnedUntil = 0, attackUntil = 0, parryUntil = 0, downed = false },
		stamina = { value = Config.STAMINA_MAX, stamp = now },
	}
end

function StateService.remove(char: Model)
	states[char] = nil

	if Config.DEBUG then
		local count = 0
		for _ in states do
			count += 1
		end
		print("state tables", count)
	end
end

function StateService.get(char: Model): CharState?
	return states[char]
end

function StateService.land(char: Model, at: number)
	local move = states[char].move
	move.airJumps = 0
	move.lastWallPart = nil
	move.groundedAt = at
end

function StateService.current(char: Model): Types.MoveState
	local move = states[char].move
	local endsAt = move.endsAt
	local after: Types.MoveState? = MoveDefs[move.state].after

	-- every timed state ends in an untimed one, so one step is enough
	if endsAt and after and workspace:GetServerTimeNow() >= endsAt then
		-- VaultMid runs out standing on the ledge, which is a landing nobody sends
		if MoveDefs[after].group == "Grounded" and MoveDefs[move.state].group ~= "Grounded" then
			StateService.land(char, endsAt)
		end
		move.prev = move.state
		move.state = after
		move.since = endsAt
		move.endsAt = nil
	end
	return move.state
end

function StateService.canMove(char: Model): boolean
	local combat = states[char].combat
	local now = workspace:GetServerTimeNow()
	return not combat.downed and now >= combat.stunnedUntil and now >= combat.attackUntil
end

function StateService.exempt(char: Model, seconds: number)
	local speed = states[char].speed
	speed.exemptUntil = math.max(speed.exemptUntil, workspace:GetServerTimeNow() + seconds)
end

function StateService.spend(char: Model, cost: number): boolean
	local stamina = states[char].stamina
	local now = workspace:GetServerTimeNow()
	local value = math.min(Config.STAMINA_MAX, stamina.value + (now - stamina.stamp) * Config.STAMINA_REGEN)
	if value < cost then
		return false
	end
	stamina.value = value - cost
	stamina.stamp = now
	return true
end

return StateService
