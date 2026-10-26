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
| John Doe | Hostile | Classic test-account look, from a reference screenshot |

Jane Doe is cut (no voice for her). Looks are rebuilt in code; no Catalog or ripped assets.

## Voice
Lines are recorded first (`docs/VOICE.md`, `audio/voice/lines.json`). Each line has a category the NPC code triggers on: `spawn`, `idle`, `greet`, `follow`, `stay`, `grabbed`, `thrown`, `hurt`, `death`, `flee`, and for John Doe `spot`, `chase`, `lost`, `kill`. `Services/NpcVoice.luau` picks a random line from the category (never the same one twice in a row), at most one every 4 s per NPC plus a server-wide cap on voices at once, plays it from the head with `PlaybackRegion` on the NPC's sprite, and shows the text as a chat bubble.

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
Spawn goes through the same range, rate, and ownership rules as props. NPC counts as prop-cap slots (proposed: 5 each).

## Open
- Weapon NPCs use the step 5 gun roster.
- Damage rules between NPCs and players on a freeroam server (opt-in PvP?).
