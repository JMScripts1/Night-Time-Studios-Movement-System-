--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Probes = require(ReplicatedStorage.Shared.Probes)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local Ground = require(script.Parent.Ground)

type Ctx = Context.Ctx

local STAND = Vector3.new(0, Config.ROOT_HEIGHT, 0)

local Mantle = {}

-- the Mantle animation plants its hands on the lip halfway through, so the curve passes there at the midpoint
local function path(hit: Types.LedgeHit, start: Vector3): (number) -> Vector3
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

function Mantle.findLedge(c: Ctx): boolean
	if not Context.isReady(c, "Mantle") then
		return false
	end
	local hit = Probes.ledge(c.root)
	if not hit then
		return false
	end
	c.ledge = hit
	return true
end

function Mantle.enter(c: Ctx)
	local hit = c.ledge :: Types.LedgeHit
	local start = c.root.Position

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

	Context.face(c, Vector3.new(-hit.normal.X, 0, -hit.normal.Z).Unit)
	c.mantling = { trove = trove, mover = mover, at = path(hit, start) }
end

function Mantle.update(c: Ctx): Types.MoveState?
	local run = c.mantling :: Context.MantleRun
	local t = (os.clock() - c.since) / Config.MANTLE_TIME

	if t >= 1 then
		return if Ground.isGrounded(c) then "Walk" else "Fall"
	end

	run.mover.Position = run.at(t)
	return nil
end

function Mantle.exit(c: Ctx)
	c.trove:Remove((c.mantling :: Context.MantleRun).trove)
	c.mantling = nil
	Context.release(c)
end

return Mantle
