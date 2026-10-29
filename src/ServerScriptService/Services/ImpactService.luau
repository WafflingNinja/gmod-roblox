--!strict
-- Thuds and crunches when props and cars hit something. Each frame the server compares every prop assembly's
-- velocity with the last frame's; a sudden loss of speed is an impact, and harder ones get the heavy sound.
-- Played from the server so everyone nearby hears it.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sfx = require(script.Parent.Sfx)

local LIGHT = 14 -- studs/s of speed lost in one frame
local HEAVY = 40
local COOLDOWN = 0.2 -- seconds between sounds from one assembly

local lastVelocity: { [BasePart]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
local quietUntil: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any

local seen: { [BasePart]: boolean } = {}

local ImpactService = {}

function ImpactService.init()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		table.clear(seen)
		for _, instance in CollectionService:GetTagged(Config.PROP_TAG) do
			if not instance:IsA("BasePart") or instance.Anchored then
				continue
			end
			local root = instance.AssemblyRootPart
			if not root or seen[root] or root.Anchored then
				continue
			end
			seen[root] = true
			local velocity = root.AssemblyLinearVelocity
			local previous = lastVelocity[root]
			lastVelocity[root] = velocity
			if not previous or (quietUntil[root] or 0) > now then
				continue
			end
			local lost = previous.Magnitude - velocity.Magnitude
			if lost >= LIGHT then
				quietUntil[root] = now + COOLDOWN
				Sfx.play(if lost >= HEAVY then "impact_heavy" else "impact_light", root)
			end
		end
	end)
end

return ImpactService
