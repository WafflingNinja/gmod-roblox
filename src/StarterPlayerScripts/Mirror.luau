--!strict
-- Mirror panels. MapService builds a thin panel on a real wall face and tags it; this draws a viewport on
-- its room-facing side. The viewport holds a reflected copy of the nearby room and of your character, and its
-- camera sits at your eye framing the panel, so you see a convincing planar reflection. Only one face
-- per panel is drawn, at a capped resolution, and panels stop rendering up the map.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

type Face = {
	gui: SurfaceGui,
	id: Enum.NormalId,
	viewport: ViewportFrame,
	camera: Camera,
	clone: Model?,
	owner: Model?,
	room: Folder,
}
type Entry = { part: BasePart, faces: { Face } }
type Candidate = { part: BasePart, distance: number }

local player = Players.LocalPlayer
local entries: { [BasePart]: Entry } = {}
local MAX_FOV = 120 -- degrees; past this the viewport camera cannot cover the glass from a steep angle
local ROOM_REBUILD_DELAY = 5 -- seconds

local function reflect(v: Vector3, normal: Vector3): Vector3
	return v - 2 * v:Dot(normal) * normal
end

local function reflectedPosition(position: Vector3, origin: Vector3, normal: Vector3): Vector3
	return origin + reflect(position - origin, normal)
end

-- Mirror a CFrame across the plane. A true reflection is left-handed, which a CFrame cannot hold, so the right
-- vector is flipped back. Boxes, wedges and limbs are symmetric along X, so the shape still reads as mirrored.
local function reflectedCFrame(cf: CFrame, origin: Vector3, normal: Vector3): CFrame
	return CFrame.fromMatrix(
		reflectedPosition(cf.Position, origin, normal),
		-reflect(cf.RightVector, normal),
		reflect(cf.UpVector, normal),
		reflect(cf.ZVector, normal)
	)
end

-- Distance from a point to the nearest point of a part's box. Map walls are big mesh brushes whose centres sit far
-- from the mirror even when their surface is right next to it.
local function boxDistance(part: BasePart, point: Vector3): number
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	local clamped = Vector3.new(
		math.clamp(localPoint.X, -half.X, half.X),
		math.clamp(localPoint.Y, -half.Y, half.Y),
		math.clamp(localPoint.Z, -half.Z, half.Z)
	)
	return (localPoint - clamped).Magnitude
end

local function faceNormal(part: BasePart, id: Enum.NormalId): Vector3
	return part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(id))
end

