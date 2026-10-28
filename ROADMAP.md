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
- [ ] Ragdoll NPC base
- [ ] Behavior (friendly, hostile, follow) per `docs/NPC.md`
- [ ] NPC cap + perf budget

## 7. Looks, multi-place, map pipeline (planned 2026-10-27, in this order)
Status 2026-10-28: items 1, 2, 3, 5, 7 are code-complete and gate-clean; item 4 (Branding) was skipped and item 6 (Server Browser) is deferred by the user. None of the boxes are ticked until the Studio/two-client checks in `docs/TESTING.md` pass. See `handoff.md` and `docs/WORLDS.md`.
1. - [ ] **Glow-up:** Per-map lighting moods (Bigcity sunny, Bangclaw bright, Mallparking overcast, Backrooms yellow haze, Brmovie evening) + tween on map change; Atmosphere, Bloom, ColorCorrection, SunRays, reflections, glass water, shadows on ~20 strongest lights per map
2. - [ ] **Gmod Skin:** GUI restyle in Gmod's theme (Arimo, accent #2387ed / hover #4f9ded, Derma greys 101,100,105 / 55,57,61 / 220,220,220, selection 100,170,220, tooltip 255,245,175, 2-6 px radius; main menu = white text list over the live map)
3. - [ ] **Menu Music:** Main menu music: looped calm track (user supplies Roblox audio id), fades out on play, back in on menu
4. - [ ] **Branding:** Icon 512x512: black bg, white W (3 variants, user picks; own glyph, no Gmod/Valve marks). Thumbnails 1920x1080: camera-placement command per shot, user snaps, crop + grade + title
5. - [ ] **Split Worlds:** One place per map in the same universe. Start place = Flatgrass + main menu. 24 players per server, server-wide prop cap 1,500 (per-player 150 / VIP 250 stay). Map change = teleport (props don't follow)
6. - [ ] **Server Browser:** Server browser: MemoryStore heartbeat per server (place, jobId, players + names, server region, avg ping); list shows map, players x/24, names, region flag, ping estimated from player vs server region (shown as "~40 ms"); click = TeleportAsync into that jobId
7. - [ ] **Map Factory:** `tools/add_map.py <workshop link>`: user subscribes in Steam first -> find .gma -> gmad extract -> bsp_to_json -> alpha audit -> texture review page in browser (>=50 per page, click to reject, rejected stay flat colour) -> upload approved -> MapCatalog + MapLighting + docs/ASSETS.md row -> asks user to "Add Place" in Creator Dashboard and paste the place id -> copies the Studio import command to the clipboard
