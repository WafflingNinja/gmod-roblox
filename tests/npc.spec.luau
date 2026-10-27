--!nocheck
-- Run: lune run tests/npc.spec.luau
local NpcCatalog = require("../src/ReplicatedStorage/Shared/NpcCatalog")
local VoiceLines = require("../src/ReplicatedStorage/Shared/VoiceLines")
local VoicePicker = require("../src/ReplicatedStorage/Shared/VoicePicker")

-- Every NPC has a sprite and spawn/idle lines; every line belongs to a known NPC.
for _, def in NpcCatalog.list do
	assert(VoiceLines.sprites[def.voice], "no sprite for " .. def.id)
	assert(#VoicePicker.candidates(VoiceLines.lines, def.voice, "idle") > 0, def.id .. " has no idle lines")
end
for id in NpcCatalog.lineWeights do
	assert(VoiceLines.lines[id], "weight for unknown line " .. id)
end

-- Lines sit inside their sprite without overlapping.
local byNpc = {}
for id, line in VoiceLines.lines do
	assert(VoiceLines.sprites[line.npc], id .. ": unknown npc " .. line.npc)
	assert(line.start >= 0 and line.length > 0, id .. ": bad region")
	byNpc[line.npc] = byNpc[line.npc] or {}
	table.insert(byNpc[line.npc], line)
end
for npc, lines in byNpc do
	table.sort(lines, function(a, b)
		return a.start < b.start
	end)
	for i = 2, #lines do
		assert(lines[i].start >= lines[i - 1].start + lines[i - 1].length, npc .. ": overlapping lines")
	end
end

-- Picker: never repeats, honours weights.
local lines = {
	a_idle_1 = { npc = "a", category = "idle" },
	a_idle_2 = { npc = "a", category = "idle" },
	a_idle_3 = { npc = "a", category = "idle" },
	a_hurt_1 = { npc = "a", category = "hurt" },
}
assert(VoicePicker.pick(lines, "a", "hurt", "a_hurt_1", {}, 0.5) == "a_hurt_1", "single line may repeat")
assert(VoicePicker.pick(lines, "a", "nope", nil, {}, 0.5) == nil, "missing category")
for i = 0, 99 do
	assert(VoicePicker.pick(lines, "a", "idle", "a_idle_2", {}, i / 100) ~= "a_idle_2", "repeated last line")
end
local counts = { a_idle_1 = 0, a_idle_2 = 0, a_idle_3 = 0 }
local steps = 3800
for i = 0, steps - 1 do
	local id = VoicePicker.pick(lines, "a", "idle", nil, { a_idle_2 = 1.8 }, i / steps)
	counts[id] += 1
end
-- weights 1 : 1.8 : 1 of 3.8
assert(math.abs(counts.a_idle_2 - steps * 1.8 / 3.8) <= 1, "weight not applied: " .. counts.a_idle_2)
assert(math.abs(counts.a_idle_1 - steps / 3.8) <= 1, "unweighted share off")

print("npc.spec ok")
