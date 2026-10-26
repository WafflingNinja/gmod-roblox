# TO-DO: everything left, in build order

Written so one long autonomous run can finish the game without re-planning. Work top to bottom. Each phase ends with a **Done when** check; do not start the next phase until it passes. Rules in `CLAUDE.md` always apply (server decides, `--!strict`, no Valve/Gmod assets, `scripts/check.sh` green, update the matching `docs/` file in the same change).

**State 2026-10-26:** see `handoff.md`. Built since: dupes, feedback, maps (Construct, Flatgrass), main menu, keyboard look, four guns, shared UI skin. Untested in Studio: guns firing, gun holds, dupes, feedback.

**State at backup time (2026-10-25):** steps 1 and 2 are built and Studio-verified with 1 client: spawn menu, ownership, 150 cap, physgun, toolgun (weld, rope, thruster, scale, paint, unweld, remove), multi-part prop details. Nothing is committed to git yet.

## 0. Needs the user (batch these, do not block on them)
| When | What | Why |
|---|---|---|
| Before phase 3 test | Studio: Test > Clients and Servers, 2 players, Start | MCP cannot drive a second real client. Run `docs/TESTING.md` multi-client items. |
| Phase 5 art | Studio: Import 3D, select all FBX in `blender/exports/`, import | Roblox mesh upload is GUI only. Skippable if the user gives an Open Cloud API key (see 5.9). |
| Launch | Publish to Roblox, enable API Services, set max players, thumbnail, description | Needs the user's account. |
| Launch | Confirm Studio is logged in | Login and ToS clicks are theirs. |

Assume a pause on any of these only when the next task truly depends on it; otherwise keep building and leave the item in the "Waiting on user" list at the bottom.

