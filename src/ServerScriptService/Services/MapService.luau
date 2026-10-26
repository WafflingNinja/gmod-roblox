--!strict
-- Map choice. Every map is loaded at once, far apart; picking one moves you to its spawn and the client
-- switches lighting. The chosen map sticks for respawns (Player attribute, read by the client).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BadAssets = require(ReplicatedStorage.Shared.BadAssets)
local Config = require(ReplicatedStorage.Shared.Config)
local MapCatalog = require(ReplicatedStorage.Shared.MapCatalog)
local RateLimiter = require(script.Parent.RateLimiter)
local Validate = require(script.Parent.Validate)

local SPREAD = 6 -- studs; players picking the same map don't stack
local FACES = {
	Enum.NormalId.Front,
	Enum.NormalId.Back,
	Enum.NormalId.Left,
	Enum.NormalId.Right,
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
}
local MIRROR_FOLDER = "MirrorPanels"

type FacePick = { part: BasePart, id: Enum.NormalId, normal: Vector3, point: Vector3, distance: number }

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

local OPPOSITE: { [Enum.NormalId]: Enum.NormalId } = {
	[Enum.NormalId.Front] = Enum.NormalId.Back,
	[Enum.NormalId.Back] = Enum.NormalId.Front,
	[Enum.NormalId.Left] = Enum.NormalId.Right,
	[Enum.NormalId.Right] = Enum.NormalId.Left,
	[Enum.NormalId.Top] = Enum.NormalId.Bottom,
	[Enum.NormalId.Bottom] = Enum.NormalId.Top,
}

-- The nearest face of any map part to a MapCatalog point. The old code tagged the nearest part by its centre,
-- which picked a huge collision box buried inside the wall, so the mirror was never visible. Faces are compared
-- by the distance from the point to the face plane, and the panel is built at the point projected onto that
-- plane (not at the face centre, which can be many studs away on a 150-stud wall).
local function nearestFace(model: Instance, target: Vector3): FacePick?
	local best: FacePick? = nil
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Mirror" and part.Name ~= "MirrorFrame" then
			local localTarget = part.CFrame:PointToObjectSpace(target)
			for _, id in FACES do
				local localNormal = Vector3.FromNormalId(id)
				local extent = math.abs(localNormal.X) * part.Size.X
					+ math.abs(localNormal.Y) * part.Size.Y
					+ math.abs(localNormal.Z) * part.Size.Z
				local normalCoord = localTarget:Dot(localNormal)
				local distance = math.abs(normalCoord - extent / 2)
				if distance > Config.MIRROR_SEARCH then
					continue
				end
				-- The point must be over the face, not off the side of a small part.
				local tangential = localTarget - localNormal * normalCoord
				if
					math.abs(tangential.X) > part.Size.X / 2 + 1
					or math.abs(tangential.Y) > part.Size.Y / 2 + 1
					or math.abs(tangential.Z) > part.Size.Z / 2 + 1
				then
					continue
				end
				if not best or distance < best.distance then
					local projected = localTarget - localNormal * (normalCoord - extent / 2)
					best = {
						part = part,
						id = id,
						normal = part.CFrame:VectorToWorldSpace(localNormal),
						point = part.CFrame:PointToWorldSpace(projected),
						distance = distance,
					}
				end
			end
		end
	end
	return best
end

-- The face on the other side of the same wall, so a two-sided room gets a mirror whichever side you stand on.
local function oppositeFace(pick: FacePick): FacePick?
	local id = OPPOSITE[pick.id]
	local localNormal = Vector3.FromNormalId(id)
	local part = pick.part
	local extent = math.abs(localNormal.X) * part.Size.X
		+ math.abs(localNormal.Y) * part.Size.Y
		+ math.abs(localNormal.Z) * part.Size.Z
	if extent > Config.MIRROR_SEARCH then
		return nil
	end
	return {
		part = part,
		id = id,
		normal = part.CFrame:VectorToWorldSpace(localNormal),
		point = pick.point - pick.normal * extent,
		distance = extent,
	}
end

local function hasPanel(folder: Instance, pick: FacePick): boolean
	for _, child in folder:GetChildren() do
		if
			child:IsA("BasePart")
			and child.Name == "Mirror"
			and (child.Position - pick.point).Magnitude < Config.MIRROR_OFFSET + 0.25
			and child.CFrame.LookVector:Dot(pick.normal) > 0.9
		then
			return true
		end
	end
	return false
end

