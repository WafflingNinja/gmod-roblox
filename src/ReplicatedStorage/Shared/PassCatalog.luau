--!strict
-- Every game pass and developer product the game sells. Plain data (no Roblox datatypes) so lune can test it.
-- IDs are the asset IDs from Creator Hub. `icon` is the original local PNG in Desktop/gamepass-icons; `assetId`
-- is that PNG after upload to Roblox, which the in-game Store shows. A missing assetId falls back to a tinted tile.
export type Kind = "pass" | "product"

export type Item = {
	key: string,
	kind: Kind,
	id: number,
	name: string,
	description: string,
	price: number,
	icon: string,
	tint: { number },
	assetId: number?,
}

local list: { Item } = {
	{
		key = "physgun_colors",
		kind = "pass",
		id = 2058388684,
		name = "Physgun Colors",
		description = "Pick any color for your physgun and gravity gun beam.",
		price = 99,
		icon = "1_physgun_colors.png",
		tint = { 70, 225, 255 },
		assetId = 123211614889082,
	},
	{
		key = "more_dupe_slots",
		kind = "pass",
		id = 2058670704,
		name = "More Dupe Slots",
		description = "Save up to 30 builds instead of 10.",
		price = 99,
		icon = "2_more_dupe_slots.png",
		tint = { 70, 130, 220 },
		assetId = 79492071811962,
	},
	{
		key = "builder_plus",
		kind = "pass",
		id = 2058016713,
		name = "Builder+",
		description = "Spawn 100 more props (250 instead of 150).",
		price = 149,
		icon = "3_builder_plus.png",
		tint = { 240, 160, 50 },
		assetId = 82804981418829,
	},
	{
		key = "vip",
		kind = "pass",
		id = 2059576689,
		name = "VIP",
		description = "Gold VIP name tag, golden beam, gold trail and a VIP spawn pad.",
		price = 199,
		icon = "4_vip.png",
		tint = { 255, 200, 60 },
		assetId = 122993987094261,
	},
	{
		key = "npc_pack",
		kind = "pass",
		id = 2057170769,
		name = "NPC Pack",
		description = "Spawn twice as many NPCs (20 instead of 10).",
		price = 149,
		icon = "5_npc_pack.png",
		tint = { 90, 200, 120 },
		assetId = 92001205884608,
	},
	{
		key = "sports_car",
		kind = "pass",
		id = 2057668693,
		name = "Sports Car",
		description = "Unlocks a fast sports car in the Cars tab.",
		price = 149,
		icon = "6_sports_car.png",
		tint = { 220, 60, 60 },
		assetId = 75507139512330,
	},
	{
		key = "tip_25",
		kind = "product",
		id = 2057176765,
		name = "Tip 25",
		description = "Say thanks to the dev!",
		price = 25,
		icon = "7_tip_25.png",
		tint = { 255, 170, 60 },
		assetId = 91105302280514,
	},
	{
		key = "tip_100",
		kind = "product",
		id = 2057866690,
		name = "Tip 100",
		description = "Big thanks to the dev!",
		price = 100,
		icon = "7_tip_100.png",
		tint = { 255, 140, 50 },
		assetId = 126766435287528,
	},
	{
		key = "tip_500",
		kind = "product",
		id = 2057134730,
		name = "Tip 500",
		description = "Legendary thanks to the dev!",
		price = 500,
		icon = "7_tip_500.png",
		tint = { 255, 110, 40 },
		assetId = 115026929802802,
	},
}

local passes: { Item } = {}
local products: { Item } = {}
local byKey: { [string]: Item } = {}
local passById: { [number]: Item } = {}
local productById: { [number]: Item } = {}

for _, item in list do
	byKey[item.key] = item
	if item.kind == "pass" then
		table.insert(passes, item)
		passById[item.id] = item
	else
		table.insert(products, item)
		productById[item.id] = item
	end
end

local PassCatalog = {}

PassCatalog.list = list
PassCatalog.passes = passes
PassCatalog.products = products
PassCatalog.byKey = byKey
PassCatalog.passById = passById
PassCatalog.productById = productById
PassCatalog.ATTRIBUTE_PREFIX = "Pass_"

function PassCatalog.attribute(key: string): string
	return PassCatalog.ATTRIBUTE_PREFIX .. key
end

return PassCatalog
