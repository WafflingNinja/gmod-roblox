--!strict
-- Sky, lighting and water look for the map the local player is on. Lighting is per client, so players on
-- different maps each see their own. ReplicatedStorage.MapLighting.<map id> holds value objects named after
-- Lighting properties (Water* ones are Terrain properties) plus Sky/Atmosphere/effects/Clouds to clone.
-- The place's own lighting is snapshotted at start and used for maps without a folder (the Baseplate).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local ENV_CLASSES = { "Sky", "Atmosphere", "PostEffect", "Clouds" }
local VALUE_CLASSES: { [string]: string } = { number = "NumberValue", Color3 = "Color3Value", boolean = "BoolValue" }

local function isEnv(instance: Instance): boolean
	for _, class in ENV_CLASSES do
		if instance:IsA(class) then
			return true
		end
	end
	return false
end

local function targetFor(name: string): Instance
	return if string.sub(name, 1, 5) == "Water" then Workspace.Terrain else Lighting
end

-- Map folders can name things that aren't properties (TimeOfDay as a string, typos); those are skipped.
local function read(name: string): (boolean, any)
	return pcall(function()
		return (targetFor(name) :: any)[name]
	end)
end

local function snapshot(names: { [string]: boolean }): Folder
	local folder = Instance.new("Folder")
	for name in names do
		local ok, value = read(name)
		local class = if ok then VALUE_CLASSES[typeof(value)] else nil
		if class then
			local holder = Instance.new(class)
			holder.Name = name;
			(holder :: any).Value = value
			holder.Parent = folder
		end
	end
	for _, parent in { Lighting, Workspace.Terrain } :: { Instance } do
		for _, child in parent:GetChildren() do
			if isEnv(child) then
				child:Clone().Parent = folder
			end
		end
	end
	return folder
end

-- Effects that fade in, out and between maps: the properties that tween, and the values that make one invisible.
-- Anything else (Sky) swaps at once.
local EFFECT_TWEEN: { [string]: { string } } = {
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	BloomEffect = { "Intensity", "Size", "Threshold" },
	ColorCorrectionEffect = { "Brightness", "Contrast", "Saturation", "TintColor" },
	SunRaysEffect = { "Intensity", "Spread" },
	Clouds = { "Cover", "Density", "Color" },
}
local EFFECT_OFF: { [string]: { [string]: any } } = {
	Atmosphere = { Density = 0, Haze = 0, Glare = 0 },
	BloomEffect = { Intensity = 0 },
	ColorCorrectionEffect = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) },
	SunRaysEffect = { Intensity = 0 },
	Clouds = { Cover = 0 },
}

local active: { Tween } = {}

-- Tween `goals` on `instance`, or set them at once when seconds is 0 or a property can't tween.
local function play(instance: Instance, goals: { [string]: any }, seconds: number, onDone: (() -> ())?)
	if seconds > 0 then
		local ok, tween = pcall(function()
			return TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine), goals)
		end)
		if ok then
			table.insert(active, tween)
			tween.Completed:Once(function(state)
				local index = table.find(active, tween)
				if index then
					table.remove(active, index) -- finished tweens leave the list, so it cannot grow forever
				end
				if onDone and state == Enum.PlaybackState.Completed then
					onDone()
				end
			end)
			tween:Play()
			return
		end
	end
	for name, value in goals do
		pcall(function()
			(instance :: any)[name] = value
		end)
	end
	if onDone then
		onDone()
	end
end

local function envParent(instance: Instance): Instance
	return if instance:IsA("Clouds") then Workspace.Terrain else Lighting
end

local function envKey(instance: Instance): string
	return instance.ClassName .. "/" .. instance.Name
end

local function effectGoals(instance: Instance): { [string]: any }
	local goals = {}
	for _, name in EFFECT_TWEEN[instance.ClassName] do
		goals[name] = (instance :: any)[name]
	end
	return goals
end

local function applyEffects(folder: Instance, seconds: number)
	local current: { [string]: Instance } = {}
	for _, parent in { Lighting, Workspace.Terrain } :: { Instance } do
		for _, child in parent:GetChildren() do
			if isEnv(child) then
				current[envKey(child)] = child
			end
		end
	end
	for _, child in folder:GetChildren() do
		if not isEnv(child) then
			continue
		end
		local key = envKey(child)
		local existing = current[key]
		current[key] = nil
		local class = child.ClassName
		if EFFECT_TWEEN[class] then
			if existing then
				play(existing, effectGoals(child), seconds)
			else
				local fresh = child:Clone()
				if seconds > 0 then
					for name, value in EFFECT_OFF[class] do
						(fresh :: any)[name] = value
					end
				end
				fresh.Parent = envParent(child)
				if seconds > 0 then
					play(fresh, effectGoals(child), seconds)
				end
			end
		else
			if existing then
				existing:Destroy()
			end
			child:Clone().Parent = envParent(child)
		end
	end
	-- Effects the new map doesn't have fade out, then go.
	for _, leftover in current do
		local off = EFFECT_OFF[leftover.ClassName]
		if off and seconds > 0 then
			play(leftover, off, seconds, function()
				leftover:Destroy()
			end)
		else
			leftover:Destroy()
		end
	end
end

local function apply(folder: Instance, seconds: number)
	for _, tween in active do
		tween:Cancel()
	end
	table.clear(active)

	local goals: { [Instance]: { [string]: any } } = {}
	for _, child in folder:GetChildren() do
		if not child:IsA("ValueBase") then
			continue
		end
		local target = targetFor(child.Name)
		local value = (child :: any).Value
		if (typeof(value) == "number" or typeof(value) == "Color3") and read(child.Name) then
			local forTarget = goals[target] or {}
			forTarget[child.Name] = value
			goals[target] = forTarget
		else
			-- A stray TimeOfDay (string) next to ClockTime would win by folder order; ClockTime is the source.
			if child.Name == "TimeOfDay" and folder:FindFirstChild("ClockTime") then
				continue
			end
			pcall(function()
				(target :: any)[child.Name] = value
			end)
		end
	end
	for target, forTarget in goals do
		play(target, forTarget, seconds)
	end
	applyEffects(folder, seconds)
end

local player = Players.LocalPlayer
local folders: Instance? = nil
local baseline: Folder? = nil
local previewing: string? = nil -- the main menu shows another map's sky behind it
local applied = false

local function update()
	local id = previewing or player:GetAttribute(Config.MAP_ATTRIBUTE)
	local folder = if folders and typeof(id) == "string" then folders:FindFirstChild(id) else nil
	local fallback = baseline
	if folder or fallback then
		apply((folder or fallback) :: Instance, if applied then Config.LIGHTING_FADE else 0)
		applied = true
	end
end

local MapLighting = {}

-- Show map `id`'s lighting until called with nil, which goes back to the player's own map.
function MapLighting.preview(id: string?)
	if previewing ~= id then
		previewing = id
		update()
	end
end

function MapLighting.init()
	folders = ReplicatedStorage:WaitForChild("MapLighting", 10)
	local names: { [string]: boolean } = {}
	if folders then
		for _, folder in folders:GetChildren() do
			for _, child in folder:GetChildren() do
				if child:IsA("ValueBase") then
					names[child.Name] = true
				end
			end
		end
	end
	baseline = snapshot(names)
	player:GetAttributeChangedSignal(Config.MAP_ATTRIBUTE):Connect(update)
	update()
end

return MapLighting
