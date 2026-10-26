# Sandbox (working title)

Gmod-style freeroam sandbox for Roblox. Spawn props, weld contraptions, drive cars, wreck things with friends. Public, PC only.

**Status:** Step 2 of 6 (see [ROADMAP](ROADMAP.md)): spawn menu, ownership, prop cap, physgun, toolgun.

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
| Q | Toggle spawn menu |
| Click prop in menu | Spawn at crosshair |
| X | Remove the prop you aim at (yours only) |
| 1-6, again to cycle, wheel while open, LMB / RMB | weapon selector: open slot, pick, confirm / cancel (1 = Physgun, Gravity Gun; 6 = Toolgun) |
| Physgun: LMB hold, wheel, R+mouse, RMB | grab, push/pull, rotate, freeze |
| Gravity Gun: RMB, LMB | pull or hold (again drops), punt or throw |
| Toolgun: wheel, LMB, RMB | pick mode, use, shrink (Scale) / big wheel (Wheel) |
| F | Fire your thrusters |
| G | Ragdoll / stand up |
| WASD in a Driver Seat | drive (cars from the Cars tab, or seat + Wheel tool builds) |

## Docs

| File | What |
|---|---|
| [ROADMAP](ROADMAP.md) | 6 build steps, done criteria |
| [TO-DO](TO-DO.md) | Everything left, in build order, one-take plan |
| [CLAUDE.md](CLAUDE.md) | Rules for working in this repo |
| [docs/GDD.md](docs/GDD.md) | Game design: pillars, features, non-goals |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Folders, services, remotes, data flow |
| [docs/SECURITY.md](docs/SECURITY.md) | Remote validation, limits, abuse tests |
| [docs/ASSETS.md](docs/ASSETS.md) | Asset rules (no Valve/Gmod assets), license log |
| [docs/TOOLS.md](docs/TOOLS.md) | Physgun, gravity gun, toolgun specs |
| [docs/DUPES.md](docs/DUPES.md) | Save/load builds |
| [docs/NPC.md](docs/NPC.md) | NPC AI design |
| [docs/TESTING.md](docs/TESTING.md) | Automated + manual test matrix |
| [docs/LAUNCH.md](docs/LAUNCH.md) | Publish checklist, feedback button |
