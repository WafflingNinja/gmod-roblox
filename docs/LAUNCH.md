# Launch checklist (after ROADMAP step 4)

## Gate
- [ ] `scripts/check.sh` green
- [ ] 3 friends, 30 minutes, nothing crashes or lags out
- [ ] Abuse matrix in `docs/SECURITY.md` passes
- [ ] No Valve/Gmod/HL2 assets anywhere (`docs/ASSETS.md`), license log filled
- [ ] Network ownership policy decided

## Roblox settings
- [ ] Max players 16-24
- [ ] Experience rated and questionnaire completed
- [ ] API Services enabled (DataStores)
- [ ] Streaming: decide on/off for the big map; props code tolerates missing instances
- [ ] Place has Baseplate, SpawnPad, `Props` folder (Rojo provides these)
- [ ] Title, thumbnail, description; no Gmod or Valve names or art in them

## Feedback button
- In-game button opens a small text box, sends to the server via one rate-limited remote (`SendFeedback`, 1 per 60 s, 500 char cap, `typeof` string check).
- Server stores in a DataStore key and prints to server log. Read later via Open Cloud or Studio.
- Never display feedback text to other players.

## After launch
- Watch crash logs and the Developer Console memory graph on first public servers.
- Hotfix flow: edit, `scripts/check.sh`, publish from Studio.
