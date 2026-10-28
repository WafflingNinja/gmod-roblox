--!nocheck
-- Run: lune run tests/maps.spec.luau
local MapCatalog = require("../src/ReplicatedStorage/Shared/MapCatalog")

local seen = {}
for _, def in MapCatalog.list do
	assert(not seen[def.id], "duplicate map: " .. def.id)
	seen[def.id] = true
	assert(MapCatalog.byId[def.id] == def, "byId mismatch: " .. def.id)
	assert(#def.name > 0 and #def.blurb > 0, "map needs name and blurb: " .. def.id)
	assert(#def.orbit.center == 3 and def.orbit.radius > 0, "map needs a menu orbit: " .. def.id)
	assert((def.model == nil) == (def.spawn == nil), "maps with a model need a spawn point: " .. def.id)
	assert(def.placeId == nil or (def.placeId > 0 and def.placeId % 1 == 0), "bad place id: " .. def.id)
	if def.placeId then
		assert(MapCatalog.byPlaceId[def.placeId] == def, "byPlaceId mismatch: " .. def.id)
	end
	if def.floor then
		assert(def.floor.min[1] < def.floor.max[1] and def.floor.min[2] < def.floor.max[2], "floor extent: " .. def.id)
	end
	if def.water then
		assert(def.water.depth > 0, "water depth: " .. def.id)
		assert(def.water.min[1] < def.water.max[1] and def.water.min[2] < def.water.max[2], "water extent: " .. def.id)
		assert(def.water.y == def.water.y, "water surface: " .. def.id)
	end
	for _, mirror in def.mirrors or {} do
		assert(#mirror == 3, "mirror point needs xyz: " .. def.id)
		for axis = 1, 3 do
			assert(mirror[axis] == mirror[axis] and math.abs(mirror[axis]) < 1e6, "bad mirror point: " .. def.id)
		end
	end
end
local default = MapCatalog.byId[MapCatalog.DEFAULT]
assert(default and default.id == "Flatgrass", "default map must be Flatgrass (start place)")
assert(default and default.model ~= nil, "default map needs its model in the start place")
print(`maps ok ({#MapCatalog.list} maps)`)
