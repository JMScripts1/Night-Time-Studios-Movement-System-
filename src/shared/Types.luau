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
	| "VaultLow"
	| "Jump"
	| "DoubleJump"
	| "SlideJump"
	| "Fall"
	| "WallRun"
	| "WallLeap"
	| "WallCling"
	| "WallBoost"
	| "VaultMid"

export type MoveGroup = "Grounded" | "Airborne" | "Wall"

export type DashDir = "F" | "B" | "L" | "R"

export type MoveDef = {
	group: MoveGroup,
	wire: MoveState,
	cap: number,
	cost: number,
	cooldown: number,
	duration: number?,
	after: MoveState?,
	to: { [MoveState]: true },
}

export type WallHit = {
	kind: "Run" | "Cling",
	side: ("Left" | "Right")?,
	normal: Vector3,
	part: BasePart,
}

export type VaultHit = {
	kind: "Low" | "Mid",
	part: BasePart,
	topY: number,
	normal: Vector3,
}

return {}
