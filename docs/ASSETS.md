# Assets

## Policy
**The user decides what gets imported.** Gmod/Valve maps, models, textures and sounds may be used when the user asks. Log every asset with its source in the table below. Roblox can issue DMCA takedowns; the risk is accepted by the user.

## Allowed sources
1. Gmod/Valve content, when the user asks for it (log the source).
2. Original meshes made in Blender.
3. Roblox `generate_mesh` text-to-mesh (check the result for look-alikes).
4. CC0 packs (Kenney, Quaternius, etc.). Record each pack in the log below with its license URL before use.
5. Roblox primitives (current step 1 props).

## Iconic props to recreate originally
Silhouette and function only, own proportions and textures:
- Wooden crate, red barrel, gas can, cinder block, beach ball (done as primitives)
- Traffic cone, pallet, tire, oil drum variants, sawblade, propane tank, bowling ball, watermelon
- Wheel set, thruster, balloon (tool props)

## Pipeline
Blender model -> FBX/GLB -> Studio import -> mesh id -> new entry in `PropCatalog` (extend with `meshId` and `scale`) -> lune spec still passes.

Keep source `.blend` files in `blender/` (not exports). Exports go to `blender/exports/` (gitignored).

## Sound effects
All current SFX are synthesized from scratch by `audio/sfx.py` (oscillators + noise, no samples), so they are original. Creator Store or Gmod sound uploads are allowed on the user's call; log them below. Built-in `rbxasset://sounds/` files are fine too (only 11 ship: footsteps, jump, get-up, explosion...).

Pipeline: `python3 audio/sfx.py` -> `audio/exports/*.ogg` (gitignored) -> upload (Studio: Window > Asset Manager > Bulk Import, or Creator Hub > Audio) -> paste `rbxassetid://<id>` into `Shared/Sounds.luau`. Until then the id is `""` and the sound simply doesn't play. `tests/sounds.spec.luau` checks every name the code plays exists and every not-uploaded sound has a generator.

## Map factory
`tools/add_map.py <workshop link>` does the whole import and appends the map row to the log below. It audits texture alpha, opens a local review page (50 per page) where you click textures to reject them, and only uploads approved PNGs. Rejected textures stay flat-coloured in game; the map still imports, and the ASSETS row records the Workshop source. Add a row by hand only if a step fails.

## License log
| Pack | Author | License | URL | Used for |
|---|---|---|---|---|
| gm_construct (asset 122998384728269) | Roblox user 75654656456pistol | marked public domain on the Store; provenance unknown (looks converted from the Gmod map) | create.roblox.com/store/asset/122998384728269 | `Workspace.Maps.Construct`, inserted 2026-10-26 on the user's call; risk accepted |
| AR2 (16179381803), HL2 pistol (3961174953), hl2 mmod smg1 (16705113161), RPG (136264585566005) | various Store users | provenance unknown, look like HL2/MMOD rips; meshes only, no scripts | create.roblox.com/store/asset/<id> | gun meshes in ServerStorage, inserted 2026-10-26 on the user's call; risk accepted |
| Gun sounds: Pistol Shot 132539859090895 (MrAudio6), SMG Gunshot SFX 77130830495173 (KreditReborn), PLASMA PISTOL shot 18837782261 (im_tooooooold, used for the AR2), Rocket launcher fire 87972247594387 (Zelgraz, "made by"), gun-reload_1 139048584127232 (kaizz93) | Store users | free Store audio, provenance not stated; results labelled as ripped (StarCraft, Serious Sam) were skipped | create.roblox.com/store/asset/<id> | `Shared/Sounds.luau`, 2026-10-26; risk accepted |
| gm_flatgrass (asset 139504710395407) | Roblox user 75654656456pistol | same | create.roblox.com/store/asset/139504710395407 | `Workspace.Maps.Flatgrass`, same |
| gm_mallparking (Workshop 2619660952) | Workshop uploader (GMA header says "Author Name") | Gmod Workshop map, no license stated | steamcommunity.com/sharedfiles/filedetails/?id=2619660952 | `Workspace.Maps.Mallparking`: brush geometry, brush doors, lights, textures via `tools/bsp_to_json.py`, 2026-10-27 on the user's call; risk accepted |
| RP_Bangclaw (Optimized) (Workshop 3300816330) | same | same | steamcommunity.com/sharedfiles/filedetails/?id=3300816330 | `Workspace.Maps.Bangclaw`, same |
| gm_bigcity_improved_rp (Workshop 3739182697) | same | same | steamcommunity.com/sharedfiles/filedetails/?id=3739182697 | `Workspace.Maps.Bigcity`, same |
| gm_backrooms_biomes (Workshop 3132624630) | same | same | steamcommunity.com/sharedfiles/filedetails/?id=3132624630 | `Workspace.Maps.Backrooms`, same |
| Backrooms Movie A24 / gm_brmovie_complete (Workshop 3761466972) | same | same | steamcommunity.com/sharedfiles/filedetails/?id=3761466972 | `Workspace.Maps.Brmovie`, same |
| Map textures (748 VTFs, 256px PNG) | Valve (HL2, CS:S, Gmod VPKs) and each map's packed materials | Valve game content, not licensed for redistribution | local Gmod install + BSP pakfiles | MeshPart TextureIDs on the five maps above, once uploaded; risk accepted per repo rule 1 |
| Movement base: `MovementSystem.lua` | evil-nsapple | no license stated (public GitHub repo) | github.com/evil-nsapple/roblox-movement | `StarterPlayerScripts/Movement.luau` — walk/sprint/crouch/momentum code, adapted to use `Config.WALK_SPEED`/`JUMP_HEIGHT`, LeftControl for crouch, per-character connection cleanup |
| Auto-bhop idea: "Bhop & Air Movement Module + Surfing" | sylwek1100 (DevForum) | Roblox DevForum community post | devforum.roblox.com/t/bhop-air-movement-module-surfing/3914600 | Only the hold-Space auto-jump approach in `Movement.luau`; the module's velocity code was not copied |
