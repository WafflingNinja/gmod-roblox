--!strict
-- Map choice. Every map is loaded at once, far apart; picking one moves you to its spawn and the client
-- switches lighting. The chosen map sticks for respawns (Player attribute, read by the client).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local BadAssets = require(ReplicatedStorage.Shared.BadAssets)
local Config = require(ReplicatedStorage.Shared.Config)
local MapCatalog = require(ReplicatedStorage.Shared.MapCatalog)
local Passes = require(script.Parent.Passes)
local RateLimiter = require(script.Parent.RateLimiter)
local Validate = require(script.Parent.Validate)

local SPREAD = 6 -- studs; players picking the same map don't stack
local PASS_WAIT = 4 -- seconds a spawn waits for the join-time pass check (VIP pad)
local VIP_PAD_SIZE = Vector3.new(8, 0.6, 8)
local VIP_PAD_DROP = 3.2 -- studs above the pad a VIP is placed
local VIP_PAD_OFFSETS = {
	Vector3.new(9, 0, 0),
	Vector3.new(-9, 0, 0),
	Vector3.new(0, 0, 9),
	Vector3.new(0, 0, -9),
	Vector3.new(9, 0, 9),
	Vector3.new(-9, 0, -9),
}
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
local vipPoints: { [string]: Vector3 } = {}

local function spawnPoint(def: MapCatalog.MapDef): Vector3?
	if not def.model then
		local pad = Workspace:FindFirstChild("SpawnPad")
		return if pad and pad:IsA("BasePart") then pad.Position else nil
	end
	local maps = Workspace:FindFirstChild("Maps")
	local model = maps and maps:FindFirstChild(def.model)
	local spawn = def.spawn
	if not model or not spawn then
		return nil
	end
	-- Imported maps raycast their own floor and record a Spawn attribute; MapCatalog keeps a fallback so the
	-- data stays plain for lune.
	local imported = model:GetAttribute("Spawn")
	local point = if typeof(imported) == "Vector3" then imported else Vector3.new(spawn[1], spawn[2], spawn[3])
	-- Old imports recorded the Source origin +4, which on Mall Parking is 26 studs under the deck. Same search
	-- as MapImport.spawnFor: drop from just under a ceiling, then fall back to the floor above the point.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	for _, lift in { 4, 10, 24 } do
		local ceiling = Workspace:Raycast(point, Vector3.yAxis * lift, params)
		local start = point + Vector3.yAxis * (if ceiling then math.max(ceiling.Distance - 1, 0) else lift)
		local floor = Workspace:Raycast(start, Vector3.yAxis * -120, params)
		if floor and floor.Normal.Y > 0.5 then
			return floor.Position + Vector3.yAxis * 4
		end
	end
	local above = Workspace:Raycast(point, Vector3.yAxis * 120, params)
	if above and above.Normal.Y < -0.5 then
		return above.Position + Vector3.yAxis * 4
	end
	return point
end

-- Split Worlds: a place in the universe can host exactly one map. MapCatalog.placeId is the link back.
local function hostedMap(): MapCatalog.MapDef?
	return MapCatalog.byPlaceId[game.PlaceId]
end

local function hostedMapId(): string?
	local def = hostedMap()
	return if def then def.id else nil
end

local function hasModel(def: MapCatalog.MapDef): boolean
	if not def.model then
		return true
	end
	local maps = Workspace:FindFirstChild("Maps")
	return maps ~= nil and maps:FindFirstChild(def.model) ~= nil
end

local sendTo: (Player, MapCatalog.MapDef) -> ()

-- Send a player to another map. With a place id this is a real teleport (props do not follow); while the
-- places are still being created (or in Studio) the in-place copy is used when this place has it.
local function changeMap(player: Player, def: MapCatalog.MapDef)
	if def.placeId and def.placeId ~= game.PlaceId then
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(def.placeId :: number, { player })
		end)
		if ok then
			return
		end
		warn(`MapService: teleport to {def.id} ({def.placeId}) failed: {err}`)
		if not hasModel(def) then
			return
		end
	end
	if not spawnPoint(def) then
		return
	end
	player:SetAttribute(Config.MAP_ATTRIBUTE, def.id)
	sendTo(player, def)
end

