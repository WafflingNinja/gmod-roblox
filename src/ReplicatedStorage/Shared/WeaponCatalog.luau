--!strict
-- Guns every player carries. Plain data so lune can test it. The server owns every number here: fire rate,
-- ammo, spread and damage are never taken from the client.
-- model = name of the mesh model in ServerStorage (inserted in the place file, not git).
-- yaw = degrees to turn the model so its barrel points down +Z (the Tool's forward, the way the right
-- hand holds it). muzzle = the barrel direction in the model's own space before yaw; tests/weapons.spec
-- checks that yaw really turns it to +Z. Fix both together if a gun shows up sideways or backwards.
-- damage only hits players when both shooter and target have PvP on. impulse = studs/s added to a hit prop.

export type Rocket = { speed: number, radius: number, damage: number, impulse: number, lifetime: number }

-- hold = how the arms and hand take the gun (poses in StarterPlayerScripts/GunPose, grips in ToolService).
export type Hold = "pistol" | "rifle" | "launcher"

export type WeaponDef = {
	id: string, -- also the Tool name
	label: string,
	slot: number,
	order: number,
	model: string,
	yaw: number,
	muzzle: { number }, -- model-space unit direction the barrel points
	scale: number?, -- optional model scale; the store RPG is far too long for a character
	hold: Hold,
	rpm: number,
	automatic: boolean,
	magazine: number,
	reload: number, -- seconds
	spread: number, -- degrees, half-cone
	range: number,
	damage: number,
	impulse: number,
	sound: string,
	rocket: Rocket?,
}

local list: { WeaponDef } = {
	{
		id = "Pistol",
		label = "9mm Pistol",
		slot = 2,
		order = 1,
		model = "Pistol",
		hold = "pistol",
		yaw = 0,
		muzzle = { 0, 0, 1 },
		rpm = 400,
		automatic = false,
		magazine = 18,
		reload = 1.4,
		spread = 0.8,
		range = 600,
		damage = 12,
		impulse = 30,
		sound = "pistol_fire",
	},
	{
		id = "SMG",
		label = "SMG",
		slot = 3,
		order = 1,
		model = "SMG",
		hold = "rifle",
		yaw = 180,
		muzzle = { 0, 0, -1 },
		rpm = 800,
		automatic = true,
		magazine = 45,
		reload = 1.6,
		spread = 2.5,
		range = 500,
		damage = 8,
		impulse = 20,
		sound = "smg_fire",
	},
	{
		id = "AR2",
		label = "Pulse Rifle",
		slot = 3,
		order = 2,
		model = "AR2",
		hold = "rifle",
		yaw = 180, -- the Store model faces backwards at 0
		muzzle = { 0, 0, -1 },
		rpm = 600,
		automatic = true,
		magazine = 30,
		reload = 1.8,
		spread = 1.2,
		range = 800,
		damage = 11,
		impulse = 40,
		sound = "ar2_fire",
	},
	{
		id = "RPG",
		label = "Rocket Launcher",
		slot = 5,
		order = 1,
		model = "RPG",
		hold = "launcher",
		yaw = 270, -- model length runs along +X; 270 turns +X to +Z
		muzzle = { 1, 0, 0 },
		scale = 0.45,
		rpm = 40,
		automatic = false,
		magazine = 1,
		reload = 2.2,
		spread = 0,
		range = 0,
		damage = 0,
		impulse = 0,
		sound = "rpg_fire",
		rocket = { speed = 120, radius = 18, damage = 100, impulse = 160, lifetime = 5 },
	},
}

local byId: { [string]: WeaponDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
}
