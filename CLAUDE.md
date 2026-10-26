# waffles mod: repo rules

Gmod-style freeroam sandbox on Roblox. File-based via Rojo. Scripts are in git; maps/meshes live in the place file.

## Commands

- `scripts/check.sh`: stylua --check, selene, luau-lsp strict analyze, lune tests. Must pass before saying "done".
- `rojo serve`: live sync to Studio.
- `rojo build -o <path>.rbxl`: proves the project file is valid.
- Pure-logic tests live in `tests/*.spec.luau` (lune, plain `assert`). Shared data modules must stay free of Roblox datatypes so lune can load them.

## Hard rules

1. **No Valve / Facepunch / HL2 / Gmod assets.** No models, textures, sounds, or extracted files from Gmod or Half-Life, not even "a few". Roblox takes the game down. Recreate the iconic look with original meshes or CC0 packs. See `docs/ASSETS.md`.
2. **Server decides.** Remotes carry intent (ids, aim points). Never accept damage, price, ownership, or computed results from a client.
3. Every remote handler: rate limit first, then `typeof` checks, then allowlist, then ownership/state, then act. Fail silently. See `docs/SECURITY.md`.
4. Never `RemoteFunction` server to client. One remote per concern.
5. `--!strict` on every file. `task.*` only (no `wait`/`spawn`/`delay`). `workspace:Raycast` only.
6. Per-player state must be cleaned on `PlayerRemoving`. Every `:Connect` that can outlive its owner gets disconnected.
7. Prop cap and ownership go through `Ownership.luau`. Do not spawn props any other way.
8. Don't touch other projects (FFA Firestorm, Trench Wars, etc.).

## Layout

See `docs/ARCHITECTURE.md`. New server logic goes in `src/ServerScriptService/Services/` as a module with `init()`, started from `Main.server.luau`. Shared data in `src/ReplicatedStorage/Shared/`. Client UI in `src/StarterPlayerScripts/UI/`.

## Workflow

Follow `ROADMAP.md` in order. When a step's done-criteria pass, tick it there. Update the matching `docs/` file in the same change as the code. Test networked changes with 2 clients, not Play Solo.
