# Dupes (step 4)

Save a group of props with their welds and ropes, spawn the whole thing again.

## Selecting
Toolgun "Dupe" mode: click a prop, server flood-fills through the player's welds, ropes, thrusters and Wheel-tool wheels, caps at 80 parts, and keeps the result as that player's clipboard (in memory, not saved). The panel shows the clipboard and slots 1-10 with Save (clipboard to slot), Load (slot at the crosshair) and Del. Premade cars copy as their chassis; their seat and wheels are rebuilt on load.

## Format (versioned table, JSON-safe)
```
{
  v = 1,
  name = "My car",
  parts = { { id = "plank", cf = {x,y,z, rx,ry,rz}, color = {r,g,b}, scale = 2?, anchored = true? }, ... },
  links = {
    { kind = "weld", a = 1, b = 2 },
    { kind = "rope", a = 1, b = 4, pa = {x,y,z}, pb = {x,y,z}, length = 5 },
    { kind = "thruster", a = 2, p = {x,y,z}, n = {x,y,z} },
    { kind = "wheel", a = 1, p = {x,y,z}, n = {x,y,z}, wheel = "wheel_small" },
  },
}
```
- `cf`: position relative to the first part, Euler XYZ radians (world rotation kept). Link points and normals are in the part's own frame.
- `Shared/DupeCodec.luau` is pure and lune-tested (`tests/dupes.spec.luau`): copies and DataStore reads both go through `sanitize`. Unknown id, NaN/inf, offsets over 1000 studs, bad link index, non-unit normal, rope over 100 studs: whole dupe dropped. Colour, scale and name are clamped.
- Only catalog ids; nothing client-supplied is trusted on load.
- Colors and sizes re-clamped on load.

## Storage
- `DataStore` "Dupes", key `u<UserId>`, value `{ v=1, slots = { ["1".."10"] = dupe } }` (string keys survive JSON).
- Slots live in memory for the session. A change schedules one write 15 s later (batches clicks), plus a flush on `PlayerRemoving` and `BindToClose`. `UpdateAsync`, `pcall`, 3 tries with backoff, one writer per player so writes stay in order.
- Size check < 3.5 MB per key (limit is 4 MB). Caps bound a dupe to roughly 50 KB anyway.
- Never overwrite on a failed load: until the join read succeeds nothing is written (slots still work for the session, a toast says they won't be saved). A value with an unknown `v` is left untouched.
- Studio needs API Services enabled.

## Load
`DupeLoad(slot, point)`: server rebuilds through `SpawnService.spawn` and the toolgun link builders, so ownership and every cap apply. Point must be within 150 studs and not within 6 studs of another player. Rejects the whole dupe if props, constraints or thrusters would pass their cap. The lowest part lands on the aim point.

## Open
- Sharing dupes between players (later).
- Migration path when `v` changes.
