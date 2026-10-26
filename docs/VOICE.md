# Voice acting day (2026-10-27)

House to yourself, so tomorrow is for recording every NPC voice line. The NPCs get built after that, from the recordings (step 6, `docs/NPC.md`).

Cast, all voiced by you:

| NPC | Look | Voice |
|---|---|---|
| **Guest** | Classic Guest: default body, black cap | Excited little kid, fast, a bit lost, thinks it's still 2016. Higher than your normal voice. |
| **Noob** | Yellow head and arms, blue torso, green legs | Slow, dopey, sure he's a pro. Goofy smile in the voice. |
| **Citizen** | Our own take on a city refugee: blue work shirt, dark pants, built from parts | Tired everyday guy, your normal voice, a bit rough and nervous, dry humor. |
| **RostikPro12308** (secret) | Your own Roblox avatar | You. Hyped, proud game dev who can't believe someone found him. Unlocked with the Konami code in the main menu. |

Jane Doe is cut. You're not doing a woman's voice, and there's no need to fake one. John Doe is cut too.

The Citizen is *inspired by* the HL2 citizens, nothing more. Hard rule 1 (`CLAUDE.md`, `docs/ASSETS.md`) still applies: no HL2 model, textures, sounds or voice clips, and no quoting their lines. Every line below is original, and the look is rebuilt from parts with no Lambda logo or other Valve marks.

## The plan for tomorrow

- [ ] **Setup (15 min).** Install the recorder (below), open it, pick your mic, press **Test mic**. Aim for a peak around -12 to -6 dB with no red bar.
- [ ] **Make your lines sound like you (10 min).** Close the recorder, open Claude Code in the repo and say *"make my RostikPro12308 lines sound like me"*. It reads your old chats, learns how you talk, and rewrites your 23 lines (see "Make RostikPro12308 sound like you" below). Check them, then reopen the recorder.
- [ ] **Read through (10 min).** Go down the list and say each line once out loud without recording. Change any line you don't like right in the text box. It saves by itself.
- [ ] **Noob first (20 min).** He's the easiest voice, so he's your warm-up. 21 lines.
- [ ] **Break.** Water, not soda or milk.
- [ ] **Guest (25 min).** 24 lines.
- [ ] **Citizen (20 min).** 21 lines, close to your normal voice.
- [ ] **RostikPro12308 last (20 min).** 23 lines. You're just being you, so it's the easiest one to do tired.
- [ ] **Screams last of all.** Leave `thrown` lines (Wheeee!, Aaaah!) until the end so you don't wreck your voice early.
- [ ] **Re-listen (15 min).** Click through every line with P and redo anything that's clipped, mumbled or not funny.
- [ ] **Finish.** Press the green **Finish** button. It exports everything.
- [ ] **Back up.** Commit and push `audio/voice/takes/` and `audio/voice/lines.json` (GitHub Desktop: tick them, Commit, Push origin). The takes are the one thing you can't make again once people are home.
- [ ] If there's time: upload the 4 sprite files (see "After recording").

About two and a half hours with breaks. All 89 lines, or the core ones (`spawn`, `idle`, `hurt`, `death`), gives the NPCs enough to work with.

## Setup

### Windows (double-click)

1. **Python**: install it from https://www.python.org/downloads/. On the first installer screen, tick **"Add python.exe to PATH"**. Tkinter comes with it.
2. **The repo**: get this branch onto the PC. With GitHub Desktop, clone `WafflingNinja/gmod-roblox` and switch to the branch `claude/game-voice-acting-plan-199apw`. With git:
   ```
   git clone https://github.com/WafflingNinja/gmod-roblox
   cd gmod-roblox
   git checkout claude/game-voice-acting-plan-199apw
   ```
3. **Microphone permission**: Settings > Privacy & security > Microphone. Turn on **Microphone access** and **Let desktop apps access your microphone**. If this is off, every take comes out silent.
4. **Run it**: double-click `audio\voice\record.bat`. The first time, it installs numpy, sounddevice and ffmpeg into a `.venv` folder (about a minute, needs internet). After that it opens straight away. A black console window stays open behind the recorder. Leave it open, because closing it closes the recorder.

In the recorder, pick your mic in the **Mic** list. If your headset and your webcam both have mics, choose the headset. If the mic you want isn't listed, plug it in before starting the recorder.

### Linux

