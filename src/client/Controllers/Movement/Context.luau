--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Trove = require(ReplicatedStorage.Packages.Trove)
local Types = require(ReplicatedStorage.Shared.Types)

-- the old solver can't match Trove's generic methods against the exported Trove type
type Trove = typeof(Trove.new())

local MOVER_FORCE = 1e5
-- slower than this there is no direction of travel worth keeping
local MIN_TRAVEL = 1

local UNUSED_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
}

export type DashRun = {
	isAir: boolean,
	-- the back dash keeps the direction it started in, and boostedAt is set by its animation's Boost marker
	back: Vector3?,
	boostedAt: number?,
}

export type VaultRun = {
	trove: Trove,
	mover: AlignPosition,
	facing: Vector3,
	time: number,
	-- 0 to 1 through the vault, to where the root should be
	at: (number) -> Vector3,
}

export type Ctx = {
	char: Model,
	hum: Humanoid,
	root: BasePart,
	rootJoint: Motor6D,
	attach: Attachment,
	lv: LinearVelocity,
	align: AlignOrientation,
	trove: Trove,

	state: Types.MoveState,
	prev: Types.MoveState,
	since: number,
	momentum: number,
	heading: Vector3,
	airJumps: number,
	landedAt: number,
	takeoffY: number,
	rollUntil: number,
	lastWallPart: BasePart?,
	cooldownUntil: { [Types.MoveState]: number },
	lean: Vector2,
	leanBase: CFrame,
	leanSet: CFrame,

	wall: Types.WallHit?,
	vault: Types.VaultHit?,
	vaulting: VaultRun?,
	dash: DashRun?,
}

local Context = {}

function Context.new(char: Model): Ctx
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local root = char:WaitForChild("HumanoidRootPart") :: BasePart
	local rootJoint = root:WaitForChild("RootJoint") :: Motor6D
	local trove = Trove.new()

	hum.UseJumpPower = true
	hum.JumpPower = Config.JUMP_POWER
	for _, state in UNUSED_STATES do
		hum:SetStateEnabled(state, false)
	end

	local attach = Instance.new("Attachment")
	attach.Parent = root
	trove:Add(attach)

	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = attach
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = MOVER_FORCE
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.Enabled = false
	lv.Parent = root
	trove:Add(lv)

	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attach
	align.RigidityEnabled = true
	align.Enabled = false
	align.Parent = root
	trove:Add(align)

	return {
		char = char,
		hum = hum,
		root = root,
		rootJoint = rootJoint,
		attach = attach,
		lv = lv,
		align = align,
		trove = trove,

		state = "Idle",
		prev = "Idle",
		since = os.clock(),
		momentum = Config.WALK_SPEED,
		heading = Vector3.zero,
		airJumps = 0,
		landedAt = 0,
		takeoffY = 0,
		rollUntil = 0,
		cooldownUntil = {},
		lean = Vector2.zero,
		leanBase = CFrame.identity,
		leanSet = CFrame.identity,
	}
end

function Context.isReady(c: Ctx, state: Types.MoveState): boolean
	return os.clock() >= (c.cooldownUntil[state] or 0)
end

function Context.look(c: Ctx): Vector3
	local look = c.root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

function Context.travel(c: Ctx): Vector3
	local v = c.root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > MIN_TRAVEL then flat.Unit else Vector3.zero
end

-- both flat and unit, turns around Y by at most maxAngle radians
function Context.turn(from: Vector3, to: Vector3, maxAngle: number): Vector3
	local angle = math.acos(math.clamp(from:Dot(to), -1, 1))
	if angle <= maxAngle then
		return to
	end
	local sign = if from:Cross(to).Y < 0 then -1 else 1
	return CFrame.Angles(0, sign * maxAngle, 0) * from
end

-- drives X and Z only, gravity keeps Y
function Context.glide(c: Ctx, velocity: Vector3)
	local lv = c.lv
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	lv.Enabled = true
end

function Context.drive(c: Ctx, velocity: Vector3)
	local lv = c.lv
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = velocity
	lv.Enabled = true
end

function Context.face(c: Ctx, dir: Vector3)
	c.align.CFrame = CFrame.lookAt(Vector3.zero, dir)
	c.align.Enabled = true
	c.hum.AutoRotate = false
end

function Context.release(c: Ctx)
	c.lv.Enabled = false
	c.align.Enabled = false
	c.hum.AutoRotate = true
end

return Context
