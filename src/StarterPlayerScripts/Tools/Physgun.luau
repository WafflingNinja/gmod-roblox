--!strict
-- LMB hold: grab the prop under the crosshair. Wheel: push/pull. Hold R + move mouse: rotate.
-- RMB while holding: freeze in place. The server clamps and caps everything we send.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Aim = require(script.Parent.Parent.Aim)
local Net = require(script.Parent.Parent.Net)
local ToolHud = require(script.Parent.Parent.UI.ToolHud)
local WeaponSelect = require(script.Parent.Parent.UI.WeaponSelect)
local Config = require(ReplicatedStorage.Shared.Config)

local SEND_INTERVAL = 0.05
local WHEEL_STEP = 2
local ROTATE_SPEED = 0.01

local Physgun = {}

-- Called when the Physgun enters the character. Returns the function that undoes everything.
function Physgun.start(): () -> ()
	local grab = Net.event("PhysgunGrab")
	local release = Net.event("PhysgunRelease")
	local freeze = Net.event("PhysgunFreeze")
	local aim = Net.unreliable("PhysgunAim")

	local holding: BasePart? = nil
	local holdDistance = 20
	local rotation = CFrame.identity
	local rotating = false
	local sinceSend = 0

	local function drop()
		if holding then
			release:FireServer()
			holding = nil
		end
	end

	-- First person turns the view with the mouse; freeze the camera while the mouse rotates the prop.
	-- The camera type and mouse behaviour are saved and restored, so releasing R in third person (or under a
	-- menu's own camera) does not force the default camera back on.
	local savedCameraType: Enum.CameraType? = nil
	local savedMouse: Enum.MouseBehavior? = nil
	local function setRotating(on: boolean)
		if rotating == on then
			return
		end
		rotating = on
		local camera = Workspace.CurrentCamera
		if on then
			savedCameraType = if camera then camera.CameraType else nil
			savedMouse = UserInputService.MouseBehavior
			if camera then
				camera.CameraType = Enum.CameraType.Scriptable
			end
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		else
			if camera and savedCameraType then
				camera.CameraType = savedCameraType
			end
			UserInputService.MouseBehavior = savedMouse or Enum.MouseBehavior.Default
			savedCameraType = nil
			savedMouse = nil
		end
	end

	ToolHud.setCrosshair(true)

	local connections: { RBXScriptConnection } = {}

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or WeaponSelect.isOpen() then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseButton1 and not holding then
				local hit = Aim.cast(Config.GRAB_RANGE)
				local result = hit and hit.result
				local prop = result and Aim.prop(result.Instance)
				if hit and prop then
					holding = prop
					holdDistance = math.clamp((prop.Position - hit.origin).Magnitude, Config.HOLD_MIN, Config.HOLD_MAX)
					rotation = prop.CFrame.Rotation
					grab:FireServer(prop)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 and holding then
				freeze:FireServer()
				holding = nil
			elseif input.KeyCode == Enum.KeyCode.R and holding then
				setRotating(true)
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				drop()
				setRotating(false)
			elseif input.KeyCode == Enum.KeyCode.R then
				setRotating(false)
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if not holding or WeaponSelect.isOpen() then
				return
			end
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				holdDistance =
					math.clamp(holdDistance + input.Position.Z * WHEEL_STEP, Config.HOLD_MIN, Config.HOLD_MAX)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement and rotating then
				local camera = Workspace.CurrentCamera
				if camera then
					local yaw = CFrame.fromAxisAngle(Vector3.yAxis, -input.Delta.X * ROTATE_SPEED)
					local pitch = CFrame.fromAxisAngle(camera.CFrame.RightVector, -input.Delta.Y * ROTATE_SPEED)
					rotation = yaw * pitch * rotation
				end
			end
		end)
	)

	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end
			if not holding then
				return
			end
			if not holding.Parent then
				-- The prop was removed under us (X tool, undo, Clear): let go so the next LMB grabs again
				-- instead of aiming a dead hold at a hole. drop() sends the release before clearing.
				drop()
				setRotating(false)
				return
			end
			local point = camera.CFrame.Position + camera.CFrame.LookVector * holdDistance
			local target = CFrame.new(point) * rotation
			Aim.moveHoldTarget(target)
			sinceSend += dt
			if sinceSend < SEND_INTERVAL then
				return
			end
			sinceSend = 0
			aim:FireServer(target)
		end)
	)

	return function()
		drop()
		setRotating(false)
		ToolHud.setCrosshair(false)
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

return Physgun
