--!strict
-- C: third person, on foot or in a seat; C again goes back to first person. On foot it is an over-the-shoulder
-- camera and the body turns with it, so you face where you aim; in a seat it is a chase camera behind your head
-- (the car turns you). The mouse stays locked to the centre, so the crosshair, guns and tools aim exactly as in
-- first person. It blends in from your eyes, eases back out after a wall pushed it in, and stays on through
-- respawns; the main menu (M) switches it off.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Aim = require(script.Parent.Aim)
local Config = require(ReplicatedStorage.Shared.Config)

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
local ragdollCam = false -- floppy or dead: follow the torso instead of the head, from first person too
local ragdollForced = false -- third person was off when the ragdoll started, so it goes off again after
local focus: Vector3? = nil -- smoothed point the camera looks at while following a ragdoll and for a moment after
local FOCUS_SETTLE = 9 -- per second, how fast the focus glides back to the head after the ragdoll
local BODY_REFRESH = 0.5 -- seconds between full-body transparency sweeps (new accessories, a new character)
local FADE_NEAR = 2.5 -- studs; body parts closer to the camera than this fade out so it never sits inside one

local bodyTimer = 0 -- counts down to the next setBodyHidden(false) sweep
local bodyOf: Model? = nil
local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude

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
	focus = nil
	bodyTimer = 0
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

-- Body parts too close to the camera fade out, so a flopping arm or the head never fills the screen.
local function fadeNearCamera(character: Model, from: Vector3)
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local near = (part.Position - from).Magnitude
			part.LocalTransparencyModifier = math.clamp(1 - (near - 1) / (FADE_NEAR - 1), 0, 1)
		end
	end
end

-- Smoothly move `focus` toward `target` (a new focus starts where the camera already was, so nothing snaps).
local function glide(from: Vector3?, target: Vector3, rate: number, dt: number): Vector3
	return if from then from:Lerp(target, 1 - math.exp(-rate * dt)) else target
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local humanoid = humanoidOf()
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or root)
	if
		not camera
		or (not humanoid and not ragdollCam)
		or not head
		or not head:IsA("BasePart")
		or not root
		or not root:IsA("BasePart")
		or not torso
		or not torso:IsA("BasePart")
	then
		setAutoRotate(nil)
		return -- respawning: stay in third person, pick up again on the new body
	end
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	local delta = UserInputService:GetMouseDelta() * SENSITIVITY * UserInputService.MouseDeltaSensitivity
	yaw -= delta.X
	pitch = math.clamp(pitch - delta.Y, -PITCH_LIMIT, PITCH_LIMIT)
	local rotation = CFrame.fromOrientation(pitch, yaw, 0)

	local seat = if humanoid then humanoid.SeatPart else nil
	local vehicle = if seat then Aim.prop(seat) or seat else nil
	Aim.setIgnored(vehicle)
	local ragdolled = ragdollCam or (humanoid ~= nil and humanoid:GetState() == Enum.HumanoidStateType.Physics)
	if humanoid and not seat and not ragdolled then
		setAutoRotate(humanoid)
		root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, yaw, 0)
	else
		setAutoRotate(nil)
	end

	-- A ragdoll is followed at the torso, smoothed, from straight behind; the head would whip the view around.
	-- After it, the focus glides back to the head instead of jumping there.
	local eye: Vector3
	if ragdollCam then
		focus = glide(focus or head.Position, torso.Position + Vector3.yAxis, Config.RAGDOLL_CAMERA_FOLLOW, dt)
		eye = focus :: Vector3
	elseif focus then
		focus = glide(focus, head.Position, FOCUS_SETTLE, dt)
		eye = focus :: Vector3
		if (eye - head.Position).Magnitude < 0.1 then
			focus = nil
		end
	else
		eye = head.Position
	end
	if bodyOf ~= character then
		bodyOf = character
		bodyTimer = 0
	end
	bodyTimer -= dt
	if bodyTimer <= 0 then
		bodyTimer = BODY_REFRESH
		setBodyHidden(false)
	end

	-- Pull in when a wall is between the eye and the camera; ease back out when it's clear.
	local wanted = rotation:VectorToWorldSpace(
		if ragdollCam
			then Vector3.new(0, 1.5, Config.RAGDOLL_CAMERA_DISTANCE)
			elseif seat then SEAT_OFFSET
			else FOOT_OFFSET
	)
	local ignore: { Instance } = { character :: Instance }
	if vehicle then
		table.insert(ignore, vehicle)
	end
	castParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(eye, wanted, castParams)
	local clear = if hit then math.max(hit.Distance - WALL_GAP, 0.5) else wanted.Magnitude
	distance = if clear < distance then clear else distance + (clear - distance) * math.min(1, dt * EASE_OUT)

	blend = math.min(1, blend + dt / BLEND_SECONDS)
	local out = wanted.Unit * distance * smoothstep(blend)
	camera.CFrame = rotation + eye + out
	camera.Focus = CFrame.new(eye)
	if ragdolled and character then
		fadeNearCamera(character, camera.CFrame.Position)
	end
end

-- Floppy or dead: the camera follows the torso in third person, even if the player was in first person.
-- Back to normal (first person again, if that is where they were) when it ends.
function ThirdPerson.setRagdoll(on: boolean)
	if on == ragdollCam then
		return
	end
	ragdollCam = on
	bodyTimer = 0 -- clear the near-camera fade at once when the ragdoll ends
	if on then
		ragdollForced = not active
		setActive(true)
	elseif ragdollForced then
		setActive(false)
	end
end

function ThirdPerson.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			if not ragdollCam then
				setActive(not active)
			end
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