-- Build a real glass panel on the wall face instead of putting a SurfaceGui on whatever collision box
-- happened to be nearest. The client puts the reflection on its Front face.
local function buildMirror(model: Instance, pick: FacePick)
	local existing = model:FindFirstChild(MIRROR_FOLDER)
	local folder: Folder
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = MIRROR_FOLDER
		folder.Parent = model
	end
	if hasPanel(folder, pick) then
		return
	end
	local up = if math.abs(pick.normal.Y) > 0.9 then pick.part.CFrame.LookVector else Vector3.yAxis
	local position = pick.point + pick.normal * Config.MIRROR_OFFSET
	local cf = CFrame.lookAt(position, position + pick.normal, up)

	local mirror = Instance.new("Part")
	mirror.Name = "Mirror"
	mirror.Size = Vector3.new(Config.MIRROR_WIDTH, Config.MIRROR_HEIGHT, 0.12)
	mirror.CFrame = cf
	mirror.Anchored = true
	mirror.CanCollide = false
	mirror.CanQuery = false
	mirror.CanTouch = false
	mirror.CastShadow = false
	mirror.Material = Enum.Material.SmoothPlastic
	mirror.Color = Color3.fromRGB(24, 26, 30)
	mirror.Reflectance = 0.05
	mirror:SetAttribute(Config.MIRROR_FACE_ATTRIBUTE, "Front")
	mirror.Parent = folder
	CollectionService:AddTag(mirror, Config.MIRROR_TAG)

	local frame = Instance.new("Part")
	frame.Name = "MirrorFrame"
	frame.Size =
		Vector3.new(Config.MIRROR_WIDTH + Config.MIRROR_FRAME * 2, Config.MIRROR_HEIGHT + Config.MIRROR_FRAME * 2, 0.2)
	-- Behind the glass (+Z is toward the wall). In front, the bigger black frame covered the whole reflection.
	frame.CFrame = cf * CFrame.new(0, 0, 0.1)
	frame.Anchored = true
	frame.CanCollide = false
	frame.CanQuery = false
	frame.CanTouch = false
	frame.CastShadow = false
	frame.Material = Enum.Material.Metal
	frame.Color = Color3.fromRGB(12, 13, 15)
	frame.Parent = folder
end

-- Anything pointing at a refused asset is cleared here too, so the map is clean for every client even
-- before the client sweep runs.
local function cleanBadAssets(maps: Instance)
	for _, descendant in maps:GetDescendants() do
		BadAssets.strip(descendant)
	end
end

local function makeMirrors(def: MapCatalog.MapDef, model: Instance)
	local points: { { number } } = def.mirrors or {}
	for _, at in points do
		local target = Vector3.new(at[1], at[2], at[3])
		local pick = nearestFace(model, target)
		if pick then
			buildMirror(model, pick)
			local other = oppositeFace(pick)
			if other then
				buildMirror(model, other)
			end
		else
			warn(`MapService: no wall face near mirror point {target} on {def.id}`)
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
				-- The Source converter marks invisible collision hulls as ForceField: solid_* clips and ~720 plain
				-- "Part" hulls under Structur. None carry a texture; as plastic they showed as blank white/red
				-- walls over the real textured brushes. Hide them (they still collide). Anything with a visual
				-- child is a real surface and only needs a neutral material.
				local hasVisual = false
				for _, child in descendant:GetChildren() do
					if
						child:IsA("SpecialMesh")
						or child:IsA("Decal")
						or child:IsA("Texture")
						or child:IsA("SurfaceAppearance")
						or child:IsA("SurfaceGui")
					then
						hasVisual = true
						break
					end
				end
				if not hasVisual then
					descendant.Transparency = 1
					descendant.Reflectance = 0
					descendant.CastShadow = false
				else
					descendant.Material = Enum.Material.SmoothPlastic
				end
			elseif descendant:IsA("SpecialMesh") and descendant.MeshType == Enum.MeshType.FileMesh then
				-- The converted maps draw brushes as a box Part with a mesh inside. The mesh shows the shape, but
				-- collision stays the whole box, and those boxes bury the play area (things fall straight through).
				-- The real collision is in the solid_* clip parts and the Poly triangles.
				local part = descendant.Parent
				if part and part:IsA("BasePart") then
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
					-- The converter left 124 metal ladders (the only visible FileMeshes with an empty TextureId) as
					-- Carpet material with no texture. They rendered flat gray. Use the original brushed-metal texture
					-- generated for this project (not an extracted Gmod asset) and let it show at full brightness.
					if descendant.TextureId == "" then
						descendant.TextureId = Config.MAP_LADDER_TEXTURE
						part.Material = Enum.Material.Metal
						part.Color = Color3.fromRGB(255, 255, 255)
						part.Reflectance = 0.02
					end
				end
			end
		end
		cleanBadAssets(maps)
		-- Old servers tagged whatever part was nearest the mirror point, and a saved place can still carry that
		-- tag on a 155-stud collision box. Only panels inside MirrorPanels are real mirrors.
		for _, tagged in CollectionService:GetTagged(Config.MIRROR_TAG) do
			if tagged:IsDescendantOf(maps) and (not tagged.Parent or tagged.Parent.Name ~= MIRROR_FOLDER) then
				CollectionService:RemoveTag(tagged, Config.MIRROR_TAG)
			end
		end
		for _, def in MapCatalog.list do
			local model = def.model and maps:FindFirstChild(def.model)
			if model then
				addFloor(def, model)
				makeMirrors(def, model)
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

	local function onPlayerAdded(player: Player)
		player:SetAttribute(Config.MAP_ATTRIBUTE, MapCatalog.DEFAULT)
		player.CharacterAdded:Connect(function()
			local def = MapCatalog.byId[player:GetAttribute(Config.MAP_ATTRIBUTE) :: string]
			if def and def.model then
				task.defer(sendTo, player, def) -- after the SpawnLocation has placed the character
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	-- Studio can have the local player in Players before this script starts, so PlayerAdded never fires for them.
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return MapService
