--!strict
-- How guns are held. A gun with an animation in HOLD_ANIMATIONS plays it, looped, while it is out: make one by
-- posing a rig with the mouse in Studio's Animation Editor (docs/TOOLS.md, "Gun hold poses"). A gun without one
-- uses the code pose in POSES for its hold: right arm on top of Roblox's tool hold (the launcher rides on the shoulder), left arm
-- forward and in under the gun (the pistol stays one-handed). Seated, the left arm is left alone. Joint C0 offsets
-- don't replicate, so every client poses every character itself; animations on our own character replicate, so we
-- only play our own. Degrees, Euler XYZ.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponCatalog = require(ReplicatedStorage.Shared.WeaponCatalog)

-- "rbxassetid://..." of a looped hold pose per gun (WeaponCatalog id); "" = use the code pose for its hold.
local HOLD_ANIMATIONS: { [string]: string } = {
	Pistol = "rbxassetid://77928087563303",
	SMG = "rbxassetid://130267423555055",
	AR2 = "rbxassetid://89872602265012",
	RPG = "rbxassetid://134877433390392",
}

type Pose = { [string]: { number } }

local POSES: { [string]: Pose } = {
	pistol = { RightShoulder = { 0, 10, 0 } },
	rifle = { LeftShoulder = { 85, 0, 35 } },
	launcher = {
		RightShoulder = { 30, 15, 0 },
		RightElbow = { 60, 0, 0 },
		LeftShoulder = { 85, 0, 30 },
	},
}
local JOINTS = { "RightShoulder", "RightElbow", "LeftShoulder" }
local OWN_SKIP = { RightShoulder = true, LeftShoulder = true } -- FirstPerson writes the shoulders for our character

local offsets: { [string]: { [string]: CFrame } } = {}
for hold, pose in POSES do
	local joints: { [string]: CFrame } = {}
	for joint, degrees in pose do
		joints[joint] = CFrame.Angles(math.rad(degrees[1]), math.rad(degrees[2]), math.rad(degrees[3]))
	end
	offsets[hold] = joints
end

-- Original C0 of each joint we touch, so we can put it back.
local originals: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local posed: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local localPlayer = Players.LocalPlayer
local holdTrack: AnimationTrack? = nil
local holdTrackOf: string? = nil -- the gun the track is for

local function gunOf(character: Model): string?
	local tool = character:FindFirstChildOfClass("Tool")
	return if tool and WeaponCatalog.byId[tool.Name] then tool.Name else nil
end

local function holdOf(character: Model): string?
	local gun = gunOf(character)
	return if gun then WeaponCatalog.byId[gun].hold else nil
end

local function animated(gun: string?): boolean
	return gun ~= nil and (HOLD_ANIMATIONS[gun] or "") ~= ""
end

local GunPose = {}

-- Extra rotation for `joint` of `character` (identity when no gun is out, or the hold is animated).
function GunPose.offset(character: Model, joint: string): CFrame
	local hold = holdOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if (joint == "LeftShoulder" and humanoid and humanoid.Sit) or animated(gunOf(character)) then
		return CFrame.identity
	end
	return if hold then offsets[hold][joint] or CFrame.identity else CFrame.identity
end

local function pose(character: Model, skip: { [string]: boolean }?)
	for _, joint in JOINTS do
		if skip and skip[joint] then
			continue
		end
		local motor = character:FindFirstChild(joint, true)
		if not motor or not motor:IsA("Motor6D") then
			continue
		end
		local original = originals[motor]
		if not original then
			original = motor.C0
			originals[motor] = original
		end
		motor.C0 = original * GunPose.offset(character, joint)
	end
end

-- Put the joints back once the gun is gone; otherwise the launcher's bent elbow would stick after unequipping.
local function restore(character: Model, skip: { [string]: boolean }?)
	for _, joint in JOINTS do
		if skip and skip[joint] then
			continue
		end
		local motor = character:FindFirstChild(joint, true)
		if motor and motor:IsA("Motor6D") then
			local original = originals[motor]
			if original then
				motor.C0 = original
			end
		end
	end
end

-- Our own character: play the hold animation for the gun in hand, stop it when the gun changes or goes away.
local function animate(character: Model, gun: string?)
	local id = if gun then HOLD_ANIMATIONS[gun] or "" else ""
	local wanted = if id ~= "" then gun else nil
	if wanted == holdTrackOf and (holdTrack == nil or holdTrack.IsPlaying) then
		return
	end
	if holdTrack then
		holdTrack:Stop(0.15)
		holdTrack = nil
	end
	holdTrackOf = wanted
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not wanted or not animator then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.15)
	holdTrack = track
end

function GunPose.init()
	RunService.RenderStepped:Connect(function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				local skip = if player == localPlayer then OWN_SKIP else nil
				local hold = holdOf(character)
				if hold then
					pose(character, skip)
					posed[character] = true
				elseif posed[character] then
					restore(character, skip)
					posed[character] = nil
				end
				if player == localPlayer then
					animate(character, gunOf(character))
				end
			end
		end
	end)
end

return GunPose
