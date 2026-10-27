# Architecture

## Layout
```
default.project.json            Rojo map (Workspace.Props, Remotes folder defined here)
src/
  ReplicatedStorage/Shared/
    Config.luau                 caps, limits, tag/attribute names
    PropCatalog.luau            spawnable props, plain data (lune-testable)
    DupeCodec.luau              dupe format + sanitize, plain data (lune-testable)
    MapCatalog.luau             maps on the server (Baseplate, Construct, Flatgrass): spawn, collision floor, menu orbit
    WeaponCatalog.luau          guns: slot, hold, rpm, magazine, spread, damage, rocket; plain data
  ServerScriptService/
    Main.server.luau            boots services
    Services/
      SpawnService.luau         SpawnProp / RemoveProp / ClearMine handlers
      PropBuilder.luau          catalog data -> parts (props, wheels, seats)
      VehicleService.luau       wheels (motor/servo hinges), premade cars, seat driving loop
      PhysicsGuard.luau         speed cap + network ownership reclaim for loose props
      RagdollService.luau       G toggle, death ragdoll
      Sfx.luau                  3D one-shots and loops from the server (Shared/Sounds.luau ids)
      Ownership.luau            who owns which prop, cap, cleanup
      RateLimiter.luau          token bucket per player
      Validate.luau             finite checks, alive root, equipped tool
      Constraints.luau          welds/ropes/thrusters: cap + cleanup with props
      ToolService.luau          builds Physgun/Gravity Gun/Toolgun + selector slots, gives them via StarterGear
      Hold.luau                 shared hold (Align constraints, PhysgunAim), server-owned physics
      PhysgunService.luau       grab, freeze
      GravityGunService.luau    pull, punt, hold, throw
      ToolgunService.luau       toolgun modes, thrusters; link builders shared with dupes
      DupeService.luau          Dupe mode copy, slots, paste, DataStore "Dupes"
      FeedbackService.luau      SendFeedback -> DataStore "Feedback" + server log
      MapService.luau           PickMap: move to a map's spawn, respawn there; strips scripts from Workspace.Maps, adds collision floors
      WeaponService.luau        WeaponFire/Reload/SetPvp: server fire rate, ammo, spread, hitscan, rockets, PvP damage
  StarterPlayerScripts/
    Main.client.luau
    Net.luau, Aim.luau          remote lookup, crosshair raycast
    Ragdoll.luau                G key, Humanoid Physics/GettingUp on RagdollState
    FirstPerson.luau            visible arms + tool aim, sway, view bob, FOV
    KeyboardLook.luau           arrow keys turn the camera (trackpad play)
    GunPose.luau                per-gun arm poses (pistol/rifle/launcher), applied by every client to every character
    MapLighting.luau            per-client sky/lighting/water for the player's map
    Sfx.luau                    local UI sounds
audio/sfx.py                    synthesizes the SFX -> audio/exports/*.ogg
audio/voice/recorder.py         NPC voice recorder GUI: lines.json -> takes/*.wav -> exports/<npc>.ogg sprites + VoiceLines.luau (docs/VOICE.md)
audio/voice/record.bat          Windows double-click launcher: sets up .venv on first run, then opens the recorder
    UI/SpawnMenu.luau           Q menu, HUD, toast, X remove
    UI/ToolHud.luau, Ui.luau    crosshair, toolgun panel, selection outline, shared theme
    UI/WeaponSelect.luau        HL2-style weapon selector (replaces the hotbar)
    UI/Feedback.luau            feedback text box (button in the Q menu)
    UI/Ui.luau                  shared Source skin: THEME, button, row, window, list (selector keeps Ui.CLASSIC)
    UI/MainMenu.luau            Source-style main menu on join / M: camera circles the selected map (MapCatalog orbit), Start Game / Controls / Options dialogs
    Tools/                      ToolController (equip detection, F key), Physgun, GravityGun, Toolgun, Gun (all guns)
tests/                          lune specs
scripts/check.sh                full gate
```

