# waffles mod

Gmod-style freeroam sandbox for Roblox. Spawn props, weld contraptions, drive cars, wreck things with friends. Public, PC only.

**Status:** Steps 1-4 built, step 5 partly built (maps, main menu, guns). Most of it is written but not yet play-tested. See [handoff.md](handoff.md) for the current state.

## Run it

```
rokit install            # rojo, stylua, selene, luau-lsp, lune
rojo serve               # Studio -> Plugins -> Rojo -> Connect
scripts/check.sh         # format + lint + strict types + lune tests
```

Open a new baseplate place in Studio, connect Rojo, press Play. Test with Server & Clients (2 players) for anything networked.

## Controls (v1)

| Key | Action |
|---|---|
| M | Main menu: pick a map, controls, settings (opens on join) |
| Arrow keys | Look around (for trackpads; Settings to turn off) |
| Q | Toggle spawn menu (frees the mouse; Feedback button at the bottom) |
| Click prop in menu | Spawn at crosshair |
| X | Remove the prop you aim at (yours only) |
| 1-6, again to cycle, wheel while open, LMB / RMB | weapon selector: open slot, pick, confirm / cancel (1 = Physgun, Gravity Gun; 6 = Toolgun) |
| Physgun: LMB hold, wheel, R+mouse, RMB | grab, push/pull, rotate, freeze |
| Gravity Gun: RMB, LMB | pull or hold (again drops), punt or throw |
| Toolgun: wheel, LMB, RMB | pick mode, use, shrink (Scale) / big wheel (Wheel) |
| Toolgun Dupe mode | LMB copies a build; panel Save / Load / Del per slot |
| Guns: LMB, R | fire (hold for SMG / Pulse Rifle), reload. PvP is off until you turn it on in M > Options |
| V | Fire your thrusters (hold) |
| F | Flashlight on / off |
| G | Ragdoll / stand up |
| WASD in a Driver Seat | drive (cars from the Cars tab, or seat + Wheel tool builds) |

## Docs

| File | What |
|---|---|
| [ROADMAP](ROADMAP.md) | 6 build steps, done criteria |
| [handoff](handoff.md) | Where things stand, what to test next |
| [TO-DO](TO-DO.md) | Everything left, in build order, one-take plan |
| [CLAUDE.md](CLAUDE.md) | Rules for working in this repo |
| [docs/GDD.md](docs/GDD.md) | Game design: pillars, features, non-goals |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Folders, services, remotes, data flow |
| [docs/SECURITY.md](docs/SECURITY.md) | Remote validation, limits, abuse tests |
| [docs/ASSETS.md](docs/ASSETS.md) | Asset rules (no Valve/Gmod assets), license log |
| [docs/TOOLS.md](docs/TOOLS.md) | Physgun, gravity gun, toolgun specs |
| [docs/DUPES.md](docs/DUPES.md) | Save/load builds |
| [docs/NPC.md](docs/NPC.md) | NPC AI design |
| [docs/VOICE.md](docs/VOICE.md) | NPC voice acting: lines, recorder, upload |
| [docs/TESTING.md](docs/TESTING.md) | Automated + manual test matrix |
| [docs/LAUNCH.md](docs/LAUNCH.md) | Publish checklist, feedback button |
