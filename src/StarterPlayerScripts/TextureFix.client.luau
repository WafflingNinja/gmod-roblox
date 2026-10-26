--!strict
-- Strips texture references that Roblox 403s / has removed, which otherwise render as white or red
-- placeholders. Plugins (SuperCharacterLoader and friends) re-inject these after load, so we sweep for the
-- first few seconds and watch the instances that actually carried a bad id. Only those instances get a
-- Changed connection; watching every MeshPart in the 30k-part maps cost more than the sweep itself.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BadAssets = require(ReplicatedStorage.Shared.BadAssets)

local SWEEP_SECONDS = 8
local SWEEP_EVERY = 1.5

-- These classes realistically have their texture swapped in place by a plugin. MeshPart/SpecialMesh ids are
-- set when the map is built; they are stripped by the sweep but do not need a per-instance watcher.
local WATCH = {
	Decal = true,
	Texture = true,
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	Fire = true,
	Smoke = true,
	Sparkles = true,
	ImageLabel = true,
	ImageButton = true,
	ImageHandleAdornment = true,
}

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function watch(instance: Instance)
	if watched[instance] then
		return
	end
	watched[instance] = true
	instance.Changed:Connect(function()
		BadAssets.strip(instance)
	end)
end

local function sweep()
	for _, inst in ipairs(game:GetDescendants()) do
		if BadAssets.strip(inst) and BadAssets.textureProp[inst.ClassName] then
			watch(inst)
		end
	end
end

game.DescendantAdded:Connect(function(inst)
	BadAssets.strip(inst)
	if WATCH[inst.ClassName] then
		watch(inst)
	end
end)

sweep()

-- Keep fixing for the first stretch of the session, while plugins spin up.
task.spawn(function()
	local deadline = os.clock() + SWEEP_SECONDS
	while os.clock() < deadline do
		task.wait(SWEEP_EVERY)
		sweep()
	end
end)
