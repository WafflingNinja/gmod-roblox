--!strict
-- Small text box that sends one message to the server. The server rate limits and cleans it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(script.Parent.Parent.Net)
local Ui = require(script.Parent.Ui)
local Config = require(ReplicatedStorage.Shared.Config)

local THEME = Ui.THEME
local make = Ui.make

local panel: Frame? = nil
local box: TextBox? = nil

local function build(): (Frame, TextBox)
	local sendRemote = Net.event("SendFeedback")
	local gui = make(
		"ScreenGui",
		{ Name = "Feedback", ResetOnSpawn = false, DisplayOrder = 5 },
		Players.LocalPlayer:WaitForChild("PlayerGui")
	)
	local window = Ui.window("Feedback", gui, true, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 240),
		Visible = false,
	})
	local frame = window.frame
	local input: TextBox = make("TextBox", {
		Text = "",
		PlaceholderText = "Bug, idea, anything. Only the developer reads this.",
		Font = THEME.font,
		TextSize = 16,
		TextColor3 = THEME.text,
		PlaceholderColor3 = THEME.muted,
		BackgroundColor3 = THEME.rowAlt,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		MultiLine = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, 0, 1, -40),
	}, window.body)
	make("UIStroke", { Color = THEME.border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, input)
	make(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) },
		input
	)
	input:GetPropertyChangedSignal("Text"):Connect(function()
		local cut = utf8.offset(input.Text, Config.FEEDBACK_MAX + 1)
		if cut and cut <= #input.Text then
			input.Text = string.sub(input.Text, 1, cut - 1)
		end
	end)
	local function close()
		frame.Visible = false
	end
	Ui.button("Send", window.body, true, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(100, 30),
		Modal = true, -- frees the first-person mouse while the box is open
	}).Activated
		:Connect(function()
			local text = string.match(input.Text, "^%s*(.-)%s*$") or ""
			if text ~= "" then
				sendRemote:FireServer(text)
				input.Text = ""
			end
			close()
		end)
	Ui.button("Cancel", window.body, false, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -108, 1, 0),
		Size = UDim2.fromOffset(90, 30),
	}).Activated
		:Connect(close)
	if window.close then
		window.close.Activated:Connect(close)
	end
	return frame, input
end

local Feedback = {}

function Feedback.open()
	if not panel or not box then
		panel, box = build()
	end
	local frame, input = panel :: Frame, box :: TextBox
	frame.Visible = true
	input:CaptureFocus()
end

return Feedback
