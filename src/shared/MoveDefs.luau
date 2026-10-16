--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type Target = Types.MoveState | "Land"

type Row = {
	group: Types.MoveGroup,
	wire: Types.MoveState?,
	duration: number?,
	after: Types.MoveState?,
	cooldown: number?,
	to: { Target },
}

local LAND: { Types.MoveState } = { "Walk", "Run", "Slide", "CrouchWalk" }

local WALK_TO: { Target } = { "Run", "CrouchWalk", "Jump", "Fall", "VaultLow" }
local CROUCH_TO: { Target } = { "Walk", "Run", "Jump", "Fall" }

-- rows use wire names, Idle and CrouchIdle get filled in below
local rows: { [Types.MoveState]: Row } = {
	Idle = { group = "Grounded", wire = "Walk", to = WALK_TO },
	Walk = { group = "Grounded", to = WALK_TO },
	Run = { group = "Grounded", to = { "Walk", "Slide", "Jump", "Fall", "VaultLow" } },
	Slide = {
		group = "Grounded",
		cooldown = Config.SLIDE_COOLDOWN,
		to = { "Run", "Walk", "CrouchWalk", "SlideJump", "Fall" },
	},
	CrouchIdle = { group = "Grounded", wire = "CrouchWalk", to = CROUCH_TO },
	CrouchWalk = { group = "Grounded", to = CROUCH_TO },
	VaultLow = {
		group = "Grounded",
		duration = Config.VAULT_LOW_TIME,
		after = "Walk",
		cooldown = Config.VAULT_COOLDOWN,
		to = { "Run", "Walk", "Fall" },
	},

	Jump = { group = "Airborne", to = { "DoubleJump", "Fall", "WallRun", "WallCling", "Land" } },
	DoubleJump = { group = "Airborne", to = { "Fall", "WallRun", "WallCling", "Land" } },
	SlideJump = { group = "Airborne", to = { "DoubleJump", "Fall", "WallRun", "WallCling", "Land" } },
	Fall = { group = "Airborne", to = { "DoubleJump", "WallRun", "WallCling", "Land" } },

	WallRun = {
		group = "Wall",
		duration = Config.WALLRUN_MAX_TIME,
		after = "Fall",
		to = { "WallLeap", "Fall", "Land" },
	},
	WallLeap = {
		group = "Wall",
		duration = Config.LEAP_TIME,
		after = "Fall",
		to = { "Fall", "WallRun", "WallCling", "Land" },
	},
	WallCling = {
		group = "Wall",
		duration = Config.CLING_MAX_TIME,
		after = "Fall",
		to = { "WallBoost", "VaultMid", "Fall", "Land" },
	},
	WallBoost = {
		group = "Wall",
		duration = Config.BOOST_TIME,
		after = "Fall",
		to = { "VaultMid", "Fall", "WallRun", "WallCling", "Land" },
	},
	VaultMid = {
		group = "Wall",
		duration = Config.VAULT_MID_TIME,
		after = "Walk",
		cooldown = Config.VAULT_COOLDOWN,
		to = { "Walk", "Fall" },
	},
}

local function cap(wire: Types.MoveState): number
	if wire == "Walk" then
		return Config.WALK_SPEED
	elseif wire == "CrouchWalk" then
		return Config.CROUCH_SPEED
	end
	return Config.MOMENTUM_MAX
end

local MoveDefs: { [Types.MoveState]: Types.MoveDef } = {}

-- loop vars are annotated because the old solver widens them to string
for state: Types.MoveState, row in rows do
	local wire: Types.MoveState = row.wire or state

	local to: { [Types.MoveState]: true } = {}
	for _, target: Target in row.to do
		if target == "Land" then
			for _, s: Types.MoveState in LAND do
				to[s] = true
			end
		else
			to[target] = true
		end
	end

	-- anything that can go to Walk can go to Idle, and Idle and Walk can swap freely
	for other: Types.MoveState, otherRow in rows do
		local otherWire: Types.MoveState = otherRow.wire or other
		if other ~= state and (to[otherWire] or otherWire == wire) then
			to[other] = true
		end
	end

	-- frozen in place, the new solver's read only freeze type doesn't fit MoveDef
	local def: Types.MoveDef = {
		group = row.group,
		wire = wire,
		cap = cap(wire),
		cost = 0,
		cooldown = row.cooldown or 0,
		duration = row.duration,
		after = row.after,
		to = to,
	}
	MoveDefs[state] = def
	table.freeze(to)
	table.freeze(def)
end

for state, def in MoveDefs do
	for target: Types.MoveState in def.to do
		assert(MoveDefs[target], `{state} goes to {target}, which has no row`)
	end
	assert(not def.after or MoveDefs[def.after], `{state} ends in a state with no row`)
end

return table.freeze(MoveDefs)
