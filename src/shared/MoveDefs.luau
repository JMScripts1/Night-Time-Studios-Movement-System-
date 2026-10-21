--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

type Target = Types.MoveState | "Land" | "Dash"

type Row = {
	group: Types.MoveGroup,
	wire: Types.MoveState?,
	duration: number?,
	after: Types.MoveState?,
	cooldown: number?,
	shares: Types.MoveState?,
	isDash: true?,
	isAttached: true?,
	isDashReset: true?,
	to: { Target },
}

local LAND: { Types.MoveState } = { "Walk", "Run", "Slide", "CrouchWalk" }
local DASH: { Types.MoveState } = { "DashF", "DashB", "DashL", "DashR" }

local WALK_TO: { Target } = { "Run", "CrouchWalk", "Jump", "Fall", "Dash" }
local CROUCH_TO: { Target } = { "Walk", "Run", "Fall" }
-- nothing cuts a dash short, it hands over to whatever the character is doing once it's over
local DASH_TO: { Target } = { "Walk", "Run", "CrouchWalk", "Fall" }

-- the fastest any dash bursts, and no dash runs slower than momentum
local DASH_CAP = math.max(
	Config.DASH_SPEED,
	Config.AIR_DASH_SPEED,
	Config.BACK_DASH_SPEED * Config.BACK_DASH_BOOST,
	Config.MOMENTUM_MAX
)

-- airborne so a dash off the ground is a takeoff and the end of one is a landing
local function dash(duration: number, shares: Types.MoveState): Row
	return {
		group = "Airborne",
		duration = duration,
		after = "Fall",
		cooldown = Config.DASH_COOLDOWN,
		shares = shares,
		isDash = true,
		to = DASH_TO,
	}
end

-- rows use wire names, Idle and CrouchIdle get filled in below
local rows: { [Types.MoveState]: Row } = {
	Idle = { group = "Grounded", wire = "Walk", to = WALK_TO },
	Walk = { group = "Grounded", to = WALK_TO },
	Run = { group = "Grounded", to = { "Walk", "Slide", "Jump", "Fall", "Dash" } },
	Slide = {
		group = "Grounded",
		cooldown = Config.SLIDE_COOLDOWN,
		to = { "Run", "Walk", "CrouchWalk", "SlideJump", "Fall" },
	},
	CrouchIdle = { group = "Grounded", wire = "CrouchWalk", to = CROUCH_TO },
	CrouchWalk = { group = "Grounded", to = CROUCH_TO },

	Jump = { group = "Airborne", to = { "DoubleJump", "Fall", "WallRun", "WallCling", "Mantle", "Land", "Dash" } },
	DoubleJump = { group = "Airborne", to = { "Fall", "WallRun", "WallCling", "Mantle", "Land", "Dash" } },
	SlideJump = {
		group = "Airborne",
		to = { "LedgeLeap", "DoubleJump", "Fall", "WallRun", "WallCling", "Mantle", "Land", "Dash" },
	},
	LedgeLeap = {
		group = "Airborne",
		duration = Config.LEDGE_LEAP_TIME,
		after = "Fall",
		to = { "DoubleJump", "Fall", "WallRun", "WallCling", "Mantle", "Land", "Dash" },
	},
	Fall = { group = "Airborne", to = { "DoubleJump", "WallRun", "WallCling", "Mantle", "Land", "Dash" } },

	-- front and back share a cooldown and so do the sides, so a side dash chains into a front one
	DashF = dash(Config.DASH_TIME, "DashB"),
	-- the burst comes at its animation's marker, which is never later than the end of the backstep
	DashB = dash(Config.BACK_DASH_TIME + Config.BACK_DASH_BOOST_TIME, "DashF"),
	DashL = dash(Config.DASH_TIME, "DashR"),
	DashR = dash(Config.DASH_TIME, "DashL"),

	WallRun = {
		group = "Wall",
		duration = Config.WALLRUN_MAX_TIME,
		after = "Fall",
		isAttached = true,
		isDashReset = true,
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
		-- a cling on its own doesn't give the air dash back, the boost out of it does
		isAttached = true,
		to = { "WallBoost", "Mantle", "Fall", "Land" },
	},
	WallBoost = {
		group = "Wall",
		duration = Config.BOOST_TIME,
		after = "Fall",
		isDashReset = true,
		to = { "Mantle", "Fall", "WallRun", "WallCling", "Land" },
	},
	Mantle = {
		group = "Wall",
		duration = Config.MANTLE_TIME,
		after = "Walk",
		cooldown = Config.MANTLE_COOLDOWN,
		to = { "Walk", "Fall" },
	},
}

local function cap(wire: Types.MoveState): number
	if wire == "Walk" then
		return Config.WALK_SPEED
	elseif wire == "CrouchWalk" then
		return Config.CROUCH_SPEED
	elseif wire == "WallLeap" then
		-- the leap's push goes past momentum, see WallRun on the client
		return Config.MOMENTUM_MAX + Config.LEAP_GAIN + Config.LEAP_OUT
	elseif wire == "SlideJump" then
		-- the launch runs at a multiple of momentum, see Air on the client
		return Config.MOMENTUM_MAX * Config.SLIDE_JUMP_LAUNCH
	elseif wire == "LedgeLeap" then
		return Config.MOMENTUM_MAX * Config.LEDGE_LEAP_LAUNCH
	elseif rows[wire].isDash then
		return DASH_CAP
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
		elseif target == "Dash" then
			for _, s: Types.MoveState in DASH do
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
		shares = row.shares,
		isDash = row.isDash == true,
		isAttached = row.isAttached == true,
		isDashReset = row.isDashReset == true,
		to = to,
	}
	MoveDefs[state] = def
	table.freeze(to)
	table.freeze(def)
end

-- carried speed never goes past MOMENTUM_MAX, so anything that needs more could never happen
for _, name in { "RUN_SPEED", "SLIDE_MIN_SPEED", "WALLRUN_MIN_SPEED" } do
	assert(Config[name] <= Config.MOMENTUM_MAX, `{name} is above MOMENTUM_MAX`)
end

for state, def in MoveDefs do
	for target: Types.MoveState in def.to do
		assert(MoveDefs[target], `{state} goes to {target}, which has no row`)
	end
	assert(not def.after or MoveDefs[def.after], `{state} ends in a state with no row`)
	assert(not def.shares or MoveDefs[def.shares], `{state} shares a cooldown with a state with no row`)
end

return table.freeze(MoveDefs)
