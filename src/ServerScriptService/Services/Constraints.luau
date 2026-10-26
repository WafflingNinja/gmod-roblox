--!strict
-- Counts player-made welds, ropes and thrusters against a cap, and cleans them up with their props.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local counts: { [Player]: number } = {}
local byProp: { [BasePart]: { [Instance]: boolean } } = {}

local Constraints = {}

function Constraints.count(player: Player): number
	return counts[player] or 0
end

function Constraints.canAdd(player: Player): boolean
	return Constraints.count(player) < Config.CONSTRAINT_CAP
end

-- Track a constraint that links `props`. It is destroyed with any of them, along with `extras`
-- (attachments and the like that only exist for it).
function Constraints.register(player: Player, constraint: Instance, props: { BasePart }, extras: { Instance }?)
	counts[player] = Constraints.count(player) + 1
	for _, prop in props do
		local set = byProp[prop]
		if not set then
			set = {}
			byProp[prop] = set
		end
		set[constraint] = true
		prop.Destroying:Once(function()
			constraint:Destroy()
		end)
	end
	constraint.Destroying:Once(function()
		if counts[player] then
			counts[player] = math.max(0, counts[player] - 1)
		end
		for _, prop in props do
			local set = byProp[prop]
			if set then
				set[constraint] = nil
			end
		end
		if extras then
			for _, extra in extras do
				extra:Destroy()
			end
		end
	end)
end

function Constraints.clearFor(prop: BasePart)
	local set = byProp[prop]
	if not set then
		return
	end
	local all: { Instance } = {}
	for constraint in set do
		table.insert(all, constraint)
	end
	for _, constraint in all do
		constraint:Destroy()
	end
end

Players.PlayerRemoving:Connect(function(player)
	counts[player] = nil
end)

return Constraints
