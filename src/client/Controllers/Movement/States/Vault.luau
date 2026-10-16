--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)
local Ground = require(script.Parent.Ground)

type Ctx = Context.Ctx

local STAND = Vector3.new(0, Config.ROOT_HEIGHT, 0)
local LIFT = Vector3.new(0, Config.ROOT_HEIGHT + Config.VAULT_CLEAR, 0)
local PLANT_UP = Vector3.new(0, Config.VAULT_PLANT_UP, 0)
local LOW_TIMES = { 0, Config.VAULT_LOW_PLANT_AT, Config.VAULT_LOW_CLEAR_AT, 1 }

local Vault = {}

local function slope(points: { Vector3 }, times: { number }, i: number): Vector3
	local a = math.max(i - 1, 1)
	local b = math.min(i + 1, #points)
	return (points[b] - points[a]) / (times[b] - times[a])
end

-- a hermite curve through every point at its own time, so the root hits each animation key with no corners
local function through(points: { Vector3 }, times: { number }, t: number): Vector3
	local i = #points - 1
	for k = 1, #points - 2 do
		if t <= times[k + 1] then
			i = k
			break
		end
	end

	local span = times[i + 1] - times[i]
	local s = (t - times[i]) / span
	local s2, s3 = s * s, s * s * s
	return points[i] * (2 * s3 - 3 * s2 + 1)
		+ slope(points, times, i) * (span * (s3 - 2 * s2 + s))
		+ points[i + 1] * (3 * s2 - 2 * s3)
		+ slope(points, times, i + 1) * (span * (s3 - s2))
end

-- keyed to the VaultLow animation: hands plant on the near edge, then the body clears the far side
local function lowPath(c: Ctx, hit: Types.VaultHit, start: Vector3, facing: Vector3): ((number) -> Vector3, number)
	local out = Vector3.new(hit.normal.X, 0, hit.normal.Z).Unit
	local edge = hit.point + out * Config.VAULT_INSET
	local plant = edge + facing * Config.VAULT_PLANT_IN + PLANT_UP
	local clear = edge + facing * Config.VAULT_LOW_OVER + LIFT

	-- clear is reached at run speed, then the follow through carries on at it, so a vault never brakes a run
	local across = clear - start
	local toClear = Vector3.new(across.X, 0, across.Z).Magnitude / c.momentum
	local time = math.clamp(toClear / Config.VAULT_LOW_CLEAR_AT, Config.VAULT_LOW_MIN_TIME, Config.VAULT_LOW_TIME)
	local finish = clear
		- Vector3.new(0, Config.VAULT_CLEAR, 0)
		+ facing * (c.momentum * time * (1 - Config.VAULT_LOW_CLEAR_AT))

	local points = { start, plant, clear, finish }
	return function(t)
		return through(points, LOW_TIMES, t)
	end, time
end

-- the VaultMid animation plants its hands on the lip halfway through, so the curve passes there at the midpoint
local function midPath(hit: Types.VaultHit, start: Vector3): (number) -> Vector3
	local out = Vector3.new(hit.normal.X, 0, hit.normal.Z).Unit
	local edge = hit.point + out * Config.LEDGE_DEPTH
	local mid = edge + out * Config.LEDGE_PLANT_OUT + Vector3.new(0, Config.LEDGE_PLANT_UP, 0)
	local finish = hit.point + STAND
	local bend = mid * 2 - (start + finish) / 2

	return function(t)
		local u = 1 - t
		return start * (u * u) + bend * (2 * t * u) + finish * (t * t)
	end
end

function Vault.findLedge(c: Ctx): boolean
	if not Context.isReady(c, "VaultMid") then
		return false
	end
	local hit = Probes.vaultMid(c.root)
	if not hit then
		return false
	end
	c.vault = hit
	return true
end

function Vault.enter(c: Ctx)
	local hit = c.vault :: Types.VaultHit
	local start = c.root.Position
	local facing, at
	local time = Config.VAULT_MID_TIME

	if c.state == "VaultLow" then
		facing = Context.look(c)
		c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum * Config.VAULT_BOOST)
		at, time = lowPath(c, hit, start, facing)
	else
		facing = Vector3.new(-hit.normal.X, 0, -hit.normal.Z).Unit
		at = midPath(hit, start)
	end

	local trove = c.trove:Extend()
	local mover = Instance.new("AlignPosition")
	mover.Mode = Enum.PositionAlignmentMode.OneAttachment
	mover.Attachment0 = c.attach
	mover.RigidityEnabled = true
	mover.Position = start
	mover.Parent = c.root
	trove:Add(mover)

	for _, part in c.char:GetChildren() do
		if part:IsA("BasePart") then
			local ignore = Instance.new("NoCollisionConstraint")
			ignore.Part0 = part
			ignore.Part1 = hit.part
			ignore.Parent = part
			trove:Add(ignore)
		end
	end

	Context.face(c, facing)
	c.vaulting = { trove = trove, mover = mover, facing = facing, time = time, at = at }
end

function Vault.update(c: Ctx): Types.MoveState?
	local run = c.vaulting :: Context.VaultRun
	local t = (os.clock() - c.since) / run.time

	if t >= 1 then
		if not Ground.isGrounded(c) then
			return "Fall"
		end
		return if c.state == "VaultLow" and InputController.isDown("Sprint") then "Run" else "Walk"
	end

	run.mover.Position = run.at(t)
	return nil
end

function Vault.exit(c: Ctx)
	local run = c.vaulting :: Context.VaultRun
	c.trove:Remove(run.trove)
	c.vaulting = nil
	Context.release(c)

	-- hand the speed back to the body, so a vault that ends in the air carries on instead of stalling
	if c.state == "VaultLow" then
		c.root.AssemblyLinearVelocity = run.facing * c.momentum
	end
end

return Vault
