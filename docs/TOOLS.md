# Tools (step 2)

All tools are Roblox `Tool`s built from parts in `ToolService.luau` (original designs, no imported assets). They are placed in `StarterGear` so they survive respawn.

The game is locked first person (`StarterPlayer.CameraMode = LockFirstPerson` in `default.project.json`), so the mouse wheel never zooms and stays free for the tools. While the physgun rotates (hold R) the camera is set to Scriptable so the view doesn't turn with the mouse.

`FirstPerson.luau` (client only): with a tool out your own arms and the tool stay visible and pitch with the view, the tool lags behind fast mouse moves (sway, max 6 degrees), the view bobs while walking, FOV 80. Off while ragdolled or rotating with the physgun.

Sounds (`Services/Sfx.luau`, played on the server so everyone hears): physgun grab/hum/release/freeze, gravity gun pull/hum/punt, toolgun fire on every use plus a weld click for Weld/Rope/Thruster/Wheel/Unweld, spawn pop, remove poof, ragdoll get-up. Client-only (`Sfx.luau`): selector tick, deny buzz with toasts. See `docs/ASSETS.md` for where the audio comes from.

Panels need the mouse: opening the Q menu frees it (a `Modal` button), so the toolgun panel (modes, colours, dupe slots) is clickable while Q is open. The Feedback box frees it the same way.

The Roblox hotbar is off; `UI/WeaponSelect.luau` is an HL2-style selector across the top of the screen. Keys 1-6 open a slot and pressing again cycles inside it, the wheel moves through every weapon while it is open, LMB (on release) confirms, RMB cancels, and it hides after 2.5 s without switching. Tools ignore their own input while it is open. Each Tool carries `Slot`, `SlotOrder` and `Label` attributes (set from `LOADOUT` in `ToolService`): slot 1 Physics Gun, Gravity Gun; slot 6 Tool Gun; 2-5 are free for weapons. The client starts a tool's logic when the Tool enters the character and stops it when it leaves.

All tools are server-authoritative: the client sends a tool id and an aim target, the server resolves and validates. Players can only use tools on props they own.

## Physgun (`PhysgunService.luau`, `Tools/Physgun.luau`)
| Input | Behavior |
|---|---|
| Hold LMB on own prop | Grab. A server-side anchored target part is created; `AlignPosition` + `AlignOrientation` pull the prop to it. |
| Mouse wheel | Push or pull the held prop (4 to 60 studs). |
| Hold R + move mouse | Rotate the held prop (cursor locks while rotating). |
| RMB while holding | Freeze: release and anchor in place. Grabbing a frozen prop unanchors it. |
| Release LMB | Drop or throw (velocity kept). |

Server rules: tool equipped, alive, prop owned, within 80 studs to grab, one hold per player. While held the prop is server-owned (`SetNetworkOwner(nil)`); ownership goes back to auto on release. Hold target is clamped to 60 studs from the character, speed capped at 150 studs/s, aim updates rate limited (client sends 20 per second over an `UnreliableRemoteEvent`). A cyan `Beam` links the gun's muzzle to the held prop. Release happens on tool unequip, death, prop destroyed, or leaving.

## Toolgun (`ToolgunService.luau`, `Tools/Toolgun.luau`)
Mouse wheel or the right-hand panel picks a mode. LMB uses it. One remote, `ToolgunUse(mode, prop, hitPoint, normal, extra)`.

| Mode | Behavior |
|---|---|
| Weld | Click prop A, then prop B: `WeldConstraint`. |
| Rope | Click A, then B: `RopeConstraint` between the clicked points, up to 100 studs. |
| Thruster | Click a face: a `VectorForce` pushes the prop opposite that face (click the bottom to go up). Hold V to fire all your thrusters. Force scales with assembly mass (350 studs/s squared). Max 20. |
| Wheel | Click a face: LMB small wheel, RMB big wheel, on a `HingeConstraint` motor with the axle along the face normal. The wheel is a child of the prop (dies with it, Unweld removes it) and counts as a constraint. Weld a Driver Seat to the build to drive: no steer wheels, so it turns tank-style. |
| Scale | LMB grows 1.25x, RMB shrinks, clamped to 0.25x to 4x of the original size. |
| Paint | 12 palette colours, picked in the panel. |
| Unweld | Removes every weld, rope and thruster on the prop. |
| Remove | Deletes the prop. |
| Dupe | Click a prop: copies it and everything linked to it (up to 80 parts) to your clipboard. The panel saves the clipboard to slot 1-10, loads a slot at the crosshair, deletes a slot. See `docs/DUPES.md`. |

