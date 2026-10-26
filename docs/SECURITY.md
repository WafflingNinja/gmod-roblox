# Security

The game is public from day one. Assume executors.

## Handler order (every remote)
1. Rate limit (token bucket, per player, server-side).
2. `typeof` check every argument.
3. Allowlist (`PropCatalog.byId`, tool ids).
4. Finite and bounded numbers (`< 1e5`; NaN/inf fail).
5. Player state: alive character, within range.
6. Ownership via `Ownership.isOwner` (registry, not instance attributes).
7. Act. Fail silently; only send a toast for honest-player feedback.

## Limits
| What | Value | Where |
|---|---|---|
| Props per player | 150 | `Config.PROP_CAP` |
| Spawn range | 150 studs | `Config.SPAWN_RANGE` |
| Spawn rate | 5 burst, 4/s | `Config.SPAWN_*` |
| Remove rate | 10 burst, 5/s | `Config.REMOVE_*` |
| Clear rate | 2 burst, 1 per 5 s | `Config.CLEAR_*` |

## Current remote matrix
| Remote | Exploit tried | Result |
|---|---|---|
| SpawnProp | unknown id, nil, table, string pos | rejected at type/allowlist |
| SpawnProp | `Vector3.new(0/0, 0, 0)`, `math.huge` | rejected by finite check |
| SpawnProp | position 10000 studs away | rejected by range check |
| SpawnProp | 1000 calls/sec | limiter drops after burst |
| SpawnProp | spawn while dead | rejected |
| RemoveProp | someone else's prop, map part, baseplate | rejected (not in registry) |
| RemoveProp | non-Instance, nil | rejected |
| ClearMine | spam | limiter |
| PhysgunGrab | other player's prop, map part, no tool equipped, out of range | rejected |
| PhysgunAim | NaN/inf CFrame, target 1000 studs away | rejected / clamped to 60 studs of character |
| ToolgunUse | unknown mode, Physgun equipped, point 500 studs away, other's prop | rejected |
| ToolgunUse Scale/Paint | direction 5, colour index 99 / NaN | rejected |
| ToolgunUse Thruster | non-unit normal | rejected |
| ThrustersHeld | non-boolean, spam | rejected / limiter |
| GravityPull | other's prop, anchored prop, no gravity gun equipped, 500 studs away | rejected (not yet Studio-tested) |
| GravityPunt | NaN/inf or non-unit direction, other's prop, punt someone else's held prop | rejected (not yet Studio-tested) |
| PhysgunFreeze | fired while holding with the gravity gun | rejected (Physgun must be equipped) |
| ToolgunUse Wheel | unknown wheel id, non-unit normal, past constraint cap | rejected (not yet Studio-tested) |
| SpawnProp | car id, position inside another player | cars allowed (1 prop slot); near-player rejected with toast |
| RagdollToggle | spam, while dead | limiter (3 burst, 1/s) / rejected |
| ToolgunUse Dupe | other's prop, map part | rejected (owner check); flood-fill only follows own props |
| DupeSave / DupeDelete | slot 0, 11, 1.5, NaN, string, empty clipboard, spam | rejected / limiter (not yet Studio-tested) |
| DupeLoad | empty slot, NaN/far position, near another player, over prop/constraint/thruster cap | rejected, whole dupe or nothing (not yet Studio-tested) |
| WeaponFire | unknown gun, gun not equipped, NaN/non-unit direction, origin far from head, faster than rpm, empty magazine, during reload | rejected; spread, hit and damage are server-side |
| WeaponFire | hit another player | damage only if both have PvP on; props only pushed when the shooter owns them |
| WeaponFire RPG | rocket spam | 3 rockets in flight per player, rpm 40 |
| SetPvp / WeaponReload | non-boolean, spam, gun not equipped | rejected / limiter |
| PickMap | unknown id, non-string, map missing, spam | rejected / limiter; position comes from the map, never the client |
| SendFeedback | non-string, 1 MB string, invalid UTF-8, control chars, spam | rejected / cleaned / limiter (1 per 60 s); logged with `%q`, never shown to players |
| DupeLoad | hand-edited DataStore value (unknown id, NaN, broken link) | `DupeCodec.sanitize` drops it (lune-tested) |

## Network ownership policy (step 3)
- Held props (physgun, gravity gun): server-owned while held, back to auto on release.
- Gravity gun impulses: server takes ownership for the impulse, auto again after 2 s.
- Loose props: Roblox auto-ownership. `PhysicsGuard.luau` checks every prop 10 times a second; one faster than 400 studs/s is taken server-side, clamped to 400, and handed back after 3 s. The engine already destroys parts below `FallenPartsDestroyHeight`.
- Vehicles: the seat occupant owns the assembly (Roblox default). `VehicleService` reads `ThrottleFloat`/`SteerFloat` that Roblox replicates; there is no drive remote, so a client can only drive its own seat, at capped motor speed (90 studs/s).
- Player characters are client-owned (platform); ragdoll joints are made on the server.
- Spawning within 6 studs of another player's character is refused.

## Open items
- **Physics griefing:** an owner can still drop huge slabs on others or ram them with a car below the speed cap.
- **Part cap vs prop cap:** each dupe part is one prop, so the 150 cap holds for dupes too.
- **Trust:** never log player-supplied strings unescaped; never use client text in `Instance.Name`.
