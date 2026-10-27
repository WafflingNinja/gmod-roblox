# DO-MIRROR: make the Construct mirror work

**Symptom (2026-10-26, build v12):** the mirror in the Construct room is still pitch black.

**Done when:** you stand in front of the mirror in Play and see your own character and the room, reversed left to right. Moving sideways shifts the picture like a real mirror (parallax), and nothing is black.

## What exists

| Piece | Where | Does |
|---|---|---|
| Mirror point | `src/ReplicatedStorage/Shared/MapCatalog.luau:35` | `mirrors = { { 5395, 278, -548.6 } }` on Construct |
| Panel builder (server) | `src/ServerScriptService/Services/MapService.luau:81` `nearestFace`, `:157` `buildMirror`, `:214` `makeMirrors` | Finds the nearest wall face, builds a 28x14 `Mirror` part (Front face toward the room, dark SmoothPlastic) plus a black `MirrorFrame` behind it, and tags it `Mirror` with attribute `MirrorFace = "Front"`. Also builds a back-to-back panel on the opposite face. Folder: `Workspace.Maps.Construct.MirrorPanels`. |
| Reflection (client) | `src/StarterPlayerScripts/Mirror.luau` `:220` `attach`, `:67` `buildRoom`, `:176` `update` | For each tagged panel: a SurfaceGui, a ViewportFrame, a reflected copy of up to 140 nearby map parts, and a reflected copy of the local character, all updated each frame. |
| Config | `src/ReplicatedStorage/Shared/Config.luau` `MIRROR_*` | Size, offset, pixels per stud, range, part cap |

## Already tried (all still black)

1. v3: un-reflected the camera (camera and room were both reflected, which cancelled out). Clone the character with `Archivable = true` (a player character clones to nil otherwise). Pick room parts by distance to their box, not their centre (the wall brushes are big). Wedge-safe reflected CFrame (flip X).
2. v4: moved `MirrorFrame` behind the glass. It had been in front, covering the panel.
3. v5: EgoMoose portal method. The viewport camera sits at the eye and looks straight into the glass (`CFrame.fromMatrix(eye, right, up, normal)`), FOV comes from the extent, and the ViewportFrame is stretched and shifted on the surface. The viewport background became gray-blue `(70, 78, 88)` and `attach` prints `Mirror: <path> reflects N room parts`.

4. v13 (build "v13 (NPCs, subtitles, mirror)"): SurfaceGui moved to `PlayerGui` with `Adornee = part`, parented before the room copy (which is now pcall'd and rebuilt after 5 s). `MIRROR_OFFSET` 0.3 -> 1 with the frame filling the gap to the wall. Glass is now light reflective Glass, so a failed gui shows shiny glass, not black. If it's STILL black after this, the panel itself is not what you're looking at: do Step 1.

**Key clue:** after v5 the user still sees black, not gray-blue, so the SurfaceGui is probably not drawing at all. Fix that before tuning the reflection maths.

## Step 1: diagnose in ONE Play test (do not guess again)

Play, walk to the mirror, press F9, Client tab. Collect:
- Is the `Mirror: ... reflects N room parts` line there, and what is N? No line means `attach` never ran.
- Run in the console command line (client):
  ```lua
  local cs=game:GetService("CollectionService") for _,p in cs:GetTagged("Mirror") do local g=p:FindFirstChild("MirrorGui") print(p:GetFullName(), p.Size, p.Transparency, g and g.Face, g and g.Enabled) end
  ```
- A screenshot from straight in front of the mirror.

## Step 2: likely causes, in this order

1. **SurfaceGui placement.** `Mirror.luau:282` does `gui.Parent = part`. Roblox's recommended setup is the SurfaceGui in `PlayerGui` with `gui.Adornee = part` and `gui.ResetOnSpawn = false`. A DevForum post reports ViewportFrame SurfaceGuis outside PlayerGui not rendering. This edit was prepared once but got interrupted. Apply it first.
2. **No tagged panel / attach never ran.** If there's no `Mirror:` line: check that `MapService.init` ran (any `MapService:` warnings in the Server tab, e.g. "no wall face near mirror point"), that `Workspace.Maps.Construct.MirrorPanels` exists, and that the client sees the tag.
3. **Wrong face.** If the GUI is on the wall side, the room sees bare dark plastic. Quick test: set `gui.Face` to each of the 6 faces in the console. Real fix: choose the face whose normal points at the room (dot product with `room point - panel`).
4. **Panel buried.** The panel may sit inside a visible mesh brush, so the brush is what you see. Raise `MIRROR_OFFSET`, or move the mirror point in `MapCatalog`. Check by selecting the `Mirror` part in Explorer while playing.
5. **Empty room copy (N = 0 or tiny).** Then the picture is only the gray-blue background plus the character. Fix the `buildRoom` filters (`depth`, `Transparency < 0.98`, `MIRROR_ROOM_RANGE`).

## Step 3: once something shows

- Straight on, the reflection should line up with the room edges. If it's mirrored the wrong way or flipped vertically, fix `right`/`up` in `update` (`Mirror.luau:176`).
- Check the character copy follows (R15 limbs synced by name).
- Performance: one face per panel, capped resolution (`MIRROR_PIXELS_PER_STUD` 16), and it stops updating past `MIRROR_MAX_DISTANCE`.

## Fallback if ViewportFrame can't work

The classic Roblox mirror builds a real mirrored copy of the room behind see-through glass, plus a mirrored local clone of the character. It's robust, but the copy takes up the space behind the wall, which is other parts of Construct. It only works if that space is empty or the copy is client-only and hidden from other rooms. Use it only if Step 2 fails.

## Rules for this work

- `--!strict`, `task.*` only, client-only visuals (no remotes needed).
- `scripts/check.sh` (or stylua + selene + lune specs) must pass.
- Test with as few Studio Play runs as possible: batch all checks into one run.
- Bump `Config.BUILD` so a stale Studio is obvious.
