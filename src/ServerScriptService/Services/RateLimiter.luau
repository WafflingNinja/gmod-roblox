--!strict
local Players = game:GetService("Players")

type Bucket = { tokens: number, updatedAt: number }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Limiter = typeof(setmetatable(
	{} :: { capacity: number, refill: number, buckets: { [Player]: Bucket } },
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number): Limiter
	local self = setmetatable({
		capacity = capacity,
		refill = refillPerSecond,
		buckets = {} :: { [Player]: Bucket },
	}, RateLimiter)
	Players.PlayerRemoving:Connect(function(player)
		self.buckets[player] = nil
	end)
	return self
end

-- Token bucket: true if `cost` tokens were available and spent.
function RateLimiter.consume(self: Limiter, player: Player, cost: number): boolean
	local now = os.clock()
	local bucket: Bucket = self.buckets[player] or { tokens = self.capacity, updatedAt = now }
	bucket.tokens = math.min(self.capacity, bucket.tokens + (now - bucket.updatedAt) * self.refill)
	bucket.updatedAt = now
	self.buckets[player] = bucket
	if bucket.tokens < cost then
		return false
	end
	bucket.tokens -= cost
	return true
end

return RateLimiter
