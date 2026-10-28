--!strict
-- Walk / sprint / crouch / bunny hop. Ported from evil-nsapple/roblox-movement (MovementSystem.lua) and the
-- auto-bhop idea from the DevForum "Bhop & Air Movement Module" thread; both sources are logged in
-- docs/ASSETS.md. Kept to the parts we need: Shift sprints, Ctrl crouches, holding Space bunny hops.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local SPRINT_MULTIPLIER = 1.6
local CROUCH_MULTIPLIER = 0.5
local MOMENTUM_MAX = 8 -- extra studs/s kept from running and jumping
local MOMENTUM_GAIN = 30 -- per second while moving on the ground
local MOMENTUM_DECAY = 18 -- per second while standing still
local SPRINT_KEY = Enum.KeyCode.LeftShift
local CROUCH_KEY = Enum.KeyCode.LeftControl
local JUMP_KEY = Enum.KeyCode.Space

local player = Players.LocalPlayer

local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	local hum = humanoid
	local sprinting = false
	local crouching = false
	local momentum = 0
	local alive = true

	local connections: { RBXScriptConnection } = {}
	local function track(connection: RBXScriptConnection)
		table.insert(connections, connection)
	end

	track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == SPRINT_KEY then
			sprinting = true
		elseif input.KeyCode == CROUCH_KEY then
			crouching = true
		end
	end))
	track(UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == SPRINT_KEY then
			sprinting = false
		elseif input.KeyCode == CROUCH_KEY then
			crouching = false
		end
	end))
	track(hum.Died:Connect(function()
		alive = false
	end))
	track(character.Destroying:Connect(function()
		alive = false
	end))

	track(RunService.Heartbeat:Connect(function(dt)
		if not alive or hum.Health <= 0 then
			return
		end
		local speed = Config.WALK_SPEED
		if sprinting and not crouching then
			speed *= SPRINT_MULTIPLIER
		elseif crouching then
			speed *= CROUCH_MULTIPLIER
		end
		if hum.MoveDirection.Magnitude > 0 then
			momentum = math.min(MOMENTUM_MAX, momentum + MOMENTUM_GAIN * dt)
		else
			momentum = math.max(0, momentum - MOMENTUM_DECAY * dt)
		end
		hum.WalkSpeed = speed + momentum
		-- Crouching plants you; the jump key does nothing until you stand up.
		hum.JumpHeight = if crouching then 0 else Config.JUMP_HEIGHT

		-- Bunny hop: holding Space jumps again the moment you land, keeping the momentum.
		if
			not crouching
			and UserInputService:IsKeyDown(JUMP_KEY)
			and hum.FloorMaterial ~= Enum.Material.Air
			and hum:GetState() ~= Enum.HumanoidStateType.Jumping
			and hum:GetState() ~= Enum.HumanoidStateType.Freefall
			and not hum.SeatPart
		then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end))

	character.Destroying:Once(function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end)
end

local Movement = {}

function Movement.init()
	player.CharacterAdded:Connect(setup)
	if player.Character then
		task.spawn(setup, player.Character)
	end
end

return Movement
