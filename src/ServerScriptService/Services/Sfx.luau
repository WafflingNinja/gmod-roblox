--!strict
-- 3D sound effects played from the server, so every nearby player hears them.
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Sounds)

local MAX_DISTANCE = 150 -- studs until silent
local LIFETIME = 5 -- seconds a one-shot lives

local function make(name: string): Sound?
	local def = Sounds[name]
	if not def or def.id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.RollOffMaxDistance = MAX_DISTANCE
	return sound
end

local Sfx = {}

-- One-shot from `parent` (a part or attachment), pitch varied a little so repeats don't drone.
function Sfx.play(name: string, parent: Instance)
	local sound = make(name)
	if not sound then
		return
	end
	sound.PlaybackSpeed = 0.95 + math.random() * 0.1
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, LIFETIME)
end

-- One-shot at a world point, for things that are about to be destroyed.
function Sfx.playAt(name: string, position: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Parent = Workspace.Terrain
	attachment.WorldPosition = position
	Sfx.play(name, attachment)
	Debris:AddItem(attachment, LIFETIME)
end

-- Looping sound from `parent`; the caller destroys it.
function Sfx.loop(name: string, parent: Instance): Sound?
	local sound = make(name)
	if not sound then
		return nil
	end
	sound.Looped = true
	sound.Parent = parent
	sound:Play()
	return sound
end

return Sfx
