--!strict
-- Main menu, Source/Gmod style: the camera circles the selected map behind a text-link menu on the left, and
-- each page opens as a gray dialog with a blue title bar. Opens on join, M toggles it. The full-screen root is
-- a Modal button, which frees the first-person mouse while the menu is open. Settings last for the session.
-- On join it opens with a short intro: fade from black, the camera eases out, the title and a welcome rise in,
-- then the links. Dialogs pop open and drag by their title bar. Starting a map fades through black.
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
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
local PassCatalog = require(ReplicatedStorage.Shared.PassCatalog)

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
-- Link colours from Gmod's html/css/menu/PageOptions.css: white, #ffa on hover, #ff5 for the open page.
local LINK_COLOR = Color3.new(1, 1, 1)
local LINK_HOVER = Color3.fromRGB(255, 255, 170)
local LINK_ACTIVE = Color3.fromRGB(255, 255, 85)
local CONTROLS = {
	{ "WASD", "walk" },
	{ "Shift / Ctrl", "sprint / crouch" },
	{ "Space (hold)", "bunny hop" },
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

-- Gmod's HTML pages (html/css/menu/NewGame.css, Menu.css, NavBar.css): white rounded panels, #333 text, blue
-- gradient primary buttons, #97c5ff selection, #9cf active category, #ddd category rows.
local WEB = {
	panel = Color3.new(1, 1, 1),
	text = Color3.fromRGB(51, 51, 51),
	label = Color3.fromRGB(102, 102, 102),
	muted = Color3.fromRGB(153, 153, 153),
	heading = Color3.fromRGB(68, 68, 68),
	row = Color3.new(1, 1, 1),
	rowAlt = Color3.fromRGB(242, 242, 242),
	selected = Color3.fromRGB(151, 197, 255),
	category = Color3.fromRGB(221, 221, 221),
	categoryActive = Color3.fromRGB(153, 204, 255),
	count = Color3.fromRGB(170, 170, 170),
	scrollbar = Color3.fromRGB(180, 180, 180),
	inputBorder = Color3.fromRGB(171, 173, 179),
	primary = ColorSequence.new(Color3.fromRGB(0, 136, 204), Color3.fromRGB(0, 85, 204)),
	primaryHover = ColorSequence.new(Color3.fromRGB(34, 170, 238), Color3.fromRGB(34, 119, 238)),
	primaryBorder = Color3.fromRGB(0, 85, 204),
	owned = Color3.fromRGB(34, 170, 34),
	radius = UDim.new(0, 5),
}

-- One live tween per instance: a new tween on the same instance cancels the old one, so rapid toggles
-- (curtain, dialog pop) never leave two tweens fighting over one property.
local liveTweens: { [Instance]: Tween } = {}

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	local previous = liveTweens[instance]
	if previous then
		previous:Cancel()
	end
	local running = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		goal
	)
	liveTweens[instance] = running
	running:Play()
end

