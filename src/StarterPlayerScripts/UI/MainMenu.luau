--!strict
-- Main menu, Source/Gmod style: the camera circles the selected map behind a text-link menu on the left, and
-- each page opens as a gray dialog with a blue title bar. Opens on join, M toggles it. The full-screen root is
-- a Modal button, which frees the first-person mouse while the menu is open. Settings last for the session.
-- On join it opens with a short intro: fade from black, the camera eases out, the title and a welcome rise in,
-- then the links. Dialogs pop open and drag by their title bar. Starting a map fades through black.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local FirstPerson = require(script.Parent.Parent.FirstPerson)
local KeyboardLook = require(script.Parent.Parent.KeyboardLook)
local MapLighting = require(script.Parent.Parent.MapLighting)
local Net = require(script.Parent.Parent.Net)
local Ui = require(script.Parent.Ui)
local Config = require(ReplicatedStorage.Shared.Config)
local MapCatalog = require(ReplicatedStorage.Shared.MapCatalog)

local make = Ui.make

local THEME = Ui.THEME

local TITLE = "waffles mod"
local ORBIT_SECONDS = 120 -- one full circle around the map
local INTRO_ZOOM = 0.55 -- the intro camera starts at this share of the orbit radius and eases out
local INTRO_ZOOM_SECONDS = 5
local KONAMI_TIMEOUT = 2
local KONAMI = {
	Enum.KeyCode.Up,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.B,
	Enum.KeyCode.A,
}
local LINK_STAGGER = 0.12 -- seconds between links appearing
local CONTROLS = {
	{ "WASD", "walk" },
	{ "Arrow keys", "look around (Options to turn off)" },
	{ "Mouse / trackpad", "look; tap = left click, two-finger tap = right click" },
	{ "Two-finger scroll", "mouse wheel (switch weapon; physgun push/pull, toolgun mode)" },
	{ "Q", "spawn menu, frees the mouse" },
	{ "X", "remove the prop you aim at" },
	{ "1-6", "weapon selector" },
	{ "Physgun", "hold LMB grab, wheel push/pull, R rotate, RMB freeze" },
	{ "Gravity gun", "RMB pull/hold, LMB punt/throw" },
	{ "Toolgun", "wheel picks mode, LMB use, RMB alt (Scale, Wheel)" },
	{ "V", "fire thrusters" },
	{ "F", "flashlight" },
	{ "G", "ragdoll / stand up" },
	{ "C", "third person on / off (shoulder cam, chase cam in cars), guns still aim" },
	{ "LMB / R", "fire / reload (guns)" },
	{ "M", "this menu" },
}
local TRACKPAD_TIP = "Trackpad on Linux: turn off 'disable touchpad while typing' so you can look while holding WASD."

local text = Ui.label
local button = Ui.button
local list = Ui.list

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService
		:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
		:Play()
end

-- Closable, draggable Source dialog right of the menu links.
local function dialog(title: string, parent: Instance): (Frame, Frame, TextButton)
	local window = Ui.window(title, parent, true, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.64, 0.5),
		Size = UDim2.fromScale(0.5, 0.62),
		Visible = false,
	})
	make("UISizeConstraint", { MinSize = Vector2.new(380, 300), MaxSize = Vector2.new(640, 460) }, window.frame)
	make("UIScale", {}, window.frame)
	Ui.draggable(window.frame, window.bar)
	return window.frame, window.body, window.close :: TextButton
end

-- "name   [-] value [+]" row.
local function stepper(
	parent: Instance,
	order: number,
	name: string,
	get: () -> number,
	set: (number) -> (),
	step: number,
	low: number,
	high: number
)
	local row =
		make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	text(name, row, { Size = UDim2.new(1, -150, 1, 0) })
	local value = text("", row, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -36, 0, 0),
		Size = UDim2.fromOffset(72, 34),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = THEME.semibold,
	})
	local function refresh()
		value.Text = string.format("%.1f", get())
	end
	for _, direction in { -1, 1 } do
		button(if direction < 0 then "-" else "+", row, false, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = if direction < 0 then UDim2.new(1, -110, 0.5, 0) else UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(30, 26),
			TextSize = 20,
		}).Activated:Connect(function()
			set(math.clamp(math.round((get() + direction * step) / step) * step, low, high))
			refresh()
		end)
	end
	refresh()
end

local function mapAvailable(def: MapCatalog.MapDef): boolean
	if not def.model then
		return true
	end
	local maps = Workspace:FindFirstChild("Maps")
	return maps ~= nil and maps:FindFirstChild(def.model) ~= nil
end

local MainMenu = {}

