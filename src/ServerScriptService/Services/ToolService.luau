--!strict
-- Builds the Physgun, Gravity Gun and Toolgun Tools from parts (original design) and hands them to every player.
-- Each Tool carries its weapon-selector slot as attributes; the client selector reads them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local WeaponCatalog = require(ReplicatedStorage.Shared.WeaponCatalog)

local FORWARD = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> along the gun (-Z)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y
local GRIP_TILT = CFrame.Angles(math.rad(-12), 0, 0)

type PartSpec = {
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
}

local function spec(
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): PartSpec
	return {
		shape = shape,
		size = size,
		offset = offset,
		color = color,
		material = material,
		transparency = transparency,
	}
end

local function block(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): PartSpec
	return spec(Enum.PartType.Block, size, offset, color, material)
end

-- Cylinder along the barrel. `length` runs along -Z, `diameter` across.
local function tube(length: number, diameter: number, z: number, y: number, color: Color3, material: Enum.Material)
	return spec(
		Enum.PartType.Cylinder,
		Vector3.new(length, diameter, diameter),
		CFrame.new(0, y, z) * FORWARD,
		color,
		material
	)
end

local function addPart(handle: BasePart, tool: Tool, s: PartSpec)
	local part = Instance.new("Part")
	part.Shape = s.shape
	part.Size = s.size
	part.Color = s.color
	part.Material = s.material
	part.Transparency = s.transparency or 0
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CFrame = handle.CFrame * s.offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
	part.Parent = tool
end

local function buildTool(
	name: string,
	tip: string,
	handleSize: Vector3,
	handleColor: Color3,
	parts: { PartSpec },
	muzzle: Vector3
): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = tip
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = handleSize
	handle.Color = handleColor
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	for _, s in parts do
		addPart(handle, tool, s)
	end

	local muzzleAttachment = Instance.new("Attachment")
	muzzleAttachment.Name = "Muzzle"
	muzzleAttachment.Position = muzzle
	muzzleAttachment.Parent = handle
	local leftGrip = Instance.new("Attachment")
	leftGrip.Name = "LeftGrip"
	leftGrip.Position = Vector3.new(0, -0.3, -1.2)
	leftGrip.Parent = handle
	return tool
end

local STEEL = Color3.fromRGB(70, 76, 82)
local LIGHT_STEEL = Color3.fromRGB(120, 128, 134)
local DARK = Color3.fromRGB(28, 30, 33)
local CYAN = Color3.fromRGB(70, 225, 255)
local AMBER = Color3.fromRGB(255, 176, 40)
local GREEN = Color3.fromRGB(90, 255, 140)
local RED = Color3.fromRGB(255, 70, 60)
local ORANGE = Color3.fromRGB(255, 150, 30)
local ORANGE_GLOW = Color3.fromRGB(255, 200, 110)

local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local PLASTIC = Enum.Material.SmoothPlastic

local function claws(
	parts: { PartSpec },
	count: number,
	y: number,
	z: number,
	radius: number,
	length: number,
	thickness: Vector2,
	tilt: number,
	spin: number,
	color: Color3
)
	for i = 0, count - 1 do
		local angle = spin + i * 2 * math.pi / count
		local offset = CFrame.new(0, y, z)
			* CFrame.Angles(0, 0, angle)
			* CFrame.new(0, radius, 0)
			* CFrame.Angles(math.rad(tilt), 0, 0)
			* CFrame.new(0, 0, -length / 2)
		table.insert(parts, block(Vector3.new(thickness.X, thickness.Y, length), offset, color, Enum.Material.Metal))
	end
end

