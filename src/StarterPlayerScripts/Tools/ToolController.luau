--!strict
-- Starts a tool's client logic when the Tool is equipped (enters the character), stops it when it leaves.
-- Also owns the thruster key and the server's selection highlight.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Parent.Net)
local ToolHud = require(script.Parent.Parent.UI.ToolHud)
local Config = require(ReplicatedStorage.Shared.Config)
local GravityGun = require(script.Parent.GravityGun)
local Physgun = require(script.Parent.Physgun)
local Toolgun = require(script.Parent.Toolgun)

local THRUSTER_KEY = Enum.KeyCode.F

local starters: { [string]: () -> () -> () } = {
	[Config.PHYSGUN] = Physgun.start,
	[Config.TOOLGUN] = Toolgun.start,
	[Config.GRAVGUN] = GravityGun.start,
}

local ToolController = {}

function ToolController.init()
	local player = Players.LocalPlayer
	local thrusters = Net.event("ThrustersHeld")
	local select = Net.event("ToolSelect")

	select.OnClientEvent:Connect(function(instance: unknown)
		ToolHud.select(if typeof(instance) == "Instance" then instance else nil)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == THRUSTER_KEY then
			thrusters:FireServer(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == THRUSTER_KEY then
			thrusters:FireServer(false)
		end
	end)

	local function watch(character: Model)
		local stops: { [Instance]: () -> () } = {}

		local function equipped(child: Instance)
			if not child:IsA("Tool") then
				return
			end
			local start = starters[child.Name]
			if start and not stops[child] then
				stops[child] = start()
			end
		end

		character.ChildAdded:Connect(equipped)
		character.ChildRemoved:Connect(function(child)
			local stop = stops[child]
			if stop then
				stops[child] = nil
				stop()
			end
		end)
		-- Descendants are not "removed" when the whole character is destroyed.
		character.Destroying:Once(function()
			for _, stop in stops do
				stop()
			end
			table.clear(stops)
		end)
		for _, child in character:GetChildren() do
			equipped(child)
		end
	end

	player.CharacterAdded:Connect(watch)
	if player.Character then
		watch(player.Character)
	end
end

return ToolController