Two-click modes keep their first selection on the server. The server tells the client which prop is selected (`ToolSelect`) and the client shows an outline. The selection clears when the tool is unequipped.

## Gravity gun (`GravityGunService.luau`, `Tools/GravityGun.luau`)
| Input | Behavior |
|---|---|
| RMB on own prop, over 12 studs away | Pull: velocity set to 60 studs/s toward the player (range 60). |
| RMB on own prop, within 12 studs | Hold about 8 studs in front, turning with the camera. RMB again drops. |
| LMB on own prop | Punt: adds 120 studs/s along the aim (range 30). |
| LMB while holding | Throw: release and punt. |

Remotes `GravityPull(prop)` and `GravityPunt(prop, direction)`; the hold reuses `PhysgunAim`. The server picks pull vs hold from distance and computes every impulse. Rules: Gravity gun equipped, alive, own prop, unanchored (frozen props ignore it), in range, direction finite and unit-length, 5 burst, 3 per second. The server takes network ownership for an impulse (it only applies on the simulating machine) and gives it back after 2 s. The hold code is shared with the physgun in `Hold.luau` (orange beam), so one hold per player across both tools.

## Guns (`WeaponService.luau`, `Tools/Gun.luau`, `Shared/WeaponCatalog.luau`)
Every player carries 9mm Pistol (slot 2), SMG and Pulse Rifle (slot 3), Rocket Launcher (slot 5). LMB fires (hold for SMG/AR2), R reloads, ammo panel bottom right. The client sends gun id, camera position and aim; the server checks the gun is equipped, rpm, magazine (Tool `Ammo` attribute) and that the origin is at the head, adds spread and raycasts. Hits push the shooter's own props; players only take damage when both have PvP on (Options in the M menu). Rockets fly server-side (120 studs/s, 3 in flight per player) and explode with an 18-stud radius, same push/damage rules. Gun meshes are Creator Store models in ServerStorage (`AR2`, `Pistol`, `SMG`, `RPG`); `yaw` in the catalog turns a model whose barrel faces the wrong way. Holds: `GunPose.luau` (arm joint rotations per pistol/rifle/launcher) and `GRIPS` in `ToolService` (where the gun sits in the hand).

## Vehicles (`VehicleService.luau`)
Spawn menu "Cars" tab: Sedan, Pickup Truck, Buggy. The chassis is the one registered prop; the VehicleSeat, body details and wheels are its children. Front wheels steer on an invisible knuckle turned by a Servo hinge (30 degrees); all wheels are Motor hinges. One Heartbeat drives every occupied seat: wheel speed = throttle * 90 studs/s at the rim, torque = chassis mass * 40 * radius, soft brake (20 %) with no input. A seat drives every wheel whose chassis is in the seat's rigid assembly, so seat + welded props + Wheel-tool wheels make a car.

## Ragdoll (`RagdollService.luau`, `Ragdoll.luau`)
G toggles (3 burst, 1 per s); stands up after 3 s or on G again. Death always ragdolls (`BreakJointsOnDeath = false`). Motor6Ds (except the root joint) are disabled and replaced with limited `BallSocketConstraint`s; limbs collide while floppy. The client puts its Humanoid in `Physics` / `GettingUp` when the server fires `RagdollState`.

## Limits
- 300 constraints per player (welds, ropes, thrusters), tracked in `Constraints.luau`. A constraint is destroyed with any prop it touches.
- Toolgun: 8 burst, 6 per second. Physgun grab: 5 burst, 3 per second.
- Toolgun click range: 120 studs. Click point must be on the prop.

## Not done yet
- Sounds and impact effects (need original audio).
- Open question: let others punt your props? Default is no, own props only.

## Gun hold poses (Animation Editor, no numbers)
Each hold (`pistol`, `rifle`, `launcher`) can use a pose you make with the mouse. `GunPose.luau` plays it looped while that gun is out; holds without one keep the code pose.
1. Avatar tab > Rig Builder > R15 > Block Rig. A dummy appears.
2. Put the gun on it so you can see the hands against it: drag the gun model (ServerStorage, e.g. `Pistol`) next to the dummy's right hand.
3. Avatar tab > Animation Editor, click the dummy, name it (e.g. `RifleHold`).
4. Click an arm part and drag the rotate rings, or switch on IK (top of the editor) and drag the hand: the arm follows. Only pose the arms.
5. One keyframe is enough. Turn on Looping (the loop icon).
6. `...` menu > Publish to Roblox. Copy the id.
7. Put it in `HOLD_ANIMATIONS` in `src/StarterPlayerScripts/GunPose.luau` as `"rbxassetid://<id>"` (or give it to Claude).
In first person the shoulders still follow the camera on top of the pose.
