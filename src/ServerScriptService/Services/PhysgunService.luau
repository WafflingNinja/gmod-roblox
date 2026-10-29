--!strict
-- Physgun: grab, move, rotate and freeze own props. The hold itself (constraints, aim, release) is in Hold.luau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Hold = require(script.Parent.Hold)
local Ownership = require(script.Parent.Ownership)
local Passes = require(script.Parent.Passes)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)

local remotes = ReplicatedStorage.Remotes
local grabRemote = remotes.PhysgunGrab :: RemoteEvent
local releaseRemote = remotes.PhysgunRelease :: RemoteEvent
local freezeRemote = remotes.PhysgunFreeze :: RemoteEvent

local BEAM_COLOR = Color3.fromRGB(70, 225, 255)

local grabLimiter = RateLimiter.new(Config.GRAB_BUCKET_CAPACITY, Config.GRAB_REFILL_PER_SECOND)

local PhysgunService = {}

function PhysgunService.init()
	grabRemote.OnServerEvent:Connect(function(player: Player, prop: unknown)
		if not grabLimiter:consume(player, 1) then
			return
		end
		if typeof(prop) ~= "Instance" or not prop:IsA("BasePart") or Hold.get(player) then
			return
		end
		if not Ownership.isOwner(player, prop) then
			return
		end
		local tool = Validate.equippedTool(player, Config.PHYSGUN)
		local root = Validate.aliveRoot(player)
		if not tool or not root or (prop.Position - root.Position).Magnitude > Config.GRAB_RANGE then
			return
		end
		Hold.start(player, prop, tool, Passes.beamColor(player) or BEAM_COLOR, Config.HOLD_MAX, "physgun_hold")
		Sfx.play("physgun_grab", prop)
	end)

	-- An optional prop id: the client's prediction went stale (the prop was removed) and it is just letting go.
	releaseRemote.OnServerEvent:Connect(function(player: Player, prop: unknown)
		if grabLimiter:consume(player, 1) then
			Hold.releaseAny(player, if typeof(prop) == "Instance" and prop:IsA("BasePart") then prop else nil)
		end
	end)

	freezeRemote.OnServerEvent:Connect(function(player: Player)
		if not grabLimiter:consume(player, 1) then
			return
		end
		local prop = Hold.get(player)
		if not prop then
			return
		end
		if not Validate.equippedTool(player, Config.PHYSGUN) then
			return
		end
		Hold.release(player)
		prop.AssemblyLinearVelocity = Vector3.zero
		prop.AssemblyAngularVelocity = Vector3.zero
		prop.Anchored = true
		Sfx.play("physgun_freeze", prop)
	end)
end

return PhysgunService
