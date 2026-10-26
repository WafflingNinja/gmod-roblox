--!nocheck
-- Run: lune run tests/weapons.spec.luau
local Config = require("../src/ReplicatedStorage/Shared/Config")
local Sounds = require("../src/ReplicatedStorage/Shared/Sounds")
local WeaponCatalog = require("../src/ReplicatedStorage/Shared/WeaponCatalog")

local tools = { [Config.PHYSGUN] = true, [Config.GRAVGUN] = true, [Config.TOOLGUN] = true }
local seen = {}
for _, def in WeaponCatalog.list do
	assert(not seen[def.id] and not tools[def.id], "duplicate tool name: " .. def.id)
	seen[def.id] = true
	assert(WeaponCatalog.byId[def.id] == def, "byId mismatch: " .. def.id)
	assert(def.hold == "pistol" or def.hold == "rifle" or def.hold == "launcher", "hold: " .. def.id)
	assert(def.slot >= 2 and def.slot <= 5, "guns live in slots 2-5: " .. def.id)
	assert(def.rpm > 0 and def.rpm <= 1200, "rpm: " .. def.id)
	assert(def.magazine >= 1 and def.reload > 0, "ammo: " .. def.id)
	assert(Sounds[def.sound], "unknown sound: " .. def.sound)
	if def.rocket then
		local r = def.rocket
		assert(r.speed > 0 and r.radius > 0 and r.radius <= 40 and r.lifetime > 0, "rocket: " .. def.id)
	else
		assert(def.range > 0 and def.range <= 1000 and def.spread >= 0 and def.spread < 10, "hitscan: " .. def.id)
		assert(def.damage > 0 and def.damage <= 100, "damage: " .. def.id)
	end
end
print(`weapons ok ({#WeaponCatalog.list} guns)`)
