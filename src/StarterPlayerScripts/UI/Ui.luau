--!strict
-- Shared look for every panel: Source/Gmod VGUI. Gray dialogs with a 1 px dark border, a blue title bar, raised
-- gray buttons (blue when primary), list rows that alternate shade and turn blue when selected, SourceSans text.
-- The weapon selector keeps its own HL2 look (Ui.CLASSIC).
local Ui = {}

Ui.THEME = {
	panel = Color3.fromRGB(62, 64, 68),
	titleBar = Color3.fromRGB(44, 72, 108),
	border = Color3.fromRGB(24, 25, 27),
	button = Color3.fromRGB(84, 87, 92),
	buttonHover = Color3.fromRGB(100, 104, 110),
	row = Color3.fromRGB(70, 72, 77),
	rowAlt = Color3.fromRGB(64, 66, 70),
	rowHover = Color3.fromRGB(82, 85, 90),
	accent = Color3.fromRGB(58, 128, 204), -- fills: selected rows, primary buttons
	accentHover = Color3.fromRGB(78, 146, 222),
	accentText = Color3.fromRGB(120, 180, 245), -- blue text on gray
	text = Color3.fromRGB(236, 237, 239),
	muted = Color3.fromRGB(168, 172, 178),
	font = Enum.Font.SourceSans,
	semibold = Enum.Font.SourceSansSemibold,
	bold = Enum.Font.SourceSansBold,
}

Ui.CLASSIC = {
	panel = Color3.fromRGB(24, 26, 28),
	row = Color3.fromRGB(38, 41, 44),
	text = Color3.fromRGB(232, 232, 228),
	muted = Color3.fromRGB(150, 154, 156),
	accent = Color3.fromRGB(255, 170, 50),
	font = Enum.Font.GothamMedium,
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
	make("UICorner", { CornerRadius = UDim.new(0, 2) }, b)
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
		b.BackgroundColor3 = if selected then THEME.accent else base
	end)
	return {
		button = b,
		setSelected = function(on: boolean)
			selected = on
			b.BackgroundColor3 = if on then THEME.accent else base
		end,
	}
end

export type Window = { frame: Frame, body: Frame, close: TextButton? }

-- Gray dialog with a blue title bar (and a close button when `closable`). Position and size come in `props`.
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
	make("UIStroke", { Color = THEME.border }, frame)
	local bar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = THEME.titleBar,
		BorderSizePixel = 0,
	}, frame)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
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
	return { frame = frame, body = body, close = close }
end

-- Sunken list area (scrolls), the backdrop for Ui.row.
function Ui.list(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local frame: ScrollingFrame = make(
		"ScrollingFrame",
		with({
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = THEME.rowAlt,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = THEME.button,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, props),
		parent
	)
	make("UIStroke", { Color = THEME.border }, frame)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
end

return Ui
