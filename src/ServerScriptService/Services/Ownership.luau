--!strict
-- Server-side registry of who owns which prop. The registry is the truth;
-- the tag/attribute on the instance are for debugging and the HUD only.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Passes = require(script.Parent.Passes)

local owned: { [Player]: { [Instance]: boolean } } = {}
local counts: { [Player]: number } = {}
local serverTotal = 0

local Ownership = {}

function Ownership.count(player: Player): number
	return counts[player] or 0
end

function Ownership.serverCount(): number
	return serverTotal
end

-- Builder+ raises the per-player prop cap; everything else keeps the base cap.
function Ownership.cap(player: Player): number
	return if Passes.has(player, "builder_plus") then Config.VIP_PROP_CAP else Config.PROP_CAP
end

function Ownership.canSpawn(player: Player): boolean
	return Ownership.count(player) < Ownership.cap(player) and serverTotal < Config.SERVER_PROP_CAP
end

local function release(player: Player, prop: Instance)
	local set = owned[player]
	if not set or not set[prop] then
		return
	end
	set[prop] = nil
	local n = math.max(0, Ownership.count(player) - 1)
	counts[player] = n
	serverTotal = math.max(0, serverTotal - 1)
	player:SetAttribute(Config.COUNT_ATTRIBUTE, n)
end

-- Register a prop to a player. Call before parenting it.
function Ownership.claim(player: Player, prop: Instance)
	local set = owned[player]
	if not set then
		set = {}
		owned[player] = set
	end
	set[prop] = true
	local n = Ownership.count(player) + 1
	counts[player] = n
	serverTotal += 1
	player:SetAttribute(Config.COUNT_ATTRIBUTE, n)
	prop:SetAttribute(Config.OWNER_ATTRIBUTE, player.UserId)
	CollectionService:AddTag(prop, Config.PROP_TAG)
	prop.Destroying:Once(function()
		release(player, prop)
	end)
end

function Ownership.isOwner(player: Player, instance: Instance): boolean
	local set = owned[player]
	return set ~= nil and set[instance] == true
end

function Ownership.clearAll(player: Player)
	local set = owned[player]
	if not set then
		return
	end
	local props: { Instance } = {}
	for prop in set do
		table.insert(props, prop)
	end
	for _, prop in props do
		prop:Destroy()
	end
end

-- A leaver's props go with them, otherwise the world fills with orphans.
Players.PlayerRemoving:Connect(function(player)
	Ownership.clearAll(player)
	owned[player] = nil
	counts[player] = nil
end)

return Ownership
