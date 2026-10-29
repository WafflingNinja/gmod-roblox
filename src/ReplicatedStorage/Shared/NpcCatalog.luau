--!strict
-- Spawnable NPCs. Pure data (colors are RGB triples) so lune can load it. `voice` is the VoiceLines npc key.
export type Rgb = { number }
export type NpcDef = {
	id: string,
	name: string,
	voice: string, -- whose recorded lines it says
	gun: string?, -- WeaponCatalog id it carries and shoots back with when hurt
	secret: boolean, -- only spawnable once the player has SecretUnlocked
	head: Rgb,
	torso: Rgb,
	arms: Rgb,
	legs: Rgb,
	cap: boolean, -- black Guest cap built from parts
	avatar: string?, -- Roblox username whose avatar the rig wears
}

local SKIN = { 204, 142, 105 }

local list: { NpcDef } = {
	{
		id = "guest",
		voice = "guest",
		name = "Guest",
		secret = false,
		head = SKIN,
		torso = { 99, 95, 98 },
		arms = SKIN,
		legs = { 27, 42, 53 },
		cap = true,
	},
	{
		id = "noob",
		voice = "noob",
		name = "Noob",
		secret = false,
		head = { 245, 205, 48 },
		torso = { 13, 105, 172 },
		arms = { 245, 205, 48 },
		legs = { 75, 151, 75 },
		cap = false,
	},
	{
		id = "citizen",
		voice = "citizen",
		name = "Citizen",
		secret = false,
		head = SKIN,
		torso = { 82, 124, 174 },
		arms = { 82, 124, 174 },
		legs = { 39, 46, 50 },
		cap = false,
	},
	{
		id = "citizen_armed",
		voice = "citizen",
		name = "Armed Citizen",
		secret = false,
		head = SKIN,
		torso = { 82, 124, 174 },
		arms = { 82, 124, 174 },
		legs = { 39, 46, 50 },
		cap = false,
		gun = "Pistol",
	},
	{
		id = "rostik",
		voice = "rostik",
		name = "RostikPro12308",
		secret = true,
		head = SKIN,
		torso = SKIN,
		arms = SKIN,
		legs = SKIN,
		cap = false,
		avatar = "RostikPro12308",
	},
}

local byId: { [string]: NpcDef } = {}
for _, def in list do
	assert(byId[def.id] == nil, `NpcCatalog: duplicate id {def.id}`)
	byId[def.id] = def
end

-- Shape invariants NpcService reads. `gun` names a WeaponCatalog id; the cross-check lives in
-- tests/ (shared modules cannot require each other under lune's path-based require).
for _, def in list do
	assert(type(def.voice) == "string" and def.voice ~= "", `NpcCatalog: {def.id} needs a voice`)
	assert(def.gun == nil or type(def.gun) == "string", `NpcCatalog: {def.id} gun must be a WeaponCatalog id`)
	for _, channel in { def.head, def.torso, def.arms, def.legs } do
		assert(#channel == 3, `NpcCatalog: {def.id} colour needs 3 numbers`)
	end
end

-- Pick weight per line id; anything missing is 1. The LFS joke plays 80% more often than his other idle lines.
local lineWeights: { [string]: number } = {
	rostik_idle_2 = 1.8,
}

return table.freeze({ list = list, byId = byId, lineWeights = lineWeights })
