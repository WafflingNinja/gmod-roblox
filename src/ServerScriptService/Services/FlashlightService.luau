--!strict
-- F toggles a flashlight on your head. The server makes the SpotLight so everyone sees it; the client only asks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RateLimiter = require(script.Parent.RateLimiter)
local Validate = require(script.Parent.Validate)

local toggleRemote = ReplicatedStorage.Remotes.Flashlight :: RemoteEvent
local limiter = RateLimiter.new(Config.FLASHLIGHT_BUCKET_CAPACITY, Config.FLASHLIGHT_REFILL_PER_SECOND)

-- The light is created on first use and lives on the head, so it goes away with the character.
local function lightOf(character: Model): SpotLight?
	local head = character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local existing = head:FindFirstChild(Config.FLASHLIGHT_NAME)
	if existing and existing:IsA("SpotLight") then
		return existing
	end
	local light = Instance.new("SpotLight")
	light.Name = Config.FLASHLIGHT_NAME
	light.Brightness = 3
	light.Range = 60
	light.Angle = 55
	light.Shadows = true
	light.Enabled = false
	light.Parent = head
	return light
end

local FlashlightService = {}

function FlashlightService.init()
	toggleRemote.OnServerEvent:Connect(function(player: Player, on: unknown)
		if typeof(on) ~= "boolean" or not limiter:consume(player, 1) then
			return
		end
		local character = player.Character
		if not character or not Validate.aliveRoot(player) then
			return
		end
		local light = lightOf(character)
		if light then
			light.Enabled = on
		end
	end)
end

return FlashlightService
