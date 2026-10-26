--!strict
-- Asset ids that Roblox refuses to serve (removed for ToS, private, or wrong asset type). They render as
-- white / red placeholders, so anything that points at them is treated as missing. Kept in one place because
-- both the server map cleanup and the client plugin-injection sweep need the same list.
--
-- SurfaceAppearance is deliberately absent: its ColorMap/NormalMap/... are PluginSecurity, so a LocalScript
-- cannot read them. Touching them throws; anything we cannot inspect safely is left alone.

export type TextureProp = { [string]: string }

local TEXTURE_PROP: TextureProp = {
	Decal = "Texture",
	Texture = "Texture",
	ParticleEmitter = "Texture", -- map effects (e.g. Construct's GlitchEffect) also use asset slots
	Beam = "Texture",
	Trail = "Texture",
	Fire = "Texture",
	Smoke = "Texture",
	Sparkles = "Texture",
	ImageLabel = "Image",
	ImageButton = "Image",
	ImageHandleAdornment = "Image",
	MeshPart = "TextureID",
	SpecialMesh = "TextureId",
}

-- Clearing a particle/effect texture just falls back to the default white sprite,
-- which still shows as floating squares. Turn the effect off instead.
local EFFECT_CLASS: { [string]: boolean } = {
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	Fire = true,
	Smoke = true,
	Sparkles = true,
}

local IDS = {
	"149162327", -- removed audio wired into a texture slot
	"7948622114", -- private decal by another user, not approved for this experience
	"203785492", -- audio used as an image
}

local BadAssets = {
	textureProp = TEXTURE_PROP,
	effectClass = EFFECT_CLASS,
}

function BadAssets.isBad(value: unknown): boolean
	if typeof(value) ~= "string" or value == "" then
		return false
	end
	for _, id in IDS do
		if string.find(value, id, 1, true) then
			return true
		end
	end
	return false
end

-- Clear the property and disable the effect. Returns true when it changed something.
-- Every access is pcall'd: some instances are locked, and one throwing must not abort a map sweep.
function BadAssets.strip(instance: Instance): boolean
	local prop = TEXTURE_PROP[instance.ClassName]
	if not prop then
		return false
	end
	local okRead, value = pcall(function()
		return (instance :: any)[prop]
	end)
	if not okRead or not BadAssets.isBad(value) then
		return false
	end
	pcall(function()
		(instance :: any)[prop] = ""
	end)
	if EFFECT_CLASS[instance.ClassName] then
		pcall(function()
			(instance :: any).Enabled = false
		end)
	end
	return true
end

return table.freeze(BadAssets)