```
# Debian/Ubuntu/Mint (Fedora: dnf install python3-tkinter portaudio, Arch: pacman -S tk portaudio)
sudo apt install python3-tk libportaudio2
cd ~/gmod-roblox
python3 -m venv .venv
.venv/bin/pip install numpy sounddevice imageio-ffmpeg
.venv/bin/python audio/voice/recorder.py
```

## The recorder (`audio/voice/recorder.py`)

- **Mic** dropdown plus a live level bar. Green is fine, yellow is loud, red means it's clipping.
- **Test mic (T)** records 3 seconds and plays them back, then tells you if it's too loud, too quiet or noisy.
- **Line list** on the left. A ✔ means it's recorded. **Show** filters to one NPC.
- **Say this** is the line. Click it and type to change it (Esc takes you back to the list). **Acting note** is a reminder of how to say it.
- **● Record (Space)** starts recording, Space again stops. The take saves straight to `audio/voice/takes/<id>.wav` and plays back. Space again re-records it.
- **▶ Play (P)**, **Prev/Next** (or Up/Down) and **+ Add line / Delete line** (deleted takes go to `takes/trash/`).
- **✔ Finish** saves and exports everything (see below).

Tips:
- Wait a beat after pressing Space, then talk, then wait a beat before stopping. The key click and the silence are cut off automatically.
- Mic about a fist away, talking just past it rather than straight into it, so P and B sounds don't pop.
- A small room with clothes or a bed in it has less echo than a kitchen. Turn off fans. Phone on silent.
- Do 2-3 takes of a line you care about. Only the last one is kept, so stop on the one you like.
- Say lines a bit over the top. Game voices sound flat when you play them normally.

## Make RostikPro12308 sound like you

The RostikPro12308 lines in `lines.json` are placeholders, written without knowing how you talk. Before you record them, ask the AI in your terminal to fix them: open Claude Code in the repo and say *"make my RostikPro12308 lines sound like me"*. Close the recorder first. It saves its own copy of `lines.json` when it closes, and that would overwrite the AI's changes.

**Steps for the AI:**

