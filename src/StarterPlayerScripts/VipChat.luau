--!strict
-- Gold [VIP] prefix in the chat for players who own the VIP pass. Runs on each client; the attribute is replicated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local PassCatalog = require(ReplicatedStorage.Shared.PassCatalog)

local VipChat = {}

function VipChat.init()
	local attribute = PassCatalog.attribute("vip")
	TextChatService.OnIncomingMessage = function(message: TextChatMessage): TextChatMessageProperties?
		local source = message.TextSource
		if not source then
			return nil
		end
		local player = Players:GetPlayerByUserId(source.UserId)
		if not player or player:GetAttribute(attribute) ~= true then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = `[VIP] {message.PrefixText or ""}`
		return properties
	end
end

return VipChat
