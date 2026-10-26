--!strict
-- Gravity gun: RMB pulls a far own prop toward the player or holds a near one; LMB punts, or throws the held prop.
-- The server picks pull vs hold from distance and computes every impulse; the client only sends the prop and aim.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hold = require(script.Parent.Hold)
local Ownership = require(script.Parent.Ownership)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)

local remotes = ReplicatedStorage.Remotes
local pullRemote = remotes.GravityPull :: RemoteEvent
local puntRemote = remotes.GravityPunt :: RemoteEvent

local BEAM_COLOR = Color3.fromRGB(255, 150, 30)
local OWNERSHIP_RETURN = 2 -- seconds the server keeps physics after an impulse

local limiter = RateLimiter.new(Config.GRAB_BUCKET_CAPACITY, Config.GRAB_REFILL_PER_SECOND)

-- An impulse only takes effect on the machine that simulates the assembly, so take it server-side first.
local function kick(prop: BasePart, velocity: Vector3)
	local ok = pcall(function()
		prop:SetNetworkOwner(nil)
	end)
	if not ok then
		return -- welded to something anchored
	end
	prop:ApplyImpulse(velocity * prop.AssemblyMass)
	task.delay(OWNERSHIP_RETURN, function()
		if prop.Parent and not prop.Anchored and not Hold.isHeld(prop) then
			pcall(function()
				prop:SetNetworkOwnershipAuto()
			end)
		end
	end)
end

-- Own, loose prop within `range` of a live player holding the gravity gun.
local function check(player: Player, prop: unknown, range: number): (BasePart?, Tool?, BasePart?)
	if typeof(prop) ~= "Instance" or not prop:IsA("BasePart") or prop.Anchored then
		return nil, nil, nil
	end
	if not Ownership.isOwner(player, prop) then
		return nil, nil, nil
	end
	local tool = Validate.equippedTool(player, Config.GRAVGUN)
	local root = Validate.aliveRoot(player)
	if not tool or not root or (prop.Position - root.Position).Magnitude > range then
		return nil, nil, nil
	end
	return prop, tool, root
end

local GravityGunService = {}

function GravityGunService.init()
	pullRemote.OnServerEvent:Connect(function(player: Player, target: unknown)
		if not limiter:consume(player, 1) then
			return
		end
		-- Pulling again while holding drops the prop.
		if Hold.get(player) then
			if Validate.equippedTool(player, Config.GRAVGUN) then
				Hold.release(player)
			end
			return
		end
		local prop, tool, root = check(player, target, Config.GRAVGUN_PULL_RANGE)
		if not prop or not tool or not root then
			return
		end
		local offset = root.Position - prop.Position
		if offset.Magnitude <= Config.GRAVGUN_HOLD_RANGE then
			Hold.start(player, prop, tool, BEAM_COLOR, Config.GRAVGUN_HOLD_RANGE, "gravgun_hold")
		else
			local toward = offset.Unit * Config.GRAVGUN_PULL_SPEED
			kick(prop, toward - prop.AssemblyLinearVelocity)
		end
		Sfx.play("gravgun_pull", prop)
	end)

	puntRemote.OnServerEvent:Connect(function(player: Player, target: unknown, direction: unknown)
		if not limiter:consume(player, 1) then
			return
		end
		if typeof(direction) ~= "Vector3" or not Validate.isFiniteVector(direction) then
			return
		end
		if math.abs(direction.Magnitude - 1) > 0.01 then
			return
		end
		local prop = check(player, target, Config.GRAVGUN_PUNT_RANGE)
		if not prop then
			return
		end
		local held = Hold.get(player)
		if held and held ~= prop then
			return
		end
		Hold.release(player)
		kick(prop, direction * Config.GRAVGUN_PUNT_SPEED)
		Sfx.play("gravgun_punt", prop)
	end)
end

return GravityGunService