function MainMenu.init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local pickRemote = Net.event("PickMap")
	local unlockRemote = Net.event("UnlockSecret")

	local gui = make("ScreenGui", {
		Name = "MainMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
	}, playerGui)
	local root: TextButton = make("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, gui)
	-- Darken the left side so the menu reads over any map.
	local shade = make("Frame", {
		Size = UDim2.fromScale(0.6, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
	}, root)
	make("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
	}, shade)

	-- Left column: logo, welcome, current map, text links.
	local left = make("Frame", {
		Position = UDim2.fromScale(0.06, 0.14),
		Size = UDim2.fromOffset(360, 450),
		BackgroundTransparency = 1,
	}, root)
	local title = text(TITLE, left, {
		Size = UDim2.new(1, 0, 0, 72),
		Font = THEME.bold,
		TextSize = 72,
		TextStrokeTransparency = 0.75,
	})
	local welcome = text(`Hey {player.DisplayName}, welcome in. Build something.`, left, {
		Position = UDim2.fromOffset(4, 74),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 19,
		TextColor3 = THEME.accentText,
	})
	local currentLine = text("", left, {
		Position = UDim2.fromOffset(4, 98),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 16,
		TextColor3 = THEME.muted,
	})
	local links = make("Frame", {
		Position = UDim2.fromOffset(2, 144),
		Size = UDim2.new(1, 0, 1, -144),
		BackgroundTransparency = 1,
	}, left)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, links)

	-- Black curtain for the intro and map changes. Outside `root`, so it stays up while the menu closes.
	local curtain: Frame = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, gui)

	local dialogs: { [string]: Frame } = {}
	local linkButtons: { [string]: TextButton } = {}
	local allLinks: { TextButton } = {}
	local openDialog: string? = nil
	local function showDialog(name: string?)
		openDialog = name
		for dialogName, frame in dialogs do
			local opening = dialogName == name and not frame.Visible
			frame.Visible = dialogName == name
			local scale = frame:FindFirstChildOfClass("UIScale")
			if opening and scale then
				scale.Scale = 0.9
				tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end
		for linkName, link in linkButtons do
			link.TextColor3 = if linkName == name then THEME.accentText else THEME.text
		end
	end
	local function link(order: number, label: string, onClick: () -> ()): TextButton
		local b: TextButton = make("TextButton", {
			Text = label,
			Font = THEME.semibold,
			TextSize = 28,
			TextColor3 = THEME.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = order,
		}, links)
		b.MouseEnter:Connect(function()
			b.TextColor3 = THEME.accentText
		end)
		b.MouseLeave:Connect(function()
			b.TextColor3 = if linkButtons[label] and openDialog == label then THEME.accentText else THEME.text
		end)
		b.Activated:Connect(onClick)
		table.insert(allLinks, b)
		return b
	end

	-- Camera circles the selected map while the menu is open.
	local orbitAngle = 0
	local orbitDef = MapCatalog.byId[MapCatalog.DEFAULT]
	local introStart: number? = nil
	local function startOrbit()
		RunService:BindToRenderStep("MenuOrbit", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
			local camera = Workspace.CurrentCamera
			if not camera then
				return
			end
			camera.CameraType = Enum.CameraType.Scriptable
			if not GuiService.ReducedMotionEnabled then
				orbitAngle += dt * 2 * math.pi / ORBIT_SECONDS
			end
			local orbit = orbitDef.orbit
			local center = Vector3.new(orbit.center[1], orbit.center[2], orbit.center[3])
			local zoom = 1
			if introStart and not GuiService.ReducedMotionEnabled then
				local t = math.min((os.clock() - introStart) / INTRO_ZOOM_SECONDS, 1)
				zoom = 1 - (1 - INTRO_ZOOM) * (1 - t) ^ 3
			end
			local radius = orbit.radius * zoom
			local offset =
				Vector3.new(math.cos(orbitAngle) * radius, orbit.height * zoom, math.sin(orbitAngle) * radius)
			camera.CFrame = CFrame.lookAt(center + offset, center)
		end)
	end
	local function stopOrbit()
		RunService:UnbindFromRenderStep("MenuOrbit")
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		-- The default camera keeps the distance it finds, so put it back at the head before handing over.
		local head = player.Character and player.Character:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			camera.CFrame = CFrame.lookAt(head.Position, head.Position + head.CFrame.LookVector)
		end
		camera.CameraType = Enum.CameraType.Custom
	end

	-- Other HUDs hide behind the menu and come back as they were.
	local hidden: { ScreenGui } = {}
	local function hideOtherGuis(hide: boolean)
		if not hide then
			for _, other in hidden do
				other.Enabled = true
			end
			table.clear(hidden)
			return
		end
		for _, child in playerGui:GetChildren() do
			if child:IsA("ScreenGui") and child ~= gui and child.Enabled and not child:GetAttribute("KeepWithMenu") then
				child.Enabled = false
				table.insert(hidden, child)
			end
		end
	end

	-- Start Game: map list on the left, details and Start on the right.
	local playFrame, playBody, playClose = dialog("Start Game", root)
	dialogs["Start Game"] = playFrame
	local mapList = list(playBody, { Size = UDim2.new(0.42, 0, 1, -44) })
	local details = make("Frame", {
		Position = UDim2.new(0.42, 14, 0, 0),
		Size = UDim2.new(0.58, -14, 1, -44),
		BackgroundTransparency = 1,
	}, playBody)
	local detailName = text("", details, { Size = UDim2.new(1, 0, 0, 30), Font = THEME.bold, TextSize = 28 })
	local detailHere = text("", details, {
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 15,
		TextColor3 = THEME.accentText,
	})
	local detailBlurb = text("", details, {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		TextColor3 = THEME.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local start = button("Start", playBody, true, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(120, 32),
	})
	local cancel = button("Cancel", playBody, false, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -128, 1, 0),
		Size = UDim2.fromOffset(100, 32),
	})

	local rows: { [string]: TextButton } = {}
	local selected = MapCatalog.DEFAULT
	local function rowColor(order: number): Color3
		return if order % 2 == 1 then THEME.row else THEME.rowAlt
	end
	local function selectMap(id: string)
		selected = id
		local def = MapCatalog.byId[id]
		for order, map in MapCatalog.list do
			local row = rows[map.id]
			row.BackgroundColor3 = if map.id == id then THEME.accent else rowColor(order)
			row.Visible = mapAvailable(map)
		end
		local current = player:GetAttribute(Config.MAP_ATTRIBUTE)
		detailName.Text = def.name
		detailHere.Text = if current == id then "You are here" else ""
		detailBlurb.Text = def.blurb
		start.Text = if current == id then "Respawn here" else "Start"
		orbitDef = def
		MapLighting.preview(id)
	end
	for order, def in MapCatalog.list do
		local row: TextButton = make("TextButton", {
			Text = def.name,
			Font = THEME.font,
			TextSize = 18,
			TextColor3 = THEME.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = rowColor(order),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 0, 32),
			LayoutOrder = order,
		}, mapList)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, row)
		row.MouseEnter:Connect(function()
			if selected ~= def.id then
				row.BackgroundColor3 = THEME.rowHover
			end
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundColor3 = if selected == def.id then THEME.accent else rowColor(order)
		end)
		row.Activated:Connect(function()
			selectMap(def.id)
		end)
		rows[def.id] = row
	end

	-- Controls: Source list view, alternating rows.
	local controlsFrame, controlsBody, controlsClose = dialog("Controls", root)
	dialogs.Controls = controlsFrame
	local controlsList = list(controlsBody)
	for order, entry in CONTROLS do
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = rowColor(order),
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, controlsList)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, row)
		text(entry[1], row, { Size = UDim2.fromScale(0.32, 1), Font = THEME.semibold, TextColor3 = THEME.accentText })
		text(entry[2], row, {
			Position = UDim2.fromScale(0.32, 0),
			Size = UDim2.fromScale(0.68, 1),
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local tip = text(TRACKPAD_TIP, controlsList, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		TextColor3 = THEME.muted,
		TextWrapped = true,
		LayoutOrder = #CONTROLS + 1,
	})
	make(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) },
		tip
	)

	-- Options
	local optionsFrame, optionsBody, optionsClose = dialog("Options", root)
	dialogs.Options = optionsFrame
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, optionsBody)
	stepper(optionsBody, 1, "Mouse / trackpad sensitivity", function()
		return UserInputService.MouseDeltaSensitivity
	end, function(v)
		UserInputService.MouseDeltaSensitivity = v
	end, 0.1, 0.1, 3)
	stepper(optionsBody, 2, "Field of view", FirstPerson.fieldOfView, FirstPerson.setFieldOfView, 5, 60, 110)
	local lookRow =
		make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 3 }, optionsBody)
	text("Arrow keys look around", lookRow, { Size = UDim2.new(1, -150, 1, 0) })
	local lookToggle = button("", lookRow, false, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(140, 26),
	})
	local function refreshLook()
		lookToggle.Text = if KeyboardLook.isEnabled() then "On" else "Off (arrows walk)"
	end
	lookToggle.Activated:Connect(function()
		KeyboardLook.setEnabled(not KeyboardLook.isEnabled())
		refreshLook()
	end)
	refreshLook()
	stepper(optionsBody, 4, "Arrow-key look speed", KeyboardLook.speed, KeyboardLook.setSpeed, 0.5, 0.5, 6)
	local pvpRemote = Net.event("SetPvp")
	local pvpRow =
		make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 5 }, optionsBody)
	text("PvP (guns hurt players who also have it on)", pvpRow, { Size = UDim2.new(1, -150, 1, 0) })
	local pvpToggle = button("", pvpRow, false, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(140, 26),
	})
	local function refreshPvp()
		pvpToggle.Text = if player:GetAttribute(Config.PVP_ATTRIBUTE) == true then "On" else "Off"
	end
	pvpToggle.Activated:Connect(function()
		pvpRemote:FireServer(player:GetAttribute(Config.PVP_ATTRIBUTE) ~= true)
	end)
	player:GetAttributeChangedSignal(Config.PVP_ATTRIBUTE):Connect(refreshPvp)
	refreshPvp()

	local function refreshCurrent()
		local def = MapCatalog.byId[player:GetAttribute(Config.MAP_ATTRIBUTE) :: string]
		currentLine.Text = if def then `Current map: {def.name}` else ""
	end
	player:GetAttributeChangedSignal(Config.MAP_ATTRIBUTE):Connect(refreshCurrent)

	local function setOpen(open: boolean)
		root.Visible = open
		hideOtherGuis(open)
		if open then
			refreshCurrent()
			local current = player:GetAttribute(Config.MAP_ATTRIBUTE)
			selectMap(if typeof(current) == "string" and MapCatalog.byId[current] then current else MapCatalog.DEFAULT)
			startOrbit()
		else
			showDialog(nil)
			stopOrbit()
			MapLighting.preview(nil)
		end
	end

	link(1, "Resume Game", function()
		setOpen(false)
	end)
	for order, name in { "Start Game", "Controls", "Options" } do
		linkButtons[name] = link(order + 1, name, function()
			showDialog(if openDialog == name then nil else name)
		end)
	end
	for _, close in { playClose, controlsClose, optionsClose, cancel } do
		close.Activated:Connect(function()
			showDialog(nil)
		end)
	end
	-- Fade through black so the jump to another map isn't a hard cut.
	local starting = false
	start.Activated:Connect(function()
		if starting then
			return
		end
		starting = true
		tween(curtain, 0.4, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
		task.delay(0.45, function()
			pickRemote:FireServer(selected)
			setOpen(false)
			task.wait(0.35)
			tween(curtain, 0.9, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
			starting = false
		end)
	end)

	-- Secret: the Konami code on the open menu unlocks RostikPro12308 (docs/NPC.md). A wrong key or a 2 s pause
	-- restarts it; a third Up keeps the two before it.
	local konamiStep, konamiLast = 0, 0
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			setOpen(not root.Visible)
		end
		if not root.Visible or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		local now = os.clock()
		if now - konamiLast > KONAMI_TIMEOUT then
			konamiStep = 0
		end
		konamiLast = now
		if input.KeyCode == KONAMI[konamiStep + 1] then
			konamiStep += 1
		elseif input.KeyCode == KONAMI[1] then
			konamiStep = if konamiStep == 2 then 2 else 1
		else
			konamiStep = 0
		end
		if konamiStep == #KONAMI then
			konamiStep = 0
			unlockRemote:FireServer()
		end
	end)

	-- Intro: hold on black, fade in while the camera eases out, title and welcome rise in, then the links one by
	-- one, then the Start Game dialog.
	local reduced = GuiService.ReducedMotionEnabled
	curtain.BackgroundTransparency = 0
	shade.BackgroundTransparency = 1
	for _, label in { title, welcome, currentLine } do
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
	end
	for _, b in allLinks do
		b.TextTransparency = 1
	end
	local titleHome = title.Position
	local welcomeHome = welcome.Position
	if not reduced then
		title.Position = titleHome + UDim2.fromOffset(0, 24)
		welcome.Position = welcomeHome + UDim2.fromOffset(0, 16)
	end
	introStart = os.clock()
	setOpen(true)
	task.delay(0.6, function()
		tween(curtain, 2.2, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
		tween(shade, 2.2, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
	end)
	task.delay(1.3, function()
		tween(title, 1.2, { TextTransparency = 0, TextStrokeTransparency = 0.75, Position = titleHome })
	end)
	task.delay(1.9, function()
		tween(welcome, 1, { TextTransparency = 0, Position = welcomeHome })
		tween(currentLine, 1, { TextTransparency = 0 })
	end)
	for i, b in allLinks do
		local padding = make("UIPadding", { PaddingLeft = UDim.new(0, if reduced then 0 else 28) }, b)
		task.delay(2.5 + i * LINK_STAGGER, function()
			tween(b, 0.6, { TextTransparency = 0 })
			tween(padding, 0.6, { PaddingLeft = UDim.new(0, 0) })
		end)
	end
	task.delay(2.6 + #allLinks * LINK_STAGGER, function()
		if root.Visible and openDialog == nil then
			showDialog("Start Game")
		end
	end)
end

return MainMenu