1. **Learn how he talks.** Read what Rostik has typed before, from these sources in this order:
   - Claude Code transcripts on this PC: `~/.claude/projects/*/*.jsonl` (on Windows `%USERPROFILE%\.claude\projects\`). Each line is one JSON event. Use only `"type": "user"` events with text he typed himself. Skip tool results, `<system-reminder>`, `<command-...>`, pasted blocks and anything the harness wrote. Start with this repo's project folder, then the others.
   - A claude.ai export, if he gives you one (claude.ai Settings > Privacy > Export data, then `conversations.json`, messages with sender `human`).
   - Anything else he points you to. Ask before opening any other folder or file.
2. **Write a short style profile** (in the chat only, never in the repo). Cover:
   - Sentence length; caps vs lowercase; how he uses "...", "Nooo", "!!".
   - Slang and filler ("n stuff", "like"); how he jokes; what he gets hyped or annoyed about.
   - English vs Czech.
   
   Show him the profile and 3 sample lines, and ask "does this sound like you?". Adjust until he says yes.
3. **Rewrite every `rostik` line** in `audio/voice/lines.json`:
   - Keep each `id`, `npc` and `category`, and the number of lines per category (the NPC code and the table above depend on them).
   - Rewrite `text` and `note`, and update the `voice` direction for `rostik`.
   - Write lines the way he would *say* them out loud, not how he types (no typos, no "u" for "you").
   - English, unless he asks for Czech.
   - Each line under about 4 seconds.
4. **Follow the rules** in "Rules for lines" below. On top of those:
   - No real name, school, city, age, family, friends, or anything private, even if it shows up in the chats.
   - Don't quote chat messages word for word. Match the style, not the content.
   - Never copy transcripts, excerpts or the profile into the repo or a commit.
5. **Show him the new lines as a table** (category, line, how to say it). Apply his edits. Then write `lines.json` with one line per entry, the same format `recorder.py` writes (`dump_lines`). Check that the ids are unique and the counts didn't change.
6. Tell him to reopen the recorder. He can still tweak any line there while recording.

## Rules for lines

The lines get uploaded to Roblox, and Roblox moderates audio:
- No swearing, slurs, or anything sexual. Not even bleeped.
- No real names, usernames (your own RostikPro12308 is fine), or personal info. No "free Robux" or anything that sounds like a scam.
- No song lyrics or quotes from movies and games (copyright). That includes HL2 citizen lines: write your own. Your own "oof" is fine, the old Roblox oof sound is not.
- Keep each line under about 4 seconds. Short lines are funnier and don't overlap.

## Lines

All lines are in `audio/voice/lines.json`, and the recorder is the easiest way to read or edit them. Every line has a **category**, which is when the NPC says it:

| Category | When | Guest | Noob | Citizen | RostikPro12308 |
|---|---|---|---|---|---|
| `unlock` | someone types the Konami code | | | | 2 |
| `spawn` | just spawned | 2 | 2 | 2 | 2 |
| `idle` | random, every 15-40 s | 5 | 5 | 5 | 5 |
| `greet` | a player walks up | 3 | 2 | 2 | 2 |
| `follow` / `stay` | told to follow / wait | 2 / 1 | 2 / 1 | 2 / 1 | 2 / 1 |
| `grabbed` | picked up with the physgun or gravity gun | 2 | 2 | 2 | 2 |
| `thrown` | let go fast / punted | 2 | 2 | 2 | 2 |
| `hurt` | takes damage | 3 | 2 | 2 | 2 |
| `death` | dies | 2 | 2 | 2 | 2 |
| `flee` | danger nearby | 2 | 1 | 1 | 1 |
| **total** | | **24** | **21** | **21** | **23** |

Adding lines is fine: more lines in a category means less repetition. A new category only does something once the NPC code uses it, so either stick to these or tell Claude about it on NPC day.

## After recording: what Finish makes

Finish writes `audio/voice/exports/` (gitignored, you can always remake it from the takes):
- `<npc>/<id>.ogg`: each line cleaned up (silence trimmed, key clicks cut, faded, all at the same loudness). Good for listening through.
- `guest.ogg`, `noob.ogg`, `citizen.ogg`, `rostik.ogg`: **sprites**, all of one NPC's lines in a single file with half a second of silence between them. **These are the only files to upload.** That's 4 uploads instead of 89, and Roblox limits how many audio files you can upload a month.
- `VoiceLines.luau`: where each line starts and how long it is inside its sprite, plus the text (for subtitles). The game plays a line with `Sound.PlaybackRegion`.

`lines.json` has a `pitch` setting per NPC, in semitones (0 = your real voice). If the Guest doesn't sound young enough, try `+2`. For a rougher, lower Citizen, try `-1`. Then press Finish again, because pitch only changes the export and never your takes.

Uploading (needs your Roblox account, so you do it): Creator Hub > Creations > Audio > Upload, or Studio > Asset Manager > Bulk Import. Upload the 4 sprites, wait for moderation, copy each id and paste it into `VoiceLines.luau` as `id = "rbxassetid://..."`. If you re-record and press Finish, the id only stays when that NPC's audio didn't change. When it did, Finish tells you which sprite to upload again.

## Then: building the NPCs (next session, with Claude)

1. Move `audio/voice/exports/VoiceLines.luau` to `src/ReplicatedStorage/Shared/`, run `stylua` on it, and add a lune spec (every line has a sprite, `start >= 0`, `length > 0`, no overlaps).
2. `Shared/BehaviorTree.luau` and `Services/NpcService.luau` as in `docs/NPC.md` and `TO-DO.md` section 6.
3. Rigs: R6 with body colors set in code (no Catalog items needed for Noob or Guest). Guest cap built from parts. Citizen: blue work shirt, dark pants, simple original face, built from parts (no HL2 likeness or logos). All original, nothing ripped.
4. Behaviors: all four are **Friendly**: wander, greet, follow or stay on command, flee danger, ragdoll when grabbed or thrown.
5. `Services/NpcVoice.luau`: the server picks a line from the category for the event, never the same line twice in a row, at most one line every 4 s per NPC plus a server-wide cap on voices at once. It plays from the NPC's head with `PlaybackRegion`, and shows the text as a chat bubble (`TextChatService:DisplayBubble`) so the lines still work with sound off.
6. NPC tab in the spawn menu. Spawning goes through `Ownership.luau` (5 prop slots each, cap 10 per player, 40 per server).
7. Secret: typing the Konami code (↑ ↑ ↓ ↓ ← → ← → B A) on the main menu unlocks **RostikPro12308** in the NPC tab, says an `unlock` line and shows a toast. He looks like your real avatar (loaded from your user id). Details in `docs/NPC.md`.

## Done when (tomorrow)
- Every line you want is recorded (✔ in the list) and you've re-listened to all of them.
- Finish ran with no "silent takes" warning.
- `audio/voice/takes/` and `lines.json` are committed and pushed.
