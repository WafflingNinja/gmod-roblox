--!strict
local Players = game:GetService("Players")

type Bucket = { tokens: number, updatedAt: number }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Limiter = typeof(setmetatable(
	{} :: { capacity: number, refill: number, buckets: { [Player]: Bucket } },
	RateLimiter
))

-- One cleanup connection for every limiter, instead of one each; a NaN or negative
-- rate would silently break the bucket math, so clamp at construction.
local all: { [Limiter]: boolean } = {}
Players.PlayerRemoving:Connect(function(player)
	for limiter in all do
		limiter.buckets[player] = nil
	end
end)

-- Token bucket: capacity tokens up front, refilled at refillPerSecond. A 0 refill is a burst-only
-- limiter; capacity is clamped to at least 1 so a 0/negative capacity can never deny forever.
function RateLimiter.new(capacity: number, refillPerSecond: number): Limiter
	local self = setmetatable({
		capacity = if capacity >= 1 then capacity else 1,
		refill = if refillPerSecond > 0 then refillPerSecond else 0,
		buckets = {} :: { [Player]: Bucket },
	}, RateLimiter)
	all[self] = true
	return self
end

-- Token bucket: true if `cost` tokens were available and spent. cost <= 0 is free.
-- A NaN cost would poison the bucket's token count, so it is refused as a bad request instead.
function RateLimiter.consume(self: Limiter, player: Player, cost: number): boolean
	if cost ~= cost then
		return false -- NaN cost: refuse, never touch the bucket
	end
	if cost <= 0 then
		return true -- free
	end
	local now = os.clock()
	local bucket: Bucket = self.buckets[player] or { tokens = self.capacity, updatedAt = now }
	-- elapsed is clamped: os.clock() can only move forward here, but a clock change between the
	-- two calls would give a huge dt and hand out a full bucket in one step.
	local elapsed = math.clamp(now - bucket.updatedAt, 0, 60)
	bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refill)
	bucket.updatedAt = now
	self.buckets[player] = bucket
	if bucket.tokens < cost then
		return false
	end
	bucket.tokens -= cost
	return true
end

return RateLimiter
