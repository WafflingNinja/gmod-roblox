--!strict
-- Flat UI sounds only we hear (weapon selector ticks, deny buzz on a toast).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local cache: { [string]: Sound } = {}

local function get(name: string): Sound?
	local cached = cache[name]
	if cached then
		return cached
	end
	local def = Sounds[name]
	if not def or def.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.Parent = SoundService
	cache[name] = sound
	return sound
end

local Sfx = {}

function Sfx.play(name: string)
	local sound = get(name)
	if sound then
		sound.TimePosition = 0
		sound:Play()
	end
end

return Sfx
