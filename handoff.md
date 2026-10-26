# Handoff: waffles mod

Gmod-style freeroam sandbox on Roblox. File-based via Rojo; scripts in git, maps/meshes/gun models live in the place file only.

## Where things are

- Place: "waffles mod", placeId 86612994618738 (Studio universe 10773009648).
- Repo: `/home/rostislav/gmod-roblox`, branch `master`. Last commit `5c7bbc8`. **Working tree has uncommitted changes from this and the previous session.** Commit only when asked.
- Rojo: server started this session on `127.0.0.1:34872` (`rojo serve default.project.json --address 127.0.0.1 --port 34872`). Studio was closed before it reconnected; reopen the place and use Plugins > Rojo > Connect (or the server list) to sync.
- Studio MCP: the configured `roblox-studiomcp` proxy was reachable through a local bridge while Studio was open (port 13469 / bridge 13470). Studio closed during the session; `list_roblox_studios` is empty now. Do not restart Studio without the user.
- Gate: `scripts/check.sh` (stylua, selene, luau-lsp strict, lune specs). Was green at last run.
- Rules: `CLAUDE.md` (no Valve/Gmod assets, server decides, `--!strict`, `task.*` only, update the matching `docs/` file in the same change).
- Docs: `ROADMAP.md` (ticks), `TO-DO.md` (build order), `docs/TESTING.md` (manual checks), `docs/SECURITY.md` (remote matrix), `docs/ARCHITECTURE.md` (layout, remotes), `docs/TOOLS.md`, `docs/DUPES.md`, `docs/ASSETS.md` (license log).

## Built in the previous session (2026-10-26 morning)

- **Dupes**: copy/save/load/delete builds, DataStore `Dupes`, lune-tested codec.
- **Feedback button** (Q menu) → `Feedback` DataStore + server log.
- **Maps**: Construct (X +6000) and Flatgrass (X -10000) inside the place, next to the baseplate. Spawns and the Flatgrass collision floor are in `MapCatalog.luau`. `MapService` turns off collision on 207 converter box parts that buried Construct's play area.
- **Main menu** (`UI/MainMenu.luau`): Source/Gmod style, camera orbits the selected map, Start Game / Controls / Options dialogs, PvP toggle, M key.
- **Keyboard look** (arrow keys) and per-map lighting.
- **Guns**: Pistol (slot 2), SMG and Pulse Rifle (slot 3), Rocket Launcher (slot 5). Server owns fire rate, ammo, spread, hitscan, rockets, PvP damage (`WeaponService`). Client: tracers, flash, recoil, reload (`Tools/Gun.luau`). Holds per gun: `GunPose.luau` plus `GRIPS` in `ToolService`.
- **Shared UI skin** (`UI/Ui.luau`): every panel is gray and blue except the gun selector (`Ui.CLASSIC`).
- **Sounds**: gun sounds are free Creator Store uploads now (`Shared/Sounds.luau`). Synth fallbacks in `audio/sfx.py`.

## Session 2 changes (2026-10-26, unverified in Play)

- **Gun forward convention**: the right-hand grip puts the Tool's forward on **+Z**. `WeaponCatalog` now records each model's barrel axis (`muzzle`) and yaw: SMG flipped 0 -> 180, RPG 90 -> 270; AR2 stays 180, Pistol 0. `tests/weapons.spec.luau` checks every gun's yaw turns its muzzle to +Z. `ToolService` now places the model a third of its length **ahead** of the hand (was behind), puts `Muzzle` at the front and `LeftGrip` on the foregrip, and strips welded Store scripts.
- **RPG**: scaled to 0.45 (the Store model was 10.4 studs long); its grip translation is scaled with it. Rockets spawn from the barrel muzzle when the server can see it.
- **Gun server**: `WeaponFire` ignores the claimed origin and raycasts from the server's own head, so third-person and spoofed origins work/fail correctly. Rocket raycasts no longer pass `nil` for a respawning owner. No `FIRE_ORIGIN_DRIFT`.
- **Holds**: `GunPose` restores the original C0 when the gun is unequipped and skips work for characters with no gun.
- **Map**: `MapService` hides `solid_*` ForceField collision hulls (Transparency 1, CastShadow off, collision kept) instead of turning them into opaque gray slabs; other ForceField surfaces become SmoothPlastic. Server-side bad-asset strip for maps (GlitchEffect texture) plus the client sweep.
- **Mirror room**: `MapCatalog` point moved to the wall face (5395, 278, -548.6). `MapService` builds a 28x14 mirror panel (plus a back-to-back panel on the opposite face) with a black frame and tags it; no more SurfaceGui on the buried 155-stud collision box. `Mirror.luau` draws one face per panel at 16 px/stud, reflects the nearby room (140-part cap) and the local character, and stops updating when the camera is behind the glass. **The clone resets `LocalTransparencyModifier` to 0** - the first-person camera module hides the real body with it, which was likely why the old mirror looked empty. Local character only; other players/props are not reflected.
- **Textures/effects**: `BadAssets.luau` is shared by the server and client; `TextureFix` sweeps are shorter (8 s) and only texture classes get Changed connections, fixing the ~30k connection churn.
- **Sounds**: empty tool/UI slots now use built-in `rbxasset://sounds/` feedback (click/landing/whoosh); gun sounds unchanged.
- Docs: `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/TESTING.md` updated for the mirror, map hulls and server shot origin.

