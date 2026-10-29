--!strict
-- Owns every game pass and developer product: checks ownership on join, grants immediately after a purchase,
-- and handles tip receipts. Ownership lives on the Player as Pass_<key> attributes (replicated, so the client
-- can show Owned / locked states). Perks ask Passes.has(); they never trust a client flag.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PassCatalog = require(ReplicatedStorage.Shared.PassCatalog)
local RateLimiter = require(script.Parent.RateLimiter)
local Validate = require(script.Parent.Validate)

local remotes = ReplicatedStorage.Remotes
local notifyRemote = remotes.Notify :: RemoteEvent
local sayRemote = remotes.NpcSay :: RemoteEvent
local beamRemote = remotes.SetBeamColor :: RemoteEvent

local RETRIES = 3
local beamLimiter = RateLimiter.new(Config.BEAM_BUCKET_CAPACITY, Config.BEAM_REFILL_PER_SECOND)

local Passes = {}

local function notify(player: Player, message: string)
	notifyRemote:FireClient(player, message)
end

function Passes.has(player: Player, key: string): boolean
	return player:GetAttribute(PassCatalog.attribute(key)) == true
end

-- Beam colour the server actually uses. VIP's gold wins over a chosen palette colour.
function Passes.beamColor(player: Player): Color3?
	if Passes.has(player, "vip") then
		local gold = Config.VIP_BEAM_COLOR
		return Color3.fromRGB(gold[1], gold[2], gold[3])
	end
	if not Passes.has(player, "physgun_colors") then
		return nil
	end
	local index = player:GetAttribute(Config.BEAM_COLOR_ATTRIBUTE)
	if typeof(index) ~= "number" or index % 1 ~= 0 or not Config.PALETTE[index] then
		return nil
	end	local rgb = Config.PALETTE[index]
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Small gold VIP tag above the head. Client-visible, so every player sees it.
local function applyVipTag(player: Player)
	if not Passes.has(player, "vip") then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") or head:FindFirstChild("VipTag") then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VipTag"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(96, 22)
	billboard.StudsOffset = Vector3.new(0, 2.9, 0)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "VIP"
	label.Font = Enum.Font.SourceSansBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 214, 92)
	label.TextStrokeTransparency = 0.35
	label.Parent = billboard
	billboard.Parent = head
end

-- Gold trail behind VIP characters. Purely cosmetic, but visible from every angle and at every distance.
local function applyVipTrail(player: Player)
	if not Passes.has(player, "vip") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or root:FindFirstChild("VipTrail") then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = "VipTrailTop"
	top.Position = Vector3.new(0, 1.4, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "VipTrailBottom"
	bottom.Position = Vector3.new(0, -1.4, 0)
	bottom.Parent = root
	local rgb = Config.VIP_BEAM_COLOR
	local gold = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	local trail = Instance.new("Trail")
	trail.Name = "VipTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(gold, Color3.fromRGB(255, 242, 190))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.Lifetime = 0.45
	trail.MinLength = 0.1
	trail.LightEmission = 0.35
	trail.FaceCamera = true
	trail.Parent = root
end

local function applyVipCosmetics(player: Player)
	applyVipTag(player)
	applyVipTrail(player)
end

local function grant(player: Player, key: string)
	if player.Parent == nil then
		return
	end
	player:SetAttribute(PassCatalog.attribute(key), true)
	print(`Passes: {key} -> {player.Name} ({player.UserId})`)
	if key == "vip" then
		applyVipCosmetics(player)
	end
end

local function owns(player: Player, id: number): boolean
	for attempt = 1, RETRIES do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if ok then
			return result == true
		end
		if attempt < RETRIES then
			task.wait(2 ^ attempt)
			if player.Parent == nil then
				return false
			end
		end
	end
	warn(`Passes: could not check ownership for {player.UserId} pass {id}`)
	return false
end

-- All passes are checked at once; checking them one by one stacked up to six slow calls before VIP landed.
-- `pending` counts grants still in flight; a task spawned here can finish before the next one is started,
-- so the counter must never go below zero or the wait below ends early and PASSES_CHECKED lands before
-- every grant did.
local function refresh(player: Player)
	local pending = #PassCatalog.passes
	for _, item in PassCatalog.passes do
		task.spawn(function()
			if player.Parent ~= nil and owns(player, item.id) then
				grant(player, item.key)
			end
			pending = math.max(pending - 1, 0)
		end)
	end
	while pending > 0 and player.Parent ~= nil do
		task.wait()
	end
	if player.Parent ~= nil then
		player:SetAttribute(Config.PASSES_CHECKED_ATTRIBUTE, true)
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function()
		applyVipCosmetics(player)
	end)
	task.spawn(refresh, player)
end

function Passes.init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			local item = PassCatalog.passById[passId]
			if item then
				grant(player, item.key)
			end
		end
	)

	MarketplaceService.ProcessReceipt = function(
		receipt: { ProductId: number, PlayerId: number }
	): Enum.ProductPurchaseDecision
		local item = PassCatalog.productById[receipt.ProductId]
		if not item then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		-- The receipt is delivered at most once per purchase. If the buyer left before it landed,
		-- returning NotProcessedYet would hand Roblox a receipt it can never complete and the tip
		-- would be lost. The purchase itself is the reward here; acknowledge it without messaging.
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			print(`Passes: {item.key} tip from a player who already left ({receipt.PlayerId})`)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		notify(player, `Thanks for the {item.name}!`)
		-- A thank-you line, said to the buyer directly (nil model = not from a body).
		sayRemote:FireClient(player, nil, "rostik_greet_1")
		print(`Passes: {item.key} tip from {player.Name} ({player.UserId})`)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	beamRemote.OnServerEvent:Connect(function(player: Player, rawIndex: unknown)
		if not beamLimiter:consume(player, 1) then
			return
		end
		-- 1..#PALETTE integer; Validate.isFiniteNumber rejects NaN/inf before the range check.
		if typeof(rawIndex) ~= "number" or not Validate.isFiniteNumber(rawIndex, #Config.PALETTE) then
			return
		end
		if rawIndex % 1 ~= 0 or rawIndex < 1 then
			return
		end
		if not Passes.has(player, "physgun_colors") then
			return
		end
		player:SetAttribute(Config.BEAM_COLOR_ATTRIBUTE, rawIndex)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return Passes