-- Part-built Physgun and Gravity Gun (original design). Used when the mesh models are not in ServerStorage.
local function buildPhysgun(): Tool
	local parts: { PartSpec } = {
		block(Vector3.new(0.7, 0.22, 2), CFrame.new(0, 0.45, -0.1), STEEL, METAL), -- top shroud
		tube(0.7, 0.9, 1.05, 0.1, STEEL, METAL), -- rear housing
		tube(0.08, 0.95, 1.42, 0.1, CYAN, NEON),
		tube(0.08, 0.95, -0.72, 0.1, LIGHT_STEEL, METAL), -- core chamber
		spec(
			Enum.PartType.Cylinder,
			Vector3.new(0.9, 0.85, 0.85),
			CFrame.new(0, 0.1, -1.2) * FORWARD,
			CYAN,
			Enum.Material.Glass,
			0.55
		),
		spec(Enum.PartType.Ball, Vector3.one * 0.45, CFrame.new(0, 0.1, -1.2), CYAN, NEON),
		tube(0.08, 0.95, -1.68, 0.1, LIGHT_STEEL, METAL),
		tube(1, 0.35, -2.1, 0.1, DARK, METAL), -- barrel
		tube(0.12, 0.6, -2.6, 0.1, CYAN, NEON),
		block(Vector3.new(0.06, 0.1, 1.2), CFrame.new(0.3, 0.22, 0.2), CYAN, NEON),
		block(Vector3.new(0.06, 0.1, 1.2), CFrame.new(-0.3, 0.22, 0.2), CYAN, NEON),
		block(Vector3.new(0.06, 0.5, 0.5), CFrame.new(0.38, 0.1, 0.9), STEEL, METAL), -- rear fins
		block(Vector3.new(0.06, 0.5, 0.5), CFrame.new(-0.38, 0.1, 0.9), STEEL, METAL),
		block(Vector3.new(0.3, 0.9, 0.45), CFrame.new(0, -0.75, 0.35) * GRIP_TILT, DARK, PLASTIC),
		block(Vector3.new(0.12, 0.08, 0.5), CFrame.new(0, -0.55, -0.05), STEEL, METAL), -- trigger guard
	}
	claws(parts, 4, 0.1, -2.45, 0.3, 0.8, Vector2.new(0.1, 0.12), 20, math.rad(45), LIGHT_STEEL)
	return buildTool(
		Config.PHYSGUN,
		"Grab, move, rotate and freeze your props",
		Vector3.new(0.55, 0.7, 1.6),
		DARK,
		parts,
		Vector3.new(0, 0.1, -2.9)
	)
end

local function buildGravityGun(): Tool
	local parts: { PartSpec } = {
		block(Vector3.new(0.9, 0.9, 1.2), CFrame.new(0, 0.1, 0.6), ORANGE, METAL), -- rear body
		block(Vector3.new(0.95, 0.25, 1.25), CFrame.new(0, 0.62, 0.6), DARK, METAL),
		spec(
			Enum.PartType.Cylinder,
			Vector3.new(1.6, 0.22, 0.22),
			CFrame.new(0.5, -0.05, -0.5) * FORWARD,
			LIGHT_STEEL,
			METAL
		), -- pistons
		spec(
			Enum.PartType.Cylinder,
			Vector3.new(1.6, 0.22, 0.22),
			CFrame.new(-0.5, -0.05, -0.5) * FORWARD,
			LIGHT_STEEL,
			METAL
		),
		tube(0.7, 1.3, -1.1, 0.1, ORANGE, METAL), -- front housing
		tube(0.1, 1.35, -1.48, 0.1, DARK, METAL),
		spec(Enum.PartType.Ball, Vector3.one * 0.55, CFrame.new(0, 0.1, -1.55), ORANGE_GLOW, NEON), -- core
		tube(0.6, 0.18, -1.8, 0.1, STEEL, METAL), -- emitter rod
		block(Vector3.new(0.35, 0.95, 0.5), CFrame.new(0, -0.8, 0.45) * GRIP_TILT, DARK, PLASTIC),
		block(Vector3.new(0.25, 0.7, 0.3), CFrame.new(0, -0.65, -0.6), DARK, PLASTIC), -- foregrip
	}
	for _, side in { 1, -1 } do
		for _, y in { 0.35, 0.15, -0.05 } do
			table.insert(parts, block(Vector3.new(0.04, 0.08, 0.6), CFrame.new(side * 0.46, y, 0.6), ORANGE_GLOW, NEON))
		end
	end
	claws(parts, 3, 0.1, -1.5, 0.5, 1.1, Vector2.new(0.16, 0.22), -10, 0, DARK)
	return buildTool(
		Config.GRAVGUN,
		"RMB pull or hold, LMB punt or throw",
		Vector3.new(0.7, 0.8, 1.6),
		DARK,
		parts,
		Vector3.new(0, 0.1, -2.2)
	)
end