-- A golden pad beside the map's normal spawn. VIPs land on it when they respawn; everyone else keeps the
-- normal spawn. The pad is anchored map decoration, created once per server.
local function buildVipPad(def: MapCatalog.MapDef)
	local point = spawnPoint(def)
	if not point then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	local props = Workspace:FindFirstChild("Props")
	if props then
		table.insert(ignore, props)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	local function clearAbove(position: Vector3): boolean
		local parts = Workspace:GetPartBoundsInBox(
			CFrame.new(position + Vector3.yAxis * 3),
			Vector3.new(VIP_PAD_SIZE.X - 1, 4, VIP_PAD_SIZE.Z - 1),
			overlap
		)
		for _, part in parts do
			if part.CanCollide then
				return false
			end
		end
		return true
	end
	local function groundAt(position: Vector3): Vector3?
		local hit = Workspace:Raycast(position + Vector3.yAxis, Vector3.yAxis * -200, params)
		return if hit and hit.Normal.Y > 0.5 then hit.Position else nil -- a wall's side is not ground
	end
	local base = groundAt(point)
	local ground = base or point
	if base then
		for _, offset in VIP_PAD_OFFSETS do
			local candidate = groundAt(point + offset)
			if candidate and math.abs(candidate.Y - base.Y) <= 2 and clearAbove(candidate) then
				ground = candidate
				break
			end
		end
	end
	local pad = Instance.new("Part")
	pad.Name = "VipSpawnPad"
	pad.Size = VIP_PAD_SIZE
	pad.CFrame = CFrame.new(ground + Vector3.yAxis * (VIP_PAD_SIZE.Y / 2 + 0.02))
	pad.Anchored = true
	pad.CanCollide = true
	pad.CastShadow = false
	pad.Material = Enum.Material.Neon
	pad.Color = Color3.fromRGB(255, 203, 64)
	pad.Parent = if def.model and Workspace:FindFirstChild("Maps") then Workspace.Maps else Workspace
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VipSign"
	billboard.Adornee = pad
	billboard.Size = UDim2.fromOffset(120, 28)
	billboard.StudsOffset = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = false
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "VIP SPAWN"
	text.Font = Enum.Font.ArimoBold
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 236, 170)
	text.TextStrokeTransparency = 0.35
	text.Parent = billboard
	billboard.Parent = pad
	vipPoints[def.id] = pad.Position + Vector3.yAxis * VIP_PAD_DROP
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

-- Terrain water for a map whose water brushes did not import (they were a brush entity, not world geometry).
-- Roblox swims you in terrain water and gives unanchored props buoyancy, so no custom swim code is needed.
local function fillWater(def: MapCatalog.MapDef)
	local water = def.water
	if not water or not Workspace.Terrain then
		return
	end
	local width = water.max[1] - water.min[1]
	local depth = water.max[2] - water.min[2]
	if width <= 0 or depth <= 0 then
		return
	end
	Workspace.Terrain:FillBlock(
		CFrame.new((water.min[1] + water.max[1]) / 2, water.y - water.depth / 2, (water.min[2] + water.max[2]) / 2),
		Vector3.new(width, water.depth, depth),
		Enum.Material.Water
	)
	Workspace.Terrain.WaterColor = Color3.fromRGB(57, 108, 128)
	Workspace.Terrain.WaterTransparency = 0.3
	Workspace.Terrain.WaterWaveSize = 0.08
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
	-- The client's reflection covers this face. If it ever fails to draw, shiny light glass beats a black slab.
	mirror.Material = Enum.Material.Glass
	mirror.Color = Color3.fromRGB(170, 182, 192)
	mirror.Reflectance = 0.6
	mirror:SetAttribute(Config.MIRROR_FACE_ATTRIBUTE, "Front")
	mirror.Parent = folder
	CollectionService:AddTag(mirror, Config.MIRROR_TAG)

	local frame = Instance.new("Part")
	frame.Name = "MirrorFrame"
	frame.Size = Vector3.new(
		Config.MIRROR_WIDTH + Config.MIRROR_FRAME * 2,
		Config.MIRROR_HEIGHT + Config.MIRROR_FRAME * 2,
		Config.MIRROR_OFFSET
	)
	-- Behind the glass, back to the wall (+Z is toward the wall). In front, the bigger black frame covered the
	-- whole reflection.
	frame.CFrame = cf * CFrame.new(0, 0, Config.MIRROR_OFFSET / 2)
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

-- Look pass, mirrors tools/MapImport.luau's polish so a place saved before the import fix still gets it:
-- water pieces become see-through glass you can wade through, and only the strongest lights cast shadows
-- (a shadowed PointLight is expensive, so each map keeps the same 20-light budget). New imports set
-- LookPolished, so a freshly imported map is not scanned again for nothing.
local SOLID_WATER_WORDS = { "heater", "tower", "pipe", "tank", "melon", "bottle", "cooler", "pump", "tap" }

