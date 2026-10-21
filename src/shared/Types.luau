--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.

export type MoveState =
	"Idle"
	| "Walk"
	| "Run"
	| "Slide"
	| "CrouchIdle"
	| "CrouchWalk"
	| "Jump"
	| "DoubleJump"
	| "SlideJump"
	| "LedgeLeap"
	| "Fall"
	| "WallRun"
	| "WallLeap"
	| "WallCling"
	| "WallBoost"
	| "Mantle"
	| "DashF"
	| "DashB"
	| "DashL"
	| "DashR"

export type MoveGroup = "Grounded" | "Airborne" | "Wall"

-- WallRun and WallLeap play one of their sides, R6 can't mirror at runtime
export type AnimName =
	MoveState
	| "WallRunLeft"
	| "WallRunRight"
	| "WallLeapLeft"
	| "WallLeapRight"
	| "Roll"
	| "LedgeLeap2"
	| "AirDash"

export type MoveDef = {
	group: MoveGroup,
	wire: MoveState,
	cap: number,
	cost: number,
	cooldown: number,
	duration: number?,
	after: MoveState?,
	-- the other state on the same cooldown
	shares: MoveState?,
	isDash: boolean,
	-- holds onto a wall part, so the same part can't be grabbed again straight after
	isAttached: boolean,
	to: { [MoveState]: true },
}

export type WallHit = {
	kind: "Run" | "Cling",
	side: ("Left" | "Right")?,
	normal: Vector3,
	part: BasePart,
}

export type LedgeHit = {
	part: BasePart,
	point: Vector3,
	normal: Vector3,
}

return {}
