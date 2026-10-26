--!strict
-- HL2-style weapon selector, replaces the Roblox hotbar. 1-6 open a slot (press again to cycle inside it),
-- the wheel moves through every weapon while open, LMB confirms, RMB cancels, and it hides itself after a moment.
-- Slot, order and label are attributes ToolService puts on each Tool.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Sfx = require(script.Parent.Parent.Sfx)
local Ui = require(script.Parent.Ui)
local Config = require(ReplicatedStorage.Shared.Config)

local THEME = Ui.THEME
local make = Ui.make
local label = Ui.label

local SLOTS = 6
local HIDE_AFTER = 2.5
local COLUMN_WIDTH = 44
local OPEN_COLUMN_WIDTH = 170
local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
}

local player = Players.LocalPlayer
local open = false

local function slotOf(tool: Tool): number
	local slot = tool:GetAttribute(Config.SLOT_ATTRIBUTE)
	return if typeof(slot) == "number" then math.clamp(slot, 1, SLOTS) else SLOTS
end

local function orderOf(tool: Tool): number
	local order = tool:GetAttribute(Config.SLOT_ORDER_ATTRIBUTE)
	return if typeof(order) == "number" then order else math.huge
end

local function labelOf(tool: Tool): string
	local text = tool:GetAttribute(Config.LABEL_ATTRIBUTE)
	return if typeof(text) == "string" then text else tool.Name
end

local function collect(container: Instance?, into: { Tool })
	if not container then
		return
	end
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			table.insert(into, child)
		end
	end
end

-- Every tool we carry (backpack + equipped), in selector order.
local function owned(): { Tool }
	local tools: { Tool } = {}
	collect(player:FindFirstChildOfClass("Backpack"), tools)
	collect(player.Character, tools)
	table.sort(tools, function(a, b)
		if slotOf(a) ~= slotOf(b) then
			return slotOf(a) < slotOf(b)
		end
		return orderOf(a) < orderOf(b)
	end)
	return tools
end

local WeaponSelect = {}

-- Tools ignore their own mouse input while the menu is open, so the confirm click doesn't fire them.
function WeaponSelect.isOpen(): boolean
	return open
end

function WeaponSelect.init()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	local gui = make(
		"ScreenGui",
		{ Name = "WeaponSelect", ResetOnSpawn = false, Enabled = false },
		player:WaitForChild("PlayerGui")
	)
	local row = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	local selected: Tool? = nil
	local token = 0

	local function close()
		open = false
		selected = nil
		gui.Enabled = false
	end

	local function render(tools: { Tool })
		for _, child in row:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local activeSlot = if selected then slotOf(selected) else nil
		for slot = 1, SLOTS do
			local column = make("Frame", {
				LayoutOrder = slot,
				Size = UDim2.fromOffset(if slot == activeSlot then OPEN_COLUMN_WIDTH else COLUMN_WIDTH, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, row)
			make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, column)

			local filled = false
			for _, tool in tools do
				filled = filled or slotOf(tool) == slot
			end
			local header = make("Frame", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = THEME.panel,
				BackgroundTransparency = 0.2,
			}, column)
			make("UICorner", { CornerRadius = UDim.new(0, 4) }, header)
			label(tostring(slot), header, {
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -8, 1, 0),
				TextSize = 15,
				TextColor3 = if filled then THEME.accent else THEME.muted,
			})

			if slot == activeSlot then
				for i, tool in tools do
					if slotOf(tool) ~= slot then
						continue
					end
					local isSelected = tool == selected
					local entry = make("Frame", {
						LayoutOrder = i,
						Size = UDim2.new(1, 0, 0, if isSelected then 44 else 30),
						BackgroundColor3 = if isSelected then THEME.row else THEME.panel,
						BackgroundTransparency = 0.15,
					}, column)
					make("UICorner", { CornerRadius = UDim.new(0, 4) }, entry)
					if isSelected then
						make("UIStroke", { Color = THEME.accent, Thickness = 2 }, entry)
					end
					label(labelOf(tool), entry, {
						Position = UDim2.fromOffset(10, 0),
						Size = UDim2.new(1, -20, 1, 0),
						TextSize = if isSelected then 17 else 14,
						TextColor3 = if isSelected then THEME.accent else THEME.text,
						TextTruncate = Enum.TextTruncate.AtEnd,
					})
				end
			end
		end
	end

	local function show(tool: Tool, tools: { Tool })
		selected = tool
		open = true
		gui.Enabled = true
		render(tools)
		Sfx.play("ui_tick")
		token += 1
		local id = token
		task.delay(HIDE_AFTER, function()
			if token == id then
				close()
			end
		end)
	end

	local function pressSlot(slot: number)
		local tools = owned()
		local inSlot: { Tool } = {}
		for _, tool in tools do
			if slotOf(tool) == slot then
				table.insert(inSlot, tool)
			end
		end
		if #inSlot == 0 then
			return
		end
		local current = if open and selected then table.find(inSlot, selected) else nil
		show(inSlot[if current then current % #inSlot + 1 else 1], tools)
	end

	local function step(direction: number)
		local tools = owned()
		if #tools == 0 then
			return
		end
		local current = (if selected then table.find(tools, selected) else nil) or 1
		show(tools[(current - 1 + direction) % #tools + 1], tools)
	end

	local function confirm()
		local tool = selected
		close()
		local backpack = player:FindFirstChildOfClass("Backpack")
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if tool and humanoid and backpack and tool.Parent == backpack then
			humanoid:EquipTool(tool)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		local slot = SLOT_KEYS[input.KeyCode]
		if slot and not processed then
			pressSlot(slot)
		end
	end)

	-- Act on release: the press already reached the tools, which skip it while the menu is open.
	UserInputService.InputEnded:Connect(function(input)
		if not open then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			confirm()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			close()
		end
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if open and not processed and input.UserInputType == Enum.UserInputType.MouseWheel then
			step(if input.Position.Z > 0 then -1 else 1)
		end
	end)
end

return WeaponSelect
