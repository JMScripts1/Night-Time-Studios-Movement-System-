--!strict
-- Movement & Combat System by Ruha.luau (github.com/JMScripts1)
-- MIT licensed, see LICENSE. Feel free to remove this header.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Action = "Move"

type Bucket = { tokens: number, stamp: number }

local LIMITS: { [Action]: { burst: number, refill: number } } = {
	Move = { burst = Config.MOVE_BURST, refill = Config.MOVE_REFILL },
}

local RateLimit = {}

local buckets: { [Player]: { [Action]: Bucket } } = {}

function RateLimit.check(plr: Player, action: Action): boolean
	local mine = buckets[plr]
	if not mine then
		return false
	end

	local limit = LIMITS[action]
	local now = os.clock()
	local bucket = mine[action]
	if bucket then
		bucket.tokens = math.min(limit.burst, bucket.tokens + (now - bucket.stamp) * limit.refill)
		bucket.stamp = now
	else
		bucket = { tokens = limit.burst, stamp = now }
		mine[action] = bucket
	end

	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- created on join, not on first check, so a remote that lands after PlayerRemoving can't bring an entry back
local function onPlayerAdded(plr: Player)
	buckets[plr] = {}
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(plr)
	buckets[plr] = nil
end)
for _, plr in Players:GetPlayers() do
	onPlayerAdded(plr)
end

return RateLimit
