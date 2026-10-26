# Dupes (step 4)

Save a group of props with their welds and ropes, spawn the whole thing again.

## Selecting
Toolgun "Dupe" mode: click a prop, server flood-fills through constraints owned by the player, caps at 80 parts.

## Format (versioned table, JSON-safe)
```
{
  v = 1,
  name = "My car",
  parts = { { id = "wheel_small", cf = {x,y,z, r00..r22}, color = {r,g,b}?, size = {x,y,z}? }, ... },
  links = { { kind = "weld"|"rope"|"hinge"|"thruster", a = 3, b = 7, props... }, ... },
}
```
- CFrames stored relative to the first part.
- Only catalog ids; nothing client-supplied is trusted on load.
- Colors and sizes re-clamped on load.

## Storage
- `DataStore` "Dupes", key `u<UserId>`, value `{ v=1, slots = { [1..10] = dupe } }`.
- `UpdateAsync` for writes, `pcall` + retry with backoff, flush on `PlayerRemoving` and `BindToClose`.
- Size check < 3.5 MB per key (limit is 4 MB); each dupe < 100 KB.
- Never overwrite on a failed load. See `roblox-datastores` rules.
- Studio needs API Services enabled.

## Load
Server rebuilds through `SpawnService` internals so the 150 cap and ownership apply. Spawns at aim point with range check. Rejects the whole dupe if it would exceed the cap.

## Open
- Sharing dupes between players (later).
- Migration path when `v` changes.
