--!strict
-- Shared look for every panel: Garry's Mod Derma. Grey dialogs with a dark title bar, dark buttons (Gmod blue when
-- primary), list rows that alternate shade and turn light blue when selected, white active tab, Arimo text.
-- The colours are the ones Gmod's own Derma skin uses; no Gmod art.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

-- Modal buttons free the first-person mouse; FirstPerson shows the cursor while one is on screen.
Ui.FREES_MOUSE_TAG = "FreesMouse"

Ui.THEME = {
	panel = Color3.fromRGB(101, 100, 105), -- Derma background grey
	dark = Color3.fromRGB(55, 57, 61), -- title bars, buttons, list backdrop
	titleBar = Color3.fromRGB(55, 57, 61),
	border = Color3.fromRGB(30, 31, 34),
	button = Color3.fromRGB(55, 57, 61),
	buttonHover = Color3.fromRGB(74, 76, 82),
	row = Color3.fromRGB(68, 70, 75),
	rowAlt = Color3.fromRGB(61, 63, 68),
	rowHover = Color3.fromRGB(84, 86, 92),
	accent = Color3.fromRGB(35, 135, 237), -- #2387ed: primary buttons, focus strokes
	accentHover = Color3.fromRGB(79, 157, 237), -- #4f9ded
	accentText = Color3.fromRGB(118, 182, 246), -- lighter blue for small text on dark grey
	selection = Color3.fromRGB(100, 170, 220), -- selected row fill; text on it is selectionText
	selectionText = Color3.fromRGB(24, 26, 30),
	tooltip = Color3.fromRGB(255, 245, 175),
	tooltipText = Color3.fromRGB(30, 30, 30),
	tab = Color3.fromRGB(240, 240, 240), -- active tab
	tabText = Color3.fromRGB(30, 31, 34),
	text = Color3.fromRGB(220, 220, 220),
	muted = Color3.fromRGB(165, 167, 173),
	font = Enum.Font.Arimo,
	semibold = Enum.Font.Arimo, -- Arimo has two weights; the in-between one is the regular
	bold = Enum.Font.ArimoBold,
	radius = UDim.new(0, 3), -- buttons, tabs, list backdrops
	radiusWindow = UDim.new(0, 6),
}

local THEME = Ui.THEME

local function with(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	if extra then
		for key, value in extra do
			base[key] = value
		end
	end
	return base
end

function Ui.make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if props.Modal == true then
		CollectionService:AddTag(instance, Ui.FREES_MOUSE_TAG)
	end
	instance.Parent = parent
	return instance
end

local make = Ui.make

function Ui.label(text: string, parent: Instance, props: { [string]: any }?): TextLabel
	return make(
		"TextLabel",
		with({
			Text = text,
			Font = THEME.font,
			TextSize = 17,
			TextColor3 = THEME.text,
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, props),
		parent
	)
end

-- Raised button: gray, or blue when `primary`; lighter on hover.
function Ui.button(text: string, parent: Instance, primary: boolean, props: { [string]: any }?): TextButton
	local idle = if primary then THEME.accent else THEME.button
	local hover = if primary then THEME.accentHover else THEME.buttonHover
	local b: TextButton = make(
		"TextButton",
		with({
			Text = text,
			Font = THEME.bold,
			TextSize = 16,
			TextColor3 = THEME.text,
			BackgroundColor3 = idle,
			BorderSizePixel = 0,
			AutoButtonColor = false,
		}, props),
		parent
	)
	make("UICorner", { CornerRadius = THEME.radius }, b)
	make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = hover
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = idle
	end)
	return b
end

export type Row = {
	button: TextButton,
	setSelected: (boolean) -> (),
}

-- List row: alternating shade by `order`, hover tint, blue when selected.
function Ui.row(text: string, parent: Instance, order: number, props: { [string]: any }?): Row
	local base = if order % 2 == 1 then THEME.row else THEME.rowAlt
	local selected = false
	local b: TextButton = make(
		"TextButton",
		with({
			Text = text,
			Font = THEME.font,
			TextSize = 17,
			TextColor3 = THEME.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = base,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 28),
			LayoutOrder = order,
		}, props),
		parent
	)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, b)
	b.MouseEnter:Connect(function()
		if not selected then
			b.BackgroundColor3 = THEME.rowHover
		end
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = if selected then THEME.selection else base
	end)
	return {
		button = b,
		setSelected = function(on: boolean)
			selected = on
			b.BackgroundColor3 = if on then THEME.selection else base
			b.TextColor3 = if on then THEME.selectionText else THEME.text
		end,
	}
end

export type Window = { frame: Frame, bar: Frame, body: Frame, close: TextButton? }

