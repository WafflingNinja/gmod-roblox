--!strict
-- Movement a little snappier than Roblox's default, on every character. Avatars get the standard body and scale
-- (tall ones did not fit the maps' doors and gaps) and Roblox's default animations: animation packs move the arms
-- through the first-person camera. Done once the appearance has loaded, or the avatar's own pack loads on top.
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

local ANIMATIONS = {
	"IdleAnimation",
	"WalkAnimation",
	"RunAnimation",
	"JumpAnimation",
	"FallAnimation",
	"ClimbAnimation",
	"SwimAnimation",
}

-- Standard blocky body at standard scale with default animations. Tall bundle bodies (Rthro etc.) are tall from the
-- mesh itself, so the scale values alone are not enough. Clothes, face, head and accessories stay.
local function standardAvatar(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		return
	end
	local packs = false
	for _, field in ANIMATIONS do
		packs = packs or (description :: any)[field] ~= 0
	end
	if
		not packs
		and description.Torso == 0
		and description.LeftArm == 0
		and description.RightArm == 0
		and description.LeftLeg == 0
		and description.RightLeg == 0
		and description.HeightScale == 1
		and description.WidthScale == 1
		and description.DepthScale == 1
		and description.HeadScale == 1
		and description.BodyTypeScale == 0
		and description.ProportionScale == 0
	then
		return
	end
	for _, field in ANIMATIONS do
		(description :: any)[field] = 0
	end
	pcall(function()
		description:SetEmotes({})
	end)
	description.Torso = 0
	description.LeftArm = 0
	description.RightArm = 0
	description.LeftLeg = 0
	description.RightLeg = 0
	description.HeightScale = 1
	description.WidthScale = 1
	description.DepthScale = 1
	description.HeadScale = 1
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	local applied, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	if not applied then
		warn(`PlayerFeel: standard avatar failed for {character.Name}: {err}`)
	end
end

function PlayerFeel.init()
	local function watch(player: Player)
		player.CharacterAdded:Connect(apply)
		player.CharacterAppearanceLoaded:Connect(standardAvatar)
		if player.Character then
			task.defer(apply, player.Character)
			-- In Studio the first character can finish loading before this runs.
			if player:HasAppearanceLoaded() then
				task.defer(standardAvatar, player.Character)
			end
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return PlayerFeel
