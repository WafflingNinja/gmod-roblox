--!strict
-- Curated spawn list. Plain data only (no Roblox datatypes) so lune can test it.
-- size = {x, y, z} studs. Cylinders: x is the length along the axis, y/z the diameter.
-- upright = stand a cylinder on its flat end (barrel). Wheels are not upright (axle along x).
-- material = Enum.Material name, checked at server boot.
-- details = extra parts welded to the prop (no collision) to make it look like more than a primitive.
-- offset is in the prop's own frame, rot is Euler XYZ degrees, and cylinder axes are X like the prop's.
-- className = build the prop as a VehicleSeat or Seat instead of a Part (Block only).
-- vehicle = premade car: the prop is the chassis (front is -Z), the server adds a VehicleSeat and wheels.
--   Wheel positions sit on the chassis side faces (x = +-size[1]/2); the axle points out along x.

export type PropShape = "Block" | "Ball" | "Cylinder" | "Wedge"
export type SeatClass = "VehicleSeat" | "Seat"

export type WheelMount = { position: { number }, steer: boolean? }

export type Vehicle = {
	seat: { number }, -- VehicleSeat centre, chassis frame
	wheel: string, -- prop id of the wheel used
	wheels: { WheelMount },
}
export type DetailShape = "Block" | "Ball" | "Cylinder"

export type Detail = {
	shape: DetailShape,
	size: { number },
	offset: { number },
	rot: { number }?,
	color: { number },
	material: string,
}

export type PropDef = {
	id: string,
	name: string,
	category: string,
	shape: PropShape,
	size: { number },
	color: { number },
	material: string,
	upright: boolean?,
	elasticity: number?,
	density: number?, -- below 1 floats on terrain water
	float: number?, -- extra lift in water, in mass units (FloatService); Roblox buoyancy alone is too weak for rafts
	details: { Detail }?,
	className: SeatClass?,
	vehicle: Vehicle?,
	pass: string?, -- game pass key required to spawn it
	topSpeed: number?, -- studs/s at the wheel rim; default Config.CAR_MAX_SPEED
}

local STEEL = { 110, 116, 122 }
local DARK = { 45, 48, 52 }
local WHITE = { 245, 245, 245 }

local function part(
	shape: DetailShape,
	size: { number },
	offset: { number },
	color: { number },
	material: string,
	rot: { number }?
): Detail
	return { shape = shape, size = size, offset = offset, color = color, material = material, rot = rot }
end

-- Wooden crate: dark frame on top and bottom, posts on the corners.
local function crateDetails(s: number): { Detail }
	local frame = { 112, 76, 42 }
	local half, post = s / 2, s * 0.1
	local details: { Detail } = {}
	for _, y in { half, -half } do
		table.insert(details, part("Block", { s * 1.06, s * 0.08, s * 1.06 }, { 0, y, 0 }, frame, "WoodPlanks"))
	end
	for _, x in { half, -half } do
		for _, z in { half, -half } do
			table.insert(details, part("Block", { post, s * 1.02, post }, { x, 0, z }, frame, "WoodPlanks"))
		end
	end
	return details
end

-- Three coloured discs slightly bigger than the ball: they show as bands around it.
local function ballBands(d: number, colors: { { number } }): { Detail }
	local thickness = d * 0.04
	local rots: { { number }? } = { nil, { 0, 0, 90 }, { 0, 90, 0 } }
	local details: { Detail } = {}
	for i, color in colors do
		table.insert(
			details,
			part("Cylinder", { thickness, d * 1.01, d * 1.01 }, { 0, 0, 0 }, color, "SmoothPlastic", rots[i])
		)
	end
	return details
end

-- Lug nuts around a wheel hub, on the +x face.
local function lugNuts(x: number, radius: number, count: number): { Detail }
	local details: { Detail } = {}
	for i = 1, count do
		local angle = (i - 1) / count * 2 * math.pi
		table.insert(
			details,
			part(
				"Cylinder",
				{ 0.12, 0.28, 0.28 },
				{ x, math.cos(angle) * radius, math.sin(angle) * radius },
				STEEL,
				"Metal"
			)
		)
	end
	return details
end