local function buildToolgun(): Tool
	local parts: { PartSpec } = {
		block(Vector3.new(0.75, 0.6, 0.7), CFrame.new(0, 0.7, 0.4), DARK, METAL), -- screen housing
		block(Vector3.new(0.6, 0.45, 0.04), CFrame.new(0, 0.72, 0.77), GREEN, NEON), -- screen, faces the player
		block(Vector3.new(0.55, 0.55, 0.9), CFrame.new(0, 0.1, -1.2), DARK, METAL), -- front block
		tube(0.8, 0.3, -1.95, 0.1, STEEL, METAL), -- barrel
		tube(0.07, 0.5, -1.7, 0.1, AMBER, NEON), -- coils
		tube(0.07, 0.5, -1.95, 0.1, AMBER, NEON),
		tube(0.07, 0.5, -2.2, 0.1, AMBER, NEON),
		spec(Enum.PartType.Ball, Vector3.one * 0.25, CFrame.new(0, 0.1, -2.4), GREEN, NEON), -- emitter
		spec(
			Enum.PartType.Cylinder,
			Vector3.new(0.8, 0.05, 0.05),
			CFrame.new(0.25, 1.3, 0.6) * UPRIGHT,
			LIGHT_STEEL,
			METAL
		), -- antenna
		spec(Enum.PartType.Ball, Vector3.one * 0.12, CFrame.new(0.25, 1.72, 0.6), RED, NEON),
		block(Vector3.new(0.05, 0.5, 1.2), CFrame.new(0.37, 0.1, 0), STEEL, METAL), -- side panels
		block(Vector3.new(0.05, 0.5, 1.2), CFrame.new(-0.37, 0.1, 0), STEEL, METAL),
		block(Vector3.new(0.06, 0.1, 0.3), CFrame.new(0.4, 0.3, -0.4), GREEN, NEON),
		block(Vector3.new(0.06, 0.1, 0.3), CFrame.new(-0.4, 0.3, -0.4), GREEN, NEON),
		block(Vector3.new(0.35, 0.95, 0.5), CFrame.new(0, -0.85, 0.5) * GRIP_TILT, DARK, PLASTIC),
	}
	return buildTool(
		Config.TOOLGUN,
		"Weld, rope, thrust, scale, paint",
		Vector3.new(0.7, 0.9, 1.6),
		AMBER,
		parts,
		Vector3.new(0, 0.1, -2.5)
	)
end

-- Where the gun sits in the right hand, per hold (Tool.Grip; translation moves the gun the opposite way).
-- The launcher rides up on the shoulder; rifles sit a little back so the stock meets the chest.
local GRIPS: { [string]: CFrame } = {
	pistol = CFrame.identity,
	rifle = CFrame.new(0, 0, -0.4),
	launcher = CFrame.new(0, -0.9, -0.2),
}
local PISTOL_AHEAD = 0.2 -- share of the pistol's length its centre sits ahead of the hand
local PISTOL_ABOVE = 0.3 -- share of its height the centre sits above the hand
-- Grips placed by hand on posed dummies in Studio (docs/TOOLS.md, "Gun hold poses"), read from the saved place.
-- They win over GRIPS and already include the gun's scale.
local POSED_GRIPS: { [string]: CFrame } = {
	Pistol = CFrame.new(-0.0728, -0.0195, 0.5545),
	SMG = CFrame.new(0, 0.0954, 1.033),
	AR2 = CFrame.new(0.084, -0.1281, 1.3596),
	RPG = CFrame.new(0, -0.2211, 1.642),
}

