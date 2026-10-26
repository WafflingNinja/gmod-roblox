--!strict
-- Map choice. Every map is loaded at once, far apart; picking one moves you to its spawn and the client
-- switches lighting. The chosen map sticks for respawns (Player attribute, read by the client).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local MapCatalog = require(ReplicatedStorage.Shared.MapCatalog)
local RateLimiter = require(script.Parent.RateLimiter)
local Validate = require(script.Parent.Validate)

local SPREAD = 6 -- studs; players picking the same map don't stack

local pickRemote = ReplicatedStorage.Remotes.PickMap :: RemoteEvent
local limiter = RateLimiter.new(Config.MAP_BUCKET_CAPACITY, Config.MAP_REFILL_PER_SECOND)

local function spawnPoint(def: MapCatalog.MapDef): Vector3?
	if not def.model then
		local pad = Workspace:FindFirstChild("SpawnPad")
		return if pad and pad:IsA("BasePart") then pad.Position else nil
	end
	local maps = Workspace:FindFirstChild("Maps")
	local spawn = def.spawn
	if not maps or not maps:FindFirstChild(def.model) or not spawn then
		return nil
	end
	return Vector3.new(spawn[1], spawn[2], spawn[3])
end

-- Invisible ground under a map's visible grass, in tiles (parts max out at 2048 studs).
local function addFloor(def: MapCatalog.MapDef, model: Instance)
	local floor = def.floor
	if not floor then
		return
	end
	local tile = 1800
	for x = floor.min[1], floor.max[1] - 1, tile do
		for z = floor.min[2], floor.max[2] - 1, tile do
			local width = math.min(tile, floor.max[1] - x)
			local depth = math.min(tile, floor.max[2] - z)
			local part = Instance.new("Part")
			part.Name = "CollisionFloor"
			part.Anchored = true
			part.Transparency = 1
			part.CastShadow = false
			part.Material = Enum.Material.Grass
			part.Size = Vector3.new(width, 10, depth)
			part.CFrame = CFrame.new(x + width / 2, floor.y - 5, z + depth / 2)
			part.Parent = model
		end
	end
end

-- Tag the part nearest each mirror point so the client draws a reflection on it.
local function tagMirrors(def: MapCatalog.MapDef, model: Instance)
	local points: { { number } } = def.mirrors or {}
	for _, at in points do
		local target = Vector3.new(at[1], at[2], at[3])
		local best, bestDistance = nil, Config.MIRROR_SEARCH
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and (d.Position - target).Magnitude < bestDistance then
				best, bestDistance = d, (d.Position - target).Magnitude
			end
		end
		if best then
			CollectionService:AddTag(best, Config.MIRROR_TAG)
		else
			warn(`MapService: no part near mirror point {target} on {def.id}`)
		end
	end
end

local function sendTo(player: Player, def: MapCatalog.MapDef)
	local character = player.Character
	local point = spawnPoint(def)
	if not character or not point or not Validate.aliveRoot(player) then
		return
	end
	local spread = Vector3.new((math.random() - 0.5) * SPREAD, 3, (math.random() - 0.5) * SPREAD)
	character:PivotTo(CFrame.new(point + spread))
end

local MapService = {}

function MapService.init()
	-- Maps come from the Creator Store; a script inside one would run with server rights.
	local maps = Workspace:FindFirstChild("Maps")
	if maps then
		for _, descendant in maps:GetDescendants() do
			if descendant:IsA("LuaSourceContainer") then
				warn(`MapService: removed script {descendant:GetFullName()}`)
				descendant:Destroy()
			elseif descendant:IsA("BasePart") and descendant.Material == Enum.Material.ForceField then
				-- ForceField draws almost black in Roblox; the converter painted most walls with it.
				descendant.Material = Enum.Material.SmoothPlastic
			elseif descendant:IsA("SpecialMesh") and descendant.MeshType == Enum.MeshType.FileMesh then
				-- The converted maps draw brushes as a box Part with a mesh inside. The mesh shows the shape, but
				-- collision stays the whole box, and those boxes bury the play area (things fall straight through).
				-- The real collision is in the solid_* clip parts and the Poly triangles.
				local part = descendant.Parent
				if part and part:IsA("BasePart") then
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
				end
			end
		end
		for _, def in MapCatalog.list do
			local model = def.model and maps:FindFirstChild(def.model)
			if model then
				addFloor(def, model)
				tagMirrors(def, model)
			end
		end
	end

	pickRemote.OnServerEvent:Connect(function(player: Player, id: unknown)
		if not limiter:consume(player, 1) then
			return
		end
		if typeof(id) ~= "string" then
			return
		end
		local def = MapCatalog.byId[id]
		if not def or not spawnPoint(def) then
			return
		end
		player:SetAttribute(Config.MAP_ATTRIBUTE, id)
		sendTo(player, def)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		player:SetAttribute(Config.MAP_ATTRIBUTE, MapCatalog.DEFAULT)
		player.CharacterAdded:Connect(function()
			local def = MapCatalog.byId[player:GetAttribute(Config.MAP_ATTRIBUTE) :: string]
			if def and def.model then
				task.defer(sendTo, player, def) -- after the SpawnLocation has placed the character
			end
		end)
	end)
end

return MapService
