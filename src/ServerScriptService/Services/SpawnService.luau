--!strict
-- Client sends intent (prop id + aim point). Server derives everything else.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local PropCatalog = require(ReplicatedStorage.Shared.PropCatalog)
local Ownership = require(script.Parent.Ownership)
local PropBuilder = require(script.Parent.PropBuilder)
local RateLimiter = require(script.Parent.RateLimiter)
local Sfx = require(script.Parent.Sfx)
local Validate = require(script.Parent.Validate)
local VehicleService = require(script.Parent.VehicleService)

local remotes = ReplicatedStorage.Remotes
local spawnRemote = remotes.SpawnProp :: RemoteEvent
local removeRemote = remotes.RemoveProp :: RemoteEvent
local clearRemote = remotes.ClearMine :: RemoteEvent
local notifyRemote = remotes.Notify :: RemoteEvent
local propsFolder = Workspace.Props :: Folder

local spawnLimiter = RateLimiter.new(Config.SPAWN_BUCKET_CAPACITY, Config.SPAWN_REFILL_PER_SECOND)
local removeLimiter = RateLimiter.new(Config.REMOVE_BUCKET_CAPACITY, Config.REMOVE_REFILL_PER_SECOND)
local clearLimiter = RateLimiter.new(Config.CLEAR_BUCKET_CAPACITY, Config.CLEAR_REFILL_PER_SECOND)

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

local SpawnService = {}

-- No dropping props on top of someone else.
function SpawnService.nearOtherPlayer(player: Player, position: Vector3): boolean
	for _, other in Players:GetPlayers() do
		local root = if other ~= player then Validate.aliveRoot(other) else nil
		if root and (root.Position - position).Magnitude < Config.SPAWN_PLAYER_CLEARANCE then
			return true
		end
	end
	return false
end

-- The one way a prop enters the world: build, register, parent. The caller checks caps and range.
function SpawnService.spawn(player: Player, def: PropCatalog.PropDef, cframe: CFrame): BasePart
	local part = PropBuilder.build(def, cframe)
	VehicleService.buildCar(def, part)
	Ownership.claim(player, part)
	part.Parent = propsFolder
	return part
end

function SpawnService.init()
	spawnRemote.OnServerEvent:Connect(function(player: Player, propId: unknown, position: unknown)
		if not spawnLimiter:consume(player, 1) then
			return
		end
		if typeof(propId) ~= "string" or typeof(position) ~= "Vector3" then
			return
		end
		local def = PropCatalog.byId[propId]
		if not def or not Validate.isFiniteVector(position) then
			return
		end
		local root = Validate.aliveRoot(player)
		if not root or (position - root.Position).Magnitude > Config.SPAWN_RANGE then
			return
		end
		if not Ownership.canSpawn(player) then
			notify(player, `Prop limit reached ({Config.PROP_CAP}). Remove some first.`)
			return
		end
		if SpawnService.nearOtherPlayer(player, position) then
			notify(player, "Too close to another player.")
			return
		end

		local part = SpawnService.spawn(player, def, PropBuilder.placement(def, position))
		Sfx.play("spawn", part)
	end)

	removeRemote.OnServerEvent:Connect(function(player: Player, target: unknown)
		if not removeLimiter:consume(player, 1) then
			return
		end
		if typeof(target) ~= "Instance" then
			return
		end
		if not Ownership.isOwner(player, target) then
			notify(player, "That prop is not yours.")
			return
		end
		if target:IsA("BasePart") then
			Sfx.playAt("remove", target.Position)
		end
		target:Destroy()
	end)

	clearRemote.OnServerEvent:Connect(function(player: Player)
		if not clearLimiter:consume(player, 1) then
			return
		end
		Ownership.clearAll(player)
	end)
end

return SpawnService
