--!strict
-- Strips texture references that Roblox 403s / has removed, which otherwise
-- render as white or red placeholders in test mode. Plugins (SuperCharacterLoader
-- and friends) re-inject these after load, so we sweep repeatedly, not just once.
--
-- SurfaceAppearance is deliberately not handled: its ColorMap/NormalMap/... are
-- PluginSecurity, so a LocalScript cannot even read them. Touching them throws,
-- and an error here used to abort the whole sweep, leaving every later texture
-- unfixed. Anything we cannot inspect safely is left alone.

local BAD = {
	"149162327", -- (Invalid audio) removed for ToS violations, wired into a texture slot
	"7948622114", -- private decal by another user, not approved for this experience
	"203785492", -- "Pop Close Sound" (audio) used as an image
}

local SWEEP_SECONDS = 20
local SWEEP_EVERY = 0.5

local TEXTURE_PROP = {
	Decal = "Texture",
	Texture = "Texture",
	ImageLabel = "Image",
	ImageButton = "Image",
	MeshPart = "TextureID",
	SpecialMesh = "TextureId",
}

local function isBad(value: unknown): boolean
	if typeof(value) ~= "string" then
		return false
	end
	local s = value :: string
	if s == "" then
		return false
	end
	for _, id in ipairs(BAD) do
		if string.find(s, id, 1, true) then
			return true
		end
	end
	return false
end

local function strip(inst: Instance)
	local prop = TEXTURE_PROP[inst.ClassName]
	if not prop then
		return
	end

	-- Some instances are locked/restricted. Never let one of them throw out of
	-- the sweep or the DescendantAdded handler.
	local okRead, value = pcall(function()
		return (inst :: any)[prop]
	end)
	if not okRead or not isBad(value) then
		return
	end

	pcall(function()
		(inst :: any)[prop] = ""
	end)
end

local function sweep()
	for _, inst in ipairs(game:GetDescendants()) do
		strip(inst)
	end
end

-- Property changes are what actually fire when a plugin rewrites an id in place.
game.DescendantAdded:Connect(function(inst)
	strip(inst)
	inst.Changed:Connect(function()
		strip(inst)
	end)
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
