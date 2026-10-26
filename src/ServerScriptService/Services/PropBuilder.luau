--!strict
-- Turns catalog data into parts. Shared by spawning, the Wheel tool and premade cars.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PropCatalog = require(ReplicatedStorage.Shared.PropCatalog)

local PART_TYPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- Fail loudly at boot if the catalog names a material that does not exist.
local materials: { [string]: Enum.Material } = {}
for _, def in PropCatalog.list do
	materials[def.material] = (Enum.Material :: any)[def.material]
	if def.details then
		for _, detail in def.details do
			materials[detail.material] = (Enum.Material :: any)[detail.material]
		end
	end
end

-- Decorative parts welded to the prop. They never collide or add mass; their size and offset
-- are stored so the Scale tool can resize them with the prop.
local function addDetails(part: BasePart, def: PropCatalog.PropDef)
	if not def.details then
		return
	end
	for _, detail in def.details do
		local piece = Instance.new("Part")
		piece.Shape = PART_TYPES[detail.shape]
		local size = Vector3.new(detail.size[1], detail.size[2], detail.size[3])
		local rot = detail.rot
		local relative = CFrame.new(detail.offset[1], detail.offset[2], detail.offset[3])
			* (if rot then CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3])) else CFrame.identity)
		piece.Size = size
		piece.Color = Color3.fromRGB(detail.color[1], detail.color[2], detail.color[3])
		piece.Material = materials[detail.material]
		piece.Massless = true
		piece.CanCollide = false
		piece:SetAttribute("DetailSize", size)
		piece:SetAttribute("DetailCFrame", relative)
		piece.CFrame = part.CFrame * relative
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = part
		weld.Part1 = piece
		weld.Parent = piece
		piece.Parent = part
	end
end

local function newPart(def: PropCatalog.PropDef): BasePart
	if def.className == "VehicleSeat" then
		local seat = Instance.new("VehicleSeat")
		CollectionService:AddTag(seat, Config.SEAT_TAG)
		return seat
	elseif def.className == "Seat" then
		return Instance.new("Seat")
	elseif def.shape == "Wedge" then
		return Instance.new("WedgePart")
	end
	local solid = Instance.new("Part")
	solid.Shape = PART_TYPES[def.shape]
	return solid
end

local PropBuilder = {}

-- Resting CFrame for a prop dropped at `position` (on the floor, barrels upright).
function PropBuilder.placement(def: PropCatalog.PropDef, position: Vector3): CFrame
	local lift = Vector3.yAxis * (PropCatalog.halfHeight(def) + 0.05)
	local rotation = if def.shape == "Cylinder" and def.upright then UPRIGHT else CFrame.identity
	return CFrame.new(position + lift) * rotation
end

-- Unparented part with its details. The caller registers and parents it.
function PropBuilder.build(def: PropCatalog.PropDef, cframe: CFrame): BasePart
	local part = newPart(def)
	part.Name = def.id
	part.Size = Vector3.new(def.size[1], def.size[2], def.size[3])
	part:SetAttribute("BaseSize", part.Size) -- the Scale tool multiplies this
	part.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	part.Material = materials[def.material]
	if def.elasticity then
		local base = PhysicalProperties.new(part.Material)
		part.CustomPhysicalProperties =
			PhysicalProperties.new(base.Density, base.Friction, def.elasticity, base.FrictionWeight, 100)
	end
	part.CFrame = cframe
	addDetails(part, def)
	return part
end

return PropBuilder
