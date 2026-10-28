--!nocheck
-- Run: lune run tests/passes.spec.luau
local Config = require("../src/ReplicatedStorage/Shared/Config")
local PassCatalog = require("../src/ReplicatedStorage/Shared/PassCatalog")
local PropCatalog = require("../src/ReplicatedStorage/Shared/PropCatalog")

local EXPECTED_PASSES = {
	physgun_colors = 2058388684,
	more_dupe_slots = 2058670704,
	builder_plus = 2058016713,
	vip = 2059576689,
	npc_pack = 2057170769,
	sports_car = 2057668693,
}

local EXPECTED_PRODUCTS = {
	tip_25 = 2057176765,
	tip_100 = 2057866690,
	tip_500 = 2057134730,
}

local seenKeys = {}
local seenIds = {}

for _, item in PassCatalog.list do
	assert(not seenKeys[item.key], "duplicate key: " .. item.key)
	seenKeys[item.key] = true
	assert(not seenIds[item.id], "duplicate id: " .. item.id)
	seenIds[item.id] = true
	assert(item.kind == "pass" or item.kind == "product", "bad kind: " .. item.key)
	assert(type(item.id) == "number" and item.id > 0, "id must be a positive number: " .. item.key)
	assert(type(item.name) == "string" and item.name ~= "", "name: " .. item.key)
	assert(type(item.description) == "string" and item.description ~= "", "description: " .. item.key)
	assert(type(item.price) == "number" and item.price > 0, "price: " .. item.key)
	assert(type(item.icon) == "string" and string.sub(item.icon, -4) == ".png", "icon: " .. item.key)
	assert(type(item.assetId) == "number" and item.assetId > 0, "uploaded icon assetId: " .. item.key)
	assert(#item.tint == 3, "tint needs 3 numbers: " .. item.key)
	for _, channel in item.tint do
		assert(channel >= 0 and channel <= 255, "tint out of range: " .. item.key)
	end
	assert(PassCatalog.byKey[item.key] == item, "byKey mismatch: " .. item.key)
	if item.kind == "pass" then
		assert(PassCatalog.passById[item.id] == item, "passById mismatch: " .. item.key)
	else
		assert(PassCatalog.productById[item.id] == item, "productById mismatch: " .. item.key)
	end
end

for key, id in EXPECTED_PASSES do
	local item = PassCatalog.byKey[key]
	assert(item and item.kind == "pass", "missing pass: " .. key)
	assert(item.id == id, "pass id changed: " .. key)
end

for key, id in EXPECTED_PRODUCTS do
	local item = PassCatalog.byKey[key]
	assert(item and item.kind == "product", "missing product: " .. key)
	assert(item.id == id, "product id changed: " .. key)
end

assert(#PassCatalog.passes == 6, "six passes")
assert(#PassCatalog.products == 3, "three tips")
assert(PassCatalog.attribute("vip") == "Pass_vip", "attribute format")
assert(PassCatalog.byKey.sports_car.price == 149, "sports car price")

-- The Sports Car prop is real, in the Cars tab, and asks for the pass.
local car = PropCatalog.byId.car_sports
assert(car, "car_sports prop missing")
assert(car.category == "Cars", "sports car must be in the Cars tab")
assert(car.pass == "sports_car", "sports car must be pass-locked")
assert(car.topSpeed and car.topSpeed > Config.CAR_MAX_SPEED, "sports car must be faster than a normal car")

-- The caps the perks read.
assert(Config.VIP_PROP_CAP == 250, "Builder+ prop cap")
assert(Config.VIP_NPC_CAP == 20, "NPC Pack cap")
assert(Config.VIP_DUPE_SLOTS == 30, "More Dupe Slots cap")
assert(Config.VIP_BEAM_COLOR[1] == 255 and Config.VIP_BEAM_COLOR[2] == 203, "VIP gold")

print(`passes ok ({#PassCatalog.passes} passes, {#PassCatalog.products} tips)`)
