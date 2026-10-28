--!nocheck
-- Import a converted Source map (tools/bsp_to_json.py) into Workspace.Maps.
--
-- Run from Studio (MCP / command bar) with the map JSON served over http://127.0.0.1:8765:
--   require(game.ServerStorage.MapImport).run("Mallparking", "gm_mallparking.json")
-- This is an authoring tool, not part of the game: it lives in ServerStorage only.
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MAPS = "Maps"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do
	B64_INDEX[string.sub(B64, i, i)] = i - 1
end

local function decode(s: string): string
	local parts, piece, plen = {}, table.create(512), 0
	local acc, bits = 0, 0
	for i = 1, #s do
		local v = B64_INDEX[string.sub(s, i, i)]
		if v then
			acc = acc * 64 + v
			bits += 6
			while bits >= 8 do
				bits -= 8
				local byte = math.floor(acc / 2 ^ bits) % 256
				acc = acc % 2 ^ bits
				plen += 1
				piece[plen] = string.char(byte)
				if plen == 512 then
					parts[#parts + 1] = table.concat(piece, "", 1, plen)
					plen = 0
				end
			end
		end
	end
	if plen > 0 then
		parts[#parts + 1] = table.concat(piece, "", 1, plen)
	end
	return table.concat(parts)
end

-- EditableMesh content lives in memory only: saved and reopened, those MeshParts come back as plain boxes.
-- So every chunk is uploaded as a Mesh asset and its MeshPart is built from the asset id. Ids are cached in
-- ServerStorage.MapMeshIds (attribute per chunk) so a re-run does not upload the same chunk twice.
local function meshCache(): Folder
	local folder = ServerStorage:FindFirstChild("MapMeshIds")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MapMeshIds"
		folder.Parent = ServerStorage
	end
	return folder
end

local uploads = 0
local function meshAsset(em, chunk, label: string): number
	local cache = meshCache()
	local key = string.format("%s_%d_%d", label, #chunk.pos, #chunk.idx)
	local cached = cache:GetAttribute(key)
	if cached then
		return cached
	end
	local lastError = "?"
	local failures = 0
	-- Roblox answers "too many requests" after a few hundred quick uploads, and sometimes drops one with
	-- "HTTP StatusCode: -1"; both are a wait, not a failure.
	while failures < 6 do
		local ok, result, id = pcall(AssetService.CreateAssetAsync, AssetService, em, Enum.AssetType.Mesh, {
			Name = label,
			Description = "waffles mod map chunk",
		})
		if ok and result == Enum.CreateAssetResult.Success then
			cache:SetAttribute(key, id)
			uploads += 1
			return id
		end
		lastError = tostring(if ok then id else result)
		local lower = string.lower(lastError)
		if string.find(lower, "too many", 1, true) or string.find(lower, "statuscode: -1", 1, true) then
			print(string.format("  %s: Roblox says slow down, waiting 30 s (%s)", label, lastError))
			task.wait(30)
		else
			failures += 1
			warn(string.format("  %s: upload failed (try %d of 6), retrying: %s", label, failures, lastError))
			task.wait(5 * failures)
		end
	end
	error(string.format("mesh upload failed for %s: %s", label, lastError))
end

-- One MeshPart per chunk, vertices relative to the chunk's own bounds centre so the part's CFrame sits on its
-- geometry (gizmos, GetBoundingBox and Position are wrong if every part shares the map centre).
local function meshPart(chunk, parent, collideOnly, label: string)
	local em = AssetService:CreateEditableMesh()
	local raw = decode(chunk.pos)
	local count = #raw // 12
	local points = table.create(count)
	local lo, hi = Vector3.one * math.huge, Vector3.one * -math.huge
	for i = 0, count - 1 do
		local p = Vector3.new(string.unpack("<fff", raw, i * 12 + 1))
		points[i + 1] = p
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local origin = (lo + hi) / 2
	local ids = table.create(count)
	for i, p in ipairs(points) do
		ids[i] = em:AddVertex(p - origin)
	end

	-- One UV per vertex, in Source texture repeats; the texture tiles past 0..1.
	local uvIds = {}
	if chunk.uv then
		local uvRaw = decode(chunk.uv)
		for i = 0, #uvRaw // 8 - 1 do
			local u, v = string.unpack("<ff", uvRaw, i * 8 + 1)
			uvIds[i + 1] = em:AddUV(Vector2.new(u, v))
		end
	end

	local faces = {}
	local idx = decode(chunk.idx)
	local triCount = #idx // 12 -- three 4-byte indices per triangle
	for i = 0, triCount - 1 do
		local a, b, c = string.unpack("<III", idx, i * 12 + 1)
		local face = em:AddTriangle(ids[a + 1], ids[b + 1], ids[c + 1])
		faces[i + 1] = face
		if uvIds[a + 1] then
			em:SetFaceUVs(face, { uvIds[a + 1], uvIds[b + 1], uvIds[c + 1] })
		end
	end

	-- Flat shading: one normal per face from the converter, shared by the triangles that reference it.
	local normalRaw = decode(chunk.nrm)
	local normalIds = {}
	for i = 0, #normalRaw // 12 - 1 do
		local x, y, z = string.unpack("<fff", normalRaw, i * 12 + 1)
		normalIds[i + 1] = em:AddNormal(Vector3.new(x, y, z))
	end
	local ni = decode(chunk.ni)
	for i = 0, #ni // 2 - 1 do
		local n = normalIds[string.unpack("<H", ni, i * 2 + 1) + 1]
		local faceId = faces[i + 1]
		if n and faceId then
			em:SetFaceNormals(faceId, { n, n, n })
		end
	end

	local options = {
		CollisionFidelity = if collideOnly
			then Enum.CollisionFidelity.Box
			else Enum.CollisionFidelity.PreciseConvexDecomposition,
		RenderFidelity = Enum.RenderFidelity.Precise,
	}
	-- A fresh asset can still be "being generated" for a few seconds, so retry before giving up.
	local content = Content.fromAssetId(meshAsset(em, chunk, label))
	em:Destroy()
	local part
	for _ = 1, 20 do
		local ok, result = pcall(AssetService.CreateMeshPartAsync, AssetService, content, options)
		if ok then
			part = result
			break
		end
		task.wait(3)
	end
	if not part then
		error("mesh asset never became usable for " .. label)
	end
	part.CFrame = CFrame.new(origin)
	part.Anchored = true
	part.CanTouch = false
	part.Parent = parent
	return part
end

-- texture_ids.json: png name -> "rbxassetid://<image id>" for uploaded textures; absent or empty means flat
-- colours only. alpha_fix.json (tools/alpha_audit.py): image id -> png for opaque materials whose alpha is a
-- Source shine mask.
local function served(file: string)
	local ok, body = pcall(HttpService.GetAsync, HttpService, "http://127.0.0.1:8765/" .. file)
	return if ok then HttpService:JSONDecode(body) else {}
end

-- TextureID draws alpha as see-through, which turns shine masks into holes; Overlay mode ignores it.
local function applyTexture(part: MeshPart, image: string, shineMasks)
	part.TextureID = image
	if shineMasks[image] then
		local appearance = Instance.new("SurfaceAppearance")
		appearance.ColorMap = image
		appearance.AlphaMode = Enum.AlphaMode.Overlay
		appearance.Parent = part
	end
end

-- A mesh upload takes ~2.5 s, so chunks are built PARALLEL at a time. The first failure is re-raised by wait().
-- A command-bar run cannot be cancelled, so `workspace:SetAttribute("StopMapImport", true)` stops new pieces.
local PARALLEL = 12
local function pool()
	local running, failure = 0, nil
	local jobs = {}
	function jobs.spawn(fn: () -> ())
		while running >= PARALLEL do
			task.wait()
		end
		if Workspace:GetAttribute("StopMapImport") then
			error("stopped by StopMapImport")
		end
		running += 1
		task.spawn(function()
			local ok, err = pcall(fn)
			if not ok and not failure then
				failure = err
			end
			running -= 1
		end)
	end
	function jobs.wait()
		while running > 0 do
			task.wait()
		end
		if failure then
			error(failure)
		end
	end
	return jobs
end

local MapImport = {}

-- Look pass, safe to re-run on a live map: water pieces become see-through glass you can wade through, and only
-- the SHADOW_LIGHTS strongest lights cast shadows (a shadowed PointLight costs a lot, 400 of them are unplayable).
local SHADOW_LIGHTS = 20
function MapImport.polish(model: Instance): string
	local water = 0
	local ranked = {}
	local spawn = model:GetAttribute("Spawn")
	local floorY = if typeof(spawn) == "Vector3" then spawn.Y - 4 else nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local name = string.lower(d.Name)
			if d:IsA("MeshPart") and string.find(name, "water", 1, true) then
				d.Material = Enum.Material.Glass
				d.Transparency = 0.35
				d.Reflectance = 0.1
				d.CanCollide = false
				water += 1
			elseif
				string.find(name, "wallpapertape", 1, true)
				or (floorY and d.CanCollide and math.abs(d.Position.Y - floorY) < 2 and string.find(
					name,
					"ceiling",
					1,
					true
				))
				or (
					floorY
					and d.CanCollide
					and d.Transparency >= 0.99
					and d.Size.Y <= 2
					and math.abs(d.Position.Y - floorY) <= 3
				)
			then
				-- A tape panel fills the hidden doorway, a ceiling plane on the walk floor lids a hole, and a thin
				-- invisible hull sheet on the walk floor does the same. All three must not collide.
				d.CanCollide = false
			end
		elseif d:IsA("PointLight") then
			table.insert(ranked, d)
		end
	end
	table.sort(ranked, function(a, b)
		return a.Brightness * a.Range > b.Brightness * b.Range
	end)
	for i, light in ipairs(ranked) do
		light.Shadows = i <= SHADOW_LIGHTS
	end
	model:SetAttribute("LookPolished", true)
	return string.format(
		"%s: water=%d shadowedLights=%d of %d",
		model.Name,
		water,
		math.min(#ranked, SHADOW_LIGHTS),
		#ranked
	)
end

-- Where to stand for a Source spawn origin. Some maps put it at hull height, some on the floor itself (Mallparking),
-- so the floor can be above or below it: look down from a little above the origin (below any ceiling, retrying
-- higher), accept only a floor-like surface, and never drop under the origin when nothing is found.
function MapImport.spawnFor(model: Instance, origin: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	for _, lift in ipairs({ 4, 10, 24 }) do
		local ceiling = Workspace:Raycast(origin, Vector3.yAxis * lift, params)
		local start = origin + Vector3.yAxis * (if ceiling then math.max(ceiling.Distance - 1, 0) else lift)
		local floor = Workspace:Raycast(start, Vector3.yAxis * -120, params)
		if floor and floor.Normal.Y > 0.5 then
			return floor.Position + Vector3.yAxis * 4
		end
	end
	-- Mall Parking's origin is ~26 studs under the deck: look up for the floor above it.
	local above = Workspace:Raycast(origin, Vector3.yAxis * 120, params)
	if above and above.Normal.Y < -0.5 then
		return above.Position + Vector3.yAxis * 4
	end
	return origin + Vector3.yAxis * 4
end

-- Prop doors (prop_door_rotating): Source's own model is not imported, so a stand-in door is built in the doorway.
-- The prop's origin is the middle of the hinge edge at mid-height, so the door is dropped onto the floor it
-- stands on (a floor ray through the middle of the doorway), swings to whichever side of the wall has more room,
-- and gets raised panels, a handle on both faces and a static frame (Map.DoorFrames, it must not swing with the door).
local DOOR_HEIGHT_UNITS = 112 -- Source door height; the width comes from the map
local DOOR_STYLES = {
	Bangclaw = {
		color = Color3.fromRGB(72, 88, 82),
		trim = Color3.fromRGB(52, 64, 60),
		material = Enum.Material.Metal,
		handle = Color3.fromRGB(200, 200, 205),
	},
	Mallparking = {
		color = Color3.fromRGB(204, 206, 208),
		trim = Color3.fromRGB(150, 153, 158),
		material = Enum.Material.SmoothPlastic,
		handle = Color3.fromRGB(170, 175, 182),
	},
}
local DOOR_DEFAULT = {
	color = Color3.fromRGB(116, 78, 48),
	trim = Color3.fromRGB(84, 54, 32),
	material = Enum.Material.Wood,
	handle = Color3.fromRGB(210, 168, 72),
}

local function doorPart(parent, name, size, cframe, color, material, solid)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = solid
	part.CanQuery = solid
	part.CanTouch = solid
	part.CastShadow = solid
	part.Parent = parent
	return part
end

-- The door's source data as attributes (older imports only have the old Panel, so read the numbers back from it).
local function doorSpec(door)
	local panel = door:FindFirstChild("Panel")
	if not door:GetAttribute("SourceOrigin") and panel and panel:IsA("BasePart") then
		local axis = panel.CFrame.RightVector
		door:SetAttribute("SourceOrigin", door:GetAttribute("Hinge"))
		door:SetAttribute("Yaw", math.deg(math.atan2(-axis.Z, axis.X)))
		door:SetAttribute("Width", panel.Size.X)
		door:SetAttribute("Height", panel.Size.Y)
	end
	local origin, yaw = door:GetAttribute("SourceOrigin"), door:GetAttribute("Yaw")
	local width, height = door:GetAttribute("Width"), door:GetAttribute("Height")
	if
		typeof(origin) ~= "Vector3"
		or typeof(yaw) ~= "number"
		or typeof(width) ~= "number"
		or typeof(height) ~= "number"
	then
		return nil
	end
	return origin, yaw, width, height
end

function MapImport.dressPropDoor(map: Instance, door: Model): boolean
	local origin, yaw, width, height = doorSpec(door)
	if not origin then
		return false
	end
	local a = math.rad(yaw)
	local along = Vector3.new(math.cos(a), 0, -math.sin(a)) -- the door's long axis, hinge to latch
	local normal = Vector3.new(math.sin(a), 0, math.cos(a))
	local ignore = {}
	for _, folder in ipairs({ "Doors", "DoorFrames" }) do
		local found = map:FindFirstChild(folder)
		if found then
			table.insert(ignore, found)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local middle = origin + along * (width / 2)
	local floor = Workspace:Raycast(middle + Vector3.yAxis, Vector3.yAxis * -(height / 2 + 4), params)
	local floorY = if floor and floor.Normal.Y > 0.5 then floor.Position.Y else origin.Y - height / 2
	local hinge = Vector3.new(origin.X, floorY, origin.Z)

	-- A positive Angle swings the leaf to the -normal side; pick the side with more room.
	local centre = Vector3.new(middle.X, floorY + height / 2, middle.Z)
	local function room(direction)
		local hit = Workspace:Raycast(centre, direction * width, params)
		return if hit then hit.Distance else width
	end
	local swing = if room(normal) > room(-normal) + 0.5 then -1 else 1

	for _, child in ipairs(door:GetChildren()) do
		if child:IsA("BasePart") then
			child:Destroy()
		elseif child:IsA("ObjectValue") and child.Value then
			child.Value:Destroy()
		end
	end
	local style = DOOR_STYLES[map.Name] or DOOR_DEFAULT
	local thick = height * 0.036
	local base = CFrame.new(hinge) * CFrame.Angles(0, a, 0) -- local X along the door, Y up from the floor
	local function add(parent, name, size, offset, color, material, solid)
		return doorPart(parent, name, size, base * offset, color, material, solid)
	end

	add(
		door,
		"Panel",
		Vector3.new(width, height, thick),
		CFrame.new(width / 2, height / 2, 0),
		style.color,
		style.material,
		true
	)
	for _, column in ipairs({ 0.27, 0.73 }) do
		for _, row in ipairs({ { 0.28, 0.36 }, { 0.74, 0.3 } }) do
			add(
				door,
				"Inset",
				Vector3.new(width * 0.36, height * row[2], thick + 0.12),
				CFrame.new(width * column, height * row[1], 0),
				style.trim,
				style.material,
				false
			)
		end
	end
	local handleAt = CFrame.new(width - 0.6, height * 0.46, 0)
	add(door, "HandlePlate", Vector3.new(0.3, 1, thick + 0.2), handleAt, style.handle, Enum.Material.Metal, false)
	for _, side in ipairs({ -1, 1 }) do
		local knob = add(
			door,
			"Handle",
			Vector3.new(0.55, 0.55, 0.55),
			handleAt * CFrame.new(0, 0, side * (thick / 2 + 0.45)),
			style.handle,
			Enum.Material.Metal,
			false
		)
		knob.Shape = Enum.PartType.Ball
	end

	local frames = map:FindFirstChild("DoorFrames")
	if not frames then
		frames = Instance.new("Folder")
		frames.Name = "DoorFrames"
		frames.Parent = map
	end
	local frame = Instance.new("Model")
	frame.Name = door.Name .. "_frame"
	local trim, depth = 0.5, thick + 0.6
	add(
		frame,
		"Jamb",
		Vector3.new(trim, height + trim, depth),
		CFrame.new(-trim / 2, (height + trim) / 2, 0),
		style.trim,
		style.material,
		false
	)
	add(
		frame,
		"Jamb",
		Vector3.new(trim, height + trim, depth),
		CFrame.new(width + trim / 2, (height + trim) / 2, 0),
		style.trim,
		style.material,
		false
	)
	add(
		frame,
		"Lintel",
		Vector3.new(width + trim * 2, trim, depth),
		CFrame.new(width / 2, height + trim / 2, 0),
		style.trim,
		style.material,
		false
	)
	frame.Parent = frames
	local ref = door:FindFirstChild("FrameRef")
	if not ref then
		ref = Instance.new("ObjectValue")
		ref.Name = "FrameRef"
		ref.Parent = door
	end
	ref.Value = frame

	door.WorldPivot = CFrame.new(hinge)
	door:SetAttribute("Hinge", hinge)
	door:SetAttribute("Kind", "rotate")
	door:SetAttribute("Angle", 90 * swing)
	return true
end

-- Re-dress every prop door of one imported map (or all of Workspace.Maps) without re-importing it.
function MapImport.fixDoors(map: Instance?): string
	local dressed = 0
	local maps = if map then { map } else Workspace.Maps:GetChildren()
	for _, m in ipairs(maps) do
		local doors = m:FindFirstChild("Doors")
		for i, door in ipairs(if doors then doors:GetChildren() else {}) do
			if door:IsA("Model") and MapImport.dressPropDoor(m, door) then
				dressed += 1
			end
			if i % 10 == 0 then
				task.wait()
			end
		end
	end
	return string.format("dressed %d prop doors", dressed)
end

function MapImport.run(name: string, file: string)
	local data = HttpService:JSONDecode(HttpService:GetAsync("http://127.0.0.1:8765/" .. file))
	local textures = served("texture_ids.json")
	local shineMasks = served("alpha_fix.json")
	local textured = 0
	local maps = Workspace:FindFirstChild(MAPS) or Instance.new("Folder")
	maps.Name = MAPS
	maps.Parent = Workspace
	local old = maps:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = maps

	local started = os.clock()
	local built = 0
	local total, done = #data.chunks, 0
	for _, door in ipairs(data.doors) do
		total += #door.chunks
	end
	print(string.format("[%s] starting: %d pieces to build", name, total))
	local function tick()
		done += 1
		print(
			string.format(
				"[%s] %d/%d pieces (%d%%)  %ds",
				name,
				done,
				total,
				done * 100 // total,
				math.floor(os.clock() - started)
			)
		)
	end
	local jobs = pool()
	for i, chunk in ipairs(data.chunks) do
		jobs.spawn(function()
			local collideOnly = chunk.layer == "collide"
			local part = meshPart(chunk, model, collideOnly, string.format("%s_%d", name, i))
			part.Material = Enum.Material.SmoothPlastic
			if collideOnly then
				part.Name = "Collision"
				part.Transparency = 1
				part.CastShadow = false
			else
				part.Name = chunk.mat
				part.Color = Color3.new(chunk.color[1], chunk.color[2], chunk.color[3])
				local image = chunk.tex and textures[chunk.tex]
				if image then
					applyTexture(part, image, shineMasks)
					textured += 1
				end
			end
			built += 1
			tick()
		end)
	end

	local doorsFolder = Instance.new("Folder")
	doorsFolder.Name = "Doors"
	doorsFolder.Parent = model
	local propDoors = {}
	local scale = data.scale
	for d, door in ipairs(data.doors) do
		local doorModel = Instance.new("Model")
		doorModel.Name = door.name
		if door.kind == "prop" then
			-- The prop's model is not imported; dressPropDoor builds the stand-in once the map's floors exist.
			doorModel.WorldPivot = CFrame.new(door.pivot[1], door.pivot[2], door.pivot[3])
			doorModel:SetAttribute("Kind", "rotate")
			doorModel:SetAttribute("Angle", 90)
			doorModel:SetAttribute("SourceOrigin", Vector3.new(door.pivot[1], door.pivot[2], door.pivot[3]))
			doorModel:SetAttribute("Yaw", door.angle)
			doorModel:SetAttribute("Width", door.width * scale)
			doorModel:SetAttribute("Height", DOOR_HEIGHT_UNITS * scale)
			table.insert(propDoors, doorModel)
		else
			for j, chunk in ipairs(door.chunks) do
				jobs.spawn(function()
					local part = meshPart(chunk, doorModel, false, string.format("%s_d%d_%d", name, d, j))
					part.Name = "DoorPart"
					part.Material = Enum.Material.SmoothPlastic
					part.Color = Color3.new(chunk.color[1], chunk.color[2], chunk.color[3])
					local image = chunk.tex and textures[chunk.tex]
					if image then
						applyTexture(part, image, shineMasks)
					end
					-- Doors open when you walk into them as well as on E, so they need touch.
					part.CanTouch = true
					tick()
				end)
			end
			doorModel.WorldPivot = CFrame.new(door.pivot[1], door.pivot[2], door.pivot[3])
			if door.kind == "slide" then
				doorModel:SetAttribute("Kind", "slide")
				local yaw = math.rad(door.angle)
				local direction = if door.hasAngle then Vector3.new(math.cos(yaw), 0, -math.sin(yaw)) else Vector3.yAxis
				doorModel:SetAttribute("Offset", direction * math.max(door.width * scale * 0.95, 4))
			else
				doorModel:SetAttribute("Kind", "rotate")
				doorModel:SetAttribute("Angle", door.distance)
			end
		end
		doorModel:SetAttribute("Hinge", Vector3.new(door.pivot[1], door.pivot[2], door.pivot[3]))
		doorModel:SetAttribute("Speed", door.speed)
		doorModel.Parent = doorsFolder
		CollectionService:AddTag(doorModel, "MapDoor")
		task.wait()
	end

	jobs.wait()
	for _, door in ipairs(propDoors) do
		MapImport.dressPropDoor(model, door)
	end

	-- Source lights. The BSP's baked lightmaps do not survive the trip, so without these the interiors are black.
	local lightsFolder = Instance.new("Folder")
	lightsFolder.Name = "Lights"
	lightsFolder.Parent = model
	local lights = 0
	for _, light in ipairs(data.lights or {}) do
		local bulb = Instance.new("Part")
		bulb.Name = "Light"
		bulb.Size = Vector3.new(0.4, 0.4, 0.4)
		bulb.CFrame = CFrame.new(light.pos[1], light.pos[2], light.pos[3])
		bulb.Anchored = true
		bulb.CanCollide = false
		bulb.CanQuery = false
		bulb.CanTouch = false
		bulb.Transparency = 1
		bulb.CastShadow = false
		local point = Instance.new("PointLight")
		point.Color = Color3.new(light.color[1], light.color[2], light.color[3])
		point.Brightness = light.brightness
		point.Range = light.range
		point.Shadows = false
		point.Parent = bulb
		bulb.Parent = lightsFolder
		lights += 1
		if lights % 60 == 0 then
			task.wait()
		end
	end

	model:SetAttribute("Spawn", MapImport.spawnFor(model, Vector3.new(data.spawn[1], data.spawn[2], data.spawn[3])))
	model:SetAttribute("SourceTris", data.stats.tris)
	model:SetAttribute("SourceDoors", data.stats.doors)

	MapImport.polish(model)

	return string.format(
		"%s: chunks=%d textured=%d doors=%d uploads=%d time=%.1fs spawn=%s extents=%s",
		name,
		built,
		textured,
		#data.doors,
		uploads,
		os.clock() - started,
		tostring(model:GetAttribute("Spawn")),
		tostring(model:GetExtentsSize())
	)
end

return MapImport
