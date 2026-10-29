--!strict
-- Floats (the Float Jug) push up in terrain water. Roblox buoyancy only scales with a part's volume, so ten jugs
-- could not hold up a few concrete slabs. Each float gets a world-space VectorForce of FloatLift mass units times
-- gravity, scaled by how much of it is under water (three samples, bottom to top), with vertical damping so a raft
-- settles at the surface instead of bouncing. Updated a few times a second; the force holds in between.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local INTERVAL = 0.1 -- seconds between water checks
local DAMPING = 2 -- per second, on vertical speed while in water
local SAMPLE_OFFSETS = { Vector3.new(0, -1, 0), Vector3.new(0, 0, 0), Vector3.new(0, 1, 0) } -- from the centre, along world Y
local VOXEL = 4

local function inWater(position: Vector3): boolean
	local region = Region3.new(position, position):ExpandToGrid(VOXEL)
	local materials, occupancies = Workspace.Terrain:ReadVoxels(region, VOXEL)
	return materials[1][1][1] == Enum.Material.Water and occupancies[1][1][1] > 0
end

local function forceOf(part: BasePart): VectorForce
	local existing = part:FindFirstChild("FloatForce")
	if existing and existing:IsA("VectorForce") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "FloatAttachment"
	attachment.Parent = part
	local force = Instance.new("VectorForce")
	force.Name = "FloatForce"
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Attachment0 = attachment
	force.Force = Vector3.zero
	force.Parent = part
	return force
end

local function update(part: BasePart)
	local lift = part:GetAttribute("FloatLift")
	if typeof(lift) ~= "number" or part.Anchored then
		return
	end
	local submerged = 0
	for _, offset in SAMPLE_OFFSETS do
		if inWater(part.Position + offset) then
			submerged += 1
		end
	end
	local force = forceOf(part)
	if submerged == 0 then
		force.Force = Vector3.zero
		return
	end
	local fraction = submerged / #SAMPLE_OFFSETS
	local rise = part.AssemblyLinearVelocity.Y
	force.Force = Vector3.new(0, lift * (Workspace.Gravity * fraction - rise * DAMPING), 0)
end

local FloatService = {}

function FloatService.init()
	task.spawn(function()
		while true do
			for _, instance in CollectionService:GetTagged(Config.FLOAT_TAG) do
				if instance:IsA("BasePart") and instance:IsDescendantOf(Workspace) then
					update(instance)
				end
			end
			task.wait(INTERVAL)
		end
	end)
end

return FloatService
