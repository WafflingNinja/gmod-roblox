# IMPORT-MAPS — Gmod map pipeline (handoff)

Status as of 2026-10-27. Everything below was verified in the live Studio session on this machine.
Read this before touching `tools/bsp_to_json.py`, `tools/MapImport.luau`, `MapCatalog`, `DoorService`.

---

## 1. TL;DR

`tools/add_map.py <workshop link>` now runs sections 3.1-3.3 (extract, convert, alpha audit, texture review,
upload, MapCatalog/MapLighting/ASSETS entry) and copies the Studio import command to the clipboard. The manual
commands below remain the reference for what it does and for rebuilding by hand.

Five Gmod/Source maps are converted, imported into the place, placed far apart in `Workspace.Maps`,
registered in `MapCatalog`, lit, and their brush doors are real hinged/sliding door models driven by
`DoorService`. **props/displacements are not imported**. `gm_fork` is not installed — the user said to skip it.

**Session 4 (2026-10-27, after the table below was measured):** the converter read texinfo `flags` as the
texdata index, so almost every face was material `?`. Fixed: faces now resolve to their real materials
(35–1,240 per map), tool/skybox faces are actually skipped, and every chunk carries UVs plus a real
texture. Re-imported 2026-10-27 15:55 at the new ring positions with 705 uploaded textures (`texture_ids.json`,
image ids; 43 textures with people/ads/text/credits were held back after one triggered a Roblox PII
warning — they stay flat colour, see `png_unsafe/`). Import output: chunks/textured = Mallparking 294/259,
Bangclaw 393/387, Bigcity 860/847, Backrooms 87/81, Brmovie 304/270; extents now real (Bigcity 2,384 studs).
Textures showed "asset content representation is being generated" right after upload; not yet seen rendering.
**Session 5 (2026-10-27):** holes in buildings were (a) `RenderFidelity.Automatic` LOD on huge chunks, now
`Precise`, and (b) 76 opaque textures with shine-mask alpha drawn as see-through, now `SurfaceAppearance`
Overlay (`tools/alpha_audit.py`). Both applied to the live place by command bar; importer does the same.
The real cause of see-through walls: `face_normal` negated the plane for `side=1` faces, but vbsp already
stores the flipped plane for them (`side == planenum & 1`), so ~1/3 of faces were inside out. Fixed and
re-converted. Re-import needs `ServerStorage.MapMeshIds` cleared first: the cache key is vertex/index
count, which the fix does not change, so stale inside-out meshes would be reused.

| Map (Workspace.Maps) | Source addon | MapCatalog id | tris | chunks | doors | lights | spawn |
|---|---|---|---|---|---|---|---|
| `Mallparking` | Workshop 2619660952 | `Mallparking` | 55,011 | 17 | 48 | 337 | 20572.8, 196.2, -186.5 |
| `Bangclaw` | Workshop 3300816330 | `Bangclaw` | 57,020 | 15 | 199 | 420 | 29682.5, 278.2, -146.2 |
| `Bigcity` | Workshop 3739182697 | `Bigcity` | 98,274 | 53 | 28 | 383 | 45100.8, 452.8, 351.4 |
| `Backrooms` | Workshop 3132624630 | `Backrooms` | 91,941 | 18 | 39 | 420 | 59962.4, 394.9, -190.1 |
| `Brmovie` | Workshop 3761466972 | `Brmovie` | 97,089 | 21 | 62 | 420 | 73061.1, 858.7, -128.9 |

Re-converted (session 4, textured): tris / parts / textures = Mallparking 54,911 / 307 / 151,
Bangclaw 56,061 / 460 / 229, Bigcity 92,678 / 727 / 324, Backrooms 91,835 / 61 / 29, Brmovie 95,352 / 302 / 178.
748 unique textures across all five; 97–100% of triangles textured (the rest is water shaders).

Not imported: `Flatgrass`, `Construct` (pre-existing models already in the place file, untouched).

**The meshes only exist inside the place file.** Rojo does not and cannot sync them. If the place is
not saved in Studio, the whole import is lost. Save the place (Ctrl+S) before anything else.

---

## 2. Source files