## Remotes (`ReplicatedStorage.Remotes`)
| Name | Dir | Payload | Notes |
|---|---|---|---|
| SpawnProp | C->S | `propId: string, position: Vector3` | rate 5 burst / 4 per s |
| RemoveProp | C->S | `target: Instance` | owner only |
| ClearMine | C->S | none | 2 burst, 1 per 5 s |
| Notify | S->C | `message: string` | toast |
| PhysgunGrab | C->S | `prop: Instance` | owner only, tool equipped, range 80 |
| PhysgunAim | C->S unreliable | `CFrame` | rate 40 burst / 30 per s, position clamped |
| PhysgunRelease / PhysgunFreeze | C->S | none | |
| ToolgunUse | C->S | `mode, prop, point, normal, extra` | allowlisted mode, owner only |
| ThrustersHeld | C->S | `boolean` | 20 burst / 10 per s |
| ToolSelect | S->C | `Instance?` | selection outline |
| GravityPull | C->S | `prop: Instance?` | far: pull, near: hold, while holding: drop |
| GravityPunt | C->S | `prop: Instance, direction: Vector3` | unit direction, range 30, throws if held |
| RagdollToggle | C->S | none | 3 burst / 1 per s, alive only |
| RagdollState | S->C | `boolean` | client sets Humanoid Physics / GettingUp |
| DupeSave / DupeDelete | C->S | `slot: number` | 3 burst / 1 per 5 s, slot 1-10 |
| DupeLoad | C->S | `slot: number, position: Vector3` | 2 burst / 1 per 2 s, range 150, caps |
| WeaponFire | C->S | `id: string, origin: Vector3, direction: Vector3` | 20 burst / 16 per s, then per-gun rpm; origin is compatibility only, the server uses its own head |
| WeaponReload | C->S | `id: string` | 3 burst / 1 per s, gun equipped |
| SetPvp | C->S | `on: boolean` | 2 burst / 1 per 5 s |
| WeaponFx | S->C unreliable | `shooter, id, hit: Vector3` | other players' tracers |
| PickMap | C->S | `id: string` | 2 burst / 1 per 2 s, MapCatalog allowlist, map must exist |
| SendFeedback | C->S | `text: string` | 1 per 60 s, 500 chars, UTF-8, control chars stripped |
| DupeState | S->C | `clipboard: string, slots: {string}` | panel labels |

## Maps
One server holds every map at once, far apart: the Rojo baseplate at the origin, `Workspace.Maps.Construct` at X +6000, `Workspace.Maps.Flatgrass` at X -10000. The maps live in the place file (inserted from the Creator Store, stripped to geometry, clip walls and terrain water); spawn points and the Flatgrass collision floor live in `MapCatalog`. At boot `MapService` turns collision off on every map part drawn with a `SpecialMesh` (the converter's brush meshes keep a box-sized collision that buries the play area; real collision is the `solid_*` clips and `Poly` triangles). Their lighting/sky/water settings are in `ReplicatedStorage.MapLighting.<id>`, applied on the client by `MapLighting.luau` for the player's `Map` attribute, so two players on different maps each see their own sky. Parts the converter marked `ForceField` and named `solid_*` are invisible collision hulls; `MapService` sets them transparent (they still collide) instead of turning them into opaque gray slabs. Each `MapCatalog` mirror point gets a generated 28x14 mirror panel on the nearest wall face (and on the opposite face of the same wall), tagged `Mirror`; `Mirror.luau` renders a reflected copy of the nearby room and the local character on its room-facing side.

## Spawn flow
1. Client raycasts from screen centre, clamps point into spawn range, fires `SpawnProp(id, point)`.
2. Server: rate limit -> types -> catalog lookup -> finite position -> alive character -> within 150 studs -> under cap.
3. Server builds the part from catalog data, `Ownership.claim` (registry, tag, attribute, count), then parents into `Workspace.Props`.
4. `Player:PropCount` attribute replicates; HUD reads it.

## Ownership
`Ownership` registry is the source of truth. Tag `SandboxProp` and attribute `OwnerUserId` are informational. A prop's `Destroying` event releases its slot (also covers falling into the void). `PlayerRemoving` destroys that player's props.

## Planned additions
- NPCs (step 6): `Services/NpcService.luau`, shared behavior-tree runtime in `Shared/`.
