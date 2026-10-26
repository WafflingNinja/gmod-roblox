--!strict
-- Everyone plays Roblox's default animation set. Avatar animation packs (the ones
-- bought or equipped on the website) are dropped on spawn by zeroing the animation
-- fields of the applied HumanoidDescription and re-applying it, which makes the
-- default Animate script fall back to its built-in R6/R15 ids.

local Players = game:GetService("Players")

local RESET_ATTRIBUTE = "DefaultAnimations"

local AnimationService = {}

local function stripAnimationPacks(humanoid: Humanoid)
	if humanoid:GetAttribute(RESET_ATTRIBUTE) then
		return
	end
	humanoid:SetAttribute(RESET_ATTRIBUTE, true)

	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not ok or not description then
		return
	end

	description.IdleAnimation = 0
	description.WalkAnimation = 0
	description.RunAnimation = 0
	description.JumpAnimation = 0
	description.FallAnimation = 0
	description.ClimbAnimation = 0
	description.SwimAnimation = 0

	-- Emote packs are the same idea: wave/dance/point animations.
	pcall(function()
		description:SetEmotes({})
	end)

	pcall(function()
		humanoid:ApplyDescriptionResetAsync(description)
	end)
end

local function watchCharacter(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		stripAnimationPacks(humanoid)
		return
	end
	-- The Humanoid is usually there already, but not always on the first frame.
	character.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then
			stripAnimationPacks(child)
		end
	end)
end

function AnimationService.init()
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end
end

return AnimationService
