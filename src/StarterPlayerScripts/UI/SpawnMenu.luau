--!strict
-- Q toggles the spawn list, click a prop to spawn it at the crosshair, X removes the prop you look at.
-- UI is built in code because Rojo can't author GUI instances; the shell is small, rows are data-driven.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Aim = require(script.Parent.Parent.Aim)
local Net = require(script.Parent.Parent.Net)
local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Config = require(ReplicatedStorage.Shared.Config)
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

	local gui = make("ScreenGui", { Name = "SandboxMenu", ResetOnSpawn = false }, player:WaitForChild("PlayerGui"))

	-- Spawn list panel
	local panel = make("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.new(0, 260, 0.7, 0),
		BackgroundColor3 = THEME.panel,
		Visible = false,
	}, gui)
	make("UISizeConstraint", { MinSize = Vector2.new(220, 240), MaxSize = Vector2.new(320, 640) }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, panel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, panel)
	label("Spawn", panel, { Size = UDim2.new(1, 0, 0, 24), TextSize = 20 })

	local list = make("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -76),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", { PaddingRight = UDim.new(0, 8) }, list)

	local lastCategory = ""
	for index, def in PropCatalog.list do
		if def.category ~= lastCategory then
			lastCategory = def.category
			label(string.upper(def.category), list, {
				Size = UDim2.new(1, 0, 0, 22),
				TextSize = 12,
				TextColor3 = THEME.accent,
				LayoutOrder = index * 2 - 1,
			})
		end
		local row = make("TextButton", {
			Name = def.id,
			Text = def.name,
			Font = THEME.font,
			TextSize = 15,
			TextColor3 = THEME.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = THEME.row,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = index * 2,
		}, list)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, row)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, row)
		row.Activated:Connect(function()
			local point = SpawnMenu.aimPoint()
			if point then
				spawnRemote:FireServer(def.id, point)
			end
		end)
	end

	local clearButton = make("TextButton", {
		Text = "Remove all mine",
		Font = THEME.font,
		TextSize = 15,
		TextColor3 = THEME.text,
		BackgroundColor3 = THEME.row,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 34),
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 4) }, clearButton)
	clearButton.Activated:Connect(function()
		clearRemote:FireServer()
	end)

	-- HUD: prop count + key hints
	local hud = label("", gui, {
		Position = UDim2.fromOffset(16, 60), -- under Roblox's top bar, clear of the hotbar
		Size = UDim2.fromOffset(0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 14,
		TextColor3 = THEME.muted,
	})
	local function updateHud()
		local count = player:GetAttribute(Config.COUNT_ATTRIBUTE) or 0
		hud.Text = `Props {count}/{Config.PROP_CAP}    Q spawn menu    X remove aimed prop    1-6 weapons    G ragdoll`
	end
	player:GetAttributeChangedSignal(Config.COUNT_ATTRIBUTE):Connect(updateHud)
	updateHud()

	-- Server messages
	local toast = label("", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		TextColor3 = THEME.accent,
		Visible = false,
	})
	local toastId = 0
	notifyRemote.OnClientEvent:Connect(function(message: unknown)
		if typeof(message) ~= "string" then
			return
		end
		toastId += 1
		local id = toastId
		toast.Text = message
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
