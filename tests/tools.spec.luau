--!nocheck
-- Run: lune run tests/tools.spec.luau
local Config = require("../src/ReplicatedStorage/Shared/Config")
local ToolModes = require("../src/ReplicatedStorage/Shared/ToolModes")

local seen = {}
for _, mode in ToolModes.list do
	assert(not seen[mode.id], "duplicate mode: " .. mode.id)
	seen[mode.id] = true
	assert(ToolModes.byId[mode.id] == mode, "byId mismatch: " .. mode.id)
	assert(#mode.name > 0 and #mode.hint > 0, "mode needs name and hint: " .. mode.id)
end
for _, required in { "Weld", "Rope", "Thruster", "Wheel", "Scale", "Paint", "Unweld", "Remove", "Dupe" } do
	assert(ToolModes.byId[required], "missing mode: " .. required)
end

assert(#Config.PALETTE >= 1, "palette empty")
for i, c in Config.PALETTE do
	assert(#c == 3, "palette entry needs 3 numbers: " .. i)
	for _, v in c do
		assert(v >= 0 and v <= 255, "palette out of range: " .. i)
	end
end

assert(Config.SCALE_MIN < 1 and Config.SCALE_MAX > 1 and Config.SCALE_STEP > 1, "scale bounds")
assert(Config.HOLD_MIN < Config.HOLD_MAX, "hold bounds")
assert(Config.GRAVGUN_HOLD_DISTANCE + 1.5 < Config.GRAVGUN_HOLD_RANGE, "held prop must sit inside the hold clamp")
assert(Config.GRAVGUN_HOLD_RANGE < Config.GRAVGUN_PUNT_RANGE, "a held prop must be puntable")
assert(Config.GRAVGUN_PUNT_RANGE <= Config.GRAVGUN_PULL_RANGE, "gravity gun ranges")
assert(Config.THRUSTER_CAP <= Config.CONSTRAINT_CAP, "thrusters count against the constraint cap")

print(`tools ok ({#ToolModes.list} modes, {#Config.PALETTE} colours)`)
