# Testing

## Automated
`scripts/check.sh` runs:
1. `stylua --check`
2. `selene`
3. `luau-lsp analyze` with `--!strict` and Roblox global types
4. `lune run tests/*.spec.luau` (pure logic)

Pure logic = anything that does not need the Roblox engine. Keep data modules free of Roblox datatypes.

## Manual (Studio, Server & Clients, 2 players)

### Step 1
- [ ] Press Q: menu toggles. HUD shows `Props 0/150`.
- [ ] Click each of the 13 props: spawns at crosshair, sits on the ground, not buried or floating.
- [ ] Barrel stands upright, wheels have the axle sideways, balls bounce.
- [ ] Spawn up to 150: counter reaches 150, next click shows the limit toast.
- [ ] X on own prop removes it and count drops. X on other player's prop: toast "not yours".
- [ ] "Remove all mine" clears only your props.
- [ ] Player B leaves: B's props vanish on A's screen.
- [ ] Prop knocked into the void is destroyed and count drops.
- [ ] Die and respawn: spawn works again, props remain.
- [ ] Spam click: no output errors, server stays responsive.

### Step 2 (tools)
- [ ] Press 1: Physgun in hand, pointing forward, crosshair dot shows. Press 2: Toolgun, mode panel on the right.
- [ ] Physgun: hold LMB on a prop, it follows the crosshair with a cyan beam; wheel pushes/pulls; R + mouse rotates; RMB freezes it in place; grabbing a frozen prop unfreezes it.
- [ ] Physgun on another player's prop does nothing. Dying or unequipping while holding drops the prop.
- [ ] Toolgun Weld/Rope: first click outlines the prop, second click on another prop links them; dragging one with the physgun drags both.
- [ ] Thruster on a bottom face, hold F: prop flies up. Other player sees it fly.
- [ ] Scale: LMB grows, RMB shrinks, details (crate frame, barrel rings) scale with it.
- [ ] Paint: pick a colour in the panel, click a prop. Unweld removes welds/ropes/thrusters. Remove deletes.
- [ ] Constraint cap: 300 welds/ropes/thrusters shows the limit toast.

### Maps and menu
- [ ] Join: main menu shows, mouse is free. Cards: Baseplate, Construct, Flatgrass. Click Construct: you land on its spawn, sky changes. M reopens.
- [ ] Die on Construct: respawn on Construct. Second player on Flatgrass sees Flatgrass sky, first still sees Construct's.
- [ ] Settings: sensitivity, FOV, arrow-key look on/off and speed all take effect. Arrow keys turn and pitch the view; with look off they walk again.
- [ ] Props spawn, tools and dupes work on both maps.
- [ ] Construct: no gray `solid_*` slabs covering rooms; the `GlitchEffect` near the servers is gone (no white particle squares).
- [ ] Mirror room: walk into it and look at the wall. A framed mirror shows your character and the room, not a black rectangle. Walk to the other side of that wall: the back panel (if present) shows its own side.

### Guns
- [ ] Each gun: points forward in first person (barrel away from you), both hands on it (launcher on the shoulder); another player sees the same hold. Especially check the SMG and RPG after the `+Z` forward fix.
- [ ] Muzzle flash, tracer start and rocket smoke appear at the front of the barrel, not behind the hand.
- [ ] Fire rate, magazine count, R reload, auto-reload on empty; RPG explodes and pushes own props.
- [ ] Shooting another player does nothing until both turn PvP on (M > Options).
- [ ] `WeaponFire:FireServer("AR2", Vector3.new(0,1e6,0), Vector3.yAxis)`: nothing. Spam faster than rpm: extra shots ignored.

### Step 4 dupes (needs API Services on to test saving)
- [ ] Weld 3 planks, rope a crate, add a thruster and 2 Wheel-tool wheels. Dupe mode, click one: clipboard shows `Plank +3 (4)`.
- [ ] Save to slot 1, Load slot 1: same build appears at the crosshair, welds hold, rope, thruster (F) and wheels work. Scale, paint and frozen state kept.
- [ ] Premade car in a dupe: loads with seat and wheels, drives.
- [ ] Load with 140 props out: refused with a toast, nothing spawned.
- [ ] Rejoin: slot 1 still there. API Services off: toast says dupes won't be saved, slots still work this session.
- [ ] `DupeLoad:FireServer(1, Vector3.new(0/0, 0, 0))`, `DupeSave:FireServer(11)`, `DupeLoad:FireServer("1", Vector3.zero)`: nothing.

### Step 2 abuse (Command bar on a client)
- [ ] `ToolgunUse:FireServer("Remove", workspace.Baseplate, Vector3.zero, Vector3.yAxis)`: nothing.
- [ ] `ToolgunUse:FireServer("Scale", prop, prop.Position, Vector3.yAxis, 99)`: nothing.
- [ ] `PhysgunAim:FireServer(CFrame.new(1e9, 0, 0))` while holding: prop stays within 60 studs.

### Abuse (execute from Command bar on a client)
- [ ] `SpawnProp:FireServer("nope", Vector3.new())`: nothing.
- [ ] `SpawnProp:FireServer("crate_small", Vector3.new(1e9, 0, 0))`: nothing.
- [ ] `SpawnProp:FireServer("crate_small", Vector3.new(0/0, 0, 0))`: nothing.
- [ ] `RemoveProp:FireServer(workspace.Baseplate)`: nothing.
- [ ] `RemoveProp:FireServer(otherPlayersProp)`: only a toast.
- [ ] 500 `SpawnProp` calls in a loop: server ok, count never above cap.

### Multi-client rules
Play Solo hides replication bugs. Always run Server & Clients with at least 2 clients before ticking a networked box in ROADMAP.
