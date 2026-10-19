--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

local Probes = {}

local params = RaycastParams.new()
params.CollisionGroup = "MoveProbe"

local DROP_RAY = Vector3.new(0, -(Config.ROOT_HEIGHT + Config.LEDGE_LEAP_DROP), 0)

local function isWallFace(hit: RaycastResult): boolean
	return math.abs(hit.Normal.Y) <= Config.WALL_MAX_NORMAL_Y and hit.Instance.Anchored
end

local function isVaultable(part: BasePart): boolean
	if part:HasTag("Vaultable") then
		return true
	end
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:HasTag("Vaultable")
end

-- a ray that starts inside a part never hits it, so a top above fromY is rejected for free
local function findTop(part: BasePart, point: Vector3, fromY: number, depth: number): Vector3?
	local hit = workspace:Raycast(Vector3.new(point.X, fromY, point.Z), Vector3.new(0, -depth, 0), params)
	if hit and hit.Instance == part and hit.Normal.Y >= Config.TOP_MIN_NORMAL_Y then
		return hit.Position
	end
	return nil
end

local function hasHeadroom(from: Vector3, look: Vector3, topY: number, length: number): boolean
	local origin = Vector3.new(from.X, topY + Config.ROOT_HEIGHT, from.Z)
	return workspace:Raycast(origin, look * length, params) == nil
end

function Probes.wall(root: BasePart, speed: number, reach: number?): Types.WallHit?
	local cf = root.CFrame

	for _, dir in { cf.LookVector, cf.RightVector, -cf.RightVector } do
		local ray = dir * (reach or Config.WALL_REACH)
		local hit = workspace:Raycast(cf.Position, ray, params)
		if not hit or not isWallFace(hit) or hit.Instance:HasTag("NoWall") then
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

function Probes.ground(root: BasePart, reach: number?): RaycastResult?
	return workspace:Raycast(root.Position, Vector3.new(0, -(reach or Config.GROUND_RAY), 0), params)
end

-- nothing at knee height means the body has risen past the top of whatever is in front
function Probes.isOverLip(root: BasePart, dir: Vector3): boolean
	local knee = root.Position + Vector3.new(0, Config.KNEE_Y, 0)
	return workspace:Raycast(knee, dir * Config.WALL_REACH, params) == nil
end

-- no floor within LEDGE_LEAP_DROP under the feet, here or `ahead` of here
function Probes.isOverDrop(root: BasePart, ahead: Vector3?): boolean
	if workspace:Raycast(root.Position, DROP_RAY, params) == nil then
		return true
	end
	return ahead ~= nil and workspace:Raycast(root.Position + ahead, DROP_RAY, params) == nil
end

function Probes.ceiling(root: BasePart): RaycastResult?
	return workspace:Raycast(root.Position, Vector3.new(0, Config.STAND_RAY, 0), params)
end

-- the client also checks it's moving toward the hit, the server skips that
function Probes.vaultLow(root: BasePart, reach: number?): Types.VaultHit?
	local cf = root.CFrame
	local length = reach or Config.VAULT_REACH
	local hit = workspace:Raycast(cf.Position + Vector3.new(0, Config.KNEE_Y, 0), cf.LookVector * length, params)
	if not hit or not isWallFace(hit) or not isVaultable(hit.Instance) then
		return nil
	end

	local floorY = cf.Position.Y - Config.ROOT_HEIGHT
	local top = findTop(
		hit.Instance,
		hit.Position - hit.Normal * Config.VAULT_INSET,
		floorY + Config.VAULT_LOW_MAX_H,
		Config.VAULT_LOW_MAX_H - Config.VAULT_LOW_MIN_H
	)
	-- from the top, not the root, so it covers the vault path wherever the probe started
	if not top or not hasHeadroom(top, cf.LookVector, top.Y, Config.VAULT_LOW_OVER) then
		return nil
	end

	return { kind = "Low", part = hit.Instance, topY = top.Y, point = top, normal = hit.Normal }
end

-- the wall ray goes along the bottom of the lip window, so any lip above it is found
function Probes.vaultMid(root: BasePart, slack: number?): Types.VaultHit?
	local cf = root.CFrame
	local give = slack or 0
	local low = cf.Position + Vector3.new(0, Config.LEDGE_LOW - give, 0)

	local hit = workspace:Raycast(low, cf.LookVector * (Config.LEDGE_REACH + give), params)
	if not hit or not isWallFace(hit) or not isVaultable(hit.Instance) then
		return nil
	end

	local fromY = cf.Position.Y + Config.LEDGE_HIGH + give
	local top = findTop(hit.Instance, hit.Position - hit.Normal * Config.LEDGE_DEPTH, fromY, fromY - low.Y)
	if not top or not hasHeadroom(cf.Position, cf.LookVector, top.Y, Config.LEDGE_REACH + Config.LEDGE_DEPTH) then
		return nil
	end

	return { kind = "Mid", part = hit.Instance, topY = top.Y, point = top, normal = hit.Normal }
end

return Probes