-- "water" must start a word (water_01, Pool_Water) and not be a solid prop (water_heater, watertower).
local function isWaterMesh(name: string): boolean
	local lower = string.lower(name)
	if not (string.find(lower, "^water") or string.find(lower, "[^%a]water")) then
		return false
	end
	for _, word in SOLID_WATER_WORDS do
		if string.find(lower, word, 1, true) then
			return false
		end
	end
	return true
end

local function polishLook(model: Instance, floorY: number?)
	if model:GetAttribute("LookPolished") == true then
		return
	end
	local ranked: { PointLight } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local part: BasePart = descendant
			local name = string.lower(part.Name)
			if part:IsA("MeshPart") and isWaterMesh(part.Name) then
				local mesh = part :: MeshPart
				mesh.Material = Enum.Material.Glass
				mesh.Transparency = 0.35
				mesh.Reflectance = 0.1
				mesh.CanCollide = false
			else
				local hullLid = floorY
					and part.CanCollide
					and part.Transparency >= 0.99
					and part.Size.Y <= 2
					and math.abs(part.Position.Y - floorY) <= 3
				local blind = string.find(name, "wallpapertape", 1, true) ~= nil
					or hullLid
					or (
						floorY
						and part.CanCollide
						and math.abs(part.Position.Y - floorY) < 2
						and string.find(name, "ceiling", 1, true) ~= nil
					)
				if blind then
					-- Backrooms Movie: a tape panel fills the hidden doorway, the only thing in the gap.
					-- Backrooms: a ceiling plane on the walk floor is the invisible lid over a floor hole (its
					-- front face points down), so from above it reads as an open drop.
					-- Older conversions: a thin invisible hull sheet on the walk floor caps a hole the same way.
					(part :: BasePart).CanCollide = false
				end
			end
		elseif descendant:IsA("PointLight") then
			descendant.Brightness = math.min(descendant.Brightness, Config.MAX_LIGHT_BRIGHTNESS)
			table.insert(ranked, descendant)
		end
	end
	table.sort(ranked, function(a: PointLight, b: PointLight)
		return a.Brightness * a.Range > b.Brightness * b.Range
	end)
	for index, light in ranked do
		light.Shadows = index <= Config.SHADOW_LIGHTS
	end
	model:SetAttribute("LookPolished", true)
end

local function makeMirrors(def: MapCatalog.MapDef, model: Instance)
	local points: { { number } } = def.mirrors or {}
	for _, at in points do
		local target = Vector3.new(at[1], at[2], at[3])
		local pick = nearestFace(model, target)
		if pick then
			buildMirror(model, pick)
			print(`MapService: mirror on {def.id} at {pick.point}, facing {pick.normal}`)
			local other = oppositeFace(pick)
			if other then
				buildMirror(model, other)
			end
		else
			warn(`MapService: no wall face near mirror point {target} on {def.id}`)
		end
	end
end

sendTo = function(player: Player, def: MapCatalog.MapDef)
	local character = player.Character
	local vipPoint = if Passes.has(player, "vip") then vipPoints[def.id] else nil
	local point = vipPoint or spawnPoint(def)
	if not character or not point or not Validate.aliveRoot(player) then
		return
	end
	local spread = Vector3.new((math.random() - 0.5) * SPREAD, 3, (math.random() - 0.5) * SPREAD)
	character:PivotTo(CFrame.new(point + spread))
end

local MapService = {}

function MapService.init()
	local hosted = hostedMapId()
	ReplicatedStorage:SetAttribute(Config.SERVER_MAP_ATTRIBUTE, hosted or MapCatalog.DEFAULT)
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
				fillWater(def)
				local stand = spawnPoint(def)
				polishLook(model, if stand then stand.Y - 4 else nil)
				makeMirrors(def, model)
			end
		end
	end

	for _, def in MapCatalog.list do
		if def.model then
			buildVipPad(def)
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
		if not def then
			return
		end
		changeMap(player, def)
	end)

	local function onPlayerAdded(player: Player)
		local placeMap = hostedMapId()
		player:SetAttribute(Config.SERVER_MAP_ATTRIBUTE, placeMap or "")
		player:SetAttribute(Config.MAP_ATTRIBUTE, placeMap or MapCatalog.DEFAULT)
		player.CharacterAdded:Connect(function()
			local def = MapCatalog.byId[player:GetAttribute(Config.MAP_ATTRIBUTE) :: string]
			if def and def.model then
				task.defer(function()
					-- The VIP pad needs the join-time pass check; don't wait forever if the web call hangs.
					local waited = 0
					while not player:GetAttribute(Config.PASSES_CHECKED_ATTRIBUTE) and waited < PASS_WAIT do
						waited += task.wait()
					end
					if player.Parent then
						sendTo(player, def) -- after the SpawnLocation has placed the character
					end
				end)
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
