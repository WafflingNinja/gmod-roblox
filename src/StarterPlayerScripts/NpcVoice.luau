--!strict
-- NPC voice lines: plays the line the server picked from the NPC's head and shows it as a subtitle. Subtitles are
-- always on, so lines still work with the sound off or before the sprites are uploaded (VoiceLines id "").
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Net)
local Ui = require(script.Parent.UI.Ui)
local Config = require(ReplicatedStorage.Shared.Config)
local NpcCatalog = require(ReplicatedStorage.Shared.NpcCatalog)
local VoiceLines = require(ReplicatedStorage.Shared.VoiceLines)

local MAX_SUBTITLES = 3
local MIN_SUBTITLE_SECONDS = 2.5
local LEAD_SKIP = 0.12 -- seconds; recorder.py keeps 0.15 s of room before the first sound

local player = Players.LocalPlayer

local NpcVoice = {}

function NpcVoice.init()
	local gui = Ui.make("ScreenGui", {
		Name = "Subtitles",
		ResetOnSpawn = false,
		DisplayOrder = 11, -- above the main menu, so the unlock line shows there
	}, player:WaitForChild("PlayerGui"))
	gui:SetAttribute("KeepWithMenu", true)
	local stack = Ui.make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromScale(0.7, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, gui)
	Ui.make("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, stack)
	local rows: { TextLabel } = {}
	local order = 0

	local function subtitle(speaker: string, text: string, seconds: number)
		order += 1
		local row = Ui.label(`{speaker}: {text}`, stack, {
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextWrapped = true,
			TextSize = 20,
			Font = Ui.THEME.semibold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 0.4,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.45,
			LayoutOrder = order,
		})
		Ui.make("UISizeConstraint", { MaxSize = Vector2.new(700, math.huge) }, row)
		Ui.make("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 3),
		}, row)
		table.insert(rows, row)
		if #rows > MAX_SUBTITLES then
			local oldest = table.remove(rows, 1) :: TextLabel
			oldest:Destroy()
		end
		task.delay(seconds, function()
			local index = table.find(rows, row)
			if index then
				table.remove(rows, index)
				row:Destroy()
			end
		end)
	end

	local function play(line: VoiceLines.Line, parent: Instance)
		local sprite = VoiceLines.sprites[line.npc]
		if not sprite or sprite.id == "" then
			return
		end
		local sound = Instance.new("Sound")
		sound.SoundId = sprite.id
		sound.PlaybackRegionsEnabled = true
		-- The export keeps a little room before each line; skip most of it so the NPC answers straight away.
		local start = line.start + math.min(LEAD_SKIP, line.length / 4)
		sound.PlaybackRegion = NumberRange.new(start, line.start + line.length)
		sound.RollOffMinDistance = 10
		sound.RollOffMaxDistance = Config.NPC_HEAR_RANGE
		sound.Parent = parent
		sound:Play()
		task.delay(line.length + 1, function()
			sound:Destroy()
		end)
	end

	-- `model` nil = said to us directly, not from a body (the unlock line).
	Net.event("NpcSay").OnClientEvent:Connect(function(model: unknown, lineId: unknown)
		if typeof(lineId) ~= "string" then
			return
		end
		local line = VoiceLines.lines[lineId]
		if not line then
			return
		end
		local parent: Instance = SoundService
		if model ~= nil then
			local head = if typeof(model) == "Instance" then model:FindFirstChild("Head") else nil
			local camera = Workspace.CurrentCamera
			if not head or not head:IsA("BasePart") or not camera then
				return
			end
			if (camera.CFrame.Position - head.Position).Magnitude > Config.NPC_HEAR_RANGE then
				return
			end
			parent = head
		end
		play(line, parent)
		local def = NpcCatalog.byId[line.npc]
		subtitle(if def then def.name else line.npc, line.text, math.max(MIN_SUBTITLE_SECONDS, line.length + 1.5))
	end)
end

return NpcVoice
