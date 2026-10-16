--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local Probes = {}

local params = RaycastParams.new()
params.CollisionGroup = "MoveProbe"

local function isWallFace(hit: RaycastResult): boolean
	return math.abs(hit.Normal.Y) <= Config.WALL_MAX_NORMAL_Y and hit.Instance.Anchored
end

local function isVaultable(part: BasePart): boolean
	if part:GetAttribute("Vaultable") == true then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:GetAttribute("Vaultable") == true
end

-- a ray that starts inside a part never hits it, so a top above fromY is rejected for free
local function findTop(part: BasePart, point: Vector3, fromY: number, depth: number): number?
	local hit = workspace:Raycast(Vector3.new(point.X, fromY, point.Z), Vector3.new(0, -depth, 0), params)
	if hit and hit.Instance == part and hit.Normal.Y >= Config.TOP_MIN_NORMAL_Y then
		return hit.Position.Y
	end
	return nil
end

local function hasHeadroom(root: BasePart, topY: number, length: number): boolean
	local origin = Vector3.new(root.Position.X, topY + Config.ROOT_HEIGHT, root.Position.Z)
	return workspace:Raycast(origin, root.CFrame.LookVector * length, params) == nil
end

function Probes.wall(root: BasePart, speed: number): Types.WallHit?
	local cf = root.CFrame

	for _, dir in { cf.LookVector, cf.RightVector, -cf.RightVector } do
		local ray = dir * Config.WALL_REACH
		local hit = workspace:Raycast(cf.Position, ray, params)
		if not hit or not isWallFace(hit) or hit.Instance:GetAttribute("NoWall") then
			continue
		end

		-- centre plus one more height on the same part, so a ledge corner isn't a wall
		local spans = 0
		for _, offset in Config.WALL_SPAN_OFFSETS do
			local other = workspace:Raycast(cf.Position + Vector3.new(0, offset, 0), ray, params)
			if other and other.Instance == hit.Instance then
				spans += 1
			end
		end
		if spans == 0 then
			continue
		end

		local normal = Vector3.new(hit.Normal.X, 0, hit.Normal.Z).Unit
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
		if -look:Dot(normal) >= Config.FACING_SPLIT then
			return { kind = "Cling", normal = normal, part = hit.Instance }
		elseif speed < Config.WALLRUN_MIN_SPEED then
			return nil
		end

		local side: "Left" | "Right" = if cf.RightVector:Dot(-normal) > 0 then "Right" else "Left"
		return { kind = "Run", side = side, normal = normal, part = hit.Instance }
	end

	return nil
end

function Probes.ground(root: BasePart): RaycastResult?
	return workspace:Raycast(root.Position, Vector3.new(0, -Config.GROUND_RAY, 0), params)
end

-- the client also checks it's moving toward the hit, the server skips that
function Probes.vaultLow(root: BasePart): Types.VaultHit?
	local cf = root.CFrame
	local hit =
		workspace:Raycast(cf.Position + Vector3.new(0, Config.KNEE_Y, 0), cf.LookVector * Config.VAULT_REACH, params)
	if not hit or not isWallFace(hit) or not isVaultable(hit.Instance) then
		return nil
	end

	local floorY = cf.Position.Y - Config.ROOT_HEIGHT
	local topY = findTop(
		hit.Instance,
		hit.Position - hit.Normal * Config.VAULT_INSET,
		floorY + Config.VAULT_LOW_MAX_H,
		Config.VAULT_LOW_MAX_H - Config.VAULT_LOW_MIN_H
	)
	if not topY or not hasHeadroom(root, topY, Config.VAULT_REACH) then
		return nil
	end

	return { kind = "Low", part = hit.Instance, topY = topY, normal = hit.Normal }
end

function Probes.vaultMid(root: BasePart): Types.VaultHit?
	local cf = root.CFrame
	local head = cf.Position + Vector3.new(0, Config.HEAD_Y, 0)
	local reach = cf.LookVector * Config.LEDGE_REACH

	local hit = workspace:Raycast(head, reach, params)
	if not hit or not isWallFace(hit) or not isVaultable(hit.Instance) then
		return nil
	end
	if workspace:Raycast(head + Vector3.new(0, Config.LEDGE_MAX_UP, 0), reach, params) then
		return nil
	end

	local topY = findTop(
		hit.Instance,
		hit.Position - hit.Normal * Config.LEDGE_DEPTH,
		head.Y + Config.LEDGE_MAX_UP,
		Config.LEDGE_MAX_UP - Config.LEDGE_MIN_UP
	)
	if not topY or not hasHeadroom(root, topY, Config.LEDGE_REACH + Config.LEDGE_DEPTH) then
		return nil
	end

	return { kind = "Mid", part = hit.Instance, topY = topY, normal = hit.Normal }
end

return Probes
