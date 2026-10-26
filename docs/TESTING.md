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
