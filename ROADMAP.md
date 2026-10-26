# Roadmap

Launch after step 4. Steps 5 and 6 ship as updates. Tick a box only when verified.

## 1. Foundation: spawn, ownership, cap
- [x] Repo, Rojo project, toolchain, `scripts/check.sh` green
- [x] Prop catalog (13 primitives) + lune test
- [x] `SpawnProp` / `RemoveProp` / `ClearMine` remotes with rate limit, type checks, range check
- [x] Ownership registry, 150 cap, cleanup on leave
- [x] Q menu, crosshair spawn, X remove, HUD count, toast
- [x] Studio verified (1 client, 2026-10-25): all 13 props spawn and rest on the floor, bad id/nil/table/NaN/inf/far-away payloads ignored, cap stops at 150 with toast, remove-own works, baseplate removal ignored, ClearMine empties to 0
- [ ] Still needs 2 clients (user: Test > 2 players): removing another player's prop, leaver's props vanish

## 2. Tools
- [x] Physgun: grab, push/pull, rotate, freeze; own props only (Studio verified, 1 client)
- [ ] Gravity gun: pull, punt, hold (written; pull/punt/throw/abuse Studio-checked, aim-follow untested)
- [ ] HL2-style weapon selector replacing the hotbar (written, untested)
- [x] Toolgun modes: weld, rope, thruster, scale, paint, unweld, remove (Studio verified, 1 client)
- [ ] Toolgun wheel mode (moves to step 3 with cars)
- [x] Per-mode validation in `docs/TOOLS.md`
- [ ] 2-client check of tools (other player's props untouchable, thrusters visible to others)

## 3. Cars and ragdolls
- [ ] 3 premade drivable cars (VehicleSeat, constraints) (written, untested)
- [ ] Wheel tool builds working cars (written, untested)
- [ ] Ragdoll physics for players (toggle + on-death) (written, untested; impact ragdoll not done)
- [x] Network ownership policy decided and documented (`docs/SECURITY.md`; `PhysicsGuard` untested)

## 4. Dupes + launch
- [ ] Save/load builds (`docs/DUPES.md`) (written, codec lune-tested, Studio untested)
- [ ] Feedback button (written, Studio untested)
- [ ] Anti-exploit pass (`docs/SECURITY.md` matrix)
- [ ] 3 friends, 30 min, no crash
- [ ] **Publish**

## 5. Chaos
- [x] Maps: Construct and Flatgrass inside the place, main menu with map picker (built 2026-10-26; Construct spawn and Flatgrass standing checked in Studio, Flatgrass fall-through fixed)
- [ ] Gun roster: Pistol, SMG, Pulse Rifle, RPG in the loadout, server hitscan/rockets, PvP toggle (written, Studio untested; meshes are Store models, not license-clean)
- [ ] Breakable props
- [ ] Emotes, posable ragdolls, silly weapon animations
- [ ] Original recreations of iconic props (`docs/ASSETS.md`)

## 6. NPC AI
- [ ] Voice lines recorded and exported (`docs/VOICE.md`, recorder in `audio/voice/`)
- [ ] Roster: Guest, Noob, John Doe (all friendly), with voices
- [ ] Ragdoll NPC base
- [ ] Behavior (friendly, hostile, follow) per `docs/NPC.md`
- [ ] NPC cap + perf budget
