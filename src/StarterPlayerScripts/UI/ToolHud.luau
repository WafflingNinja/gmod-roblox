--!strict
-- Crosshair, selection highlight, and the toolgun mode panel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ToolModes = require(ReplicatedStorage.Shared.ToolModes)
local Ui = require(script.Parent.Ui)

local THEME = Ui.THEME
local make = Ui.make

export type ToolgunPanel = {
	setVisible: (boolean) -> (),
	setMode: (string) -> (),
	setColor: (number) -> (),
}

local ToolHud = {}

local gui: ScreenGui? = nil
local crosshair: Frame? = nil
local highlight: Highlight? = nil

local function getGui(): ScreenGui
	if gui then
		return gui
	end
	local newGui =
		make("ScreenGui", { Name = "ToolHud", ResetOnSpawn = false }, Players.LocalPlayer:WaitForChild("PlayerGui"))
	crosshair = make("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = THEME.accent,
		BorderSizePixel = 0,
		Visible = false,
	}, newGui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, crosshair)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5 }, crosshair)
	gui = newGui
	return newGui
end

function ToolHud.setCrosshair(visible: boolean)
	getGui()
	if crosshair then
		crosshair.Visible = visible
	end
end

-- Outline the prop the server says is selected (or clear it).
function ToolHud.select(instance: Instance?)
	if highlight then
		highlight:Destroy()
		highlight = nil
	end
	if instance then
		highlight = make("Highlight", {
			FillColor = THEME.accent,
			FillTransparency = 0.7,
			OutlineColor = THEME.accent,
			Adornee = instance,
		}, instance)
	end
end

function ToolHud.createToolgunPanel(onMode: (string) -> (), onColor: (number) -> ()): ToolgunPanel
	local root = getGui()
	local panel = make("Frame", {
		Name = "ToolgunPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.panel,
		Visible = false,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, panel)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
	}, panel)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	Ui.label("Toolgun", panel, { Size = UDim2.new(1, 0, 0, 24), TextSize = 20, LayoutOrder = 0 })

	local buttons: { [string]: TextButton } = {}
	for index, mode in ToolModes.list do
		local button = make("TextButton", {
			Text = mode.name,
			Font = THEME.font,
			TextSize = 15,
			TextColor3 = THEME.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = THEME.row,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = index,
		}, panel)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, button)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, button)
		button.Activated:Connect(function()
			onMode(mode.id)
		end)
		buttons[mode.id] = button
	end

	local hint = Ui.label("", panel, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 13,
		TextColor3 = THEME.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 100,
	})

	local swatches = make("Frame", {
		Name = "Swatches",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 101,
	}, panel)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(32, 28), CellPadding = UDim2.fromOffset(5, 5) }, swatches)
	local swatchStrokes: { UIStroke } = {}
	for index, rgb in Config.PALETTE do
		local swatch = make("TextButton", {
			Text = "",
			BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
			BorderSizePixel = 0,
			LayoutOrder = index,
		}, swatches)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, swatch)
		swatchStrokes[index] = make("UIStroke", { Color = THEME.text, Thickness = 2, Enabled = false }, swatch)
		swatch.Activated:Connect(function()
			onColor(index)
		end)
	end

	return {
		setVisible = function(visible)
			panel.Visible = visible
		end,
		setMode = function(id)
			for modeId, button in buttons do
				button.BackgroundColor3 = if modeId == id then THEME.accent else THEME.row
				button.TextColor3 = if modeId == id then Color3.new(0, 0, 0) else THEME.text
			end
			hint.Text = ToolModes.byId[id].hint
			swatches.Visible = id == "Paint"
		end,
		setColor = function(index)
			for i, stroke in swatchStrokes do
				stroke.Enabled = i == index
			end
		end,
	}
end

return ToolHud
