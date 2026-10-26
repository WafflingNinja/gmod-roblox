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

## Pipeline
Blender model -> FBX/GLB -> Studio import -> mesh id -> new entry in `PropCatalog` (extend with `meshId` and `scale`) -> lune spec still passes.

Keep source `.blend` files in `blender/` (not exports). Exports go to `blender/exports/` (gitignored).

## Sound effects
All SFX are synthesized from scratch by `audio/sfx.py` (oscillators + noise, no samples), so they are original. No Creator Store uploads by other users (provenance unknown, often ripped). Built-in `rbxasset://sounds/` files are fine too (only 11 ship: footsteps, jump, get-up, explosion...).

Pipeline: `python3 audio/sfx.py` -> `audio/exports/*.ogg` (gitignored) -> upload (Studio: Window > Asset Manager > Bulk Import, or Creator Hub > Audio) -> paste `rbxassetid://<id>` into `Shared/Sounds.luau`. Until then the id is `""` and the sound simply doesn't play. `tests/sounds.spec.luau` checks every name the code plays exists and every not-uploaded sound has a generator.

## License log
| Pack | Author | License | URL | Used for |
|---|---|---|---|---|
| (none yet) | | | | |
