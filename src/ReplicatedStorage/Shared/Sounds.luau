--!strict
-- Sound effects by name. Plain data so lune can check it.
-- Originals are synthesized by audio/sfx.py: upload audio/exports/<name>.ogg and paste the rbxassetid here.
-- id "" = not uploaded yet; playing it does nothing. rbxasset:// ids are files that ship with Roblox.
export type SoundDef = { id: string, volume: number }

local sounds: { [string]: SoundDef } = {
	physgun_grab = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5 },
	physgun_hold = { id = "", volume = 0.25 },
	physgun_release = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.4 },
	physgun_freeze = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5 },
	gravgun_hold = { id = "", volume = 0.3 },
	gravgun_pull = { id = "rbxasset://sounds/action_falling.ogg", volume = 0.4 },
	gravgun_punt = { id = "rbxasset://sounds/action_falling.ogg", volume = 0.5 },
	toolgun_fire = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.4 },
	weld = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5 },
	deny = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.4 },
	spawn = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.4 },
	remove = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.5 },
	ui_tick = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.25 },
	ragdoll_getup = { id = "rbxasset://sounds/action_get_up.mp3", volume = 0.5 },
	pistol_fire = { id = "rbxassetid://132539859090895", volume = 1.8 },
	smg_fire = { id = "rbxassetid://77130830495173", volume = 1.6 },
	ar2_fire = { id = "rbxassetid://18837782261", volume = 1.8 },
	rpg_fire = { id = "rbxassetid://87972247594387", volume = 2.5 },
	reload = { id = "rbxassetid://139048584127232", volume = 1.6 },
	dry_fire = { id = "rbxasset://sounds/volume_slider.ogg", volume = 0.4 },
	explosion = { id = "rbxasset://sounds/impact_explosion_03.mp3", volume = 1 },
}

return table.freeze(sounds)
