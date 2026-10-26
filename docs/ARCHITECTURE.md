# Architecture

## Layout
```
default.project.json            Rojo map (Workspace.Props, Remotes folder defined here)
src/
  ReplicatedStorage/Shared/
    Config.luau                 caps, limits, tag/attribute names
    PropCatalog.luau            spawnable props, plain data (lune-testable)
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
      ToolgunService.luau       toolgun modes, thrusters
  StarterPlayerScripts/
    Main.client.luau
    Net.luau, Aim.luau          remote lookup, crosshair raycast
    Ragdoll.luau                G key, Humanoid Physics/GettingUp on RagdollState
    FirstPerson.luau            visible arms + tool aim, sway, view bob, FOV
    Sfx.luau                    local UI sounds
audio/sfx.py                    synthesizes the SFX -> audio/exports/*.ogg
    UI/SpawnMenu.luau           Q menu, HUD, toast, X remove
    UI/ToolHud.luau, Ui.luau    crosshair, toolgun panel, selection outline, shared theme
    UI/WeaponSelect.luau        HL2-style weapon selector (replaces the hotbar)
    Tools/                      ToolController (equip detection, F key), Physgun, GravityGun, Toolgun
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

## Spawn flow
1. Client raycasts from screen centre, clamps point into spawn range, fires `SpawnProp(id, point)`.
2. Server: rate limit -> types -> catalog lookup -> finite position -> alive character -> within 150 studs -> under cap.
3. Server builds the part from catalog data, `Ownership.claim` (registry, tag, attribute, count), then parents into `Workspace.Props`.
4. `Player:PropCount` attribute replicates; HUD reads it.

## Ownership
`Ownership` registry is the source of truth. Tag `SandboxProp` and attribute `OwnerUserId` are informational. A prop's `Destroying` event releases its slot (also covers falling into the void). `PlayerRemoving` destroys that player's props.

## Planned additions
- Dupes (step 4): `Services/DupeService.luau`, DataStore access only here.
- NPCs (step 6): `Services/NpcService.luau`, shared behavior-tree runtime in `Shared/`.
