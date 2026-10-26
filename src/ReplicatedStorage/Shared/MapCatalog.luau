--!strict
-- Maps on the one server, far apart in Workspace. Plain data so lune can test it.
-- model = child of Workspace.Maps (the maps live in the place file, not git); nil = the Rojo baseplate, spawn
-- on SpawnPad. spawn = world floor point players land on. floor = invisible collision the server adds where the
-- converted map's grass has none: top Y and the X/Z extent. Lighting is ReplicatedStorage.MapLighting.<id>.
-- orbit = where the main menu camera circles: world centre (the maps sit at fixed offsets), radius, height.
export type Orbit = { center: { number }, radius: number, height: number }
export type Floor = { y: number, min: { number }, max: { number } } -- min/max = {x, z}
-- mirrors = world points on the room-facing surface of a mirror wall. MapService finds the nearest wall face and
-- builds a real mirror panel there (a huge collision box behind the wall is not used).
export type MapDef = {
	id: string,
	name: string,
	blurb: string,
	model: string?,
	spawn: { number }?,
	floor: Floor?,
	orbit: Orbit,
	mirrors: { { number } }?,
}

local list: { MapDef } = {
	{
		id = "Baseplate",
		name = "Baseplate",
		blurb = "Flat and empty. Room to build.",
		orbit = { center = { 0, 2, 0 }, radius = 90, height = 35 },
	},
	{
		id = "Construct",
		name = "Construct",
		blurb = "Buildings, ramps and a pool.",
		model = "Construct",
		spawn = { 5202, 268.29, -481 }, -- ground floor of the main building, where Gmod spawns you
		mirrors = { { 5395, 278, -548.6 } },
		orbit = { center = { 5208, 270, -265 }, radius = 180, height = 35 },
	},
	{
		id = "Flatgrass",
		name = "Flatgrass",
		blurb = "Huge open grass field.",
		model = "Flatgrass",
		spawn = { -9440, 1129.47, -90 }, -- in front of the brick building
		floor = { y = 1129.47, min = { -14600, -4800 }, max = { -5600, 4800 } },
		orbit = { center = { -9483, 1140, -214 }, radius = 260, height = 45 },
	},
}

local byId: { [string]: MapDef } = {}
for _, def in list do
	byId[def.id] = def
end

return {
	list = list,
	byId = byId,
	DEFAULT = "Baseplate",
}
