--!strict
-- Wheel (or the panel) picks a mode, LMB uses it, RMB shrinks in Scale mode.
-- The server keeps the two-click state; we only send where we clicked.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Aim = require(script.Parent.Parent.Aim)
local Net = require(script.Parent.Parent.Net)
local SpawnMenu = require(script.Parent.Parent.UI.SpawnMenu)
local ToolHud = require(script.Parent.Parent.UI.ToolHud)
local WeaponSelect = require(script.Parent.Parent.UI.WeaponSelect)
local Config = require(ReplicatedStorage.Shared.Config)
local ToolModes = require(ReplicatedStorage.Shared.ToolModes)

local modeIndex = 1
local colorIndex = 1
local panel: ToolHud.ToolgunPanel? = nil
local dupeState: { clipboard: string, slots: { string } } = { clipboard = "", slots = {} }

local function selectMode(id: string)
	for index, mode in ToolModes.list do
		if mode.id == id then
			modeIndex = index
			break
		end
	end
	if panel then
		panel.setMode(id)
	end
end

local function selectColor(index: number)
	colorIndex = index
	if panel then
		panel.setColor(index)
	end
end

local function dupeAction(action: ToolHud.DupeAction, slot: number)
	if action == "save" then
		Net.event("DupeSave"):FireServer(slot)
	elseif action == "delete" then
		Net.event("DupeDelete"):FireServer(slot)
	else
		local point = SpawnMenu.aimPoint()
		if point then
			Net.event("DupeLoad"):FireServer(slot, point)
		end
	end
end

local Toolgun = {}

function Toolgun.start(): () -> ()
	local use = Net.event("ToolgunUse")
	if not panel then
		-- Events sent before this point are queued by Roblox and arrive now.
		Net.event("DupeState").OnClientEvent:Connect(function(clipboard: unknown, slots: unknown)
			if typeof(clipboard) ~= "string" or typeof(slots) ~= "table" then
				return
			end
			dupeState = { clipboard = clipboard, slots = slots :: { string } }
			if panel then
				panel.setDupes(dupeState.clipboard, dupeState.slots)
			end
		end)
	end
	local activePanel = panel or ToolHud.createToolgunPanel(selectMode, selectColor, dupeAction)
	panel = activePanel
	activePanel.setDupes(dupeState.clipboard, dupeState.slots)
	activePanel.setMode(ToolModes.list[modeIndex].id)
	activePanel.setColor(colorIndex)
	activePanel.setVisible(true)
	ToolHud.setCrosshair(true)

	local function fire(extra: unknown)
		local hit = Aim.cast(Config.TOOL_RANGE)
		local result = hit and hit.result
		local prop = result and Aim.prop(result.Instance)
		if not result or not prop then
			return
		end
		use:FireServer(ToolModes.list[modeIndex].id, prop, result.Position, result.Normal, extra)
	end

	local connections: { RBXScriptConnection } = {}

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed or WeaponSelect.isOpen() then
				return
			end
			local mode = ToolModes.list[modeIndex].id
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				if mode == "Scale" then
					fire(1)
				elseif mode == "Paint" then
					fire(colorIndex)
				elseif mode == "Wheel" then
					fire("wheel_small")
				else
					fire(nil)
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				if mode == "Scale" then
					fire(-1)
				elseif mode == "Wheel" then
					fire("wheel_big")
				end
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input, processed)
			if processed or WeaponSelect.isOpen() or input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			local count = #ToolModes.list
			local step = if input.Position.Z > 0 then -1 else 1
			selectMode(ToolModes.list[(modeIndex - 1 + step) % count + 1].id)
		end)
	)

	return function()
		activePanel.setVisible(false)
		ToolHud.setCrosshair(false)
		ToolHud.select(nil)
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

return Toolgun
