--!strict
-- C: third person, on foot or in a seat; C again goes back to first person. On foot it is an over-the-shoulder
-- camera and the body turns with it, so you face where you aim; in a seat it is a chase camera behind your head
-- (the car turns you). The mouse stays locked to the centre, so the crosshair, guns and tools aim exactly as in
-- first person. It blends in from your eyes, eases back out after a wall pushed it in, and stays on through
-- respawns; the main menu (M) switches it off.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Aim = require(script.Parent.Aim)

local FOOT_OFFSET = Vector3.new(1.8, 1.2, 8) -- studs from the head: right, up, back
local SEAT_OFFSET = Vector3.new(0, 2.5, 12)
local SENSITIVITY = 0.004 -- radians per pixel, before MouseDeltaSensitivity
local PITCH_LIMIT = math.rad(70)
local BLEND_SECONDS = 0.25 -- from the eyes out to the shoulder when switching on
local EASE_OUT = 6 -- per second, how fast the camera backs out again after a wall
local WALL_GAP = 0.5 -- studs kept between the camera and a wall

local player = Players.LocalPlayer
local active = false
local yaw = 0
local pitch = 0
local blend = 1 -- 0 = at the eyes, 1 = fully out
local distance = 0 -- current camera distance along the offset, after walls
local turnedOff: Humanoid? = nil -- the humanoid we took AutoRotate from

local ThirdPerson = {}

function ThirdPerson.isActive(): boolean
	return active
end

local function humanoidOf(): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
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

-- On foot we turn the body ourselves; give turning back to the humanoid when we stop.
local function setAutoRotate(humanoid: Humanoid?)
	if turnedOff and turnedOff ~= humanoid then
		turnedOff.AutoRotate = true
		turnedOff = nil
	end
	if humanoid and turnedOff ~= humanoid then
		humanoid.AutoRotate = false
		turnedOff = humanoid
	end
end

local function setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	local camera = Workspace.CurrentCamera
	if on then
		if camera then
			local x, y = camera.CFrame:ToOrientation()
			pitch, yaw = x, y
			camera.CameraType = Enum.CameraType.Scriptable
		end
		blend = 0
		distance = 0
	else
		setAutoRotate(nil)
		Aim.setIgnored(nil)
		setBodyHidden(true)
		if camera then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local humanoid = humanoidOf()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not humanoid or not head or not head:IsA("BasePart") or not root or not root:IsA("BasePart") then
		setAutoRotate(nil)
		return -- dead or respawning: stay in third person, pick up again on the new body
	end
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	setBodyHidden(false)

	local delta = UserInputService:GetMouseDelta() * SENSITIVITY * UserInputService.MouseDeltaSensitivity
	yaw -= delta.X
	pitch = math.clamp(pitch - delta.Y, -PITCH_LIMIT, PITCH_LIMIT)
	local rotation = CFrame.fromOrientation(pitch, yaw, 0)

	local seat = humanoid.SeatPart
	local vehicle = if seat then Aim.prop(seat) or seat else nil
	Aim.setIgnored(vehicle)
	local ragdolled = humanoid:GetState() == Enum.HumanoidStateType.Physics
	if seat or ragdolled then
		setAutoRotate(nil)
	else
		setAutoRotate(humanoid)
		root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, yaw, 0)
	end

	-- Pull in when a wall is between the head and the camera; ease back out when it's clear.
	local eye = head.Position
	local wanted = rotation:VectorToWorldSpace(if seat then SEAT_OFFSET else FOOT_OFFSET)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { character :: Instance }
	if vehicle then
		table.insert(ignore, vehicle)
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(eye, wanted, params)
	local clear = if hit then math.max(hit.Distance - WALL_GAP, 0.5) else wanted.Magnitude
	distance = if clear < distance then clear else distance + (clear - distance) * math.min(1, dt * EASE_OUT)

	blend = math.min(1, blend + dt / BLEND_SECONDS)
	local out = wanted.Unit * distance * smoothstep(blend)
	camera.CFrame = rotation + eye + out
	camera.Focus = CFrame.new(eye)
end

function ThirdPerson.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			setActive(not active)
		elseif input.KeyCode == Enum.KeyCode.M then
			setActive(false) -- the main menu flies its own camera
		end
	end)

	RunService:BindToRenderStep("ThirdPersonCamera", Enum.RenderPriority.Camera.Value + 3, function(dt: number)
		if active then
			update(dt)
		end
	end)
end

return ThirdPerson
