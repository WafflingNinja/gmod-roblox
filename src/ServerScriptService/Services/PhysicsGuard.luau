--!strict
-- Network ownership policy for loose props: Roblox auto-assigns them to nearby clients, which can then
-- fling them. A prop moving faster than the cap is taken server-side, clamped, and handed back later.
-- Props that fall below Workspace.FallenPartsDestroyHeight are already destroyed by the engine.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hold = require(script.Parent.Hold)

local CHECK_INTERVAL = 0.1
local RECLAIM_SECONDS = 3

local reclaimed: { [BasePart]: number } = {} -- prop -> when ownership goes back to auto

local PhysicsGuard = {}

-- ponytail: walks every tagged prop 10x per second (150 per player); bucket by assembly if it shows in profiles.
local function check()
	local now = os.clock()
	local maxSpeed = Config.PROP_MAX_SPEED
	for _, instance in CollectionService:GetTagged(Config.PROP_TAG) do
		if not instance:IsA("BasePart") or instance.Anchored then
			continue
		end
		local velocity = instance.AssemblyLinearVelocity
		local speed = velocity.Magnitude
		if speed > maxSpeed then
			-- One shared no-op harness instead of a fresh closure per hot prop.
			pcall(instance.SetNetworkOwner, instance, nil)
			instance.AssemblyLinearVelocity = velocity * (maxSpeed / speed)
			reclaimed[instance] = now + RECLAIM_SECONDS
		end
	end
	for prop, at in reclaimed do
		if not prop.Parent then
			reclaimed[prop] = nil
		elseif now >= at then
			reclaimed[prop] = nil
			if not prop.Anchored and not Hold.isHeld(prop) then
				pcall(prop.SetNetworkOwnershipAuto, prop)
			end
		end
	end
end

function PhysicsGuard.init()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= CHECK_INTERVAL then
			elapsed = 0
			check()
		end
	end)
end

return PhysicsGuard
