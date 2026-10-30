--!strict
-- HL2-style weapon selector, replaces the Roblox hotbar. 1-6 open a slot (press again to cycle inside it),
-- the wheel moves through every weapon while open, LMB confirms, RMB cancels, and it hides itself after a moment.
-- With the selector closed the wheel switches weapons at once, except when the Toolgun is out (its wheel picks
-- a mode) or the Physgun is holding a prop (its wheel pushes and pulls); use 1-6 there.
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

-- Colours from Gmod's resource/ClientScheme.res: yellow text on square black boxes (alpha 70 empty, 150 selected).
local HUD_YELLOW = Color3.fromRGB(255, 220, 0)
local HUD_BOX = Color3.new(0, 0, 0)
local BOX_EMPTY_TRANSPARENCY = 1 - 70 / 255
local BOX_SELECTED_TRANSPARENCY = 1 - 150 / 255

local function label(text: string, parent: Instance, props: { [string]: any }): TextLabel
	props.Font = props.Font or THEME.bold
	props.TextColor3 = props.TextColor3 or HUD_YELLOW
	props.TextSize = props.TextSize or 16
	return Ui.label(text, parent, props)
end

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
	-- Pure touch has no number keys or wheel, so keep Roblox's hotbar there; the selector replaces it
	-- everywhere a keyboard exists.
	if not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end

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

	-- A respawn drops every Tool; never keep the selector open over stale entries.
	player.CharacterAdded:Connect(function()
		close()
	end)

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
				BackgroundColor3 = HUD_BOX,
				BackgroundTransparency = if filled then BOX_SELECTED_TRANSPARENCY else BOX_EMPTY_TRANSPARENCY,
				BorderSizePixel = 0,
			}, column)
			label(tostring(slot), header, {
				Position = UDim2.fromOffset(8, 0),
				Size = UDim2.new(1, -8, 1, 0),
				TextSize = 15,
				TextTransparency = if filled then 0 else 0.5,
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
						BackgroundColor3 = HUD_BOX,
						BackgroundTransparency = if isSelected
							then BOX_SELECTED_TRANSPARENCY
							else BOX_EMPTY_TRANSPARENCY,
						BorderSizePixel = 0,
					}, column)
					label(labelOf(tool), entry, {
						Position = UDim2.fromOffset(10, 0),
						Size = UDim2.new(1, -20, 1, 0),
						TextSize = if isSelected then 17 else 14,
						TextTransparency = if isSelected then 0 else 0.25,
						TextTruncate = Enum.TextTruncate.AtEnd,
					})
				end
			end
		end
	end

	-- `picking` leaves the selector waiting for LMB; the wheel's quick switch only shows it.
	local function show(tool: Tool, tools: { Tool }, picking: boolean)
		selected = tool
		open = picking
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
		show(inSlot[if current then current % #inSlot + 1 else 1], tools, true)
	end

	local function step(direction: number)
		local tools = owned()
		if #tools == 0 then
			return
		end
		local current = (if selected then table.find(tools, selected) else nil) or 1
		show(tools[(current - 1 + direction) % #tools + 1], tools, true)
	end

	local function quickSwitch(direction: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local held = character and character:FindFirstChildOfClass("Tool")
		if not humanoid then
			return
		end
		if held and held.Name == Config.TOOLGUN then
			return
		end
		if
			held
			and held.Name == Config.PHYSGUN
			and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		then
			return
		end
		local tools = owned()
		if #tools == 0 then
			return
		end
		local current = if held then table.find(tools, held) else nil
		local nextTool = if current
			then tools[(current - 1 + direction) % #tools + 1]
			elseif direction > 0 then tools[1]
			else tools[#tools]
		humanoid:EquipTool(nextTool)
		show(nextTool, tools, false)
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

	-- Keyboard slots plus a gamepad mapping: the d-pad does the wheel's job, A confirms, B cancels.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local slot = SLOT_KEYS[input.KeyCode]
		if slot then
			pressSlot(slot)
			return
		end
		local code = input.KeyCode
		if code == Enum.KeyCode.DPadLeft or code == Enum.KeyCode.DPadRight then
			local direction = if code == Enum.KeyCode.DPadRight then 1 else -1
			if open then
				step(direction)
			else
				quickSwitch(direction)
			end
		elseif code == Enum.KeyCode.DPadUp then
			local tools = owned()
			if #tools > 0 then
				local character = player.Character
				local held = character and character:FindFirstChildOfClass("Tool")
				local index = 1
				if held then
					index = table.find(tools, held) or index
				elseif selected then
					index = table.find(tools, selected) or index
				end
				show(tools[index], tools, true)
			end
		elseif open and gui.Enabled then
			if code == Enum.KeyCode.ButtonA then
				confirm()
			elseif code == Enum.KeyCode.ButtonB then
				close()
			end
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
		if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		local direction = if input.Position.Z > 0 then -1 else 1
		if open then
			step(direction)
		else
			quickSwitch(direction)
		end
	end)
end

return WeaponSelect
