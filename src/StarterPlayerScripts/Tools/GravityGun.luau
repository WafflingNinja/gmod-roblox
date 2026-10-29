--!strict
-- RMB: pull a far prop, or hold a near one (RMB again drops). LMB: punt, or throw the held prop.
-- The server decides pull vs hold and computes every impulse; we only predict the hold for aim updates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Aim = require(script.Parent.Parent.Aim)
local Net = require(script.Parent.Parent.Net)
local ToolHud = require(script.Parent.Parent.UI.ToolHud)
local WeaponSelect = require(script.Parent.Parent.UI.WeaponSelect)
local Config = require(ReplicatedStorage.Shared.Config)

local SEND_INTERVAL = 0.05
local EYE_OFFSET = Vector3.new(0, 1.5, 0)

local GravityGun = {}

function GravityGun.start(): () -> ()
	local pull = Net.event("GravityPull")
	local punt = Net.event("GravityPunt")
	local aim = Net.unreliable("PhysgunAim")
	local player = Players.LocalPlayer

	local holding: BasePart? = nil
	local rotation = CFrame.identity -- held prop rotation relative to the camera
	local sinceSend = 0

	local function rootPart(): BasePart?
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root else nil
	end

	ToolHud.setCrosshair(true)

	local connections: { RBXScriptConnection } = {}

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or WeaponSelect.isOpen() then
				return
			end
			local camera = Workspace.CurrentCamera
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				if holding then
					pull:FireServer()
					holding = nil
					return
				end
				local hit = Aim.cast(Config.GRAVGUN_PULL_RANGE)
				local result = hit and hit.result
				local prop = result and Aim.prop(result.Instance)
				local root = rootPart()
				if not prop or not root or not camera then
					return
				end
				pull:FireServer(prop)
				if (prop.Position - root.Position).Magnitude <= Config.GRAVGUN_HOLD_RANGE then
					holding = prop
					rotation = camera.CFrame.Rotation:Inverse() * prop.CFrame.Rotation
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 and camera then
				if holding then
					punt:FireServer(holding, camera.CFrame.LookVector)
					holding = nil
					return
				end
				local hit = Aim.cast(Config.GRAVGUN_PUNT_RANGE)
				local result = hit and hit.result
				local prop = result and Aim.prop(result.Instance)
				if hit and prop then
					punt:FireServer(prop, hit.direction.Unit)
				end
			end
		end)
	)

	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			local camera = Workspace.CurrentCamera
			local root = rootPart()
			if holding and not holding.Parent then
				holding = nil -- the prop was removed; the next RMB pulls again instead of "dropping"
			end
			if not holding or not camera or not root then
				return
			end
			local point = root.Position + EYE_OFFSET + camera.CFrame.LookVector * Config.GRAVGUN_HOLD_DISTANCE
			local target = CFrame.new(point) * camera.CFrame.Rotation * rotation
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
		holding = nil -- the server releases on unequip
		ToolHud.setCrosshair(false)
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

return GravityGun