-- A Tool around a mesh model from ServerStorage. The handle is invisible and sits at the grip; the model is turned so
-- its barrel points down +Z (the way the right hand holds it) and placed forward of the hand, with a Muzzle at its
-- front. Two-handed holds get a LeftGrip attachment at the foregrip (GunPose puts the left hand on it). Scripts inside
-- store models are removed. nil if the model is missing.
local function buildModelTool(
	name: string,
	tip: string,
	modelName: string,
	yaw: number,
	hold: string,
	magazine: number?,
	scale: number?
): Tool?
	local source = ServerStorage:FindFirstChild(modelName)
	if not source then
		warn(`ToolService: model ServerStorage.{modelName} missing, {name} not given`)
		return nil
	end
	local model = Instance.new("Model")
	local copy = source:Clone()
	if scale and scale > 0 and scale ~= 1 then
		copy:ScaleTo(scale)
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	copy.Parent = model
	local box, size = model:GetBoundingBox()
	local length = math.max(size.X, size.Z)
	-- Bounding box centre ends up a third of the gun ahead of the hand, slightly above it. +Z is the tool's
	-- forward, so the stock sits just behind the hand and the barrel runs ahead of it. A pistol's grip hangs under
	-- its rear, so the hand sits lower and further back: at that height it was holding the slide and barrel.
	local ahead = if hold == "pistol" then length * PISTOL_AHEAD else length / 3
	local above = if hold == "pistol" then size.Y * PISTOL_ABOVE else 0.15
	local target = CFrame.new(0, above, ahead) * CFrame.Angles(0, math.rad(yaw), 0)
	model:PivotTo(target * box:ToObjectSpace(model:GetPivot()))

	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = tip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local gripFrame = GRIPS[hold] or GRIPS.rifle
	if scale then
		gripFrame = CFrame.new(gripFrame.Position * scale) * gripFrame.Rotation
	end
	tool.Grip = POSED_GRIPS[name] or gripFrame
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 0.3)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	handle.CFrame = CFrame.identity
	handle.Parent = tool
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		elseif part:IsA("WeldConstraint") and part.Parent and not part.Parent:IsA("BasePart") then
			part:Destroy()
		end
	end
	model.Name = "Model"
	model.Parent = tool
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, above, ahead + length / 2)
	muzzle.Parent = handle
	if hold ~= "pistol" then
		local grip = Instance.new("Attachment")
		grip.Name = "LeftGrip"
		grip.Position = Vector3.new(0, -0.3, length * 0.4)
		grip.Parent = handle
	end
	if magazine then
		tool:SetAttribute(Config.AMMO_ATTRIBUTE, magazine)
	end
	return tool
end

type LoadoutEntry = { build: () -> Tool?, label: string, slot: number, order: number }

-- Weapon-selector layout, Gmod style: grab tools in slot 1, guns in 2-5, the toolgun in slot 6.
local LOADOUT: { LoadoutEntry } = {
	{
		build = function()
			return buildModelTool(
				Config.PHYSGUN,
				"Grab, move, rotate and freeze your props",
				"PhysgunModel",
				0,
				"rifle"
			) or buildPhysgun()
		end,
		label = "Physics Gun",
		slot = 1,
		order = 1,
	},
	{
		build = function()
			return buildModelTool(Config.GRAVGUN, "RMB pull or hold, LMB punt or throw", "GravityGunModel", 0, "rifle")
				or buildGravityGun()
		end,
		label = "Gravity Gun",
		slot = 1,
		order = 2,
	},
	{ build = buildToolgun, label = "Tool Gun", slot = 6, order = 1 },
}
for _, def in WeaponCatalog.list do
	table.insert(LOADOUT, {
		build = function()
			return buildModelTool(def.id, def.label, def.model, def.yaw, def.hold, def.magazine, def.scale)
		end,
		label = def.label,
		slot = def.slot,
		order = def.order,
	})
end

local ToolService = {}

-- A fresh copy of a WeaponCatalog gun (the Armed Citizen carries one). nil if its model is missing.
function ToolService.buildWeapon(id: string): Tool?
	local def = WeaponCatalog.byId[id]
	return if def then buildModelTool(def.id, def.label, def.model, def.yaw, def.hold, def.magazine, def.scale) else nil
end

local function give(player: Player)
	for _, entry in LOADOUT do
		local tool = entry.build()
		if not tool then
			continue
		end
		tool:SetAttribute(Config.SLOT_ATTRIBUTE, entry.slot)
		tool:SetAttribute(Config.SLOT_ORDER_ATTRIBUTE, entry.order)
		tool:SetAttribute(Config.LABEL_ATTRIBUTE, entry.label)
		tool.Parent = player:WaitForChild("StarterGear")
		-- StarterGear only reaches the backpack on the next spawn; cover a character that already exists.
		local backpack = player:FindFirstChildOfClass("Backpack")
		if player.Character and backpack then
			tool:Clone().Parent = backpack
		end
	end
end

function ToolService.init()
	Players.PlayerAdded:Connect(give)
	for _, player in Players:GetPlayers() do
		task.spawn(give, player)
	end
end

return ToolService