-- Four wheels at the chassis corners; front pair steers.
local function fourWheels(halfWidth: number, y: number, front: number, rear: number): { WheelMount }
	return {
		{ position = { halfWidth, y, front }, steer = true },
		{ position = { -halfWidth, y, front }, steer = true },
		{ position = { halfWidth, y, rear } },
		{ position = { -halfWidth, y, rear } },
	}
end

local GLASS = { 170, 210, 230 }
local HEADLIGHT = { 255, 244, 214 }
local TAILLIGHT = { 220, 30, 30 }

local function concat(...: { Detail }): { Detail }
	local all: { Detail } = {}
	for _, group in { ... } do
		for _, detail in group do
			table.insert(all, detail)
		end
	end
	return all
end

local list: { PropDef } = {
	{
		id = "crate_small",
		name = "Crate",
		category = "Props",
		shape = "Block",
		size = { 2, 2, 2 },
		color = { 176, 128, 74 },
		material = "WoodPlanks",
		details = crateDetails(2),
	},
	{
		id = "crate_large",
		name = "Big Crate",
		category = "Props",
		shape = "Block",
		size = { 4, 4, 4 },
		color = { 168, 120, 68 },
		material = "WoodPlanks",
		details = crateDetails(4),
	},
	{
		id = "barrel",
		name = "Barrel",
		category = "Props",
		shape = "Cylinder",
		size = { 3.5, 2.4, 2.4 },
		color = { 170, 50, 40 },
		material = "Metal",
		upright = true,
		details = {
			part("Cylinder", { 0.2, 2.55, 2.55 }, { -1.1, 0, 0 }, STEEL, "Metal"),
			part("Cylinder", { 0.2, 2.55, 2.55 }, { 0, 0, 0 }, STEEL, "Metal"),
			part("Cylinder", { 0.2, 2.55, 2.55 }, { 1.1, 0, 0 }, STEEL, "Metal"),
			part("Cylinder", { 0.1, 2.2, 2.2 }, { 1.78, 0, 0 }, DARK, "Metal"),
			part("Cylinder", { 0.14, 0.45, 0.45 }, { 1.84, 0.55, 0 }, STEEL, "Metal"),
		},
	},
	{
		id = "float_jug",
		name = "Float Jug",
		category = "Props",
		shape = "Cylinder",
		size = { 3, 2.2, 2.2 },
		color = { 70, 150, 220 },
		material = "Plastic",
		upright = true,
		density = 0.15,
		float = 60, -- 10 jugs hold up a platform of 4 concrete slabs
		details = {
			part("Cylinder", { 0.15, 2.3, 2.3 }, { -0.9, 0, 0 }, WHITE, "Plastic"),
			part("Cylinder", { 0.15, 2.3, 2.3 }, { 0.9, 0, 0 }, WHITE, "Plastic"),
			part("Cylinder", { 0.5, 0.9, 0.9 }, { 1.7, 0, 0 }, WHITE, "Plastic"),
		},
	},
	{
		id = "gas_can",
		name = "Gas Can",
		category = "Props",
		shape = "Block",
		size = { 1.2, 1.8, 0.8 },
		color = { 200, 40, 40 },
		material = "Plastic",
		details = {
			part("Cylinder", { 0.35, 0.32, 0.32 }, { 0.3, 1.05, 0 }, { 200, 40, 40 }, "Plastic", { 0, 0, 90 }),
			part("Cylinder", { 0.14, 0.4, 0.4 }, { 0.3, 1.27, 0 }, { 245, 205, 50 }, "Plastic", { 0, 0, 90 }),
			part("Block", { 0.5, 0.12, 0.2 }, { -0.25, 0.94, 0 }, DARK, "Plastic"),
			part("Block", { 1.22, 0.3, 0.82 }, { 0, -0.2, 0 }, { 245, 205, 50 }, "Plastic"),
		},
	},
	{
		id = "cinder_block",
		name = "Cinder Block",
		category = "Props",
		shape = "Block",
		size = { 3, 1.5, 1.5 },
		color = { 150, 150, 148 },
		material = "Concrete",
		details = {
			part("Block", { 0.9, 0.04, 0.7 }, { 0.75, 0.76, 0 }, DARK, "Concrete"),
			part("Block", { 0.9, 0.04, 0.7 }, { -0.75, 0.76, 0 }, DARK, "Concrete"),
		},
	},
	{
		id = "beach_ball",
		name = "Beach Ball",
		category = "Props",
		shape = "Ball",
		size = { 3, 3, 3 },
		color = { 240, 200, 60 },
		material = "Plastic",
		elasticity = 0.9,
		details = ballBands(3, { { 220, 50, 50 }, WHITE, { 50, 100, 220 } }),
	},
	{
		id = "plank",
		name = "Plank",
		category = "Building",
		shape = "Block",
		size = { 8, 0.5, 2 },
		color = { 190, 140, 88 },
		material = "WoodPlanks",
		details = {
			part("Cylinder", { 0.06, 0.16, 0.16 }, { 3.5, 0.27, 0.7 }, DARK, "Metal", { 0, 0, 90 }),
			part("Cylinder", { 0.06, 0.16, 0.16 }, { 3.5, 0.27, -0.7 }, DARK, "Metal", { 0, 0, 90 }),
			part("Cylinder", { 0.06, 0.16, 0.16 }, { -3.5, 0.27, 0.7 }, DARK, "Metal", { 0, 0, 90 }),
			part("Cylinder", { 0.06, 0.16, 0.16 }, { -3.5, 0.27, -0.7 }, DARK, "Metal", { 0, 0, 90 }),
		},
	},
	{
		id = "beam",
		name = "Steel Beam",
		category = "Building",
		shape = "Block",
		size = { 12, 1, 1 },
		color = { 120, 125, 130 },
		material = "Metal",
		details = {
			part("Block", { 12, 0.15, 1.5 }, { 0, 0.5, 0 }, { 150, 156, 162 }, "Metal"),
			part("Block", { 12, 0.15, 1.5 }, { 0, -0.5, 0 }, { 150, 156, 162 }, "Metal"),
		},
	},
	{
		id = "slab",
		name = "Concrete Slab",
		category = "Building",
		shape = "Block",
		size = { 10, 1, 10 },
		color = { 150, 150, 150 },
		material = "Concrete",
		details = {
			part("Block", { 9.2, 0.06, 9.2 }, { 0, 0.52, 0 }, { 170, 170, 168 }, "Concrete"),
			part("Cylinder", { 0.08, 0.5, 0.5 }, { 4.4, 0.55, 4.4 }, DARK, "Metal", { 0, 0, 90 }),
			part("Cylinder", { 0.08, 0.5, 0.5 }, { -4.4, 0.55, 4.4 }, DARK, "Metal", { 0, 0, 90 }),
			part("Cylinder", { 0.08, 0.5, 0.5 }, { 4.4, 0.55, -4.4 }, DARK, "Metal", { 0, 0, 90 }),
			part("Cylinder", { 0.08, 0.5, 0.5 }, { -4.4, 0.55, -4.4 }, DARK, "Metal", { 0, 0, 90 }),
		},
	},
	{
		id = "ramp",
		name = "Ramp",
		category = "Building",
		shape = "Wedge",
		size = { 8, 4, 8 },
		color = { 232, 188, 40 },
		material = "Concrete",
	},
	{
		id = "big_ball",
		name = "Big Ball",
		category = "Building",
		shape = "Ball",
		size = { 6, 6, 6 },
		color = { 90, 140, 220 },
		material = "SmoothPlastic",
		elasticity = 0.6,
		details = ballBands(6, { WHITE, { 245, 205, 50 }, WHITE }),
	},
	{
		id = "wheel_small",
		name = "Small Wheel",
		category = "Vehicle Parts",
		shape = "Cylinder",
		size = { 1, 3, 3 },
		color = { 30, 30, 30 },
		material = "Rubber",
		details = {
			part("Cylinder", { 1.06, 1.7, 1.7 }, { 0, 0, 0 }, STEEL, "Metal"),
			part("Cylinder", { 1.12, 0.55, 0.55 }, { 0, 0, 0 }, DARK, "Metal"),
		},
	},
	{
		id = "wheel_big",
		name = "Big Wheel",
		category = "Vehicle Parts",
		shape = "Cylinder",
		size = { 1.5, 5, 5 },
		color = { 30, 30, 30 },
		material = "Rubber",
		details = concat({
			part("Cylinder", { 1.56, 2.9, 2.9 }, { 0, 0, 0 }, STEEL, "Metal"),
			part("Cylinder", { 1.62, 0.9, 0.9 }, { 0, 0, 0 }, DARK, "Metal"),
		}, lugNuts(0.8, 0.85, 5)),
	},
	{
		id = "vehicle_seat",
		name = "Driver Seat",
		category = "Vehicle Parts",
		shape = "Block",
		size = { 2, 1, 2 },
		color = { 60, 60, 64 },
		material = "Fabric",
		className = "VehicleSeat",
		details = {
			part("Block", { 2, 1.6, 0.3 }, { 0, 1.3, 0.85 }, { 60, 60, 64 }, "Fabric"),
			part("Block", { 0.4, 0.06, 0.4 }, { 0, 0.53, -0.7 }, { 255, 176, 40 }, "Neon"),
		},
	},
	{
		id = "car_sedan",
		name = "Sedan",
		category = "Cars",
		shape = "Block",
		size = { 6, 1, 11 },
		color = { 190, 40, 40 },
		material = "SmoothPlastic",
		vehicle = { seat = { -1.3, 1, 0.6 }, wheel = "wheel_small", wheels = fourWheels(3, -0.2, -3.6, 3.6) },
		details = {
			part("Block", { 5.8, 0.9, 3.6 }, { 0, 0.95, -3.6 }, { 190, 40, 40 }, "SmoothPlastic"), -- hood
			part("Block", { 5.8, 0.9, 2.6 }, { 0, 0.95, 4.1 }, { 190, 40, 40 }, "SmoothPlastic"), -- trunk
			part("Block", { 0.3, 1.1, 4.8 }, { 2.85, 1.05, 0.3 }, { 190, 40, 40 }, "SmoothPlastic"), -- doors
			part("Block", { 0.3, 1.1, 4.8 }, { -2.85, 1.05, 0.3 }, { 190, 40, 40 }, "SmoothPlastic"),
			part("Block", { 5.4, 1.5, 0.12 }, { 0, 2.1, -1.55 }, GLASS, "Glass", { -25, 0, 0 }), -- windshield
			part("Block", { 5.4, 0.5, 0.8 }, { 0, 1.65, -1.2 }, DARK, "SmoothPlastic"), -- dashboard
			part("Ball", { 0.7, 0.7, 0.7 }, { 2.1, 0.95, -5.45 }, HEADLIGHT, "Neon"),
			part("Ball", { 0.7, 0.7, 0.7 }, { -2.1, 0.95, -5.45 }, HEADLIGHT, "Neon"),
			part("Block", { 1, 0.4, 0.1 }, { 2.1, 1.05, 5.42 }, TAILLIGHT, "Neon"),
			part("Block", { 1, 0.4, 0.1 }, { -2.1, 1.05, 5.42 }, TAILLIGHT, "Neon"),
			part("Block", { 3, 0.5, 0.1 }, { 0, 0.95, -5.42 }, DARK, "Metal"), -- grille
			part("Block", { 6.2, 0.5, 0.4 }, { 0, 0.2, -5.6 }, DARK, "Metal"), -- bumpers
			part("Block", { 6.2, 0.5, 0.4 }, { 0, 0.2, 5.6 }, DARK, "Metal"),
		},
	},
	{
		id = "car_truck",
		name = "Pickup Truck",
		category = "Cars",
		shape = "Block",
		size = { 7, 1.2, 14 },
		color = { 40, 90, 160 },
		material = "SmoothPlastic",
		vehicle = { seat = { -1.5, 1.1, -2 }, wheel = "wheel_big", wheels = fourWheels(3.5, -0.3, -4.6, 4.6) },
		details = {
			part("Block", { 6.8, 1.6, 3.2 }, { 0, 1.4, -5.3 }, { 40, 90, 160 }, "SmoothPlastic"), -- hood
			part("Block", { 0.3, 3, 0.3 }, { 3.2, 2.1, -3.6 }, { 40, 90, 160 }, "SmoothPlastic"), -- cab pillars
			part("Block", { 0.3, 3, 0.3 }, { -3.2, 2.1, -3.6 }, { 40, 90, 160 }, "SmoothPlastic"),
			part("Block", { 0.3, 3, 0.3 }, { 3.2, 2.1, -0.6 }, { 40, 90, 160 }, "SmoothPlastic"),
			part("Block", { 0.3, 3, 0.3 }, { -3.2, 2.1, -0.6 }, { 40, 90, 160 }, "SmoothPlastic"),
			part("Block", { 6.8, 0.3, 3.6 }, { 0, 3.75, -2.1 }, { 40, 90, 160 }, "SmoothPlastic"), -- roof
			part("Block", { 6.2, 2.3, 0.12 }, { 0, 2.5, -3.65 }, GLASS, "Glass", { -10, 0, 0 }), -- windshield
			part("Block", { 6.8, 2.6, 0.3 }, { 0, 2, -0.45 }, { 40, 90, 160 }, "SmoothPlastic"), -- cab back
			part("Block", { 0.3, 1.5, 7 }, { 3.35, 1.35, 3.2 }, { 40, 90, 160 }, "SmoothPlastic"), -- bed
			part("Block", { 0.3, 1.5, 7 }, { -3.35, 1.35, 3.2 }, { 40, 90, 160 }, "SmoothPlastic"),
			part("Block", { 7, 1.5, 0.3 }, { 0, 1.35, 6.85 }, { 40, 90, 160 }, "SmoothPlastic"),
			part("Ball", { 0.8, 0.8, 0.8 }, { 2.5, 1.5, -6.95 }, HEADLIGHT, "Neon"),
			part("Ball", { 0.8, 0.8, 0.8 }, { -2.5, 1.5, -6.95 }, HEADLIGHT, "Neon"),
			part("Block", { 4, 1, 0.1 }, { 0, 1.4, -6.92 }, DARK, "Metal"), -- grille
			part("Block", { 7.4, 0.6, 0.5 }, { 0, 0.3, -7.1 }, STEEL, "Metal"), -- bumper
		},
	},
	{
		id = "car_buggy",
		name = "Buggy",
		category = "Cars",
		shape = "Block",
		size = { 5, 0.8, 8 },
		color = { 240, 190, 30 },
		material = "SmoothPlastic",
		vehicle = { seat = { 0, 0.9, 0.6 }, wheel = "wheel_big", wheels = fourWheels(2.5, -0.1, -2.8, 2.8) },
		details = {
			part("Block", { 0.25, 3, 0.25 }, { 2.2, 1.9, -0.8 }, DARK, "Metal"), -- roll cage
			part("Block", { 0.25, 3, 0.25 }, { -2.2, 1.9, -0.8 }, DARK, "Metal"),
			part("Block", { 0.25, 3, 0.25 }, { 2.2, 1.9, 2 }, DARK, "Metal"),
			part("Block", { 0.25, 3, 0.25 }, { -2.2, 1.9, 2 }, DARK, "Metal"),
			part("Block", { 0.25, 0.25, 3 }, { 2.2, 3.4, 0.6 }, DARK, "Metal"),
			part("Block", { 0.25, 0.25, 3 }, { -2.2, 3.4, 0.6 }, DARK, "Metal"),
			part("Block", { 4.65, 0.25, 0.25 }, { 0, 3.4, -0.8 }, DARK, "Metal"),
			part("Block", { 4.65, 0.25, 0.25 }, { 0, 3.4, 2 }, DARK, "Metal"),
			part("Block", { 4.6, 0.8, 1.6 }, { 0, 0.7, -3.4 }, { 240, 190, 30 }, "SmoothPlastic", { -15, 0, 0 }), -- nose
			part("Block", { 2.4, 1.2, 1.8 }, { 0, 1, 3 }, STEEL, "Metal"), -- engine
			part("Cylinder", { 1.4, 0.3, 0.3 }, { 0.6, 1.5, 4.1 }, DARK, "Metal", { 0, 90, 0 }), -- exhausts
			part("Cylinder", { 1.4, 0.3, 0.3 }, { -0.6, 1.5, 4.1 }, DARK, "Metal", { 0, 90, 0 }),
			part("Ball", { 0.6, 0.6, 0.6 }, { 1.6, 1.1, -4.05 }, HEADLIGHT, "Neon"),
			part("Ball", { 0.6, 0.6, 0.6 }, { -1.6, 1.1, -4.05 }, HEADLIGHT, "Neon"),
		},
	},
	{
		id = "car_sports",
		name = "Sports Car",
		category = "Cars",
		shape = "Block",
		size = { 6, 0.8, 11 },
		color = { 235, 82, 42 },
		material = "SmoothPlastic",
		pass = "sports_car",
		topSpeed = 75, -- Config.CAR_MAX_SPEED notes 90 spins the wheels out; untested in Studio
		vehicle = { seat = { -0.9, 0.9, 0.4 }, wheel = "wheel_small", wheels = fourWheels(3, -0.15, -3.4, 3.4) },
		details = {
			part("Block", { 5.7, 0.7, 3.4 }, { 0, 0.45, -3.5 }, { 235, 82, 42 }, "SmoothPlastic"), -- low nose
			part("Block", { 5.7, 0.55, 2.2 }, { 0, 0.35, 4.1 }, { 235, 82, 42 }, "SmoothPlastic"), -- rear deck
			part("Block", { 0.25, 0.7, 5.6 }, { 2.9, 0.35, 0.3 }, { 225, 72, 36 }, "SmoothPlastic"), -- skirts
			part("Block", { 0.25, 0.7, 5.6 }, { -2.9, 0.35, 0.3 }, { 225, 72, 36 }, "SmoothPlastic"),
			part("Block", { 5.2, 1.15, 0.12 }, { 0, 1.25, -1.35 }, GLASS, "Glass", { -32, 0, 0 }), -- windshield
			part("Block", { 4.9, 0.9, 0.12 }, { 0, 1.2, 2.3 }, GLASS, "Glass", { 28, 0, 0 }), -- rear glass
			part("Block", { 5.4, 0.25, 0.4 }, { 0, 1.85, 5.35 }, DARK, "Metal"), -- wing
			part("Block", { 0.18, 1.1, 0.4 }, { 2.4, 1.3, 5.35 }, DARK, "Metal"), -- wing mounts
			part("Block", { 0.18, 1.1, 0.4 }, { -2.4, 1.3, 5.35 }, DARK, "Metal"),
			part("Block", { 5.8, 0.35, 0.6 }, { 0, 0.05, -5.55 }, DARK, "Metal"), -- splitter
			part("Block", { 5.8, 0.4, 0.5 }, { 0, 0.15, 5.45 }, DARK, "Metal"), -- diffuser
			part("Ball", { 0.7, 0.7, 0.7 }, { 1.9, 0.7, -5.45 }, HEADLIGHT, "Neon"),
			part("Ball", { 0.7, 0.7, 0.7 }, { -1.9, 0.7, -5.45 }, HEADLIGHT, "Neon"),
			part("Block", { 1.2, 0.3, 0.1 }, { 1.9, 0.75, 5.42 }, TAILLIGHT, "Neon"),
			part("Block", { 1.2, 0.3, 0.1 }, { -1.9, 0.75, 5.42 }, TAILLIGHT, "Neon"),
			part("Cylinder", { 0.8, 0.28, 0.28 }, { 0.9, 0.3, 5.65 }, STEEL, "Metal", { 0, 90, 0 }), -- exhausts
			part("Cylinder", { 0.8, 0.28, 0.28 }, { -0.9, 0.3, 5.65 }, STEEL, "Metal", { 0, 90, 0 }),
		},
	},
}

local byId: { [string]: PropDef } = {}
for _, def in list do
	byId[def.id] = def
end

local PropCatalog = {}

PropCatalog.list = list
PropCatalog.byId = byId

-- Distance from the prop's centre to its lowest point once placed. A car rests on its wheels.
function PropCatalog.halfHeight(def: PropDef): number
	local vehicle = def.vehicle
	if vehicle then
		return byId[vehicle.wheel].size[2] / 2 - vehicle.wheels[1].position[2]
	end
	if def.shape == "Cylinder" and def.upright then
		return def.size[1] / 2
	end
	return def.size[2] / 2
end

return PropCatalog
