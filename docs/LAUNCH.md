# Launch checklist (after ROADMAP step 4)

## Gate
- [ ] `scripts/check.sh` green
- [ ] 3 friends, 30 minutes, nothing crashes or lags out
- [ ] Abuse matrix in `docs/SECURITY.md` passes
- [ ] Asset log filled (`docs/ASSETS.md`); DMCA risk accepted by the user
- [ ] Network ownership policy decided

## Roblox settings
- [ ] Max players 24 (matches `Config.MAX_PLAYERS` and the server browser's x/24)
- [ ] Split Worlds: create one place per map in the same universe; paste each place id into `MapCatalog.placeId`; start place stays Flatgrass
- [ ] Experience rated and questionnaire completed
- [ ] API Services enabled (DataStores, map import)
- [ ] Streaming: decide on/off for the big map; props code tolerates missing instances
- [ ] Place has Baseplate, SpawnPad, `Props` folder (Rojo provides these)
- [ ] Title, thumbnail, description; Gmod/Valve names or art only if you accept the takedown risk

## Feedback button (built: `UI/Feedback.luau`, `FeedbackService.luau`)
- "Feedback" button in the Q menu opens a small text box, sends to the server via one rate-limited remote (`SendFeedback`, 1 per 60 s, 500 char cap, `typeof` string check).
- Server stores in a DataStore key and prints to server log. Read later via Open Cloud or Studio.
- Never display feedback text to other players.

## After launch
- Watch crash logs and the Developer Console memory graph on first public servers.
- Hotfix flow: edit, `scripts/check.sh`, publish from Studio.
