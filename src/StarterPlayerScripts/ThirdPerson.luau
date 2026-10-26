--!strict
-- C while seated: a chase camera behind your head that turns with the mouse, so you can see the car you drive.
-- The mouse stays locked to the centre, so the crosshair, guns and tools aim exactly as in first person.
-- Turns itself off when you leave the seat, die, or press C again.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Aim = require(script.Parent.Aim)

local DISTANCE = 12 -- studs behind the head
local HEIGHT = 2.5 -- studs above it
local SENSITIVITY = 0.004 -- radians per pixel, before MouseDeltaSensitivity
local PITCH_LIMIT = math.rad(70)

local player = Players.LocalPlayer
local active = false
local yaw = 0
local pitch = 0

local ThirdPerson = {}

function ThirdPerson.isActive(): boolean
	return active
end

local function seatPart(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid.SeatPart else nil
end

-- Roblox's camera script stops updating body transparency while the camera is Scriptable, so the body stays
-- hidden the way first person left it. Show it ourselves; hide it again on the way back to first person.
local function setBodyHidden(hidden: boolean)
	local character = player.Character
	if not character then
		return
	end
	for _, descendant in character:GetDescendants() do
		if
			(descendant:IsA("BasePart") or descendant:IsA("Decal"))
			and not descendant:FindFirstAncestorOfClass("Tool")
		then
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	if not on then
		setBodyHidden(true)
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local seat = seatPart()
	Aim.setIgnored(if on and seat then Aim.prop(seat) or seat else nil)
	if on then
		local x, y = camera.CFrame:ToOrientation()
		pitch, yaw = x, y
		camera.CameraType = Enum.CameraType.Scriptable
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

function ThirdPerson.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			setActive(not active and seatPart() ~= nil)
		elseif input.KeyCode == Enum.KeyCode.M then
			setActive(false) -- the main menu flies its own camera
		end
	end)

	RunService:BindToRenderStep("ThirdPersonCamera", Enum.RenderPriority.Camera.Value + 3, function()
		if not active then
			return
		end
		local seat = seatPart()
		local head = player.Character and player.Character:FindFirstChild("Head")
		local camera = Workspace.CurrentCamera
		if not seat or not head or not head:IsA("BasePart") or not camera then
			setActive(false)
			return
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		setBodyHidden(false)
		local delta = UserInputService:GetMouseDelta() * SENSITIVITY * UserInputService.MouseDeltaSensitivity
		yaw -= delta.X
		pitch = math.clamp(pitch - delta.Y, -PITCH_LIMIT, PITCH_LIMIT)
		local rotation = CFrame.fromOrientation(pitch, yaw, 0)
		local focus = head.Position + Vector3.new(0, HEIGHT, 0)
		local wanted = rotation:VectorToWorldSpace(Vector3.new(0, 0, DISTANCE))
		-- Pull in when a wall is between the head and the camera.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance, Aim.prop(seat) or seat }
		local hit = Workspace:Raycast(focus, wanted, params)
		local offset = if hit then wanted.Unit * math.max(hit.Distance - 0.5, 1) else wanted
		camera.CFrame = rotation + focus + offset
		camera.Focus = CFrame.new(focus)
	end)
end

return ThirdPerson
