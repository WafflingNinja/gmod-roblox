--!strict
-- In-game feedback: one message per minute per player, stored in the "Feedback" DataStore and printed to the
-- server log. Never shown to other players.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local RateLimiter = require(script.Parent.RateLimiter)

local sendRemote = ReplicatedStorage.Remotes.SendFeedback :: RemoteEvent
local notifyRemote = ReplicatedStorage.Remotes.Notify :: RemoteEvent
-- An unpublished place throws here. Feedback still prints to the server log; only the DataStore copy is skipped.
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("Feedback")
	end)
	if ok then
		store = result
	else
		warn(`Feedback: DataStore unavailable, feedback will only be logged: {result}`)
	end
end
local limiter = RateLimiter.new(1, 1 / Config.FEEDBACK_COOLDOWN)

-- Valid UTF-8 only, control characters out, trimmed, at most FEEDBACK_MAX characters.
local function clean(raw: string): string?
	if not utf8.len(raw) then
		return nil
	end
	local text = string.gsub(raw, "%c", " ")
	text = string.match(text, "^%s*(.-)%s*$") or ""
	local cut = utf8.offset(text, Config.FEEDBACK_MAX + 1)
	if cut then
		text = string.sub(text, 1, cut - 1)
	end
	return if text ~= "" then text else nil
end

local FeedbackService = {}

function FeedbackService.init()
	sendRemote.OnServerEvent:Connect(function(player: Player, raw: unknown)
		if not limiter:consume(player, 1) then
			return
		end
		if typeof(raw) ~= "string" or #raw > Config.FEEDBACK_MAX * 4 then
			return
		end
		local text = clean(raw)
		if not text then
			return
		end
		print(string.format("Feedback %d: %q", player.UserId, text))
		local db = store
		if db then
			local ok, err = pcall(function()
				db:SetAsync(`{os.time()}-{player.UserId}`, { userId = player.UserId, text = text })
			end)
			if not ok then
				warn(`Feedback: save failed for {player.UserId}: {err}`)
			end
		end
		notifyRemote:FireClient(player, "Thanks, feedback sent.")
	end)
end

return FeedbackService