Gmod install: `C:\Program Files (x86)\Steam\steamapps\common\GarrysMod`
Workshop content: `C:\Program Files (x86)\Steam\steamapps\workshop\content\4000\<id>`

| Workshop id | .gma | BSP inside | Extracted to |
|---|---|---|---|
| 2619660952 | `2619660952_via_crowbar.gma` | `maps/gm_mallparking.bsp` | `%TEMP%\kilo\maps_out\mallparking` |
| 3300816330 | `rp_bangclaw_optisat.gma` | `maps/rp_bangclaw_optisat.bsp` | `%TEMP%\kilo\maps_out\bangclaw` |
| 3739182697 | `gmpublisher.gma` | `maps/gm_bigcity_improved_rp.bsp` | `%TEMP%\kilo\maps_out\bigcity` |
| 3132624630 | `gmpublisher.gma` | `maps/gm_backrooms_biomes.bsp` | `%TEMP%\kilo\maps_out\backrooms` |
| 3761466972 | `gmpublisher.gma` | `maps/gm_brmovie_complete.bsp` | `%TEMP%\kilo\maps_out\brmovie` |

Extract with the Gmod tool (no Crowbar/GCFScape needed):

```
"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\bin\gmad.exe" extract -file "<gma>" -out "<dir>"
```

`gm_fork`: **not present**. Only a `bgn_compile_gm_fork.lua` string inside an unrelated addon exists,
and no Creator Store version. The user explicitly dropped it — do not chase it.

---

## 3. Pipeline

```
.gma --gmad--> .bsp --tools/bsp_to_json.py--> .json --HTTP 127.0.0.1:8765--> tools/MapImport.luau (Studio)
                                                                              |
                                                          EditableMesh -> MeshPart, saved into the place
```

### 3.1 Convert (offline, Python 3 + Pillow)

```
python tools\bsp_to_json.py "<...>.bsp" -o "%TEMP%\kilo\maps_out\<name>.json" -x <centreX> -z <centreZ> --png-dir "%TEMP%\kilo\maps_out\png"
```

