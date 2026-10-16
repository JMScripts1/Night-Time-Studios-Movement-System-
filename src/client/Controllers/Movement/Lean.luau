--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local MoveDefs = require(ReplicatedStorage.Shared.MoveDefs)
local Types = require(ReplicatedStorage.Shared.Types)
local Context = require(script.Parent.Context)

type Ctx = Context.Ctx

local WALK = math.rad(Config.LEAN_WALK)
local SPRINT = math.rad(Config.LEAN_SPRINT)

local OFF: { [Types.MoveState]: true } = { Slide = true, VaultLow = true }

local Lean = {}

function Lean.update(c: Ctx, dt: number)
	local state: Types.MoveState = c.state
	local target = Vector2.zero
	if MoveDefs[state].group ~= "Wall" and not OFF[state] then
		local dir = c.root.CFrame:VectorToObjectSpace(c.hum.MoveDirection)
		target = Vector2.new(-dir.Z, dir.X) * (if state == "Run" then SPRINT else WALK)
	end
	c.lean += (target - c.lean) * (1 - math.exp(-dt / Config.LEAN_TIME))

	-- the animator only rewrites Transform on frames it animates this joint, so our last write can still be there
	local joint = c.rootJoint
	local base = if joint.Transform:FuzzyEq(c.leanSet) then c.leanBase else joint.Transform

	-- tilt is in root space, wrapping it in C0 puts it in joint space on top of the animated pose
	local c0 = joint.C0.Rotation
	local tilt = CFrame.Angles(-c.lean.X, 0, -c.lean.Y)
	c.leanBase = base
	c.leanSet = c0:Inverse() * tilt * c0 * base
	joint.Transform = c.leanSet
end

return Lean