## 1. Housekeeping (30 min)
- [ ] `git add -A && git commit` the current state (conventional message). Ask first if a remote is wanted; no push without being told.
- [x] Delete `Sandbox*.rbxl` and `.lock` leftovers (done; Studio's own AutoRecovery files live outside the repo).
- [x] Project name: "waffles mod" (README, project name, menu title).
- [ ] Studio test helper: add `tests/studio/` with small Luau snippets (spawn N props, fire remote, assert) so MCP runs are repeatable. Keep each under 40 s (MCP drops longer calls).

**Done when:** `git log` has the baseline commit and `scripts/check.sh` passes.

## 2. Finish step 2 (tools)
### 2.1 Gravity gun
- Tool `GravityGun` built in `ToolService` (original look: orange/black). `Config.GRAVGUN`.
- `GravityGunService.luau`, client `Tools/GravityGun.luau`, registered in `ToolController`.
- RMB on a far own prop: pull (impulse toward player, capped speed). RMB on a near prop (< 12 studs): hold at fixed distance (reuse the physgun hold code: extract `Hold.luau` from `PhysgunService`, both services call it). LMB: punt, `ApplyImpulse(direction * assemblyMass * PUNT_SPEED)` with `PUNT_SPEED = 120`. LMB while holding: throw.
- Validate: tool equipped, own prop, in range, unanchored, direction finite and unit-length, rate limit (5 burst, 3 per s).
- Add remotes `GravityPunt`, `GravityPull` to `default.project.json`; add rows to `docs/SECURITY.md`; spec in `docs/TOOLS.md`.

### 2.2 Tool polish
- [ ] Sounds with built-in `rbxasset://sounds/` files only (grab, release, weld, error). No uploaded or ripped audio.
- [ ] Beam colour per tool, tool names on the hotbar tooltip, "Not yours" toast on physgun misses.
- [ ] Toolgun Weld: optional "no collide" flag? Skip unless playtests ask.

**Done when:** MCP test shows pull, punt, hold, throw work; abuse calls (NaN direction, other player's prop, tool not equipped) do nothing; `docs/TOOLS.md` updated.

## 3. Cars, wheels, ragdolls, network ownership (ROADMAP step 3)
### 3.1 Network ownership policy (decide first, document in `docs/SECURITY.md`)
- Held props: server-owned (done).
- Loose props: leave Roblox auto-ownership, but clamp speed: a Heartbeat loop in `PhysicsGuard.luau` that caps `AssemblyLinearVelocity` of owned props at 400 studs/s and destroys props below `FallenPartsDestroyHeight`.
- Vehicles: seat occupant owns the assembly (Roblox default for VehicleSeat); server reads seat input.
- Spawn exclusion: reject a spawn point within 6 studs of another player's character.

### 3.2 Seat and wheel props
- Add catalog props: `vehicle_seat` (VehicleSeat, 2x1x2), `wheel_small`, `wheel_big` already exist. Catalog supports a `className` field (default Part; `VehicleSeat`/`Seat`); the lune spec validates it.
- Toolgun **Wheel** mode: click a prop face, server spawns a wheel (small or big per toolgun setting) hinged with `HingeConstraint` (Motor actuator) at that point, axle along the face's tangent. Wheel is a child of the clicked prop (like details) so it dies with it, counts against `CONSTRAINT_CAP`, steering toggle in the panel (front wheels use a second Servo hinge).
- `VehicleService.luau`: one Heartbeat connection for every occupied VehicleSeat; reads `ThrottleFloat`/`SteerFloat`, sets motor `AngularVelocity` (clamped) and servo `TargetAngle` (clamped to 30 degrees). No custom drive remote: Roblox replicates seat input already.

### 3.3 Three premade cars
- `Cars/` data in `Shared/CarCatalog.luau` (plain data, lune-tested) and builder in `VehicleService`: sedan, truck, buggy. Chassis part is the single registered prop; seat, body parts and wheels are welded/hinged children. Spawn tab "Cars" in the spawn menu.
- Tune: centre of mass low (custom `CustomPhysicalProperties` on chassis), wheel friction, max speed 90 studs/s, anti-flip torque while seated.

### 3.4 Ragdolls (players)
- `RagdollService.luau`: swap Motor6D for `BallSocketConstraint` + collision capsules (R15 `BuildRigFromAttachments` pattern), `PlatformStand`, get-up after 3 s or on key. Toggle key `G` (rate limited), automatic on death (keep `BreakJointsOnDeath = false`), automatic on high-speed impact (`> 80` studs/s relative) and when a held/thrown prop hits hard.
- Respawn must restore Motor6Ds cleanly; test rapid toggle spam.

### 3.5 Tests
- lune: `tests/cars.spec.luau` validates `CarCatalog`. MCP: spawn car, seat the character via server `Seat:Sit`, set `ThrottleFloat`, assert displacement.

**Done when:** a car built with the Wheel tool and one premade car both drive, ragdoll toggle and death ragdoll work and recover, 2-client test (section 0) shows the car seen driving by the second player.

## 4. Dupes, feedback, hardening, launch (ROADMAP step 4)
### 4.1 Dupes (spec in `docs/DUPES.md`)
- `DupeService.luau`: Toolgun **Dupe** mode (click prop, flood-fill through constraints, cap 80 parts) and a Dupes panel (save to slot 1-10, load, delete).
- Pure serialisation in `Shared/DupeCodec.luau` (plain tables in/out, version field, clamps on load), fully lune-tested with round-trip and hostile input cases.
- DataStore `Dupes`, `UpdateAsync` + `pcall` + retry/backoff, never overwrite on a failed load (`DataLoaded` flag), flush on `PlayerRemoving` and `BindToClose`, size check below 3.5 MB per key. Studio needs API Services on.
- Loading goes through the same code as spawning (ownership, 150 cap, constraint cap). Reject the whole dupe if it would exceed a cap.

### 4.2 Feedback button
- HUD button opens a text box (max 500 chars, client trims); `SendFeedback` remote, 1 per 60 s per player, `typeof` string check, strip control characters, store in DataStore `Feedback` (key `<timestamp>-<userid>`), print to server log. Never show feedback text to other players. No external HTTP.

### 4.3 Anti-exploit and stability pass
- Walk every remote against the matrix in `docs/SECURITY.md`; add an abuse test per remote in `tests/studio/`.
- Server-side caps: parts per player (props + details counted), NPC/ragdoll budgets, total unanchored parts per server (soft limit 3000, spawn refused above it with a toast).
- Memory/leak check: spawn/remove 1000 props in a loop, confirm no growth in `Stats:GetTotalMemoryUsageMb()` and no leftover connections (grep every `:Connect` has an owner).
- Decide `StreamingEnabled` for the 2048 map; props code already tolerates missing instances.
- Disable features for low-end: `Config.QUALITY` flag to drop particle rates.

### 4.4 Launch checklist
Work through `docs/LAUNCH.md`. Needs the user for publishing, thumbnail, description, questionnaire.

**Done when:** save a dupe, rejoin, load it; abuse suite passes; 3 friends play 30 minutes without a crash; feedback arrives in the DataStore; then publish.

## 5. Chaos content (ROADMAP step 5, ships as updates)
### 5.1 Original prop meshes (replaces primitives)
- `blender/props.py` builds each catalog prop procedurally (headless: `blender -b --python blender/props.py`), exports FBX per prop to `blender/exports/`. Start with the 13 current props plus: traffic cone, pallet, tire, propane tank, bowling ball, watermelon, sawblade, oil drum, bench, door.
- After the user imports (or 5.9), catalog gets `visual = {meshId, size, offset}`: a MeshPart child, no collision, welded to the primitive hitbox; the old `details` are dropped for that prop. Scale tool already rescales children with `DetailSize`.
- License log in `docs/ASSETS.md` for any CC0 pack used (Kenney, Quaternius). No Gmod/Valve shapes copied 1:1; own proportions and textures.

### 5.2 Gun roster (partly built 2026-10-26: Pistol, SMG, Pulse Rifle, Rocket Launcher; untested in play; models and sounds come from Creator Store users, see `docs/ASSETS.md`)
- Provenance check first: the FFA work has 7 procedurally generated Blender guns (original) and a separate set of 48 "BD" meshes. Do not use the BD meshes in a public game until the user confirms where they came from and the license. The 7 are fine.
- Spawn tab "Weapons": guns are Tools given on spawn click (cap 3 per player). `WeaponService.luau`: server hitscan raycast, fire rate and ammo server-side, recoil is client cosmetic. Hits apply capped `ApplyImpulse` to props and ragdolls. Player damage only when the player has PvP toggled on (default off; toggle panel; a PvP player can only be damaged by other PvP players).
- Client viewmodel optional; reuse the FFA viewmodel approach only for the 7 original guns.

### 5.3 Breakable props
- Catalog flag `breakable = {health, shards}`: glass pane, vase, wooden fence, watermelon, light bulb, crate (weak). `BreakService.luau`: Heartbeat speed check on `breakable` props only (relative speed above threshold or explosion), replace with 6-12 shard parts (unanchored, `CanQuery = false`, destroyed by `Debris` after 8 s), global shard cap 300, spawner's prop slot freed. Explosion tool/prop with capped blast radius and impulse.

### 5.4 Emotes and funny animations
- Built-in emotes through `Humanoid:PlayEmote` (dance, dance2, dance3, cheer, laugh, point, wave).
- Procedural silly emotes (T-pose, spin, flop, headspin, noodle arms) as Motor6D pose sequences in `Shared/EmoteData.luau` (plain data); server validates emote id + rate limit and fires `EmotePlay(player, id)` to all clients, each client animates that character locally. Emote wheel on `B`.
- Weapon and tool silliness: gun spin on equip, slide reload, physgun recoil wobble, all client-side cosmetics driven by server `ToolFx` events.

### 5.5 Posable ragdolls
- Catalog prop "Dummy": torso is the registered prop, limbs are children linked by `BallSocketConstraint` so Ownership and cap logic stay unchanged.
- `PhysgunGrab` accepts a limb that is a descendant of an owned prop (resolve to its prop for ownership, grab the limb). Toolgun **Pose** mode: click limb to freeze it (anchor + weld), click again to release. Poses saved inside dupes.

### 5.6 More map and atmosphere
- Themed areas on the big map (ramp park, water pool, tall tower, flat dyno strip), built in Studio and saved in the place; sky, lighting, ambient music from `rbxasset://` built-ins.

### 5.7 UI
- Replace the plain Q list with tabs (Props, Cars, Weapons, NPCs, Dupes) and search. Controller and mobile stay out of scope.

### 5.8 Prop and weapon sound
- Collision sounds via built-in impact sounds, volume scaled by speed, capped by a global sound budget.

### 5.9 Optional automation of mesh upload
Only if the user provides an Open Cloud API key with `asset:write`: `tools/upload_assets.py` uploads each FBX through the Assets API, polls the operation, and writes `meshId`s into `Shared/PropMeshes.luau`. Verify endpoint and asset type in Roblox docs first (`roblox_get_cloud_endpoint`). The key never goes in the repo (`.env` is gitignored).

**Done when:** every prop has a mesh visual or a deliberate primitive, guns shoot props and ragdolls, breakables shatter within caps, emotes play for everyone in range, dummies pose and freeze; `docs/ASSETS.md` license log complete.

## 6. NPC AI (ROADMAP step 6, spec in `docs/NPC.md`)
- Voice first: the user records the lines with `audio/voice/recorder.py` (`docs/VOICE.md`). Then move `audio/voice/exports/VoiceLines.luau` to `Shared/`, stylua it, lune-spec it, and build `Services/NpcVoice.luau`.
- Roster: Guest and Noob (Friendly), John Doe (Hostile). No Jane Doe.
- `Shared/BehaviorTree.luau`: blackboard, sequence/selector/parallel, inverter/cooldown/repeat decorators, lune-tested with a fake clock.
- `NpcService.luau`: one Heartbeat tick for all NPCs, round-robin thinking at 4-10 Hz, sleep when no player within 150 studs; pathfinding with path cache and re-path throttle; ragdoll reuse from 3.4.
- Types: Dummy, Friendly (wander, follow owner on command, flee), Hostile (chase, melee or gun, give up); NPC spawn tab; budget 10 per player, 40 per server, each costs 5 prop slots.
- Server owns NPC physics; NPCs never trust clients; damage rules follow the PvP toggle for players, always on for NPC vs NPC.

**Done when:** 40 NPCs run for 10 minutes with server frame time under budget (check `Stats`), cleanup on owner leave leaves zero NPCs behind.

## 7. Final pass
- [ ] `docs/` and `ROADMAP.md` fully ticked and accurate; README controls table complete.
- [ ] All `docs/TESTING.md` boxes ticked or explicitly waived with a reason.
- [ ] Code review pass (`code-review` skill) and security review pass over every remote.
- [ ] Clean git history, tag `v1.0`.

## Waiting on user (keep updated)
- 2-player Studio test: pending
- Record NPC voice lines (`docs/VOICE.md`), then upload the 3 sprites: planned 2026-10-27
- FBX import or API key for meshes: pending
- Upload the 13 generated SFX (`audio/exports/*.ogg`, Asset Manager > Bulk Import): pending
- BD mesh provenance and license: pending
- Publish and settings: pending
- gm_construct / gm_flatgrass Store maps: provenance unknown, DMCA risk accepted by the user 2026-10-26; replace with originals before a public launch if they turn out to be Valve conversions
- Studio: Game Settings > Security > Enable Studio Access to API Services (dupe saving): pending
