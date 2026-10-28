# Plan

Status: 2026-10-27. Next work is **free features only** — no new passes, no paid gates.

## 1. Ghost preview (free)

A translucent version of the selected prop follows your aim while the Q spawn menu is open. Click spawns the real prop; closing the menu removes the preview.

### Behaviour
- Only while the Q menu is open and a prop row is selected.
- Preview is client-only, non-collidable, non-query, non-touch; it never exists on the server.
- Green tint when the spot is allowed, red when it is not (out of range, locked pass, too close to another player).
- Hidden when the pointer is over UI or the aim ray hits nothing.
- One preview at a time; destroyed on close, respawn, or tool change.

### Implementation
1. Add `src/StarterPlayerScripts/UI/GhostPreview.luau`.
2. Build the preview from `PropCatalog` using the same shape, size, colour and detail list as `PropBuilder` — no server call and no mesh asset needed.
3. Move the pure placement maths (surface normal -> CFrame) out of `PropBuilder` into `Shared/Placement.luau` so the preview and the server agree on orientation. `PropBuilder` keeps the physics/ownership parts.
4. Feed it `SpawnMenu.aimPoint()` once per frame while the menu is open. Throttle raycasts to the existing aim cadence; reuse one model, do not clone every frame.
5. On spawn, hide the preview until the server replies (or until the next aim update).
6. Clean up: one `RenderStepped` connection, disconnected on menu close; all preview parts destroyed.

### Done when
- Preview matches the spawned prop’s position, rotation and size.
- Locked Sports Car shows red and never spawns without the pass.
- Menu close / respawn leaves no preview parts or connections.
- No new remotes, no server changes, `scripts/check.sh` passes.

## 2. More maps from the Gmod mods folder

The user names the maps; we do not bulk-import the whole folder.

### Source folders (detected)
- `C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\maps` — `gm_construct.bsp`, `gm_flatgrass.bsp` and any loose maps.
- `C:\Program Files (x86)\Steam\steamapps\workshop\content\4000\<id>` — subscribed Workshop addons (`.gma`).
- `C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons` — legacy addons.

### Assets
Maps and their original Gmod/Valve textures and props may be ported as-is on your call. Log every map, texture pack and model with its source in `docs/ASSETS.md`. Roblox DMCA risk is accepted; keep the log accurate so a takedown can be traced to a source.

### Pipeline per map
1. **Inventory.** Record map name, source file, author, licence, dimensions, spawn, and whether it uses stock HL2/Gmod content. Reject maps with no usable licence unless you explicitly accept the risk.
2. **Extract layout.** Read the `.bsp`/`.gma` offline (Crowbar / SourceIO / bsp2obj) or capture top/front/side references in Gmod. No game files go into git or Roblox at this stage.
3. **Scale.** Reuse the scale of the existing Construct import (measure a 128-unit door against the in-game door height) and keep one scale constant for every new map.
4. **Convert.** Keep the source geometry and materials, or strip and retexture only if you ask for it. Rebuild/repair in Blender where the BSP needs it, export GLB. Props that matter to gameplay (ramps, cover) become collision hulls.
5. **Import.** Put the model under `Workspace.Maps.<id>` at the next free world offset (Construct is at X +6000, Flatgrass at X -10000; keep at least 4000 studs between map bounds). Remove scripts, anchor geometry, set collision fidelity, add an invisible floor where the source map relies on terrain.
6. **`MapCatalog` entry.** Add `id`, `name`, `blurb`, `model`, `spawn`, optional `floor`, `orbit`, optional `mirrors`.
7. **Lighting.** Author `ReplicatedStorage.MapLighting.<id>` (sky, clock time, fog, water). `MapLighting.luau` already applies it per player.
8. **Verify.** Spawn and respawn on the map; walk the critical path; check doors, stairs, gaps, water, and the orbit camera framing. Two players on different maps must see their own lighting.
9. **Docs and tests.** Bump the map count in `tests/maps.spec.luau`; update `docs/ARCHITECTURE.md` and `docs/ASSETS.md`.

### Done when
- Map is selectable in **Start Game**, spawns correctly, and has a working floor.
- No scripts in the imported model, and the asset log is updated.
- Orbit camera frames the map without clipping; mirrors work if configured.
- Two-player test passes; `scripts/check.sh` and `rojo build` pass.

### Open questions
- Which maps, and are they in `garrysmod\maps`, a `.gma` addon, or the Workshop folder?
- Any map that needs water, ladders, or moving doors — those need extra map-specific code.

## 3. Other free features (ordered after the two above)
1. **Mobile/touch buttons** for Menu and Spawn — M/Q are keyboard-only today.
2. **Prop search + favourites** in the Q menu (type to filter, star to pin).
3. **Undo** last spawn/remove (one step, server-side ownership check).
4. **Grid snap** toggle for prop placement.
5. **Map vote** in the lobby when there are 4+ maps.
6. **Achievements/stats** — first car, 100 props, first dupe, first mirror found.

## Order of work
1. Ghost preview (small, immediate, no new content).
2. Map pipeline + the first two maps the user names.
3. Mobile menu buttons.
4. Search/favourites, then undo, then grid snap.
