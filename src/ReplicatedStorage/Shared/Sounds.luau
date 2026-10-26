--!strict
-- Sound effects by name. Plain data so lune can check it.
-- Originals are synthesized by audio/sfx.py: upload audio/exports/<name>.ogg and paste the rbxassetid here.
-- id "" = not uploaded yet; playing it does nothing. rbxasset:// ids are files that ship with Roblox.
export type SoundDef = { id: string, volume: number }

local sounds: { [string]: SoundDef } = {
	physgun_grab = { id = "", volume = 0.5 },
	physgun_hold = { id = "", volume = 0.25 },
	physgun_release = { id = "", volume = 0.4 },
	physgun_freeze = { id = "", volume = 0.5 },
	gravgun_hold = { id = "", volume = 0.3 },
	gravgun_pull = { id = "", volume = 0.5 },
	gravgun_punt = { id = "", volume = 0.7 },
	toolgun_fire = { id = "", volume = 0.4 },
	weld = { id = "", volume = 0.5 },
	deny = { id = "", volume = 0.4 },
	spawn = { id = "", volume = 0.4 },
	remove = { id = "", volume = 0.5 },
	ui_tick = { id = "", volume = 0.3 },
	ragdoll_getup = { id = "rbxasset://sounds/action_get_up.mp3", volume = 0.5 },
}

return table.freeze(sounds)
