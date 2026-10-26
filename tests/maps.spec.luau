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
	if def.floor then
		assert(def.floor.min[1] < def.floor.max[1] and def.floor.min[2] < def.floor.max[2], "floor extent: " .. def.id)
	end
end
local default = MapCatalog.byId[MapCatalog.DEFAULT]
assert(default and default.model == nil, "default map must be the always-present baseplate")
print(`maps ok ({#MapCatalog.list} maps)`)
