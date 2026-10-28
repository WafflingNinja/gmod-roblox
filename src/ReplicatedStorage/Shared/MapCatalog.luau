--!strict
-- Maps on the one server, far apart in Workspace. Plain data so lune can test it.
-- model = child of Workspace.Maps (the maps live in the place file, not git); nil = the Rojo baseplate, spawn
-- on SpawnPad. spawn = world floor point players land on; a converted map overrides it with its own Spawn
-- attribute (tools/MapImport.luau raycasts the real floor). floor = invisible collision the server adds where
-- the converted map's grass has none: top Y and the X/Z extent. Lighting is ReplicatedStorage.MapLighting.<id>.
-- orbit = where the main menu camera circles: world centre (the maps sit at fixed offsets), radius, height.
-- placeId = that map's own Roblox place in the same universe (Split Worlds). nil = the map lives inside this
-- place; the start place hosts Flatgrass. tools/add_map.py writes the id after the user adds the place.
export type Orbit = { center: { number }, radius: number, height: number }
export type Floor = { y: number, min: { number }, max: { number } } -- min/max = {x, z}
-- water = a terrain water volume the server fills at startup (only Big City needs one: its river brushes are
-- a Source func_water entity and the converter does not import brush entities). y = surface, depth = studs.
export type Water = { y: number, depth: number, min: { number }, max: { number } } -- min/max = {x, z}
-- mirrors = world points on the room-facing surface of a mirror wall. MapService finds the nearest wall face and
-- builds a real mirror panel there (a huge collision box behind the wall is not used).
export type MapDef = {
	id: string,
	name: string,
	blurb: string,
	model: string?,
	spawn: { number }?,
	floor: Floor?,
	water: Water?,
	orbit: Orbit,
	mirrors: { { number } }?,
	placeId: number?,
}

-- Add `placeId = <id>` to an entry once that map has its own place (Creator Dashboard > Add Place, same
-- universe). Until then PickMap switches to the map inside this place (development / the start place).
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
		placeId = 86612994618738, -- the start place ("waffles mod"); update if the start place moves
	},
	{
		id = "Mallparking",
		name = "Mall Parking",
		blurb = "Two-level parking deck, 48 doors, long ramps.",
		model = "Mallparking",
		spawn = { 40572.8, 192.2, -186.5 },
		orbit = { center = { 39999, 190, 4 }, radius = 720, height = 190 },
	},
	{
		id = "Bigcity",
		name = "Big City",
		blurb = "Downtown blocks, streets and rooftops.",
		model = "Bigcity",
		spawn = { -31899.2, 450.3, 23851.4 },
		-- The river along the south-west edge. Its brushes are a func_water entity in the Source map, which the
		-- converter drops, so the canal had a bed and no water. Terrain water gives swimming and prop buoyancy.
		water = { y = 221, depth = 30, min = { -33060, 22540 }, max = { -32760, 22860 } },
		orbit = { center = { -32000, 470, 23500 }, radius = 1350, height = 620 },
	},
	{
		id = "Bangclaw",
		name = "Bangclaw",
		blurb = "RP town: streets, houses and 199 doors.",
		model = "Bangclaw",
		spawn = { 11682.5, 275.7, 37853.8 },
		orbit = { center = { 11995, 330, 38005 }, radius = 950, height = 380 },
	},
	{
		id = "Backrooms",
		name = "Backrooms",
		blurb = "Yellow wallpaper, wet carpet, no way out.",
		model = "Backrooms",
		spawn = { -32037.6, 383.8, -23690.1 },
		orbit = { center = { -31999, 250, -23500 }, radius = 1150, height = 260 },
	},
	{
		id = "Brmovie",
		name = "Backrooms Movie",
		blurb = "The A24 backrooms movie set, room by room.",
		model = "Brmovie",
		spawn = { 12061.1, 855.5, -38128.9 },
		orbit = { center = { 12001, 560, -37100 }, radius = 1700, height = 620 },
	},
}

local byId: { [string]: MapDef } = {}
local byPlaceId: { [number]: MapDef } = {}
for _, def in list do
	byId[def.id] = def
	if def.placeId then
		byPlaceId[def.placeId] = def
	end
end

return {
	list = list,
	byId = byId,
	byPlaceId = byPlaceId,
	-- The start place hosts Flatgrass (Split Worlds). Tools that need a map in a place whose id is in the
	-- catalog use byPlaceId; everywhere else falls back to this.
	DEFAULT = "Flatgrass",
}
