# NPC AI (step 6)

## Goals
Spawnable ragdoll-capable NPCs that feel alive without hurting server performance.

## Types
| Type | Behavior |
|---|---|
| Friendly | Wanders, follows owner when told, flees danger |
| Hostile | Chases nearest player in range, melee/shoot, gives up on distance |
| Dummy | Stands, ragdolls on hit |

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
