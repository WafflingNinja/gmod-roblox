# Assets

## Hard rule
**No assets from Garry's Mod, Half-Life 2, Source engine games, or Valve/Facepunch in any form.** That includes models, textures, sounds, icons, and extracted or converted copies, even a few, even private, even "just for reference". Uploading them to Roblox is a DMCA takedown and puts the account at risk.

The Gmod install on this PC is for inspiration only: look at what makes a prop iconic, then build your own.

## Allowed sources
1. Original meshes made in Blender.
2. Roblox `generate_mesh` text-to-mesh (check the result for look-alikes).
3. CC0 packs (Kenney, Quaternius, etc.). Record each pack in the log below with its license URL before use.
4. Roblox primitives (current step 1 props).

## Iconic props to recreate originally
Silhouette and function only, own proportions and textures:
- Wooden crate, red barrel, gas can, cinder block, beach ball (done as primitives)
- Traffic cone, pallet, tire, oil drum variants, sawblade, propane tank, bowling ball, watermelon
- Wheel set, thruster, balloon (tool props)
- Citizen NPC: blue work shirt and dark pants from parts; voice and lines are the developer's own (`docs/VOICE.md`)

## Pipeline
Blender model -> FBX/GLB -> Studio import -> mesh id -> new entry in `PropCatalog` (extend with `meshId` and `scale`) -> lune spec still passes.

Keep source `.blend` files in `blender/` (not exports). Exports go to `blender/exports/` (gitignored).

## Sound effects
All SFX are synthesized from scratch by `audio/sfx.py` (oscillators + noise, no samples), so they are original. No Creator Store uploads by other users (provenance unknown, often ripped). Built-in `rbxasset://sounds/` files are fine too (only 11 ship: footsteps, jump, get-up, explosion...).

Pipeline: `python3 audio/sfx.py` -> `audio/exports/*.ogg` (gitignored) -> upload (Studio: Window > Asset Manager > Bulk Import, or Creator Hub > Audio) -> paste `rbxassetid://<id>` into `Shared/Sounds.luau`. Until then the id is `""` and the sound simply doesn't play. `tests/sounds.spec.luau` checks every name the code plays exists and every not-uploaded sound has a generator.

## Voice lines
NPC voices are recorded by the developer (original, own voice) with `audio/voice/recorder.py`; see `docs/VOICE.md`. Raw takes are committed in `audio/voice/takes/`; exports are gitignored. One sprite per NPC is uploaded, lines are played with `PlaybackRegion`.

## License log
| Pack | Author | License | URL | Used for |
|---|---|---|---|---|
| gm_construct (asset 122998384728269) | Roblox user 75654656456pistol | marked public domain on the Store; provenance unknown (looks converted from the Gmod map) | create.roblox.com/store/asset/122998384728269 | `Workspace.Maps.Construct`, inserted 2026-10-26 on the user's call despite hard rule 1 |
| AR2 (16179381803), HL2 pistol (3961174953), hl2 mmod smg1 (16705113161), RPG (136264585566005) | various Store users | provenance unknown, look like HL2/MMOD rips; meshes only, no scripts | create.roblox.com/store/asset/<id> | gun meshes in ServerStorage, inserted 2026-10-26 on the user's call |
| Gun sounds: Pistol Shot 132539859090895 (MrAudio6), SMG Gunshot SFX 77130830495173 (KreditReborn), PLASMA PISTOL shot 18837782261 (im_tooooooold, used for the AR2), Rocket launcher fire 87972247594387 (Zelgraz, "made by"), gun-reload_1 139048584127232 (kaizz93) | Store users | free Store audio, provenance not stated; results labelled as ripped (StarCraft, Serious Sam) were skipped | create.roblox.com/store/asset/<id> | `Shared/Sounds.luau`, 2026-10-26; replace with the synthesized `audio/sfx.py` set or CC0 uploads before launch |
| gm_flatgrass (asset 139504710395407) | Roblox user 75654656456pistol | same | create.roblox.com/store/asset/139504710395407 | `Workspace.Maps.Flatgrass`, same |