Textures (`tools/source_textures.py`): material -> `.vmt` -> `$basetexture` -> `.vtf`, searched in the BSP
pakfile, then the extracted addon folder, then Gmod's VPKs (`garrysmod_dir`, `hl2_textures_dir`,
`hl2_misc_dir`, `content_cstrike_dir`). Patch materials (`maps/<map>/..._x_y_z`, cubemap variants) follow
`include`. One mip <= 256 px is decoded (DXT1/3/5 via Pillow's `bcn` decoder, plus the common raw formats),
written as `<path__name>.png`, and its average colour becomes the chunk colour. Materials that share a
texture share a MeshPart.

### 3.1b Upload textures (needs an Open Cloud API key)

```
set ROBLOX_API_KEY=...        (Creator Dashboard -> Open Cloud -> API Keys, Assets: read + write)
set ROBLOX_USER_ID=...
python tools\upload_textures.py "%TEMP%\kilo\maps_out\png" "%TEMP%\kilo\maps_out\texture_ids.json" --limit 1
```

Run with `--limit 1` first and check the one id in Studio; then without `--limit`. It skips names already
in `texture_ids.json`, so it can be re-run after a failure.

`-x` is the world X the map is centred on. Use these (they keep the maps from overlapping):

| map | -x | -z |
|---|---|---|
| mallparking | 40000 | 0 |
| bangclaw | 12000 | 38000 |
| bigcity | -32000 | 23500 |
| backrooms | -32000 | -23500 |
| brmovie | 12000 | -38000 |

Session 4 moved the maps from a line along +X (20k–73k) to a ring of radius 40k: ~47k studs between
neighbours, and no map further than 40k from the origin (float jitter grows with distance). The spawn
column in section 1 is the old layout; `MapCatalog` has the new spawns.

### 3.2 Serve the JSON + importer

Both are already running as persistent background processes in this session:

```
python -m http.server 8765 --bind 127.0.0.1      (cwd %TEMP%\kilo\maps_out)
rojo serve                                        (cwd repo, port 34872)
```

If they are gone, restart them and re-link the Studio Rojo plugin.

### 3.3 Import (Studio only, authoring tool)

`ServerStorage.MapImport` is **not** in `src/` on purpose: it needs HttpService and creates meshes, so it
is an authoring tool, not runtime game code. Source of truth is `tools/MapImport.luau`. Install it with:

```lua
local ss = game:GetService("ServerStorage")
local old = ss:FindFirstChild("MapImport"); if old then old:Destroy() end
local m = Instance.new("ModuleScript"); m.Name = "MapImport"
m.Source = game:GetService("HttpService"):GetAsync("http://127.0.0.1:8765/MapImport.lua")
m.Parent = ss
```

(`tools/MapImport.luau` is copied to `%TEMP%\kilo\maps_out\MapImport.lua` so the HTTP server can serve it.)

Then, per map:

```lua
local imp = require(game.ServerStorage.MapImport)
print(imp.run("Mallparking", "gm_mallparking.json"))
print(imp.run("Bangclaw",   "rp_bangclaw.json"))
print(imp.run("Bigcity",    "gm_bigcity.json"))
print(imp.run("Backrooms",  "gm_backrooms.json"))
print(imp.run("Brmovie",    "gm_brmovie.json"))
```

Each call takes 4–9 s and `task.wait()`s between parts so Studio does not freeze. Re-running a map
destroys and rebuilds `Workspace.Maps.<name>` — it is safe and idempotent.

### 3.4 What the importer writes into the map model

```
Workspace.Maps.<Name>            Model
├── <material name>              MeshPart per chunk (visual, coloured)
├── Collision                    MeshPart per chunk, Transparency = 1, Box collision (NODRAW only)
├── Doors/                       Model per door, tagged "MapDoor"
│     └── DoorPart (MeshPart)    or Panel (Part) for prop-door stand-ins
├── Lights/                      tiny invisible parts, each with a PointLight
└── attributes: Spawn (Vector3), SourceTris, SourceDoors
```

---

## 4. Data format (`*.json`)

```jsonc
{
  "name": "gm_mallparking",
  "scale": 0.09,                       // Source units -> studs
  "offset": [ox, oy, oz],              // added after conversion
  "bounds": { "min": [x,y,z], "max": [x,y,z] },
  "spawn": [x, y, z],                  // converted info_player_start
  "chunks": [{
    "mat": "PARKING_LOT/CONCRETEFLOOR_WAREHOUSE",
    "color": [r,g,b],                  // flat placeholder colour, derived from the material name
    "layer": "visual" | "collide",     // collide = TOOLS/TOOLSNODRAW, invisible but solid
    "tex": "brick__brickwall001a.png", // null when no texture resolved (MISC / water)
    "uv":  "<base64 2f>",              // per vertex, Source texture repeats (tiles past 0..1)
    "pos": "<base64 3f>",              // vertex positions
    "idx": "<base64 u32>",             // triangle indices, 3 per triangle
    "nrm": "<base64 3f>",              // unique face normals (flat shading)
    "ni":  "<base64 u16>",             // normal index per triangle
    "tris": 1234
  }],
  "doors": [{
    "name": "door_37",
    "kind": "rotate" | "slide" | "prop",
    "pivot": [x,y,z],                  // Source `origin` == the hinge
    "angle": 90, "hasAngle": true,
    "distance": 90, "speed": 100,      // Source units, unused by DoorService today
    "width": 50,                       // Source units
    "color": [r,g,b],
    "chunks": [ ...same chunk shape, one per texture, each with its own color/tex... ]
  }],
  "lights": [{
    "pos": [x,y,z], "color": [r,g,b],
    "brightness": 1.6,                 // already clamped 0.4..3.0
    "range": 27.7,                     // studs, clamped 14..90
    "cone": 80                          // kept for future spotlights; currently ignored
  }],
  "stats": { "tris": 55011, "dropped": 0, "doors": 48, "spawns": 1 }
}
```

### Coordinates

Source is Z-up, right-handed; Roblox is Y-up. Conversion (one scale for every map so props and door
sizes stay consistent):

```
roblox.x =  src.x * 0.09 + ox
roblox.y =  src.z * 0.09 + oy
roblox.z = -src.y * 0.09 + oz
```

`oy` is chosen so the world model's floor lands on Y = 100. `ox` centres the map on `-x`.

### Brush entities

Some maps store brush-entity vertices in world space, others store them around (0,0,0) and rely on the
entity `origin` (Source moves the brush at spawn). `model_shift()` decides per model: if the entity
`origin` is far outside the model's own bounds, the model is local and gets shifted. **Doors are
excluded from the static pass** and get their own shift + hinge handling. This was the bug that made
every door render at the map centre; it is fixed and verified.

---

## 5. Game-side code added

| File | What |
|---|---|
| `tools/bsp_to_json.py` | The converter. ~680 lines. |
| `tools/source_textures.py` | VPK/pakfile/addon lookup, VMT follow, VTF decode (Pillow). |
| `tools/upload_textures.py` | PNGs -> Open Cloud Assets API -> `texture_ids.json`. |
| `tools/alpha_audit.py` | Writes `alpha_fix.json`: uploaded textures whose alpha is a Source shine mask, not transparency (no `$translucent`/`$alphatest`). `MapImport` gives those parts a `SurfaceAppearance` with `AlphaMode.Overlay`, otherwise Roblox draws the mask as holes. |
| `tools/MapImport.luau` | Studio-side importer (authoring tool). |
| `src/ServerScriptService/Services/DoorService.luau` | Opens/closes tagged doors on `ProximityPrompt` (E) or touch, auto-closes after 4 s. |
| `src/ServerScriptService/Main.server.luau` | `require(services.DoorService).init()` added after MapService. |
| `src/ServerScriptService/Services/MapService.luau` | `spawnPoint()` now prefers the imported model's `Spawn` Vector3 attribute. |
| `src/ReplicatedStorage/Shared/MapCatalog.luau` | 5 map entries: id, name, blurb, model, spawn, orbit (menu camera). |
| `default.project.json` | `MapLighting` folders for Mallparking / Bigcity / Bangclaw / Backrooms / Brmovie. |

Door attributes consumed by `DoorService`: `Hinge` (Vector3), `Kind` (`rotate`/`slide`),
`Angle` (degrees), `Offset` (Vector3, slide), `Speed`. CollectionService tag: `MapDoor`.

---

## 6. Verified

- No triangles dropped for being outside the world bounds (`dropped=0` on all five).
- Every chunk fits the MeshPart limits (largest axis per map: 1048 / 933 / 1797 / 1112 / 1077 studs, all < 2048).
- Mesh normals are flat per face; winding matches the stored normal, and the stored normal now matches the
  Source vertex winding (checked on all Bigcity faces, session 5)
  (a handful of degenerate micro-triangles are misaligned; they are invisible).
- Spawn raycasts find real floor on all five maps.
- Lights exist and illuminate interiors (Mallparking verified in play mode).
- Door rotation works: touching `Mallparking.Doors.door_1` moved the door's bounding box 3.18 studs
  (a 90° swing about its hinge). Play-mode test, 2026-10-27.
- `stylua --check`, `selene`, `luau-lsp analyze`, all 8 `lune` spec files pass.

## 6.1 Not verified

- Door **auto-close** timing and **slide direction** per door (the slide offset uses the entity yaw and
  falls back to straight up when the map has no `angle`; some slide doors may move the wrong way).
- Two-client playtest (repo rule: networked changes need 2 clients, not Play Solo).
- Full walkthrough of every map for holes / missing collision.
- Menu camera orbit radii: values in `MapCatalog` are estimates, not measured per map.

---

## 7. Known issues / gotchas (read before editing)

1. **Place file is the only home for the meshes.** Rojo will not rebuild them. Save the place.
2. **Fixed in `tools/MapImport.luau`, needs re-import:** each MeshPart's `CFrame` is now its own chunk's
   bounds centre, so `GetExtentsSize()`, `Position` and gizmos are right. The current place still has the
   old map-centre parts until the maps are re-imported.
3. **Textures are converted, not uploaded.** `MapImport` reads `texture_ids.json` from the HTTP server
   (`{"<png name>": "rbxassetid://..."}`); missing entries keep the real average colour. Unverified until
   the first textured import: UV V direction (Source has V down; flip `v` in `meshPart` if textures are
   upside down) and that MeshPart textures tile past 0..1.
4. **Displacements are skipped** (`dispinfo != -1`). Outdoor terrain in these maps is mostly brushes, but
   any displacement hills are missing.
5. **Skybox skipped** (`TOOLS/TOOLSSKYBOX*`). Roblox sky is the default.
6. **NODRAW is imported as invisible collision**, but after the texinfo fix no map has NODRAW faces
   (vbsp strips them). The old "Bigcity street plate is NODRAW" was the texinfo bug; the plate has its
   real material now.
7. **Props are not imported.** `prop_dynamic`, `prop_physics`, `prop_door_rotating` are absent. Prop
   doors become a 64×112-unit wooden slab (`kind: "prop"`), which is why Bangclaw/Bigcity doors look
   like plain panels.
8. **Lights are capped at 420 per map**, merged on a 16-stud grid, all converted to `PointLight`
   (`Shadow = false`). No spot cones, no shadows. Raising the cap costs frame time.
9. **MeshPart axis limit is 2048 studs** and **EditableMesh has a triangle cap** — the converter tiles
   by 1200 studs, subdivides oversized triangles (`subdivide`) and bins (`fit`) before chunking at 8,000
   triangles. Keep those limits if you change `TILE`, `FIT_LIMIT`, `CHUNK_TRIS`.
10. **`HttpService.Base64Decode` does not exist** in this Studio build; the importer carries its own
    decoder. `Enum.CollisionFidelity.Precise` does not exist either; use `PreciseConvexDecomposition`.
11. **`MeshPart.Position` is its CFrame, not its geometry.** Checking "is the door near its hinge" with
    `part.Position` gives false alarms; measure with `Model:GetBoundingBox()`.
12. **stylua and line endings.** The repo has `core.autocrlf=true`; local `stylua --check` reports every
    file as a diff unless run with `--line-endings Windows`. CI/`scripts/check.sh` is unaffected.
13. `tools/__pycache__` is a local artefact; do not commit it.
14. Uncommitted work: `MapCatalog.luau`, `Main.server.luau`, `MapService.luau`, `ToolService.luau`,
    `DoorService.luau` (new), `tools/` (new), `default.project.json`, `plan.md`, `docs/ASSETS.md`.
    Nothing was committed.

---

## 8. Next steps, in order

1. **Save the place** (Studio Ctrl+S), then confirm `Maps` survived a reopen.
2. ~~Per-chunk CFrame fix~~ done in code (session 4).
3. **Textures**: ~~extract + decode~~ done (748 PNGs in `%TEMP%\kilo\maps_out\png`). Left: upload them
   (3.1b), reinstall `MapImport` (3.3) and re-run the five `imp.run` calls. Re-importing even without
   uploads is worth it: real colours, no skybox walls, fixed CFrames.
4. **Prop doors**: import the `prop_door_rotating` models (`models/props_doors/*.mdl` — needs a MDL
   importer or a vphysics-collision box stand-in) so doors stop looking like slabs.
5. **Verify doors per map**: walk a route, check slide direction, hinge side, auto-close, and that no door
   opens into a wall. `DoorService`'s slide vector is the first thing to tune.
6. **Map menu**: blurb/orbit values in `MapCatalog` are placeholders; run the menu (`M`) on each map and
   adjust `orbit.center/radius/height` so the map fills frame.
7. **2-client playtest**, then tick the map step in `ROADMAP.md` / `plan.md`.
8. ~~docs/ASSETS.md rows~~ done (session 4).
9. Consider `Workspace.StreamingEnabled` for Bigcity; 98k tris + 383 lights is the heaviest map.

---

## 9. Rebuild from zero (if the place is lost)

```
# 1. extract
"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\bin\gmad.exe" extract -file "<gma>" -out "%TEMP%\kilo\maps_out\<map>"
# 2. convert (five commands from section 3.1)
# 3. serve + rojo
cd %TEMP%\kilo\maps_out && python -m http.server 8765 --bind 127.0.0.1
cd C:\Users\rosti\gmod-roblox && rojo serve
# 4. install tools/MapImport.luau into ServerStorage (section 3.3), then run the five imp.run calls
```

Expected output per map is the `chunks=/doors=/spawn=/extents=` line printed by `MapImport.run`.