**Verified:** `scripts/check.sh` green (stylua, selene, luau-lsp strict, all lune specs including the new muzzle/yaw and mirror-point checks); `rojo build` succeeds; gun orientation was read from Studio screen captures and marker renders before Studio closed. **Not verified:** anything in Play. The mirror room clone, gun hold/grip feel, RPG scale, collision-hull hiding and the texture result need a Studio Play test. Studio was closed during the session, so no live MCP test or publish happened.

## Studio state (check first)

- Gun models (AR2, Pistol, SMG, RPG) are in `ServerStorage`. They were lost once in a crash. **Press Ctrl+S** before doing anything risky.
- Last test before this session (Play, Pulse Rifle equipped): backpack has all 7 tools, rifle in right hand, ammo HUD 30/30.
- This session's Studio inspection used `ServerStorage` model bounds and Construct part/raycast queries. A temporary `__KiloGunPreview` folder was created in Edit and removed; `Lighting.Ambient` was set and restored to black. No map or gun model was saved.
- Studio freeze recipe: after a freeze, Studio shows a hidden "recover file?" dialog that blocks all input. Fix: move `appdata/Roblox/RobloxStudio/AutoSaves/<placeId>_AutoRecovery_*.rbxl` aside, then relaunch. Keep Studio windowed (no F11). Restart: `flatpak kill org.vinegarhq.Vinegar; setsid flatpak run org.vinegarhq.Vinegar`.
- Studio blocks DataStore (`StudioAccessToApisNotAllowed`). Dupe loads and feedback will not work in Studio until **Game Settings > Security > Allow HTTP / API services** is on.

## Untested in Studio (do these next)

- Gun shooting, reload, auto fire, rocket explosion and prop pushes.
- Gun holds in first person (pose numbers are guesses, in `GunPose.luau`; yaw/muzzle now fixed and tested, but hand feel is not).
- Two-client checks: other players' tracers, PvP on/off, props owned by others.
- Dupes (save/load), feedback, Flatgrass after the floor change.
- Main menu: Options toggles, arrow look, map cards on a second client.

## Mirror hot spots to check

- Walk into the Construct room near `(5395, 278, -548)`. The mirror is 28x14, mounted 0.3 studs off the wall; if it is behind a brush, increase `MIRROR_OFFSET` in `Config`.
- If the reflection shows a black frame only, check `Mirror.luau` warnings (the panel tag and `MirrorFace` attribute) and whether the room clone cap missed the room.
- If the map now has invisible walls/gaps where `solid_*` parts were, change the `Transparency` branch in `MapService` back to `SmoothPlastic` for those names.

## Known issues

- **Gun meshes and some sounds may be ripped** from HL2 / MMOD / other games. The meshes were requested by the user; treat as a launch blocker. See `docs/ASSETS.md`.
- Gmod maps `gm_construct` and `gm_flatgrass` are Store uploads with unknown provenance. Same blocker.
- Construct is about 26k parts. Consider StreamingEnabled before launch.
- The toolgun, Q menu and other panels use the new skin. Toolgun panel and dupe panel not visually checked after the restyle.
- Gun sounds: `rbxassetid` ids are in `Shared/Sounds.luau`; the earlier synth `.ogg` files in `audio/exports/` are not uploaded.

## Next steps

1. Ctrl+S, then test guns (see "Untested" above). Fix hold numbers if a gun looks wrong.
2. Commit when the user asks (conventional message, Co-Authored-By line from the session rules).
3. Continue `TO-DO.md` from section 3 / 4 items still unticked: vehicles and ragdoll 2-client test, anti-exploit pass, launch checklist.
4. Replace ripped-looking assets before any public launch.
