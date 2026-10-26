--!strict
-- Mirrors: a part tagged Mirror (MapService tags them from MapCatalog) gets a ViewportFrame on each face. The
-- viewport holds a copy of your character, and its camera sits where your camera's reflection would be, so you see
-- yourself in the glass. A viewport only draws what is inside it, so the room itself is not reflected.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local RANGE = 60 -- studs; farther mirrors are not drawn
local FACES = { Enum.NormalId.Front, Enum.NormalId.Back }

type Face = {
	gui: SurfaceGui,
	id: Enum.NormalId,
	viewport: ViewportFrame,
	camera: Camera,
	clone: Model?,
	owner: Model?, -- the character the clone was copied from
}
type Entry = { part: BasePart, faces: { Face } }

local player = Players.LocalPlayer
local entries: { [BasePart]: Entry } = {}

local function reflect(v: Vector3, normal: Vector3): Vector3
	return v - 2 * v:Dot(normal) * normal
end

-- A copy of the character with no scripts, joints or tools. Its parts are moved by hand every frame (sync).
local function copyOf(character: Model): Model?
	local copy = character:Clone()
	if not copy then
		return nil
	end
	for _, child in copy:GetChildren() do
		if child:IsA("Accessory") or child:IsA("Tool") or child:IsA("LuaSourceContainer") or child:IsA("Humanoid") then
			child:Destroy()
		end
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	return copy
end

-- Limbs are direct children of an R15 character, so matching by name is enough. The copy sits where your
-- body would be seen behind the glass, so every part is reflected across the mirror plane.
local function sync(source: Model, copy: Model, origin: Vector3, normal: Vector3)
	for _, child in copy:GetChildren() do
		if child:IsA("BasePart") then
			local original = source:FindFirstChild(child.Name)
			if original and original:IsA("BasePart") then
				local cf = original.CFrame
				local position = origin + reflect(cf.Position - origin, normal)
				child.CFrame = CFrame.fromMatrix(
					position,
					reflect(cf.RightVector, normal),
					reflect(cf.UpVector, normal),
					-reflect(cf.LookVector, normal)
				)
			end
		end
	end
end

local function update(entry: Entry, camera: Camera, character: Model?)
	local part = entry.part
	local origin = part.Position
	local view = camera.CFrame
	for _, face in entry.faces do
		local normal = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face.id))
		local position = origin + reflect(view.Position - origin, normal)
		face.camera.FieldOfView = camera.FieldOfView
		face.camera.CFrame =
			CFrame.lookAt(position, position + reflect(view.LookVector, normal), reflect(view.UpVector, normal))

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
	local faces: { Face } = {}
	for _, id in FACES do
		local gui = Instance.new("SurfaceGui")
		gui.Face = id
		gui.LightInfluence = 0
		local viewport = Instance.new("ViewportFrame")
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BackgroundColor3 = Color3.fromRGB(20, 22, 26)
		viewport.Ambient = Color3.new(0.8, 0.8, 0.8)
		viewport.LightColor = Color3.new(1, 1, 1)
		viewport.Parent = gui
		local camera = Instance.new("Camera")
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		gui.Parent = part
		table.insert(faces, { gui = gui, id = id, viewport = viewport, camera = camera, clone = nil, owner = nil })
	end
	entries[part] = { part = part, faces = faces }
end

local function detach(part: BasePart)
	local entry = entries[part]
	if not entry then
		return
	end
	for _, face in entry.faces do
		face.gui:Destroy()
		if face.clone then
			face.clone:Destroy()
		end
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
			if (entry.part.Position - camera.CFrame.Position).Magnitude < RANGE then
				update(entry, camera, character)
			end
		end
	end)
end

return Mirror
