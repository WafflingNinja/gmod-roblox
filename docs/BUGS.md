# Bugs found in the full-repo review (2026-10-28)

Review of the gameplay modules (`src/ServerScriptService`, `src/StarterPlayerScripts`, `src/ReplicatedStorage/Shared`)
plus `tools/MapImport.luau` and `tools/bsp_to_json.py`, against the repo rules (server authority, one remote per
concern, cleanup, `task.*`, strict typing). Each item was fixed in the same pass.

| # | Area | Bug | Fix |
|---|---|---|---|
| 1 | MapService.spawnPoint | Trusted the map's `Spawn` attribute. Mall Parking's attribute is `Y=166.16`, 26 studs under the deck, so every spawn/respawn there started under the map. | `spawnPoint` now repeats `MapImport.spawnFor` (ray down from under a ceiling) and, when the point is under a floor, rays up for the floor above, returning floor + 4. The saved attribute was corrected to `196.16` too. |
| 2 | DoorService / MapImport | Prop doors imported before `dressPropDoor` existed sat at the Source origin (mid-height), so 194 of 199 Bangclaw doors and every Backrooms door floated ~5 studs. The same offset pushed the panels' upper half into the wall above the doorway, which is the Bangclaw door that looked blocked by another wall. | `DoorService` measures the floor under a door once at setup and lowers the model (and its `Hinge`) by the gap when it is 2–20 studs, which puts the panel back in the doorway. `MapImport.spawnFor` got the same under-floor fallback so new imports record the right spawn. |
| 3 | DoorService | A blue "E" `BillboardGui` on **every** door (250+ across the maps), `AlwaysOnTop`, visible through walls. | Removed `addMarker`, its constants and the call. The `ProximityPrompt` (E) still exists. |
| 4 | Lighting | Bangclaw was blown out: `Brightness 3.4`, `ExposureCompensation 0.3`, near-white ambient, `Glare 0.7`, no shadows. | Retuned to `Brightness 2.2`, `Exposure 0.1`, darker ambient, `ClockTime 15`, `Glare 0.2`, `GlobalShadows` on, softer bloom/sun rays. |
| 5 | Lighting | Mall Parking had a mid-day mood only (no night). Five mood folders had no `GlobalShadows`, so switching from a map with shadows left the previous value behind. | Mall Parking now has a night mood (`ClockTime 21.5`, dark blue ambient, `Exposure 0.05`, haze, blue tint). `GlobalShadows` added to all eight folders. |
| 6 | MapLighting | A stray `TimeOfDay` string in a folder could override `ClockTime` depending on child order. | `apply` skips `TimeOfDay` when the folder also has `ClockTime`. |
| 7 | KeyboardLook | The arrow-key action sank arrows while a `TextBox` had focus, so the map search could not move its caret. | Passes the input through (and clears held keys) when `GetFocusedTextBox()` is set. |
| 8 | Feedback | Closing the feedback box hid it but left it focused, still eating keyboard input. | `ReleaseFocus()` on close. |
| 9 | Backrooms map | A ceiling-material plane sits exactly on the spawn floor (`Y=383.68`, 285×538 studs) and is only visible from below; its collision sealed the floor hole above it. | The look pass clears collision on ceiling parts that sit on the map's walk floor. Roblox collision is per part, so the whole merged ceiling plane loses collision (not just the hole); it is the lower level's ceiling, so the worst case is dropping through where the upper floor is missing. |
| 10 | Backrooms Movie map | The tape-outlined panel (`CUSTOM/WALLPAPERTAPE`) is the only thing filling the hidden doorway (walls 6 studs left, 5 studs right, open on both faces), so the film's passage was solid. | The panel is non-collidable (runtime look pass + place data). |
| 11 | Big City map | The river exists in the BSP only as water brush entities (`func_water`), which `bsp_to_json` does not import. The canal had a bed and no water, so no swimming and no buoyancy. | `MapCatalog` gained a small `water` volume; `MapService` fills it with `Terrain:FillBlock(..., Water)` at startup. Roblox handles swimming and prop buoyancy. |
| 12 | MapService.polishLook | Re-scanned every map's descendants for water/lights on every server start. | The importer now does the same pass (plus tape/ceiling) and sets `LookPolished`; `MapService` only scans maps without the attribute (legacy saves). |
| 13 | Lights | Imported `PointLight.Brightness` was copied from Source unchanged; some lamps were blinding. | Look pass caps brightness at `Config.MAX_LIGHT_BRIGHTNESS` (4). |
| 14 | Movement | No sprint, crouch or bunny hop: `PlayerFeel` only set `WalkSpeed`/`JumpHeight`. | Added `StarterPlayerScripts/Movement.luau`, ported from a premade open-source system (sources in `docs/ASSETS.md`). |
| 15 | Main menu | Start Game used a 140×160 grid of grey "?" boxes and the menu buttons had no icons. | Start Game is a map list (coloured icon tile, name, blurb, selected row); the links, nav buttons, Start button and map rows all carry a flat frame-drawn icon. |
| 16 | MapService.init (legacy hulls) | The Source converter's invisible collision hulls (`ForceField` material, `solid_*` clips, plain `Part` hulls) are hidden but kept collidable. Thin horizontal ones sitting on the walk floor are the recurring invisible blocker over openings. | The look pass now removes collision from invisible parts with `Size.Y <= 2` within 3 studs of the map's walk floor. Tall hulls (walls) are untouched, and `CollisionFloor` (5 studs below the floor) is not matched. |

## Checked and left alone

- Remote handlers already rate-limit first, then `typeof`, allowlist, ownership/state (`StartHold`, `EndHold`,
  `SpawnProp`, `Toolgun`, `WeaponFire`, `PickMap`, `RagdollToggle`, `SendFeedback`, `SetPvp`).
- `Remove`, `ClearProps`, `Dupe` and `Map` handlers all check caps through `Ownership`/`DupeService`.
- No `RemoteFunction` from server to client, no legacy `wait`/`spawn`/`delay` in `src/`.
- Every `:Connect` that can outlive its owner is disconnected on `PlayerRemoving`, `Destroying` or `CharacterRemoving`.