local function merge(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	if extra then
		for key, value in extra do
			base[key] = value
		end
	end
	return base
end

-- Dark text for the white pages.
local function ink(str: string, parent: Instance, props: { [string]: any }?): TextLabel
	return text(str, parent, merge({ TextColor3 = WEB.text }, props))
end

-- Tiny flat icons drawn from frames: no ripped art, no asset ids that can go missing. Returns the frames so a
-- caller can tint them (hover) or fade them (intro). Kinds: play, back, grid, pad, gear, bag, search.
local function icon(kind: string, parent: GuiObject, color: Color3): { Frame }
	local box = make("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
	}, parent)
	local frames: { Frame } = {}
	local function bar(w: number, h: number, x: number, y: number, round: number, rot: number?)
		local shape = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Rotation = rot or 0,
		}, box)
		make("UICorner", { CornerRadius = UDim.new(0, round) }, shape)
		table.insert(frames, shape)
	end
	if kind == "play" then
		bar(3, 8, 6, 6, 1, 40)
		bar(3, 8, 6, 14, 1, -40)
	elseif kind == "back" then
		bar(3, 8, 8, 6, 1, -40)
		bar(3, 8, 8, 14, 1, 40)
	elseif kind == "grid" then
		bar(6, 6, 5, 5, 1)
		bar(6, 6, 13, 5, 1)
		bar(6, 6, 5, 13, 1)
		bar(6, 6, 13, 13, 1)
	elseif kind == "pad" then
		bar(16, 9, 10, 11, 4)
		bar(3, 3, 7, 11, 1)
		bar(3, 3, 13, 11, 1)
	elseif kind == "gear" then
		bar(11, 11, 10, 10, 6)
		bar(3, 5, 10, 3, 1)
		bar(3, 5, 10, 17, 1)
		bar(5, 3, 3, 10, 1)
		bar(5, 3, 17, 10, 1)
	elseif kind == "search" then
		bar(10, 10, 8, 8, 5)
		bar(3, 7, 14, 14, 1, -45)
	elseif kind == "bag" then
		bar(13, 10, 10, 12, 2)
		bar(2, 4, 10, 5, 1)
		bar(8, 2, 10, 4, 1)
	end
	return frames
end

-- Browser-default grey button, for the white pages' small controls.
local function plainButton(label: string, parent: Instance, props: { [string]: any }?): TextButton
	local b: TextButton = make(
		"TextButton",
		merge({
			Text = label,
			Font = THEME.font,
			TextSize = 14,
			TextColor3 = WEB.text,
			BackgroundColor3 = Color3.fromRGB(239, 239, 239),
			BorderSizePixel = 0,
			AutoButtonColor = false,
		}, props),
		parent
	)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, b)
	make("UIStroke", { Color = Color3.fromRGB(118, 118, 118), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = Color3.fromRGB(229, 229, 229)
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = Color3.fromRGB(239, 239, 239)
	end)
	return b
end

-- Gmod's .btn-primary: blue gradient, darker blue border, white bold text. `props` size and place the fill, which
-- is the button's parent (the gradient would tint text if it sat on the button itself).
local function primaryButton(label: string, parent: Instance, props: { [string]: any }?): TextButton
	local fill: Frame =
		make("Frame", merge({ BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, props), parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, fill)
	make("UIStroke", { Color = WEB.primaryBorder, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, fill)
	local gradient: UIGradient = make("UIGradient", { Color = WEB.primary, Rotation = 90 }, fill)
	local b: TextButton = make("TextButton", {
		Text = label,
		Font = THEME.bold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
	}, fill)
	b.MouseEnter:Connect(function()
		gradient.Color = WEB.primaryHover
	end)
	b.MouseLeave:Connect(function()
		gradient.Color = WEB.primary
	end)
	return b
end

-- Gmod's .innerpage: a white rounded panel right of the menu links, above the nav bar.
local function infoPage(name: string, parent: Instance): Frame
	local frame: Frame = make("Frame", {
		Name = name,
		Position = UDim2.fromOffset(320, 16),
		Size = UDim2.new(1, -336, 1, -32),
		BackgroundColor3 = WEB.panel,
		BorderSizePixel = 0,
		Visible = false,
	}, parent)
	make("UICorner", { CornerRadius = WEB.radius }, frame)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 16),
		PaddingBottom = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 16),
		PaddingRight = UDim.new(0, 16),
	}, frame)
	-- showDialog pops this open (Scale 0.9 -> 1); without it the page would just blink on.
	make("UIScale", { Scale = 1 }, frame)
	return frame
end

