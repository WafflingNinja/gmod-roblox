--!strict
-- How guns are held. Right arm: a per-hold pose on top of Roblox's tool hold (the launcher rides on the shoulder).
-- Left arm: any tool with a LeftGrip attachment is two-handed, so an IKControl reaches the left hand onto it; the
-- pistol has none and stays one-handed. Joint C0 offsets don't replicate, so every client poses every character
-- itself. Degrees, Euler XYZ.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WeaponCatalog = require(ReplicatedStorage.Shared.WeaponCatalog)

type Pose = { [string]: { number } }

local POSES: { [string]: Pose } = {
	pistol = { RightShoulder = { 0, 10, 0 } },
	rifle = {},
	launcher = {
		RightShoulder = { 30, 15, 0 },
		RightElbow = { 60, 0, 0 },
	},
}
local JOINTS = { "RightShoulder", "RightElbow" }
local OWN_SKIP = { RightShoulder = true } -- FirstPerson writes the shoulders for our character

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

type Hand = { tool: Tool, control: IKControl }
local hands: { [Model]: Hand } = setmetatable({}, { __mode = "k" }) :: any

local localPlayer = Players.LocalPlayer

local function holdOf(character: Model): string?
	local tool = character:FindFirstChildOfClass("Tool")
	local def = tool and WeaponCatalog.byId[tool.Name]
	return if def then def.hold else nil
end

local GunPose = {}

-- Extra rotation for `joint` of `character` (identity when no gun is out).
function GunPose.offset(character: Model, joint: string): CFrame
	local hold = holdOf(character)
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

-- Two-handed tools: the left hand follows the tool's LeftGrip. Rebuilt when the tool changes, dropped on unequip.
local function reachLeftHand(character: Model)
	local tool = character:FindFirstChildOfClass("Tool")
	local handle = tool and tool:FindFirstChild("Handle")
	local grip = handle and handle:FindFirstChild("LeftGrip")
	local current: Hand? = hands[character]
	if current and (not grip or current.tool ~= tool) then
		current.control:Destroy()
		hands[character] = nil
		current = nil
	end
	if current or not tool or not grip then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local upper = character:FindFirstChild("LeftUpperArm")
	local hand = character:FindFirstChild("LeftHand")
	if not humanoid or not upper or not hand or not upper:IsA("BasePart") or not hand:IsA("BasePart") then
		return
	end
	local control = Instance.new("IKControl")
	control.Type = Enum.IKControlType.Position
	control.ChainRoot = upper
	control.EndEffector = hand
	control.Target = grip
	control.Weight = 1
	control.Parent = humanoid
	hands[character] = { tool = tool :: Tool, control = control }
end

function GunPose.init()
	RunService.RenderStepped:Connect(function()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				pose(character, if player == localPlayer then OWN_SKIP else nil)
				reachLeftHand(character)
			end
		end
	end)
end

return GunPose
