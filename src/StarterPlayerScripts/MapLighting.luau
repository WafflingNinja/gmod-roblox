--!strict
-- Sky, lighting and water look for the map the local player is on. Lighting is per client, so players on
-- different maps each see their own. ReplicatedStorage.MapLighting.<map id> holds value objects named after
-- Lighting properties (Water* ones are Terrain properties) plus Sky/Atmosphere/effects/Clouds to clone.
-- The place's own lighting is snapshotted at start and used for maps without a folder (the Baseplate).
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local function apply(folder: Instance)
	for _, parent in { Lighting, Workspace.Terrain } :: { Instance } do
		for _, child in parent:GetChildren() do
			if isEnv(child) then
				child:Destroy()
			end
		end
	end
	for _, child in folder:GetChildren() do
		if child:IsA("ValueBase") then
			pcall(function()
				(targetFor(child.Name) :: any)[child.Name] = (child :: any).Value
			end)
		elseif isEnv(child) then
			child:Clone().Parent = if child:IsA("Clouds") then Workspace.Terrain else Lighting
		end
	end
end

local player = Players.LocalPlayer
local folders: Instance? = nil
local baseline: Folder? = nil
local previewing: string? = nil -- the main menu shows another map's sky behind it

local function update()
	local id = previewing or player:GetAttribute(Config.MAP_ATTRIBUTE)
	local folder = if folders and typeof(id) == "string" then folders:FindFirstChild(id) else nil
	local fallback = baseline
	if folder or fallback then
		apply((folder or fallback) :: Instance)
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
