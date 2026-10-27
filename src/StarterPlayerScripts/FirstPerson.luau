--!strict
-- Makes locked first person feel less like a floating camera: with a tool out, your own arms and the tool
-- stay visible and aim where you look, the tool sways behind fast mouse moves, and the view bobs while
-- walking. All local: other players see the normal character. R15 rigs only (shoulder frames differ on R6).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GunPose = require(script.Parent.GunPose)
local ThirdPerson = require(script.Parent.ThirdPerson)
local Ui = require(script.Parent.UI.Ui)

local fieldOfView = 80 -- the menu's Settings page changes it
local BOB_SPEED = 9 -- radians per second at walk speed 16
local BOB_SIDE = 0.06 -- studs
local BOB_UP = 0.08
local BOB_ROLL = math.rad(0.6)
local SWAY_PER_PIXEL = 0.002 -- radians of lag per pixel of mouse movement
local SWAY_LIMIT = math.rad(6)
local SWAY_RETURN = 10 -- how fast the lag settles, per second
local RIGHT_ARM = { "RightUpperArm", "RightLowerArm", "RightHand" }
local LEFT_ARM = { "LeftUpperArm", "LeftLowerArm", "LeftHand" }
local SHOULDERS = { "RightShoulder", "LeftShoulder" }
-- Two-handed tools (a LeftGrip on the handle), first person only: both shoulders move in, forward and down
-- (torso space: +X right, +Y up, -Z forward). The gun sits nearer the middle, still pointing straight, and the
-- left hand reaches the foregrip instead of stretching from the left shoulder across the camera.
local TWO_HAND_SHIFT: { [string]: CFrame } = {
	RightShoulder = CFrame.new(-0.5, -0.3, -0.4),
	LeftShoulder = CFrame.new(0.2, -0.4, -0.3), -- further in and forward put the left hand in the middle of the view
}

-- A menu with a Modal button is on screen (Q, M, feedback). Roblox frees the mouse for it but still reports
-- MouseBehavior as LockCenter, so the cursor check needs this too.
local function menuFreesMouse(): boolean
	for _, button in CollectionService:GetTagged(Ui.FREES_MOUSE_TAG) do
		local node: Instance? = button
		local shown = true
		while node and not node:IsA("LayerCollector") do
			if node:IsA("GuiObject") and not node.Visible then
				shown = false
				break
			end
			node = node.Parent
		end
		if shown and node and (node :: LayerCollector).Enabled then
			return true
		end
	end
	return false
end

local FirstPerson = {}

function FirstPerson.setFieldOfView(degrees: number)
	fieldOfView = degrees
end

function FirstPerson.fieldOfView(): number
	return fieldOfView
end

function FirstPerson.init()
	local player = Players.LocalPlayer
	local shoulders: { [Motor6D]: CFrame } = {} -- motor -> its original C0
	local shouldersOf: Model? = nil
	local bobTime = 0
	local sway = Vector2.zero

	-- Shoulders load a moment after the character, so look them up lazily.
	local function findShoulders(character: Model)
		if shouldersOf == character then
			return
		end
		table.clear(shoulders)
		for _, name in SHOULDERS do
			local motor = character:FindFirstChild(name, true)
			if motor and motor:IsA("Motor6D") then
				shoulders[motor] = motor.C0
			end
		end
		if next(shoulders) then
			shouldersOf = character
		end
	end

	RunService:BindToRenderStep("FirstPersonView", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		-- No mouse cursor while the mouse is locked to the centre (it showed as a hand over the crosshair); menus that
		-- free the mouse (Q, M) get it back.
		UserInputService.MouseIconEnabled = UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
			or menuFreesMouse()
		local camera = Workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not camera or not character or not humanoid or humanoid.Health <= 0 then
			return
		end
		if humanoid:GetState() == Enum.HumanoidStateType.Physics then
			return -- ragdolled
		end
		camera.FieldOfView = fieldOfView
		findShoulders(character)

		local tool = character:FindFirstChildOfClass("Tool")
		local holding = tool ~= nil
		local handle = tool and tool:FindFirstChild("Handle")
		local twoHanded = handle ~= nil and handle:FindFirstChild("LeftGrip") ~= nil
		local shifted = twoHanded and not ThirdPerson.isActive()
		local delta = UserInputService:GetMouseDelta()
		local settle = math.max(0, 1 - dt * SWAY_RETURN)
		sway = Vector2.new(
			math.clamp(sway.X * settle + delta.X * SWAY_PER_PIXEL, -SWAY_LIMIT, SWAY_LIMIT),
			math.clamp(sway.Y * settle + delta.Y * SWAY_PER_PIXEL, -SWAY_LIMIT, SWAY_LIMIT)
		)
		-- The camera module hides the whole body in first person every frame; bring the arms back after it.
		if holding then
			for _, arm in (if twoHanded then { RIGHT_ARM, LEFT_ARM } else { RIGHT_ARM }) :: { { string } } do
				for _, name in arm do
					local part = character:FindFirstChild(name)
					if part and part:IsA("BasePart") then
						part.LocalTransparencyModifier = 0
					end
				end
			end
		end
		local pitch = math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))
		for motor, c0 in shoulders do
			local shift = if shifted then TWO_HAND_SHIFT[motor.Name] or CFrame.identity else CFrame.identity
			motor.C0 = if holding
				then shift * c0 * CFrame.Angles(pitch + sway.Y, sway.X, 0) * GunPose.offset(character, motor.Name)
				else c0
		end

		local walking = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.FloorMaterial ~= Enum.Material.Air
		if walking and camera.CameraType == Enum.CameraType.Custom then
			bobTime += dt * BOB_SPEED * humanoid.WalkSpeed / 16
			camera.CFrame *= CFrame.new(math.sin(bobTime) * BOB_SIDE, math.abs(math.cos(bobTime)) * BOB_UP, 0) * CFrame.Angles(
				0,
				0,
				math.sin(bobTime) * BOB_ROLL
			)
		end
	end)
end

return FirstPerson
