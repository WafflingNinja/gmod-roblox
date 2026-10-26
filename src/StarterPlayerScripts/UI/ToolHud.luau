--!strict
-- Crosshair, selection highlight, the toolgun mode window and the ammo counter.
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
	setDupes: (string, { string }) -> (),
}

export type DupeAction = "save" | "load" | "delete"

local ToolHud = {}

local gui: ScreenGui? = nil
local crosshair: Frame? = nil
local highlight: Highlight? = nil
local ammo: Frame? = nil
local ammoCount: TextLabel? = nil
local ammoName: TextLabel? = nil

local function getGui(): ScreenGui
	if gui then
		return gui
	end
	-- IgnoreGuiInset: otherwise the top bar pushes the GUI down and the dot sits ~29 px below the real screen centre
	-- that Aim raycasts through.
	local newGui = make(
		"ScreenGui",
		{ Name = "ToolHud", ResetOnSpawn = false, IgnoreGuiInset = true },
		Players.LocalPlayer:WaitForChild("PlayerGui")
	)
	crosshair = make("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = THEME.text,
		BorderSizePixel = 0,
		Visible = false,
	}, newGui)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, crosshair)
	make("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5 }, crosshair)

	-- Ammo: small Source panel in the bottom-right corner.
	local panel = make("Frame", {
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(170, 64),
		BackgroundColor3 = THEME.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Visible = false,
	}, newGui)
	make("UIStroke", { Color = THEME.border }, panel)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, panel)
	ammoName = Ui.label("", panel, {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 15,
		TextColor3 = THEME.muted,
	})
	ammoCount = Ui.label("", panel, {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 36),
		Font = THEME.bold,
		TextSize = 34,
		TextColor3 = THEME.accentText,
	})
	ammo = panel
	gui = newGui
	return newGui
end

function ToolHud.setCrosshair(visible: boolean)
	getGui()
	if crosshair then
		crosshair.Visible = visible
	end
end

-- Gun name and magazine; nil name hides the panel.
function ToolHud.setAmmo(name: string?, count: number?, magazine: number?, reloading: boolean?)
	getGui()
	if not ammo or not ammoName or not ammoCount then
		return
	end
	ammo.Visible = name ~= nil
	ammoName.Text = name or ""
	ammoCount.Text = if reloading then "RELOADING" else `{count or 0} / {magazine or 0}`
	ammoCount.TextSize = if reloading then 24 else 34
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
			OutlineColor = THEME.accentText,
			Adornee = instance,
		}, instance)
	end
end

-- Clipboard line and one row per slot: label, Save, Load, Del.
local function dupeRows(parent: Instance, onDupe: (DupeAction, number) -> ()): (Frame, (string, { string }) -> ())
	local frame = make("Frame", {
		Name = "Dupes",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 102,
	}, parent)
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	local clip = Ui.label("", frame, {
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 15,
		TextColor3 = THEME.accentText,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local labels: { TextLabel } = {}
	for slot = 1, Config.DUPE_SLOTS do
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder = slot,
		}, frame)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		labels[slot] = Ui.label("", row, {
			Size = UDim2.new(1, -123, 1, 0),
			TextSize = 15,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 0,
		})
		for order, action: DupeAction in { "save", "load", "delete" } :: { DupeAction } do
			local text = if action == "save" then "Save" elseif action == "load" then "Load" else "Del"
			Ui.button(text, row, action == "load", {
				Size = UDim2.fromOffset(38, 22),
				TextSize = 13,
				LayoutOrder = order,
			}).Activated
				:Connect(function()
					onDupe(action, slot)
				end)
		end
	end
	return frame,
		function(clipboard, slots)
			clip.Text = if clipboard == "" then "Clipboard empty" else `Clipboard: {clipboard}`
			for slot, slotLabel in labels do
				local text = slots[slot]
				slotLabel.Text = `{slot}  {if text and text ~= "" then text else "-"}`
				slotLabel.TextColor3 = if text and text ~= "" then THEME.text else THEME.muted
			end
		end
end

function ToolHud.createToolgunPanel(
	onMode: (string) -> (),
	onColor: (number) -> (),
	onDupe: (DupeAction, number) -> ()
): ToolgunPanel
	local root = getGui()
	local window = Ui.window("Tool Gun", root, false, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(250, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	local panel = window.frame
	local body = window.body
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Size = UDim2.fromScale(1, 0)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, body)

	local modeList = make("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.rowAlt,
		BorderSizePixel = 0,
		LayoutOrder = 1,
	}, body)
	make("UIStroke", { Color = THEME.border }, modeList)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, modeList)
	local rows: { [string]: Ui.Row } = {}
	for index, mode in ToolModes.list do
		local row = Ui.row(mode.name, modeList, index)
		row.button.Activated:Connect(function()
			onMode(mode.id)
		end)
		rows[mode.id] = row
	end

	local hint = Ui.label("", body, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
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
	}, body)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(32, 28), CellPadding = UDim2.fromOffset(5, 5) }, swatches)
	local swatchStrokes: { UIStroke } = {}
	for index, rgb in Config.PALETTE do
		local swatch = make("TextButton", {
			Text = "",
			BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3]),
			BorderSizePixel = 0,
			LayoutOrder = index,
		}, swatches)
		make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, swatch)
		swatchStrokes[index] = make("UIStroke", { Color = THEME.text, Thickness = 2, Enabled = false }, swatch)
		swatch.Activated:Connect(function()
			onColor(index)
		end)
	end

	local dupes, setDupes = dupeRows(body, onDupe)
	setDupes("", {})

	return {
		setVisible = function(visible)
			panel.Visible = visible
		end,
		setMode = function(id)
			for modeId, row in rows do
				row.setSelected(modeId == id)
			end
			hint.Text = ToolModes.byId[id].hint
			swatches.Visible = id == "Paint"
			dupes.Visible = id == "Dupe"
		end,
		setColor = function(index)
			for i, stroke in swatchStrokes do
				stroke.Enabled = i == index
			end
		end,
		setDupes = setDupes,
	}
end

return ToolHud