-- Static copy of the room around the panel, reflected behind it. Props and characters are not included.
local function buildRoom(face: Face, origin: Vector3, normal: Vector3)
	local maps = Workspace:FindFirstChild("Maps")
	if not maps then
		return
	end
	local candidates: { Candidate } = {}
	for _, descendant in maps:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Only parts wholly on the room side. The map's walls are huge merged meshes that also run behind the
			-- mirror; reflected, those would land between the eye and the glass and hide the picture.
			local cf, half = descendant.CFrame, descendant.Size / 2
			local reach = math.abs(cf.RightVector:Dot(normal)) * half.X
				+ math.abs(cf.UpVector:Dot(normal)) * half.Y
				+ math.abs(cf.LookVector:Dot(normal)) * half.Z
			local depth = (descendant.Position - origin):Dot(normal) - reach
			if
				descendant.Transparency < 0.98
				and descendant.Size.Magnitude > 0.5
				and depth > 0.2
				and descendant.Name ~= "Mirror"
				and descendant.Name ~= "MirrorFrame"
				and not CollectionService:HasTag(descendant, Config.MIRROR_TAG)
			then
				local distance = boxDistance(descendant, origin)
				if distance <= Config.MIRROR_ROOM_RANGE then
					table.insert(candidates, { part = descendant, distance = distance })
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	for index = 1, math.min(#candidates, Config.MIRROR_ROOM_PARTS) do
		local source = candidates[index].part
		local copy = source:Clone()
		if not copy then
			continue
		end
		for _, child in copy:GetDescendants() do
			if
				child:IsA("LuaSourceContainer")
				or child:IsA("ParticleEmitter")
				or child:IsA("Beam")
				or child:IsA("Trail")
				or child:IsA("Fire")
				or child:IsA("Smoke")
				or child:IsA("Sparkles")
				or child:IsA("Light")
				or child:IsA("Sound")
				or child:IsA("GuiBase2d")
				or child:IsA("JointInstance")
				or child:IsA("Constraint")
				or child:IsA("WeldConstraint")
			then
				child:Destroy()
			end
		end
		if copy:IsA("BasePart") then
			copy.Anchored = true
			copy.CanCollide = false
			copy.CanQuery = false
			copy.CanTouch = false
			copy.CastShadow = false
			copy.CFrame = reflectedCFrame(source.CFrame, origin, normal)
		end
		copy.Parent = face.room
	end
end

-- A copy of the character with no scripts, joints, tools or accessories. Parts are moved by hand every frame.
local function copyOf(character: Model): Model?
	-- Player characters are not Archivable, and Clone() returns nil for them.
	local archivable = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = archivable
	if not copy then
		return nil
	end
	for _, child in copy:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Tool") or child:IsA("LuaSourceContainer") or child:IsA("Humanoid") then
			child:Destroy()
		end
	end
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			-- The first-person camera module hides the real body by setting this every frame. The clone is not
			-- managed by it, so copy the geometry but not the invisibility.
			descendant.LocalTransparencyModifier = 0
		elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end
	return copy
end

-- R15 limbs are direct children, so matching by name moves the reflected body part by part.
local function sync(source: Model, copy: Model, origin: Vector3, normal: Vector3)
	for _, child in copy:GetChildren() do
		if child:IsA("BasePart") then
			local original = source:FindFirstChild(child.Name)
			if original and original:IsA("BasePart") then
				child.CFrame = reflectedCFrame(original.CFrame, origin, normal)
			end
		end
	end
end

local function update(entry: Entry, camera: Camera, character: Model?)
	local part = entry.part
	local origin = part.Position
	for _, face in entry.faces do
		local normal = faceNormal(part, face.id)
		local eye = camera.CFrame.Position
		local toEye = eye - origin
		local distance = toEye:Dot(normal)
		local up = part.CFrame.UpVector
		local right = (-normal):Cross(up)
		local dx = toEye:Dot(right)
		local dy = toEye:Dot(up)
		local halfWidth, halfHeight = part.Size.X / 2, part.Size.Y / 2
		-- Drawn on top of the world (the map's own mirror mesh sits in front of the panel and hid it), so it is only
		-- on while the camera is in the box of room in front of the glass; past that it would show through walls.
		local inRoom = distance > 0.1
			and distance < Config.MIRROR_VIEW_DEPTH
			and math.abs(dx) < halfWidth + Config.MIRROR_VIEW_SIDE
			and math.abs(dy) < halfHeight + Config.MIRROR_VIEW_HEIGHT
		face.gui.Enabled = inRoom
		if not inRoom then
			continue
		end
		-- EgoMoose's portal trick. The room and body copies are reflected behind the glass; the viewport camera sits at
		-- your eye looking straight into the glass, so the panel projects to an upright rectangle with no skew. The
		-- viewport is then stretched and shifted on the surface so its picture lands exactly on the glass. The
		-- SurfaceGui clips whatever falls outside the panel.
		local extent = math.max(math.abs(dx) + halfWidth, math.abs(dy) + halfHeight)
		extent = math.min(extent, distance * math.tan(math.rad(MAX_FOV / 2)))
		face.camera.FieldOfView = math.deg(2 * math.atan(extent / distance))
		face.camera.CFrame = CFrame.fromMatrix(eye, right, up, normal)
		local pixels = Config.MIRROR_PIXELS_PER_STUD
		face.viewport.Position = UDim2.fromOffset((halfWidth + dx) * pixels, (halfHeight - dy) * pixels)
		face.viewport.Size = UDim2.fromOffset(2 * extent * pixels, 2 * extent * pixels)

		if face.owner ~= character then
			if face.clone then
				face.clone:Destroy()
			end
			face.clone = if character then copyOf(character) else nil
			if face.clone then
				face.clone.Parent = face.viewport
			end
			face.owner = character
		end
		if face.clone and character then
			sync(character, face.clone, origin, normal)
		end
	end
end

local function attach(part: BasePart)
	if entries[part] then
		return
	end
	local faceName = part:GetAttribute(Config.MIRROR_FACE_ATTRIBUTE)
	local faceId = Enum.NormalId.Front
	if faceName == "Back" then
		faceId = Enum.NormalId.Back
	elseif faceName == "Left" then
		faceId = Enum.NormalId.Left
	elseif faceName == "Right" then
		faceId = Enum.NormalId.Right
	elseif faceName == "Top" then
		faceId = Enum.NormalId.Top
	elseif faceName == "Bottom" then
		faceId = Enum.NormalId.Bottom
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "MirrorGui"
	gui.Face = faceId
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.Enabled = false -- update() turns it on from inside the room
	gui.MaxDistance = Config.MIRROR_MAX_DISTANCE
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Config.MIRROR_PIXELS_PER_STUD

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Reflection"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundColor3 = Color3.fromRGB(150, 150, 148) -- stands in for the room's walls, which can't be copied
	viewport.Ambient = Color3.fromRGB(150, 155, 165)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)
	viewport.ZIndex = 1
	viewport.Parent = gui

	local tint = Instance.new("Frame")
	tint.Name = "GlassTint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Color3.fromRGB(165, 185, 200)
	tint.BackgroundTransparency = 0.93
	tint.BorderSizePixel = 0
	tint.ZIndex = 2
	tint.Parent = gui

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local room = Instance.new("Folder")
	room.Name = "Room"
	room.Parent = viewport

	local face: Face =
		{ gui = gui, id = faceId, viewport = viewport, camera = camera, clone = nil, owner = nil, room = room }
	-- In PlayerGui with an Adornee, not parented to the part: a ViewportFrame SurfaceGui under a Workspace part
	-- did not draw (the mirror stayed the panel's own color). Parented before the room copy is built, so a
	-- failure there can't leave the mirror without its gui.
	gui.Adornee = part
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local entry: Entry = { part = part, faces = { face } }
	entries[part] = entry

	local origin = part.Position
	local normal = faceNormal(part, faceId)
	local function rebuild()
		room:ClearAllChildren()
		local ok, err = pcall(function()
			buildRoom(face, origin, normal)
		end)
		if not ok then
			warn(`Mirror: room copy failed for {part:GetFullName()}: {err}`)
		end
	end
	rebuild()
	-- The map may still be replicating when the tagged panel arrives; copy the room again once it has.
	task.delay(ROOM_REBUILD_DELAY, function()
		if entries[part] == entry then
			rebuild()
		end
	end)
end

local function detach(part: BasePart)
	local entry = entries[part]
	if not entry then
		return
	end
	for _, face in entry.faces do
		if face.clone then
			face.clone:Destroy()
		end
		face.gui:Destroy()
	end
	entries[part] = nil
end

local Mirror = {}

function Mirror.init()
	local function track(instance: Instance)
		if instance:IsA("BasePart") then
			attach(instance)
			instance.Destroying:Once(function()
				detach(instance)
			end)
		end
	end
	for _, instance in CollectionService:GetTagged(Config.MIRROR_TAG) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.MIRROR_TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Config.MIRROR_TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			detach(instance)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local character = player.Character
		for _, entry in entries do
			if (entry.part.Position - camera.CFrame.Position).Magnitude < Config.MIRROR_MAX_DISTANCE then
				update(entry, camera, character)
			else
				for _, face in entry.faces do
					face.gui.Enabled = false
				end
			end
		end
	end)
end

return Mirror
