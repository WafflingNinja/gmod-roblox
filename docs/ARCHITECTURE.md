# Architecture

## Layout
```
default.project.json            Rojo map (Workspace.Props, Remotes folder defined here)
src/
  ReplicatedStorage/Shared/
    Config.luau                 caps, limits, tag/attribute names
    PropCatalog.luau            spawnable props, plain data (lune-testable)
    DupeCodec.luau              dupe format + sanitize, plain data (lune-testable)
    MapCatalog.luau             maps on the server (Baseplate, Construct, Flatgrass, the five Workshop maps): spawn, collision floor, menu orbit, optional placeId
    PassCatalog.luau            pass/product ids, names, prices, icons (plain data, lune-tested)
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
      MapService.luau           PickMap: move to a map's spawn, respawn there; split-world teleports; strips scripts from Workspace.Maps, adds collision floors, water/shadow polish
      Passes.luau               pass ownership, purchases, tips, beam colour, VIP tag
      WeaponService.luau        WeaponFire/Reload/SetPvp: server fire rate, ammo, spread, hitscan, rockets, PvP damage
  StarterPlayerScripts/
    Main.client.luau
    Net.luau, Aim.luau          remote lookup, crosshair raycast
    Ragdoll.luau                G key, Humanoid Physics/GettingUp on RagdollState
    FirstPerson.luau            visible arms + tool aim, sway, view bob, FOV
    KeyboardLook.luau           arrow keys turn the camera (trackpad play)
    GunPose.luau                per-gun arm poses (pistol/rifle/launcher), applied by every client to every character
    MapLighting.luau            per-client sky/lighting/water for the player's map, tweened on change
    Sfx.luau                    local UI sounds
    VipChat.luau                gold [VIP] chat prefix from the Pass_vip attribute
audio/sfx.py                    synthesizes the SFX -> audio/exports/*.ogg
    UI/SpawnMenu.luau           Q menu, HUD, toast, X remove
    UI/ToolHud.luau, Ui.luau    crosshair, toolgun panel, selection outline, shared theme
    UI/WeaponSelect.luau        HL2-style weapon selector (replaces the hotbar)
    UI/Feedback.luau            feedback text box (button in the Q menu)
    UI/Ui.luau                  shared Gmod/Derma skin: THEME, button, row, window, list (selector keeps Ui.CLASSIC)
    UI/MainMenu.luau            Gmod-style main menu on join / M: camera circles the selected map (MapCatalog orbit), Start Game / Controls / Options / Store
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
| SetBeamColor | C->S | `paletteIndex: number` | 5 burst / 2 per s, pass required, index in `Config.PALETTE` |
| WeaponFx | S->C unreliable | `shooter, id, hit: Vector3` | other players' tracers |
| PickMap | C->S | `id: string` | 2 burst / 1 per 2 s, MapCatalog allowlist, map must exist or have a placeId; a remote map teleports |
| SendFeedback | C->S | `text: string` | 1 per 60 s, 500 chars, UTF-8, control chars stripped |
| DupeState | S->C | `clipboard: string, slots: {string}` | panel labels |

## Maps
Split Worlds: each map gets its own place in the same universe. The **start place is Flatgrass** (plus the main menu); the other maps carry `placeId` in `MapCatalog` once their place exists. `PickMap` teleports with `TeleportService:TeleportAsync` when the target has a different placeId, so props do not follow; while a map has no place yet (or in Studio, where teleporting fails) it falls back to the in-place copy. A place whose id is in `MapCatalog.placeId` sets its `ServerMap` attribute at boot and spawns players on that map. 24 players per server (`Config.MAX_PLAYERS`; set the actual limit in Creator Dashboard) and 1,500 props across all players (`Config.SERVER_PROP_CAP`); per-player 150 / Builder+ 250 still apply.

The development place still holds every map far apart: the Rojo baseplate at the origin, `Workspace.Maps.Construct` at X +6000, `Workspace.Maps.Flatgrass` at X -10000, and the five Workshop maps on a 40k-stud ring (see `IMPORT-MAPS.md`). Spawn points and the Flatgrass collision floor live in `MapCatalog`. On boot `MapService` removes scripts, hides converter hulls, adds floors, gives water pieces the glass look, turns shadows on for the 20 strongest lights per map (`Config.SHADOW_LIGHTS`), and builds mirrors. Their lighting/sky/water settings are in `ReplicatedStorage.MapLighting.<id>`, applied on the client by `MapLighting.luau` for the player's `Map` attribute and tweened over `Config.LIGHTING_FADE`, so two players on different maps (or in menus) each see their own sky. `default.project.json` sets `Lighting.Technology = Future` and has a mood folder for every map, including Baseplate/Construct/Flatgrass.

## Map factory
`tools/add_map.py <workshop link>` is the one-command pipeline: subscribe check -> find `.gma` -> `gmad extract` -> `bsp_to_json` -> alpha audit -> browser review (50 per page, click to reject) -> upload approved textures -> insert into `MapCatalog`, `MapLighting` and `docs/ASSETS.md` -> prompt for the new place id -> copy the Studio import command. It also copies `tools/MapImport.luau` into `%TEMP%/kilo/maps_out` and starts the local HTTP server. Rejected textures are never uploaded, so `MapImport` leaves those materials flat-coloured.

## Spawn flow
1. Client raycasts from screen centre, clamps point into spawn range, fires `SpawnProp(id, point)`.
2. Server: rate limit -> types -> catalog lookup -> finite position -> alive character -> within 150 studs -> under cap.
3. Server builds the part from catalog data, `Ownership.claim` (registry, tag, attribute, count), then parents into `Workspace.Props`.
4. `Player:PropCount` attribute replicates; HUD reads it.

## Ownership
`Ownership` registry is the source of truth. Tag `SandboxProp` and attribute `OwnerUserId` are informational. A prop's `Destroying` event releases its slot (also covers falling into the void). `PlayerRemoving` destroys that player's props.

## Passes and tips
`Shared/PassCatalog.luau` is the single list: six passes and three tip products, IDs as numbers. `Services/Passes.luau` checks `UserOwnsGamePassAsync` on join (pcall + retry/backoff), grants on `PromptGamePassPurchaseFinished`, and stores ownership as `Pass_<key> = true` on the Player. `Passes.has(player, key)` is the only check perks use; the client only reads the attribute to draw Owned/locked states. Tips go through `ProcessReceipt`, which thanks the buyer and returns `PurchaseGranted`; unknown products return `NotProcessedYet`.

Perks: Builder+ (`Ownership.cap` 250), More Dupe Slots (`DupeService` 30), NPC Pack (`NpcService` 20 per player), Physgun Colors (`SetBeamColor` -> `BeamColor` attribute), VIP (billboard tag, chat prefix, gold beam, gold trail, golden spawn pads built once by `MapService`), Sports Car (`car_sports` with `pass = "sports_car"`, `topSpeed = 95`). The Q menu locks the Sports Car until owned; the M menu Store page lists every item with live Buy/Owned state.

## Planned additions
- NPCs (step 6): `Services/NpcService.luau`, shared behavior-tree runtime in `Shared/`.
