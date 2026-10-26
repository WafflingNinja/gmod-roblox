--!nocheck
-- Run: lune run tests/dupes.spec.luau
local Config = require("../src/ReplicatedStorage/Shared/Config")
local DupeCodec = require("../src/ReplicatedStorage/Shared/DupeCodec")
local PropCatalog = require("../src/ReplicatedStorage/Shared/PropCatalog")

local rules = {
	ids = PropCatalog.byId,
	wheels = Config.WHEEL_PROPS,
	maxParts = Config.DUPE_PART_CAP,
	maxLinks = Config.CONSTRAINT_CAP,
	slots = Config.DUPE_SLOTS,
	scaleMin = Config.SCALE_MIN,
	scaleMax = Config.SCALE_MAX,
	ropeMax = Config.ROPE_MAX_LENGTH,
}

local function deepEqual(a, b): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = copy(v)
	end
	return out
end

local valid = {
	v = 1,
	name = "Plank +3",
	parts = {
		{ id = "plank", cf = { 0, 0, 0, 0, 0, 0 }, color = { 120, 80, 40 } },
		{ id = "plank", cf = { 0, 2, 0, 0, 1.5, 0 }, color = { 120, 80, 40 }, scale = 2 },
		{ id = "vehicle_seat", cf = { 0, 3, 0, 0, 0, 0 }, color = { 20, 20, 20 }, anchored = true },
		{ id = "crate_small", cf = { 4, 0, 0, 0.1, 0.2, 0.3 }, color = { 255, 0, 0 } },
	},
	links = {
		{ kind = "weld", a = 1, b = 2 },
		{ kind = "rope", a = 1, b = 4, pa = { 1, 0, 0 }, pb = { -1, 0, 0 }, length = 5 },
		{ kind = "thruster", a = 2, p = { 0, -0.5, 0 }, n = { 0, -1, 0 } },
		{ kind = "wheel", a = 1, p = { 1, 0, 0 }, n = { 1, 0, 0 }, wheel = "wheel_small" },
	},
}

-- Round trip: a valid dupe comes back unchanged, and through the store format too.
assert(deepEqual(DupeCodec.sanitize(copy(valid), rules), valid), "valid dupe round trip")
local stored = DupeCodec.toStore({ [3] = valid, [10] = valid })
assert(stored.v == 1 and stored.slots["3"] and stored.slots["10"], "store keys are strings")
local slots = DupeCodec.fromStore(copy(stored), rules)
assert(slots and deepEqual(slots[3], valid) and deepEqual(slots[10], valid) and slots[1] == nil, "store round trip")
assert(deepEqual(DupeCodec.fromStore(nil, rules), {}), "new player: empty slots")
assert(DupeCodec.fromStore({ v = 2, slots = {} }, rules) == nil, "unknown store version: refuse (never overwrite)")
assert(DupeCodec.fromStore("junk", rules) == nil, "junk store: refuse")
local mixed = DupeCodec.fromStore({ v = 1, slots = { ["1"] = valid, ["2"] = "junk", ["99"] = valid } }, rules)
assert(mixed and mixed[1] and mixed[2] == nil and mixed[99] == nil, "bad slots dropped, good kept")

local function reject(label: string, mutate: (any) -> ())
	local dupe = copy(valid)
	mutate(dupe)
	assert(DupeCodec.sanitize(dupe, rules) == nil, "should reject: " .. label)
end

local NAN = 0 / 0
reject("not a table", function(d)
	d.parts = "x"
end)
reject("wrong version", function(d)
	d.v = 2
end)
reject("no parts", function(d)
	d.parts = {}
end)
reject("unknown id", function(d)
	d.parts[1].id = "nuke"
end)
reject("id not string", function(d)
	d.parts[1].id = 5
end)
reject("NaN position", function(d)
	d.parts[2].cf[1] = NAN
end)
reject("inf rotation", function(d)
	d.parts[2].cf[5] = math.huge
end)
reject("far position", function(d)
	d.parts[2].cf[2] = 1e6
end)
reject("short cf", function(d)
	d.parts[2].cf = { 0, 0, 0 }
end)
reject("string number", function(d)
	d.parts[2].cf[1] = "1"
end)
reject("no color", function(d)
	d.parts[1].color = nil
end)
reject("scale not number", function(d)
	d.parts[2].scale = "big"
end)
reject("link index out of range", function(d)
	d.links[1].b = 99
end)
reject("link index fraction", function(d)
	d.links[1].b = 1.5
end)
reject("self link", function(d)
	d.links[1].b = 1
end)
reject("unknown link kind", function(d)
	d.links[1].kind = "explode"
end)
reject("rope too long", function(d)
	d.links[2].length = Config.ROPE_MAX_LENGTH + 1
end)
reject("rope point far", function(d)
	d.links[2].pa = { 1e4, 0, 0 }
end)
reject("non-unit normal", function(d)
	d.links[3].n = { 0, -5, 0 }
end)
reject("zero normal", function(d)
	d.links[3].n = { 0, 0, 0 }
end)
reject("wheel not a wheel", function(d)
	d.links[4].wheel = "barrel"
end)
reject("too many parts", function(d)
	for i = 1, Config.DUPE_PART_CAP do
		d.parts[i] = valid.parts[1]
	end
	d.parts[Config.DUPE_PART_CAP + 1] = valid.parts[1]
end)
reject("too many links", function(d)
	for i = 1, Config.CONSTRAINT_CAP + 1 do
		d.links[i] = valid.links[1]
	end
end)

-- Clamps instead of rejects: colour, scale, name, junk fields.
local loose = copy(valid)
loose.parts[1].color = { -20, 300, 12.6 }
loose.parts[2].scale = 100
loose.parts[1].evil = "x"
loose.parts[3].anchored = "yes"
loose.links[1].extra = { 1, 2, 3 }
loose.name = "Bad\0Name\n<font>" .. string.rep("a", 100)
loose.junk = true
local clean = DupeCodec.sanitize(loose, rules)
assert(clean, "loose dupe accepted")
assert(deepEqual(clean.parts[1].color, { 0, 255, 13 }), "colour clamped and rounded")
assert(clean.parts[2].scale == Config.SCALE_MAX, "scale clamped")
assert(clean.parts[1].evil == nil and clean.links[1].extra == nil and clean.junk == nil, "unknown fields dropped")
assert(clean.parts[3].anchored == nil, "anchored only when true")
assert(#clean.name <= 40 and not string.find(clean.name, "[%c<>]"), "name cleaned: " .. clean.name)
assert(DupeCodec.sanitize(copy(valid), rules).name == "Plank +3", "normal name kept")
local unnamed = copy(valid)
unnamed.name = nil
assert(DupeCodec.sanitize(unnamed, rules).name == "Dupe", "missing name gets a default")

assert(Config.DUPE_PART_CAP <= Config.PROP_CAP, "a dupe must fit under the prop cap")
print("dupes ok")