-- Grey dialog with a dark title bar (and a close button when `closable`). Position and size come in `props`.
function Ui.window(title: string, parent: Instance, closable: boolean, props: { [string]: any }?): Window
	local frame: Frame = make(
		"Frame",
		with({
			Name = title,
			BackgroundColor3 = THEME.panel,
			BorderSizePixel = 0,
		}, props),
		parent
	)
	make("UICorner", { CornerRadius = THEME.radiusWindow }, frame)
	make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	local bar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = THEME.titleBar,
		BorderSizePixel = 0,
	}, frame)
	make("UICorner", { CornerRadius = THEME.radiusWindow }, bar)
	-- The bar's bottom corners are square: a filler hides the rounding there.
	make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, THEME.radiusWindow.Offset),
		BackgroundColor3 = THEME.titleBar,
		BorderSizePixel = 0,
	}, bar)
	Ui.label(title, bar, {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -44, 1, 0),
		Font = THEME.bold,
	})
	local close: TextButton? = nil
	if closable then
		close = Ui.button("X", bar, false, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -5, 0.5, 0),
			Size = UDim2.fromOffset(22, 20),
			TextSize = 14,
		})
	end
	local body: Frame = make("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		BackgroundTransparency = 1,
	}, frame)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, body)
	return { frame = frame, bar = bar, body = body, close = close }
end

-- Drag `frame` by `handle` (a window's title bar), kept inside its parent so it can't be lost off-screen.
function Ui.draggable(frame: GuiObject, handle: GuiObject)
	local dragStart: Vector3? = nil
	local startPosition = frame.Position
	local startCorner = Vector2.zero
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	handle.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			dragStart = input.Position
			startPosition = frame.Position
			startCorner = frame.AbsolutePosition
		end
	end)
	local moved = UserInputService.InputChanged:Connect(function(input: InputObject)
		local origin = dragStart
		local parent = frame.Parent
		if
			not origin
			or not parent
			or not parent:IsA("GuiBase2d")
			or (
				input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch
			)
		then
			return
		end
		local delta = input.Position - origin
		local low = parent.AbsolutePosition - startCorner
		local high = low + parent.AbsoluteSize - frame.AbsoluteSize
		frame.Position = startPosition
			+ UDim2.fromOffset(math.clamp(delta.X, low.X, high.X), math.clamp(delta.Y, low.Y, high.Y))
	end)
	local ended = UserInputService.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			dragStart = nil
		end
	end)
	-- These two are global; drop them with the window.
	frame.Destroying:Once(function()
		moved:Disconnect()
		ended:Disconnect()
	end)
end

-- Sunken list area (scrolls), the backdrop for Ui.row.
function Ui.list(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local frame: ScrollingFrame = make(
		"ScrollingFrame",
		with({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = THEME.dark,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = THEME.muted,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, props),
		parent
	)
	make("UICorner", { CornerRadius = THEME.radius }, frame)
	make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
end

export type Tabs = { strip: Frame, select: (string) -> () }

-- Row of tabs; the active one is white with dark text, the rest sit dark. `onSelect` gets the tab's name.
function Ui.tabs(names: { string }, parent: Instance, onSelect: (string) -> (), props: { [string]: any }?): Tabs
	local strip: Frame =
		make("Frame", with({ Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, props), parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, strip)
	local buttons: { [string]: TextButton } = {}
	local function pick(name: string)
		for tabName, tab in buttons do
			local active = tabName == name
			tab.BackgroundColor3 = if active then THEME.tab else THEME.dark
			tab.TextColor3 = if active then THEME.tabText else THEME.muted
		end
		onSelect(name)
	end
	for order, name in names do
		local tab: TextButton = make("TextButton", {
			Text = name,
			Font = THEME.bold,
			TextSize = 16,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = order,
		}, strip)
		make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, tab)
		make("UICorner", { CornerRadius = THEME.radius }, tab)
		tab.Activated:Connect(function()
			pick(name)
		end)
		buttons[name] = tab
	end
	pick(names[1])
	return { strip = strip, select = pick }
end

-- Yellow Derma tooltip that follows the mouse while it is over `target`.
local tipLabel: TextLabel? = nil
local function tooltipLabel(): TextLabel
	if tipLabel then
		return tipLabel
	end
	local gui = make("ScreenGui", {
		Name = "Tooltip",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	local tip: TextLabel = make("TextLabel", {
		Font = THEME.font,
		TextSize = 15,
		TextColor3 = THEME.tooltipText,
		BackgroundColor3 = THEME.tooltip,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		Visible = false,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0, 2) }, tip)
	make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tip)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 3),
		PaddingBottom = UDim.new(0, 3),
	}, tip)
	tipLabel = tip
	return tip
end

function Ui.tooltip(target: GuiObject, text: string)
	local function follow()
		local tip = tooltipLabel()
		local mouse = UserInputService:GetMouseLocation()
		local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
		local x = math.min(mouse.X + 14, viewport.X - tip.AbsoluteSize.X - 4)
		tip.Position = UDim2.fromOffset(math.max(x, 4), mouse.Y + 18)
	end
	target.MouseEnter:Connect(function()
		local tip = tooltipLabel()
		tip.Text = text
		tip.Visible = true
		follow()
	end)
	target.MouseMoved:Connect(follow)
	target.MouseLeave:Connect(function()
		tooltipLabel().Visible = false
	end)
end

return Ui
