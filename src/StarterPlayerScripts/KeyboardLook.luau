--!strict
-- Arrow keys turn the camera and look up/down, so the game plays on a trackpad. The default camera reads its
-- look direction back from Camera.CFrame every frame, so turning the camera just before it updates sticks.
-- While on, the arrows no longer walk (WASD still does).
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local KEYS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.Down] = Vector2.new(0, -1),
}
local MAX_PITCH = math.rad(80)

local enabled = true
local speed = 2 -- radians per second
local held: { [Enum.KeyCode]: boolean } = {}

local KeyboardLook = {}

function KeyboardLook.setEnabled(on: boolean)
	enabled = on
	table.clear(held)
end

function KeyboardLook.isEnabled(): boolean
	return enabled
end

function KeyboardLook.setSpeed(radiansPerSecond: number)
	speed = radiansPerSecond
end

function KeyboardLook.speed(): number
	return speed
end

function KeyboardLook.init()
	ContextActionService:BindActionAtPriority(
		"KeyboardLook",
		function(_, state, input)
			if not enabled then
				return Enum.ContextActionResult.Pass
			end
			held[input.KeyCode] = state == Enum.UserInputState.Begin
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.Left,
		Enum.KeyCode.Right,
		Enum.KeyCode.Up,
		Enum.KeyCode.Down
	)

	RunService:BindToRenderStep("KeyboardLook", Enum.RenderPriority.Camera.Value - 1, function(dt: number)
		local turn = Vector2.zero
		for key, direction in KEYS do
			if held[key] then
				turn += direction
			end
		end
		local camera = Workspace.CurrentCamera
		if turn == Vector2.zero or not camera or camera.CameraType ~= Enum.CameraType.Custom then
			return
		end
		local look = camera.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z) - turn.X * speed * dt
		local pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)) + turn.Y * speed * dt, -MAX_PITCH, MAX_PITCH)
		camera.CFrame = CFrame.new(camera.CFrame.Position) * CFrame.fromOrientation(pitch, yaw, 0)
	end)
end

return KeyboardLook
