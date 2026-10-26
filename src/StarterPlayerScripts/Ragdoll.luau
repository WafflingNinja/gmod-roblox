--!strict
-- G asks the server to ragdoll or stand up. The server swaps the joints; we own the Humanoid,
-- so we switch its state when the server says so.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Net)

local RAGDOLL_KEY = Enum.KeyCode.G

local Ragdoll = {}

function Ragdoll.init()
	local player = Players.LocalPlayer
	local toggle = Net.event("RagdollToggle")
	local state = Net.event("RagdollState")

	state.OnClientEvent:Connect(function(on: unknown)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if typeof(on) ~= "boolean" or not humanoid or humanoid.Health <= 0 then
			return
		end
		humanoid:ChangeState(if on then Enum.HumanoidStateType.Physics else Enum.HumanoidStateType.GettingUp)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == RAGDOLL_KEY then
			toggle:FireServer()
		end
	end)
end

return Ragdoll
