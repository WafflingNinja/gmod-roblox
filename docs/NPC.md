# NPC AI (step 6)

## Goals
Spawnable ragdoll-capable NPCs that feel alive without hurting server performance.

## Types
| Type | Behavior |
|---|---|
| Friendly | Wanders, follows owner when told, flees danger |
| Hostile | Chases nearest player in range, melee/shoot, gives up on distance |
| Dummy | Stands, ragdolls on hit |

## Roster
| NPC | Type | Look |
|---|---|---|
| Guest | Friendly | Classic Guest: default body colors, black cap built from parts |
| Noob | Friendly | Yellow head and arms, blue torso, green legs (R6 body colors) |
| Citizen | Friendly | Original take on a city refugee: blue work shirt, dark pants, built from parts. HL2-inspired only, no Valve assets or lines |
| RostikPro12308 (secret) | Friendly | The developer's own avatar, loaded with `Players:GetHumanoidDescriptionFromUserId(Config.DEV_USER_ID)` |

Jane Doe and John Doe are cut. Looks are rebuilt in code; no Catalog or ripped assets.

## Built (v13, `Services/NpcService.luau`, `StarterPlayerScripts/NpcVoice.luau`)
- Spawn menu (Q) has an NPCs section. Each NPC is an R6 Model under `Workspace.Props`; its HumanoidRootPart is the part `Ownership` registers, so it takes 1 prop slot, X removes it, the physgun and gravity gun grab it (`Aim.prop` maps the Model to its root). Caps 10 per player, 40 per server.
- One Heartbeat loop thinks for all NPCs at 5 Hz: wander around home, follow / stay through an E prompt (owner only), greet a player who walks up (once per 30 s each), an idle line every 15-40 s, flee explosions within 40 studs and whoever is near after being hurt.
- Grabbed (held by `Hold`) = limp (PlatformStand) + `grabbed` line. Released or punted faster than 40 studs/s = `thrown` line, gets up after 2.5 s.
- Any gun hurts NPCs, PvP or not. Death line, body removed after 5 s.
- Heads turn to the nearest player within 20 studs; greeting stops, faces you, then talks. Wandering sometimes hops.
- Armed Citizen (`NpcCatalog` `gun = "Pistol"`, citizen voice): carries the pistol and, when hurt, shoots back for 8 s at the player who shot it (nearest player within 60 studs if it was something else) instead of running. That player takes the damage PvP or not; anyone else in the line of fire only with PvP on (`WeaponService.npcFire`).
- Walk/idle use Roblox's default R6 animations, played on the server.
- Subtitles are always on: every line shows at the bottom of the screen for players within 90 studs, even before the sprites are uploaded (`VoiceLines` id `""` = text only).
- `NpcCatalog.lineWeights`: `rostik_idle_2` (the LFS line) is picked 1.8x as often as his other idle lines.

## Voice
Lines are recorded first (`docs/VOICE.md`, `audio/voice/lines.json`). Each line has a category the NPC code triggers on: `spawn`, `idle`, `greet`, `follow`, `stay`, `grabbed`, `thrown`, `hurt`, `death`, `flee`, plus `unlock` for RostikPro12308. `Services/NpcVoice.luau` picks a random line from the category (never the same one twice in a row), at most one every 4 s per NPC plus a server-wide cap on voices at once, plays it from the head with `PlaybackRegion` on the NPC's sprite, and shows the text as a chat bubble.

## Secret unlock: Konami code
- `UI/MainMenu.luau` listens with `UserInputService.InputBegan` while the menu is open, for Up Up Down Down Left Right Left Right B A. A wrong key resets the sequence, and so do 2 s without input. Arrow keys still turn the menu camera, which is fine. Ignore input while a TextBox has focus.
- On a match the client fires `UnlockSecret` (no payload). The server rate-limits it (1 per 10 s), sets the player's `SecretUnlocked` attribute, saves it in the `Unlocks` DataStore (same `UpdateAsync`/retry pattern as dupes), and the client shows a toast ("You found RostikPro12308!") and plays an `unlock` line.
- The NPC tab shows RostikPro12308 only when `SecretUnlocked` is true. The server checks the attribute again on spawn.
- Security note: the server can't see keypresses, so an exploiter could fire `UnlockSecret` directly. That's accepted, because the unlock is cosmetic (one more friendly NPC) and the spawn still goes through the normal NPC caps and `Ownership.luau`. Add the remote row to `docs/SECURITY.md` when it's built.
- Not listed in the README controls. It's a secret.

## Architecture
- `Shared/BehaviorTree.luau`: Blackboard + sequence/selector/parallel + decorators. Pure logic, lune-tested.
- `Services/NpcService.luau`: spawn, tick, cleanup. One Heartbeat connection ticks all NPCs round-robin, not one loop per NPC.
- Pathfinding via `PathfindingService`, with path cache and re-path throttle.
- Ragdoll via Motor6D -> BallSocketConstraint swap.

## Budget
- Cap: 10 NPCs per player, 40 per server.
- Think rate: 4-10 Hz, distance-based, sleeping when no player is near.
- Server network-owns NPC physics.

## Validation
Spawn goes through the same range, rate, and ownership rules as props. An NPC counts as 1 prop slot.

## Open
- Weapon NPCs use the step 5 gun roster.
- Damage rules between NPCs and players on a freeroam server (opt-in PvP?).
