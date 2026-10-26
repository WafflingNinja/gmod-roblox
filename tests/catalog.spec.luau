--!nocheck
-- Run: lune run tests/catalog.spec.luau
local PropCatalog = require("../src/ReplicatedStorage/Shared/PropCatalog")

local SHAPES = { Block = true, Ball = true, Cylinder = true, Wedge = true }
local seen = {}

for _, def in PropCatalog.list do
	assert(not seen[def.id], "duplicate id: " .. def.id)
	seen[def.id] = true
	assert(PropCatalog.byId[def.id] == def, "byId mismatch: " .. def.id)
	assert(SHAPES[def.shape], "bad shape: " .. def.id)
	assert(#def.size == 3, "size needs 3 numbers: " .. def.id)
	for _, v in def.size do
		assert(v > 0, "size must be positive: " .. def.id)
	end
	assert(#def.color == 3, "color needs 3 numbers: " .. def.id)
	for _, v in def.color do
		assert(v >= 0 and v <= 255, "color out of range: " .. def.id)
	end
	if def.shape == "Ball" then
		assert(def.size[1] == def.size[2] and def.size[2] == def.size[3], "ball must be uniform: " .. def.id)
	end
	assert(PropCatalog.halfHeight(def) > 0, "halfHeight: " .. def.id)
	for i, detail in def.details or {} do
		local where = def.id .. " detail " .. i
		assert(
			detail.shape == "Block" or detail.shape == "Ball" or detail.shape == "Cylinder",
			"detail shape: " .. where
		)
		assert(#detail.size == 3 and #detail.offset == 3 and #detail.color == 3, "detail needs 3 numbers: " .. where)
		for _, v in detail.size do
			assert(v > 0, "detail size must be positive: " .. where)
		end
		assert(detail.rot == nil or #detail.rot == 3, "detail rot needs 3 numbers: " .. where)
	end
end

local cars = 0
for _, def in PropCatalog.list do
	if def.className then
		assert(def.className == "VehicleSeat" or def.className == "Seat", "className: " .. def.id)
		assert(def.shape == "Block", "seats must be blocks: " .. def.id)
	end
	local vehicle = def.vehicle
	if vehicle then
		cars += 1
		assert(def.category == "Cars", "cars go in the Cars tab: " .. def.id)
		local wheel = PropCatalog.byId[vehicle.wheel]
		assert(wheel and wheel.shape == "Cylinder" and not wheel.upright, "wheel must be a lying cylinder: " .. def.id)
		assert(#vehicle.seat == 3, "seat needs 3 numbers: " .. def.id)
		for axis = 1, 3, 2 do
			assert(math.abs(vehicle.seat[axis]) < def.size[axis] / 2, "seat outside chassis: " .. def.id)
		end
		assert(#vehicle.wheels >= 3, "car needs 3+ wheels: " .. def.id)
		local y = vehicle.wheels[1].position[2]
		for i, mount in vehicle.wheels do
			local where = def.id .. " wheel " .. i
			local p = mount.position
			assert(#p == 3, "wheel position needs 3 numbers: " .. where)
			assert(math.abs(math.abs(p[1]) - def.size[1] / 2) < 1e-6, "wheel must sit on a side face: " .. where)
			assert(math.abs(p[3]) <= def.size[3] / 2, "wheel past chassis end: " .. where)
			assert(p[2] == y, "wheels share one height (halfHeight uses the first): " .. where)
		end
		assert(PropCatalog.halfHeight(def) > def.size[2] / 2, "car rests on its wheels: " .. def.id)
	end
end
assert(cars == 3, "three premade cars")
assert(PropCatalog.byId.vehicle_seat.className == "VehicleSeat", "driver seat")
assert(PropCatalog.halfHeight(PropCatalog.byId.car_sedan) == 1.7, "sedan: wheel radius 1.5 + mount 0.2 below centre")

assert(PropCatalog.halfHeight(PropCatalog.byId.barrel) == 1.75, "upright barrel uses length")
assert(PropCatalog.halfHeight(PropCatalog.byId.wheel_big) == 2.5, "wheel uses diameter")
assert(PropCatalog.halfHeight(PropCatalog.byId.crate_small) == 1, "block uses y")

print(`catalog ok ({#PropCatalog.list} props)`)
