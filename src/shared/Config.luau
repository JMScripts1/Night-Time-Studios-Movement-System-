--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.

return table.freeze({
	DEBUG = true,

	WALK_SPEED = 14,
	CROUCH_SPEED = 7,
	RUN_SPEED = 22,
	RUN_BUILD = 2,
	-- MoveDirection against the look vector, above this counts as running straight
	RUN_STRAIGHT = 0.95,
	MOMENTUM_MAX = 40,
	MOMENTUM_GROUND_DECAY = 30,
	MOMENTUM_AIR_DECAY = 1.5,
	LAND_GRACE = 0.15,
	AIR_TURN_RATE = 120,

	JUMP_POWER = 50,
	DOUBLE_JUMP_POWER = 80,
	MAX_AIR_JUMPS = 1,
	COYOTE = 0.15,
	-- a drop of at least this below where the ground was left lands in a roll
	ROLL_HEIGHT = 10,
	ROLL_SPEED = 20,
	-- the roll animation is 26 frames at 60 fps, stretched to this
	ROLL_TIME = 26 / 60,

	SLIDE_MIN_SPEED = 18,
	SLIDE_BOOST = 1.1,
	SLIDE_DECAY = 12,
	SLIDE_END_SPEED = 10,
	SLIDE_COOLDOWN = 1.2,
	SLIDE_JUMP_GAIN = 4,
	-- the slide jump launches at momentum times this plus SLIDE_JUMP_LIFT up, held for SLIDE_JUMP_LAUNCH_TIME
	SLIDE_JUMP_LAUNCH = 1.5,
	SLIDE_JUMP_LIFT = 18,
	SLIDE_JUMP_LAUNCH_TIME = 0.25,
	-- a slide jump that clears a drop of LEDGE_LEAP_DROP within LEDGE_LEAP_WINDOW of takeoff turns into a ledge leap
	LEDGE_LEAP_WINDOW = 0.2,
	LEDGE_LEAP_DROP = 8,
	LEDGE_LEAP_GAIN = 8,
	LEDGE_LEAP_LAUNCH = 2,
	LEDGE_LEAP_LIFT = 30,
	LEDGE_LEAP_LAUNCH_TIME = 0.25,
	-- the leap lasts as long as its animation, this is the most the server allows and the length until it loads
	LEDGE_LEAP_TIME = 1,
	-- degrees per second the slide turns toward the camera
	SLIDE_TURN_RATE = 90,

	WALL_REACH = 2.5,
	WALL_SPAN_OFFSETS = table.freeze({ 1.5, -1.5 }),
	WALL_MAX_NORMAL_Y = 0.2,
	FACING_SPLIT = 0.7,
	WALL_REGRAB = 0.4,
	WALLRUN_MIN_SPEED = 16,
	WALLRUN_MAX_TIME = 2.5,
	WALLRUN_FALL_SPEED = 3,
	WALLRUN_DECAY = 2,
	CLING_MAX_TIME = 3,
	CLING_SLIDE_SPEED = 2,
	LEAP_OUT = 60,
	LEAP_UP = 80,
	LEAP_TIME = 0.35,
	LEAP_GAIN = 6,
	BOOST_UP = 100,
	BOOST_TIME = 0.6,
	BOOST_IN = 10,

	MANTLE_COOLDOWN = 0.4,
	LEDGE_REACH = 2.5,
	-- Mantle lip window from the root centre, just above the feet to 5 over the head
	LEDGE_LOW = -2.5,
	LEDGE_HIGH = 6.5,
	LEDGE_DEPTH = 1.5,
	-- seconds after letting go of a cling or boost that Mantle still works from Fall
	LEDGE_GRACE = 0.3,
	-- the Mantle animation's length, it plants its hands at the halfway point
	MANTLE_TIME = 0.4,
	-- where the root sits when the hands land, above the lip and out from the wall face
	LEDGE_PLANT_UP = 0.5,
	LEDGE_PLANT_OUT = 0.5,
	TOP_MIN_NORMAL_Y = 0.8,

	DASH_SPEED = 55,
	DASH_TIME = 0.25,
	DASH_TAIL = 0.15,
	DASH_AIR_HOLD = 0.1,
	-- the back dash is a slow backstep, then a burst when its animation hits the Boost marker
	BACK_DASH_SPEED = 20,
	BACK_DASH_DRIFT = 0.8,
	BACK_DASH_BOOST = 3,
	-- the backstep stops here if the marker hasn't fired, so the marker has to come before it
	BACK_DASH_TIME = 0.5,
	BACK_DASH_BOOST_TIME = 0.2,
	BACK_DASH_ANIM_TIME = 1,
	-- a forward dash in the air bursts at AIR_DASH_SPEED, then carries momentum plus AIR_DASH_GAIN, at least AIR_DASH_EXIT
	AIR_DASH_SPEED = 70,
	AIR_DASH_GAIN = 4,
	AIR_DASH_EXIT = 28,
	-- upward speed held through DASH_AIR_HOLD instead of zero, so the air dash rises a little
	AIR_DASH_LIFT = 30,
	LEAN_WALK = 9,
	LEAN_SPRINT = 11,
	LEAN_TIME = 0.08,
	ANIM_FADE = 0.1,
	-- run animation speed through a running jump, back to 1 on landing
	RUN_JUMP_ANIM_SPEED = 0.3,
	HURT_THRESHOLD = 0.3,
	HURT_SPEED_PENALTY = 4,
	DODGE_TIME = 0.15,
	DASH_COOLDOWN = 1.2,

	KEYS = table.freeze({
		SPRINT = Enum.KeyCode.W,
		CROUCH = Enum.KeyCode.LeftControl,
		JUMP = Enum.KeyCode.Space,
		DASH = Enum.KeyCode.Q,
		MANTLE = Enum.KeyCode.F,
	}),
	-- most seconds between the two taps of the sprint key
	DOUBLE_TAP = 0.3,

	-- offsets from the HumanoidRootPart centre, same for every R6 character
	ROOT_HEIGHT = 3,
	KNEE_Y = -2,
	GROUND_RAY = 4,
	STAND_RAY = 2.5,

	MOVE_BURST = 10,
	MOVE_REFILL = 8,
	SPEED_SAMPLE_INTERVAL = 0.25,
	SPEED_TOLERANCE = 1.25,
	SPEED_LAG_STUDS = 4,
	SPEED_BUCKET_MAX = 6,
	SPEED_BUCKET_DRAIN = 1.5,
	SPAWN_EXEMPT = 1.5,
	-- server side give, so jitter and the server's slightly old view never deny a real player
	COOLDOWN_TOLERANCE = 0.15,
	LAND_SLACK = 3,
	PROBE_SLACK = 3,
	PROBE_LAG = 0.25,

	STAMINA_MAX = 100,
	STAMINA_REGEN = 15,
})
