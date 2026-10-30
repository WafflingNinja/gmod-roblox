--!strict
-- F turns your flashlight on or off. The light itself is made and shown by the server; we only ask.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Net = require(script.Parent.Net)

local Flashlight = {}

function Flashlight.init()
	local toggle = Net.event("Flashlight")
	local on = false
	-- The server's light dies with the character, so a new body starts off.
	Players.LocalPlayer.CharacterAdded:Connect(function()
		on = false
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.F then
			return
		end
		on = not on
		toggle:FireServer(on)
	end)
end

return Flashlight
