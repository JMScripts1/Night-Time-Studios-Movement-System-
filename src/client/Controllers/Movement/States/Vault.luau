--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Parent.Context)
local InputController = require(script.Parent.Parent.Parent.InputController)
local Ground = require(script.Parent.Ground)

type Ctx = Context.Ctx

local STAND = Vector3.new(0, Config.ROOT_HEIGHT, 0)
local LIFT = Vector3.new(0, Config.ROOT_HEIGHT + Config.VAULT_CLEAR, 0)

local Vault = {}

function Vault.enter(c: Ctx)
	local hit = c.vault :: Types.VaultHit
	local start = c.root.Position
	local facing, peak, finish

	if c.state == "VaultLow" then
		facing = Context.look(c)
		peak = hit.point + LIFT
		finish = peak + facing * Config.VAULT_LOW_OVER
		c.momentum = math.min(Config.MOMENTUM_MAX, c.momentum * Config.VAULT_BOOST)
	else
		facing = Vector3.new(-hit.normal.X, 0, -hit.normal.Z).Unit
		peak = Vector3.new(start.X, hit.point.Y + LIFT.Y, start.Z)
		finish = hit.point + STAND
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
	-- a quadratic through start and finish that passes the peak halfway
	c.vaulting =
		{ trove = trove, mover = mover, start = start, bend = peak * 2 - (start + finish) / 2, finish = finish }
end

function Vault.update(c: Ctx): Types.MoveState?
	local run = c.vaulting :: Context.VaultRun
	local isLow = c.state == "VaultLow"
	local t = (os.clock() - c.since) / (if isLow then Config.VAULT_LOW_TIME else Config.VAULT_MID_TIME)

	if t >= 1 then
		if not Ground.isGrounded(c) then
			return "Fall"
		end
		return if isLow and InputController.isDown("Sprint") then "Run" else "Walk"
	end

	local u = 1 - t
	run.mover.Position = run.start * (u * u) + run.bend * (2 * t * u) + run.finish * (t * t)
	return nil
end

function Vault.exit(c: Ctx)
	c.trove:Remove((c.vaulting :: Context.VaultRun).trove)
	c.vaulting = nil
	Context.release(c)
end

return Vault
