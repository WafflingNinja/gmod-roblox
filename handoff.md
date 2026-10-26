# Handoff: waffles mod

Gmod-style freeroam sandbox on Roblox. File-based via Rojo; scripts in git, maps/meshes/gun models live in the place file only.

## Where things are

- Place: "waffles mod", placeId 86612994618738 (Studio universe 10773009648).
- Repo: `/home/rostislav/gmod-roblox`, branch `master`. Last commit `5c7bbc8`. **About 48 files changed and not committed.** Commit only when asked.
- Rojo: `rojo serve` on `localhost:34872`. Studio: Plugins > Rojo > Connect.
- Gate: `scripts/check.sh` (stylua, selene, luau-lsp strict, lune specs). Was green at last run.
- Rules: `CLAUDE.md` (no Valve/Gmod assets, server decides, `--!strict`, `task.*` only, update the matching `docs/` file in the same change).
- Docs: `ROADMAP.md` (ticks), `TO-DO.md` (build order), `docs/TESTING.md` (manual checks), `docs/SECURITY.md` (remote matrix), `docs/ARCHITECTURE.md` (layout, remotes), `docs/TOOLS.md`, `docs/DUPES.md`, `docs/ASSETS.md` (license log).

## Built this session (2026-10-26)

- **Dupes**: copy/save/load/delete builds, DataStore `Dupes`, lune-tested codec.
- **Feedback button** (Q menu) → `Feedback` DataStore + server log.
- **Maps**: Construct (X +6000) and Flatgrass (X -10000) inside the place, next to the baseplate. Spawns and the Flatgrass collision floor are in `MapCatalog.luau`. `MapService` turns off collision on 207 converter box parts that buried Construct's play area.
- **Main menu** (`UI/MainMenu.luau`): Source/Gmod style, camera orbits the selected map, Start Game / Controls / Options dialogs, PvP toggle, M key.
- **Keyboard look** (arrow keys) and per-map lighting.
- **Guns**: Pistol (slot 2), SMG and Pulse Rifle (slot 3), Rocket Launcher (slot 5). Server owns fire rate, ammo, spread, hitscan, rockets, PvP damage (`WeaponService`). Client: tracers, flash, recoil, reload (`Tools/Gun.luau`). Holds per gun: `GunPose.luau` plus `GRIPS` in `ToolService`.
- **Shared UI skin** (`UI/Ui.luau`): every panel is gray and blue except the gun selector (`Ui.CLASSIC`).
- **Sounds**: gun sounds are free Creator Store uploads now (`Shared/Sounds.luau`). Synth fallbacks in `audio/sfx.py`.

## Studio state (check first)

- Gun models (AR2, Pistol, SMG, RPG) are in `ServerStorage`. They were lost once in a crash. **Press Ctrl+S** before doing anything risky.
- Last test (Play, Pulse Rifle equipped): backpack has all 7 tools, rifle in right hand, ammo HUD 30/30.
- Studio freeze recipe: after a freeze, Studio shows a hidden "recover file?" dialog that blocks all input. Fix: move `appdata/Roblox/RobloxStudio/AutoSaves/<placeId>_AutoRecovery_*.rbxl` aside, then relaunch. Keep Studio windowed (no F11). Restart: `flatpak kill org.vinegarhq.Vinegar; setsid flatpak run org.vinegarhq.Vinegar`.
- Studio blocks DataStore (`StudioAccessToApisNotAllowed`). Dupe loads and feedback will not work in Studio until **Game Settings > Security > Allow HTTP / API services** is on.

## Untested in Studio (do these next)

- Gun shooting, reload, auto fire, rocket explosion and prop pushes.
- Gun holds in first person (pose numbers are guesses, in `GunPose.luau`; `yaw` in `WeaponCatalog`).
- Two-client checks: other players' tracers, PvP on/off, props owned by others.
- Dupes (save/load), feedback, Flatgrass after the floor change.
- Main menu: Options toggles, arrow look, map cards on a second client.

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