local function webList(parent: Instance): ScrollingFrame
	local frame: ScrollingFrame = make("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = WEB.scrollbar,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, parent)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
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
	ink(name, row, { Size = UDim2.new(1, -150, 1, 0) })
	local value = ink("", row, {
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
		plainButton(if direction < 0 then "-" else "+", row, {
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
	if def.placeId and def.placeId ~= game.PlaceId then
		return true -- Split Worlds: the map lives in its own place; teleporting there is the start.
	end
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
		Position = UDim2.fromOffset(86, 50), -- Gmod: 50 px padding + 20 margin + 16 px item padding
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
	make("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }, links)

	-- Gmod's .page: every page sits above the nav bar.
	local pageArea = make("Frame", { Size = UDim2.new(1, 0, 1, -50), BackgroundTransparency = 1 }, root)

	-- Gmod's #NavBar: a half-black 50 px strip with white 40 px buttons that glow on hover.
	local navbar = make("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, root)
	local function navButton(label: string, kind: string, props: { [string]: any }): TextButton
		local b: TextButton = make(
			"TextButton",
			merge({
				Text = label,
				Font = THEME.bold,
				TextSize = 13,
				TextColor3 = WEB.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				AutoButtonColor = false,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 40),
			}, props),
			navbar
		)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
		make("UIPadding", { PaddingLeft = UDim.new(0, 36), PaddingRight = UDim.new(0, 14) }, b)
		local tint = icon(kind, b, WEB.text)
		for _, shape in tint do
			shape.Position += UDim2.fromOffset(12, 0)
		end
		local glow = make("UIStroke", {
			Color = Color3.new(1, 1, 1),
			Thickness = 4,
			Transparency = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, b)
		b.MouseEnter:Connect(function()
			glow.Transparency = 0.5
		end)
		b.MouseLeave:Connect(function()
			glow.Transparency = 1
		end)
		return b
	end
	local backButton = navButton("Back to Main Menu", "back", { Position = UDim2.fromOffset(5, 5), Visible = false })
	local gameButton =
		navButton("Back to Game", "play", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.9, 0, 0, 5) })

	-- Black curtain for the intro and map changes. Outside `root`, so it stays up while the menu closes.
	local curtain: Frame = make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, gui)

	-- Menu music: nothing is created until Config.MENU_MUSIC_ID is set.
	local music: Sound? = nil
	if Config.MENU_MUSIC_ID ~= "" then
		music = make("Sound", { Name = "MenuMusic", SoundId = Config.MENU_MUSIC_ID, Looped = true, Volume = 0 }, gui)
	end
	local musicToken = 0
	local function fadeMusic(on: boolean)
		local sound = music
		if not sound then
			return
		end
		musicToken += 1
		local token = musicToken
		if on and not sound.IsPlaying then
			sound.Volume = 0
			sound:Play()
		end
		local fade = TweenService:Create(
			sound,
			TweenInfo.new(Config.MENU_MUSIC_FADE, Enum.EasingStyle.Sine),
			{ Volume = if on then Config.MENU_MUSIC_VOLUME else 0 }
		)
		if not on then
			fade.Completed:Once(function()
				if musicToken == token then
					sound:Stop()
				end
			end)
		end
		fade:Play()
	end

	local dialogs: { [string]: Frame } = {}
	local linkButtons: { [string]: TextButton } = {}
	local linkIcons: { [TextButton]: { Frame } } = {}
	local allLinks: { TextButton } = {}
	local openDialog: string? = nil
	local function showDialog(name: string?)
		local previous = openDialog
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
			link.TextColor3 = if linkName == name then LINK_ACTIVE else LINK_COLOR
		end
		-- Gmod's New Game page replaces the menu links; the other pages sit beside them.
		left.Visible = name ~= "Start Game"
		backButton.Visible = name ~= nil
		-- A gamepad needs a focused control: the first button on the page, or the link that opened it back.
		if UserInputService.GamepadEnabled and root.Visible then
			local frame = if name then dialogs[name] else nil
			if frame then
				GuiService.SelectedObject = frame:FindFirstWhichIsA("GuiButton", true)
			elseif previous then
				GuiService.SelectedObject = linkButtons[previous] or allLinks[1]
			end
		end
	end
	-- Gmod main menu: plain white text, no boxes, a soft shadow so it reads over any map. Each link gets a
	-- small flat icon so the column reads at a glance.
	local function link(order: number, label: string, kind: string, onClick: () -> ()): TextButton
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, links)
		local tint = icon(kind, row, LINK_COLOR)
		local b: TextButton = make("TextButton", {
			Text = label,
			Font = THEME.bold,
			TextSize = 23,
			TextColor3 = LINK_COLOR,
			TextStrokeTransparency = 0.6,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Position = UDim2.fromOffset(30, 0),
			Size = UDim2.new(1, -30, 1, 0),
		}, row)
		b.MouseEnter:Connect(function()
			b.TextColor3 = LINK_HOVER
			for _, shape in tint do
				shape.BackgroundColor3 = LINK_HOVER
			end
		end)
		b.MouseLeave:Connect(function()
			b.TextColor3 = if openDialog == label then LINK_ACTIVE else LINK_COLOR
			for _, shape in tint do
				shape.BackgroundColor3 = LINK_COLOR
			end
		end)
		b.Activated:Connect(onClick)
		table.insert(allLinks, b)
		linkIcons[b] = tint
		return b
	end

	-- Camera circles the selected map while the menu is open.
	local orbitAngle = 0
	local orbitDef = MapCatalog.byId[MapCatalog.DEFAULT]
	local orbitCenter = Vector3.zero -- set from orbitDef in selectMap, so the render step allocates nothing
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
			local center = orbitCenter
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
				if other.Parent then
					other.Enabled = true
				end
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

	-- Start Game: Gmod's New Game page. A white map list (category, search, 128 px tiles) on the left, a white
	-- panel with the map details and the big blue button on the right.
	local playFrame = make(
		"Frame",
		{ Name = "Start Game", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false },
		pageArea
	)
	dialogs["Start Game"] = playFrame
	make("UIScale", { Scale = 1 }, playFrame)
	local mapPanel = make("Frame", {
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -272, 1, -32),
		BackgroundColor3 = WEB.panel,
		BorderSizePixel = 0,
	}, playFrame)
	make("UICorner", { CornerRadius = WEB.radius }, mapPanel)
	local category = make("Frame", {
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.new(1, -20, 0, 26),
		BackgroundColor3 = WEB.categoryActive,
		BorderSizePixel = 0,
	}, mapPanel)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, category)
	ink("Sandbox", category, {
		Position = UDim2.fromOffset(6, 0),
		Size = UDim2.new(1, -38, 1, 0),
		Font = THEME.bold,
		TextSize = 12,
	})
	local categoryCount = ink("", category, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -5, 0.5, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		TextColor3 = WEB.count,
		Font = THEME.bold,
		TextSize = 11,
	})
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, categoryCount)
	make("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, categoryCount)
	local search: TextBox = make("TextBox", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(1, -20, 0, 26),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Search...",
		PlaceholderColor3 = WEB.muted,
		TextColor3 = WEB.text,
		Font = THEME.font,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
	}, mapPanel)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, search)
	make("UIStroke", { Color = WEB.inputBorder, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, search)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, search)

	-- Map list: one row per map (icon tile, name, blurb). Gmod's New Game page, without the 128 px grey "?"
	-- placeholder grid that made the page look unfinished.
	local mapScroll: ScrollingFrame = make("ScrollingFrame", {
		Position = UDim2.fromOffset(10, 44),
		Size = UDim2.new(1, -20, 1, -88),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = WEB.scrollbar,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, mapPanel)
	make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, mapScroll)

	local settingsPanel = make("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.new(0, 226, 1, -32),
		BackgroundColor3 = WEB.panel,
		BorderSizePixel = 0,
	}, playFrame)
	make("UICorner", { CornerRadius = WEB.radius }, settingsPanel)
	local details = make(
		"Frame",
		{ Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -90), BackgroundTransparency = 1 },
		settingsPanel
	)
	local detailName = ink("", details, { Size = UDim2.new(1, 0, 0, 28), Font = THEME.bold, TextSize = 22 })
	local detailHere = ink("", details, {
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 12,
		Font = THEME.bold,
		TextColor3 = WEB.primaryBorder,
	})
	local detailBlurb = ink("", details, {
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		TextSize = 13,
		TextColor3 = WEB.label,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local start = primaryButton("Start", settingsPanel, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(1, -36, 0, 44),
	})
	start.TextSize = 20
	for _, shape in icon("play", start, Color3.new(1, 1, 1)) do
		shape.Position += UDim2.fromOffset(14, 0)
	end

	local function rowColor(order: number): Color3
		return if order % 2 == 1 then WEB.row else WEB.rowAlt
	end

	local MAP_TINTS = {
		{ 122, 156, 196 },
		{ 122, 166, 138 },
		{ 156, 132, 180 },
		{ 190, 152, 112 },
		{ 112, 158, 180 },
		{ 172, 138, 130 },
		{ 182, 172, 122 },
		{ 140, 142, 164 },
	}
	local tiles: { [string]: TextButton } = {}
	local tileBase: { [string]: Color3 } = {}
	local selected = MapCatalog.DEFAULT
	local function refreshTiles()
		local query = string.lower(search.Text)
		local shown = 0
		for _, map in MapCatalog.list do
			local row = tiles[map.id]
			local visible = mapAvailable(map)
				and (query == "" or string.find(string.lower(map.name), query, 1, true) ~= nil)
			row.Visible = visible
			row.BackgroundColor3 = if map.id == selected then WEB.selected else tileBase[map.id]
			if visible then
				shown += 1
			end
		end
		categoryCount.Text = tostring(shown)
	end
	local function selectMap(id: string)
		local def = MapCatalog.byId[id]
		if not def then
			return
		end
		selected = id
		local current = player:GetAttribute(Config.MAP_ATTRIBUTE)
		detailName.Text = def.name
		detailHere.Text = if current == id then "You are here" else ""
		detailBlurb.Text = def.blurb
		start.Text = if current == id then "Respawn here" else "Start"
		orbitDef = def
		orbitCenter = Vector3.new(def.orbit.center[1], def.orbit.center[2], def.orbit.center[3])
		MapLighting.preview(id)
		refreshTiles()
	end
	for order, def in MapCatalog.list do
		local row: TextButton = make("TextButton", {
			Name = def.name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = rowColor(order),
			BorderSizePixel = 0,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 56),
		}, mapScroll)
		make("UICorner", { CornerRadius = UDim.new(0, 3) }, row)
		local tint = MAP_TINTS[(order - 1) % #MAP_TINTS + 1]
		local thumb = make("Frame", {
			Position = UDim2.fromOffset(6, 6),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = Color3.fromRGB(tint[1], tint[2], tint[3]),
			BorderSizePixel = 0,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 3) }, thumb)
		ink(string.upper(string.sub(def.name, 1, 1)), thumb, {
			Size = UDim2.fromScale(1, 1),
			Font = THEME.bold,
			TextSize = 24,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		ink(def.name, row, {
			Position = UDim2.fromOffset(58, 7),
			Size = UDim2.new(1, -68, 0, 20),
			Font = THEME.bold,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		ink(def.blurb, row, {
			Position = UDim2.fromOffset(58, 27),
			Size = UDim2.new(1, -68, 0, 22),
			TextSize = 12,
			TextColor3 = WEB.label,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		row.MouseEnter:Connect(function()
			if selected ~= def.id then
				row.BackgroundColor3 = WEB.category
			end
		end)
		row.MouseLeave:Connect(function()
			if selected ~= def.id then
				row.BackgroundColor3 = tileBase[def.id]
			end
		end)
		row.Activated:Connect(function()
			selectMap(def.id)
		end)
		tiles[def.id] = row
		tileBase[def.id] = rowColor(order)
	end
	search:GetPropertyChangedSignal("Text"):Connect(refreshTiles)

	-- Controls: alternating rows on a white page.
	local controlsFrame = infoPage("Controls", pageArea)
	dialogs.Controls = controlsFrame
	local controlsList = webList(controlsFrame)
	for order, entry in CONTROLS do
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = rowColor(order),
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, controlsList)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, row)
		ink(entry[1], row, { Size = UDim2.fromScale(0.32, 1), Font = THEME.bold, TextColor3 = WEB.primaryBorder })
		ink(entry[2], row, {
			Position = UDim2.fromScale(0.32, 0),
			Size = UDim2.fromScale(0.68, 1),
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	local tip = ink(TRACKPAD_TIP, controlsList, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 15,
		TextColor3 = WEB.muted,
		TextWrapped = true,
		LayoutOrder = #CONTROLS + 1,
	})
	make(
		"UIPadding",
		{ PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) },
		tip
	)

	-- Options
	local optionsBody = infoPage("Options", pageArea)
	dialogs.Options = optionsBody
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, optionsBody)
	stepper(optionsBody, 1, "Mouse / trackpad sensitivity", function()
		return UserInputService.MouseDeltaSensitivity
	end, function(v)
		UserInputService.MouseDeltaSensitivity = v
	end, 0.1, 0.1, 3)
	stepper(optionsBody, 2, "Field of view", FirstPerson.fieldOfView, FirstPerson.setFieldOfView, 5, 60, 110)
	-- "name   [state]" row; returns the button so the caller sets its text.
	local function toggleRow(order: number, name: string): TextButton
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, optionsBody)
		ink(name, row, { Size = UDim2.new(1, -150, 1, 0) })
		return plainButton("", row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(140, 26),
		})
	end
	local lookToggle = toggleRow(3, "Arrow keys look around")
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
	local pvpToggle = toggleRow(5, "PvP (guns hurt players who also have it on)")
	local function refreshPvp()
		pvpToggle.Text = if player:GetAttribute(Config.PVP_ATTRIBUTE) == true then "On" else "Off"
	end
	pvpToggle.Activated:Connect(function()
		pvpRemote:FireServer(player:GetAttribute(Config.PVP_ATTRIBUTE) ~= true)
	end)
	Ui.tooltip(pvpToggle, "Guns only hurt players who also have PvP on")
	player:GetAttributeChangedSignal(Config.PVP_ATTRIBUTE):Connect(refreshPvp)
	refreshPvp()

	-- Store: every pass and tip, with the owned state live from the Player attributes.
	local storeFrame = infoPage("Store", pageArea)
	dialogs.Store = storeFrame
	local storeList = webList(storeFrame)
	local storeOrder = 0
	local function storeHeading(headingText: string)
		storeOrder += 1
		local heading = ink(headingText, storeList, {
			Size = UDim2.new(1, 0, 0, 36),
			TextSize = 26,
			TextColor3 = WEB.heading,
			LayoutOrder = storeOrder,
		})
		make("UIPadding", { PaddingLeft = UDim.new(0, 5) }, heading)
	end
	local function storeRow(item: PassCatalog.Item)
		storeOrder += 1
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundColor3 = rowColor(storeOrder),
			BorderSizePixel = 0,
			LayoutOrder = storeOrder,
		}, storeList)
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, row)
		local itemIcon: GuiObject
		if item.assetId then
			itemIcon = make("ImageLabel", {
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.fromOffset(44, 44),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = `rbxassetid://{item.assetId}`,
				ScaleType = Enum.ScaleType.Fit,
			}, row)
		else
			itemIcon = make("Frame", {
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.fromOffset(44, 44),
				BackgroundColor3 = Color3.fromRGB(item.tint[1], item.tint[2], item.tint[3]),
				BorderSizePixel = 0,
			}, row)
			text(string.sub(item.name, 1, 1), itemIcon, {
				Size = UDim2.fromScale(1, 1),
				Font = THEME.bold,
				TextSize = 20,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = Color3.new(0, 0, 0),
				TextTransparency = 0.25,
			})
		end
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, itemIcon)
		ink(item.name, row, {
			Position = UDim2.fromOffset(54, 6),
			Size = UDim2.new(1, -160, 0, 20),
			Font = THEME.bold,
			TextSize = 17,
		})
		ink(item.description, row, {
			Position = UDim2.fromOffset(54, 26),
			Size = UDim2.new(1, -160, 0, 28),
			TextSize = 14,
			TextColor3 = WEB.label,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		local buy = primaryButton(`R${item.price}`, row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(88, 30),
		})
		local buyFill = buy.Parent :: Frame
		local ownedLabel = ink("Owned", row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(88, 30),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = THEME.bold,
			TextColor3 = WEB.owned,
			Visible = false,
		})
		if item.kind == "pass" then
			local attribute = PassCatalog.attribute(item.key)
			local function refresh()
				local owned = player:GetAttribute(attribute) == true
				buyFill.Visible = not owned
				ownedLabel.Visible = owned
			end
			player:GetAttributeChangedSignal(attribute):Connect(refresh)
			refresh()
			buy.Activated:Connect(function()
				MarketplaceService:PromptGamePassPurchase(player, item.id)
			end)
		else
			buy.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(player, item.id)
			end)
		end
	end
	storeHeading("Passes")
	for _, item in PassCatalog.passes do
		storeRow(item)
	end
	storeHeading("Tips")
	for _, item in PassCatalog.products do
		storeRow(item)
	end

	local function refreshCurrent()
		local id = player:GetAttribute(Config.MAP_ATTRIBUTE)
		local def = if typeof(id) == "string" then MapCatalog.byId[id] else nil
		currentLine.Text = if def then `Current map: {def.name}` else ""
	end
	player:GetAttributeChangedSignal(Config.MAP_ATTRIBUTE):Connect(refreshCurrent)

	local function setOpen(open: boolean)
		root.Visible = open
		hideOtherGuis(open)
		fadeMusic(open)
		if open then
			refreshCurrent()
			local current = player:GetAttribute(Config.MAP_ATTRIBUTE)
			selectMap(if typeof(current) == "string" and MapCatalog.byId[current] then current else MapCatalog.DEFAULT)
			startOrbit()
			-- A gamepad needs something focused or it can't move through the menu.
			if UserInputService.GamepadEnabled and allLinks[1] then
				GuiService.SelectedObject = allLinks[1]
			end
		else
			showDialog(nil)
			stopOrbit()
			GuiService.SelectedObject = nil
			MapLighting.preview(nil)
		end
	end

	link(1, "Resume Game", "play", function()
		setOpen(false)
	end)
	for order, entry in { { "Start Game", "grid" }, { "Controls", "pad" }, { "Options", "gear" }, { "Store", "bag" } } do
		local name = entry[1]
		linkButtons[name] = link(order + 1, name, entry[2], function()
			showDialog(if openDialog == name then nil else name)
		end)
	end
	backButton.Activated:Connect(function()
		showDialog(nil)
	end)
	gameButton.Activated:Connect(function()
		setOpen(false)
	end)
	-- Fade through black so the jump to another map isn't a hard cut.
	local starting = false
	start.Activated:Connect(function()
		if starting then
			return
		end
		starting = true
		fadeMusic(false)
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
		-- Gamepad B: close the open page first, then the menu itself.
		if not processed and root.Visible and input.KeyCode == Enum.KeyCode.ButtonB then
			if openDialog then
				showDialog(nil)
			else
				setOpen(false)
			end
			return
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
		local shapes = linkIcons[b]
		if shapes then
			for _, shape in shapes do
				shape.BackgroundTransparency = 1
			end
		end
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
			local shapes = linkIcons[b]
			if shapes then
				for _, shape in shapes do
					tween(shape, 0.6, { BackgroundTransparency = 0 })
				end
			end
		end)
	end
end

return MainMenu
