--!strict
-- Q toggles the spawn list, click a prop to spawn it at the crosshair, X removes the prop you look at.
-- UI is built in code because Rojo can't author GUI instances; the shell is small, rows are data-driven.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Aim = require(script.Parent.Parent.Aim)
local Feedback = require(script.Parent.Feedback)
local Net = require(script.Parent.Parent.Net)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Config = require(ReplicatedStorage.Shared.Config)
local NpcCatalog = require(ReplicatedStorage.Shared.NpcCatalog)
local PassCatalog = require(ReplicatedStorage.Shared.PassCatalog)
local PropCatalog = require(ReplicatedStorage.Shared.PropCatalog)

local THEME = Ui.THEME
local make = Ui.make
local label = Ui.label

local AIM_RANGE = Config.SPAWN_RANGE * 0.6
local TOAST_SECONDS = 2.5

local player = Players.LocalPlayer

local SpawnMenu = {}

function SpawnMenu.init()
	local spawnRemote = Net.event("SpawnProp")
	local removeRemote = Net.event("RemoveProp")
	local clearRemote = Net.event("ClearMine")
	local notifyRemote = Net.event("Notify")
	local spawnNpcRemote = Net.event("SpawnNpc")

	local gui = make("ScreenGui", { Name = "SandboxMenu", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))

	-- Spawn list window
	local window = Ui.window("Spawn", gui, false, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.new(0, 270, 0.7, 0),
		Visible = false,
	})
	local panel = window.frame
	make("UISizeConstraint", { MinSize = Vector2.new(230, 260), MaxSize = Vector2.new(320, 660) }, panel)

	-- Props and NPCs are tabs; each tab is its own list so a row's own Visible (locked, secret) is never fought over.
	local listProps = { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -72) }
	local propList = Ui.list(window.body, listProps)
	local npcList = Ui.list(window.body, listProps)
	npcList.Visible = false
	Ui.tabs({ "Props", "NPCs" }, window.body, function(name: string)
		propList.Visible = name == "Props"
		npcList.Visible = name == "NPCs"
	end)
	local order = 0
	local function heading(text: string)
		order += 1
		local title = label(text, propList, {
			Size = UDim2.new(1, 0, 0, 24),
			TextSize = 15,
			Font = THEME.bold,
			TextColor3 = THEME.accentText,
			LayoutOrder = order,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, title)
	end
	local lastCategory = ""
	for _, def in PropCatalog.list do
		if def.category ~= lastCategory then
			lastCategory = def.category
			heading(def.category)
		end
		order += 1
		local row = Ui.row(def.name, propList, order)
		row.button.Name = def.id
		local pass = if def.pass then PassCatalog.byKey[def.pass] else nil
		if pass then
			local attribute = PassCatalog.attribute(pass.key)
			local function refresh()
				local owned = player:GetAttribute(attribute) == true
				row.button.Text = if owned then def.name else `{def.name}  (locked - R${pass.price})`
				row.button.TextColor3 = if owned then THEME.text else THEME.muted
			end
			player:GetAttributeChangedSignal(attribute):Connect(refresh)
			refresh()
		end
		row.button.Activated:Connect(function()
			if pass and player:GetAttribute(PassCatalog.attribute(pass.key)) ~= true then
				MarketplaceService:PromptGamePassPurchase(player, pass.id)
				return
			end
			local point = SpawnMenu.aimPoint()
			if point then
				spawnRemote:FireServer(def.id, point)
			end
		end)
	end
	for _, def in NpcCatalog.list do
		order += 1
		local row = Ui.row(def.name, npcList, order)
		row.button.Name = `npc_{def.id}`
		row.button.Activated:Connect(function()
			local point = SpawnMenu.aimPoint()
			if point then
				spawnNpcRemote:FireServer(def.id, point)
			end
		end)
		if def.secret then
			local function refresh()
				row.button.Visible = player:GetAttribute(Config.SECRET_ATTRIBUTE) == true
			end
			player:GetAttributeChangedSignal(Config.SECRET_ATTRIBUTE):Connect(refresh)
			refresh()
		end
	end

	-- Physgun Colors: a swatch row that cycles the palette. VIP's gold beam overrides it (shown in the label).
	order += 1
	local beamRow = Ui.row("Beam color", propList, order)
	local swatch = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(22, 16),
		BackgroundColor3 = THEME.text,
		BorderSizePixel = 0,
	}, beamRow.button)
	make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, swatch)
	make("UICorner", { CornerRadius = UDim.new(0, 2) }, swatch)
	local beamRemote = Net.event("SetBeamColor")
	local colorsAttribute = PassCatalog.attribute("physgun_colors")
	local vipAttribute = PassCatalog.attribute("vip")
	local function refreshBeam()
		local owned = player:GetAttribute(colorsAttribute) == true
		beamRow.button.Visible = owned
		if not owned then
			return
		end
		local index = player:GetAttribute(Config.BEAM_COLOR_ATTRIBUTE)
		if typeof(index) ~= "number" or not Config.PALETTE[index] then
			index = 1
		end
		local vip = player:GetAttribute(vipAttribute) == true
		local rgb = if vip then Config.VIP_BEAM_COLOR else Config.PALETTE[index] :: { number }
		swatch.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		beamRow.button.Text = if vip then "Beam color (VIP gold)" else "Beam color"
	end
	beamRow.button.Activated:Connect(function()
		if player:GetAttribute(colorsAttribute) ~= true then
			return
		end
		local index = player:GetAttribute(Config.BEAM_COLOR_ATTRIBUTE)
		if typeof(index) ~= "number" then
			index = 0
		end
		beamRemote:FireServer(index % #Config.PALETTE + 1)
	end)
	player:GetAttributeChangedSignal(colorsAttribute):Connect(refreshBeam)
	player:GetAttributeChangedSignal(vipAttribute):Connect(refreshBeam)
	player:GetAttributeChangedSignal(Config.BEAM_COLOR_ATTRIBUTE):Connect(refreshBeam)
	refreshBeam()

	local clearButton = Ui.button("Remove all mine", window.body, false, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(0.6, -3, 0, 30),
		Modal = true, -- frees the first-person mouse while the menu is open
	})
	clearButton.Activated:Connect(function()
		clearRemote:FireServer()
	end)
	Ui.tooltip(clearButton, "Deletes every prop you spawned")
	local feedbackButton = Ui.button("Feedback", window.body, false, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(0.4, -3, 0, 30),
	})
	feedbackButton.Activated:Connect(Feedback.open)
	Ui.tooltip(feedbackButton, "Send a bug or idea to the developer")

	-- HUD: prop count + key hints
	local hud = label("", gui, {
		Position = UDim2.fromOffset(16, 60), -- under Roblox's top bar, clear of the selector
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 16,
		TextColor3 = THEME.muted,
		TextStrokeTransparency = 0.6,
	})
	local function updateHud()
		local count = player:GetAttribute(Config.COUNT_ATTRIBUTE) or 0
		local cap = if player:GetAttribute(PassCatalog.attribute("builder_plus")) == true
			then Config.VIP_PROP_CAP
			else Config.PROP_CAP
		hud.Text =
			`Props {count}/{cap}    Q spawn menu    X remove aimed prop    1-6 weapons    G ragdoll    C third person    M menu    build {Config.BUILD}`
	end
	player:GetAttributeChangedSignal(Config.COUNT_ATTRIBUTE):Connect(updateHud)
	player:GetAttributeChangedSignal(PassCatalog.attribute("builder_plus")):Connect(updateHud)
	updateHud()

	-- Server messages: a small Source panel under the top bar.
	local toast = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = THEME.dark,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = THEME.radius }, toast)
	make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toast)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, toast)
	local toastText = label("", toast, {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = THEME.semibold,
		TextColor3 = THEME.accentText,
	})
	local toastId = 0
	notifyRemote.OnClientEvent:Connect(function(message: unknown)
		if typeof(message) ~= "string" then
			return
		end
		toastId += 1
		local id = toastId
		toastText.Text = message
		Sfx.play("deny")
		toast.Visible = true
		task.delay(TOAST_SECONDS, function()
			if toastId == id then
				toast.Visible = false
			end
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			panel.Visible = not panel.Visible
		elseif input.KeyCode == Enum.KeyCode.X then
			local hit = Aim.cast(AIM_RANGE)
			local result = hit and hit.result
			local prop = result and Aim.prop(result.Instance)
			if prop then
				removeRemote:FireServer(prop)
			end
		end
	end)
end

-- Crosshair hit point, pulled back inside the server's spawn range of our character.
function SpawnMenu.aimPoint(): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local hit = Aim.cast(AIM_RANGE)
	if not hit or not root or not root:IsA("BasePart") then
		return nil
	end
	local point = if hit.result then hit.result.Position else hit.origin + hit.direction * AIM_RANGE

	local offset = point - root.Position
	local maxDistance = Config.SPAWN_RANGE - 5
	if offset.Magnitude > maxDistance then
		point = root.Position + offset.Unit * maxDistance
	end
	return point
end

return SpawnMenu
