--!strict
-- Movement a little snappier than Roblox's default, on every character.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local PlayerFeel = {}

local function apply(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = Config.WALK_SPEED
		humanoid.JumpHeight = Config.JUMP_HEIGHT
	end
end

function PlayerFeel.init()
	local function watch(player: Player)
		player.CharacterAdded:Connect(apply)
		if player.Character then
			task.defer(apply, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return PlayerFeel
