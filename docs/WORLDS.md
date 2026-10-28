# Split Worlds

Status 2026-10-28: code-complete, not Studio-verified. Start place = Flatgrass; map places need published places to test.

## Worlds

- One Roblox place per map, all in the same universe. The start place hosts **Flatgrass** and the main menu.
- Set the real place id on the map's `MapCatalog` entry (`placeId = 123...`). `tools/add_map.py` prompts for it
  and writes it for you.
- `MapService` reads `MapCatalog.byPlaceId[game.PlaceId]` at boot:
  - If the place hosts a map, joining players get `Map` = that map and spawn there.
  - The start place is Flatgrass (its placeId is already set); a place with no matching entry also falls back to
    Flatgrass.
- Starting a map in the menu:
  - target has a different `placeId`: `TeleportService:TeleportAsync` (props do not follow);
  - target has no place, or Studio refuses the teleport: switch to the in-place copy when this place has one.
- `Config.MAX_PLAYERS = 24` is the intended limit. Set the real limit to 24 for each place in Creator Dashboard;
  the script cannot change it.
- `Config.SERVER_PROP_CAP = 1500` is enforced in `Ownership.canSpawn`, so props, cars, dupes and NPCs all count
  server-wide. Per-player caps stay 150 / 250 (Builder+).

## Adding a map as a place

1. `python tools/add_map.py <workshop link> --mood overcast` (or let it use `day`).
2. When asked, create the place in Creator Dashboard > Creations > **Add Place** in the same universe and paste
   its place id. The script writes `placeId`, `MapCatalog`, `MapLighting` and the ASSETS row.
3. Run the copied Studio command in that place (or in the start place first to build the meshes), then Ctrl+S.
   The meshes live only in the place file.
4. Publish the place.

## Testing shortcuts

- Temporarily lower `Config.SERVER_PROP_CAP` to test the server-wide toast quickly.
- Studio cannot teleport between unpublished places; test the local fallback in one place first, then publish two
  places to test the real teleport.
