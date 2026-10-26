"""Voice line recorder for the NPCs (see docs/VOICE.md).

Lists every line in lines.json, records your mic per line, lets you edit the text, and the Finish
button exports cleaned-up .ogg files for Roblox plus the VoiceLines.luau timing table.

Windows: double-click record.bat (installs everything into .venv on the first run).
Linux/Mac: python3 audio/voice/recorder.py   (needs numpy, sounddevice, tkinter, and ffmpeg or imageio-ffmpeg)

Keys: Space record/stop, P play, Up/Down change line, T test mic, Esc leave a text box.
A take is saved to takes/<id>.wav the moment you stop, so closing the window never loses audio.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import wave
from pathlib import Path

import tkinter as tk
from tkinter import messagebox, ttk

import numpy as np

try:
    import sounddevice as sd
except (ImportError, OSError) as err:
    sys.exit(f"sounddevice is missing or PortAudio is not installed ({err}). See docs/VOICE.md, Setup.")

try:
    import imageio_ffmpeg  # pip-installed ffmpeg, so Windows needs nothing on PATH
except ImportError:
    imageio_ffmpeg = None

HERE = Path(__file__).resolve().parent
LINES = HERE / "lines.json"
TAKES = HERE / "takes"
OUT = HERE / "exports"
SHARED = HERE.parents[1] / "src" / "ReplicatedStorage" / "Shared" / "VoiceLines.luau"

FFMPEG = shutil.which("ffmpeg") or (imageio_ffmpeg.get_ffmpeg_exe() if imageio_ffmpeg else None)
RATE = 48000  # export rate; takes keep whatever the mic gave
TEST_SECONDS = 3
GAP = 0.5  # silence between lines inside a sprite, so a PlaybackRegion never bleeds into the next line
KEY_CLICK = (0.12, 0.2)  # seconds cut from the start/end of a raw take: the Space key click lives there
PEAK_DB = -3.0  # every exported line is normalized to this peak
TRIM_RATIO = 0.08  # 10 ms windows quieter than this fraction of the peak count as silence
LEAD, TAIL = 0.15, 0.25  # seconds of room kept before the first and after the last loud window


# ---------- audio helpers (no GUI) ----------


def save_wav(path, audio, rate):
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    tmp = path.with_suffix(".tmp")
    with wave.open(str(tmp), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(pcm.tobytes())
    tmp.replace(path)


def load_wav(path):
    with wave.open(str(path), "rb") as f:
        rate = f.getframerate()
        pcm = np.frombuffer(f.readframes(f.getnframes()), "<i2")
    return pcm.astype(np.float32) / 32768, rate


def resample(audio, rate, target):
    if rate == target or len(audio) == 0:
        return audio
    n = int(len(audio) * target / rate)
    return np.interp(np.linspace(0, len(audio) - 1, n), np.arange(len(audio)), audio).astype(np.float32)


def db(level):
    return 20 * np.log10(max(level, 1e-6))


def clean(audio, rate):
    """Cut the key clicks, trim silence, fade the edges, normalize. Empty result = nothing was said."""
    audio = audio[int(KEY_CLICK[0] * rate) : len(audio) - int(KEY_CLICK[1] * rate)]
    if len(audio) == 0:
        return audio
    audio = audio - np.mean(audio)
    peak = float(np.max(np.abs(audio)))
    if peak < 0.01:
        return audio[:0]
    win = rate // 100
    windows = len(audio) // win
    env = np.abs(audio[: windows * win]).reshape(windows, win).max(axis=1)
    loud = np.nonzero(env > peak * TRIM_RATIO)[0]
    start = max(0, int(loud[0] * win - LEAD * rate))
    end = min(len(audio), int((loud[-1] + 1) * win + TAIL * rate))
    audio = audio[start:end] / peak * 10 ** (PEAK_DB / 20)
    fade = min(len(audio) // 2, rate // 50)
    ramp = np.linspace(0, 1, fade, dtype=np.float32)
    audio[:fade] *= ramp
    audio[len(audio) - fade :] *= ramp[::-1]
    return audio.astype(np.float32)


def pitch_shift(audio, semitones):
    """Higher or lower voice, same length (ffmpeg asetrate + atempo). 0 = untouched."""
    if semitones == 0 or len(audio) == 0:
        return audio
    factor = 2 ** (semitones / 12)
    result = subprocess.run(
        [FFMPEG, "-loglevel", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-af", f"asetrate={RATE * factor:.0f},aresample={RATE},atempo={1 / factor:.6f}",
         "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-"],
        input=audio.astype("<f4").tobytes(),
        capture_output=True,
        check=True,
    )
    return np.frombuffer(result.stdout, "<f4").astype(np.float32)


def write_ogg(path, audio):
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2")
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "6", str(path)],
        input=pcm.tobytes(),
        check=True,
    )
    return pcm


def input_devices():
    """(index, name) of every mic, using only the default mic's host API so Windows doesn't list each mic 4 times."""
    devices = list(enumerate(sd.query_devices()))
    mics = [(i, d) for i, d in devices if d["max_input_channels"] > 0]
    default = sd.default.device[0]
    if 0 <= default < len(devices):
        same_api = [(i, d) for i, d in mics if d["hostapi"] == devices[default][1]["hostapi"]]
        mics = same_api or mics
    return [(i, d["name"]) for i, d in mics]


def take_path(line_id):
    return TAKES / f"{line_id}.wav"


# ---------- lines.json ----------


def load_lines():
    return json.loads(LINES.read_text(encoding="utf-8"))


def dump_lines(data):
    """One line per entry so git diffs stay readable."""
    npcs = json.dumps(data["npcs"], indent=2, ensure_ascii=False).replace("\n", "\n  ")
    rows = ",\n".join("    " + json.dumps(line, ensure_ascii=False) for line in data["lines"])
    return '{\n  "npcs": ' + npcs + ',\n  "lines": [\n' + rows + "\n  ]\n}\n"


def save_lines(data):
    tmp = LINES.with_suffix(".tmp")
    tmp.write_text(dump_lines(data), encoding="utf-8")
    tmp.replace(LINES)


# ---------- Finish: export ----------


def luau_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def old_sprite_ids():
    """Asset ids already pasted into VoiceLines.luau, kept when a sprite's audio did not change."""
    for path in (SHARED, OUT / "VoiceLines.luau"):
        if path.exists():
            text = path.read_text(encoding="utf-8")
            return {m[0]: (m[1], m[2]) for m in re.findall(r'(\w+) = \{ id = "([^"]*)", hash = "(\w*)" \}', text)}
    return {}


def write_luau(sprites, entries):
    lines = [
        "--!strict",
        "-- NPC voice lines. Generated by audio/voice/recorder.py (Finish): edit the text there, not here.",
        "-- Each NPC's lines live in one sprite sound (audio/voice/exports/<npc>.ogg). Play a line with",
        "-- PlaybackRegionsEnabled = true and PlaybackRegion = NumberRange.new(start, start + length).",
        '-- id "" = sprite not uploaded yet. hash changes when the sprite audio changes: re-upload it then.',
        "export type Sprite = { id: string, hash: string }",
        "export type Line = { npc: string, category: string, text: string, start: number, length: number }",
        "",
        "local sprites: { [string]: Sprite } = {",
    ]
    for npc, (asset, digest) in sprites.items():
        lines.append(f'\t{npc} = {{ id = "{asset}", hash = "{digest}" }},')
    lines += ["}", "", "local lines: { [string]: Line } = {"]
    for line, start, length in entries:
        lines.append(
            f'\t{line["id"]} = {{ npc = "{line["npc"]}", category = "{line["category"]}", '
            f"text = {luau_string(line['text'])}, start = {start:.3f}, length = {length:.3f} }},"
        )
    lines += ["}", "", "return table.freeze({ sprites = table.freeze(sprites), lines = table.freeze(lines) })", ""]
    (OUT / "VoiceLines.luau").write_text("\n".join(lines), encoding="utf-8")


def export_all(data, progress):
    """Clean every take, write exports/<npc>/<id>.ogg, one sprite exports/<npc>.ogg per NPC and VoiceLines.luau."""
    old = old_sprite_ids()
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    sprites, entries, missing, silent, reupload = {}, [], [], [], []
    for npc, info in data["npcs"].items():
        (OUT / npc).mkdir()
        parts, cursor = [], 0
        for line in (entry for entry in data["lines"] if entry["npc"] == npc):
            progress(f"Exporting {line['id']}...")
            if not take_path(line["id"]).exists():
                missing.append(line["id"])
                continue
            audio, rate = load_wav(take_path(line["id"]))
            audio = pitch_shift(clean(resample(audio, rate, RATE), RATE), info.get("pitch", 0))
            if len(audio) == 0:
                silent.append(line["id"])
                continue
            write_ogg(OUT / npc / f"{line['id']}.ogg", audio)
            entries.append((line, cursor / RATE, len(audio) / RATE))
            gap = np.zeros(int(GAP * RATE), np.float32)
            parts += [audio, gap]
            cursor += len(audio) + len(gap)
        if parts:
            pcm = write_ogg(OUT / f"{npc}.ogg", np.concatenate(parts))
            digest = hashlib.sha1(pcm.tobytes()).hexdigest()[:10]
            asset, old_digest = old.get(npc, ("", ""))
            if old_digest != digest:
                asset = ""
                reupload.append(f"{npc}.ogg")
            sprites[npc] = (asset, digest)
    write_luau(sprites, entries)
    return entries, missing, silent, reupload


def open_folder(path):
    if sys.platform.startswith("win"):
        os.startfile(path)
    else:
        subprocess.Popen(["open" if sys.platform == "darwin" else "xdg-open", str(path)])


# ---------- mic ----------


class Mic:
    """One input stream for the whole session: feeds the level meter and, while recording, a buffer."""

    def __init__(self):
        self.lock = threading.Lock()
        self.stream = None
        self.rate = RATE
        self.chunks = None
        self.peak = 0.0

    def open(self, device):
        self.close()
        try:
            self.rate = RATE
            self.stream = sd.InputStream(device=device, channels=1, samplerate=RATE, dtype="float32", callback=self._feed)
        except Exception:
            self.rate = int(sd.query_devices(device)["default_samplerate"])
            self.stream = sd.InputStream(
                device=device, channels=1, samplerate=self.rate, dtype="float32", callback=self._feed
            )
        self.stream.start()

    def close(self):
        if self.stream is not None:
            self.stream.close()
            self.stream = None

    def _feed(self, block, _frames, _time, _status):
        mono = block[:, 0].copy()
        with self.lock:
            self.peak = max(self.peak, float(np.max(np.abs(mono))))
            if self.chunks is not None:
                self.chunks.append(mono)

    def read_peak(self):
        with self.lock:
            peak, self.peak = self.peak, 0.0
        return peak

    def start(self):
        with self.lock:
            self.chunks = []

    def stop(self):
        with self.lock:
            chunks, self.chunks = self.chunks, None
        return np.concatenate(chunks) if chunks else np.zeros(0, np.float32)

    @property
    def busy(self):
        return self.chunks is not None


# ---------- GUI ----------


class App:
    def __init__(self, root):
        self.root = root
        self.data = load_lines()
        self.mic = Mic()
        self.current = None  # line id shown in the editor
        self.rec_id = None  # line id being recorded, None when idle
        self.testing = False
        self.save_job = None
        TAKES.mkdir(exist_ok=True)

        self.scale = max(1.0, root.winfo_fpixels("1i") / 96)  # Windows display scaling (125%, 150%...)
        root.title("waffles mod - voice recorder")
        width = min(self.px(1100), root.winfo_screenwidth() - 40)
        height = min(self.px(680), root.winfo_screenheight() - 100)  # room for the taskbar
        root.geometry(f"{width}x{height}")
        root.minsize(min(self.px(900), width), min(self.px(560), height))
        self.build()
        self.fill_tree()
        self.pick_device()
        self.tick()
        root.protocol("WM_DELETE_WINDOW", self.close)

    def px(self, n):
        return int(n * self.scale)

    # layout
    def build(self):
        bar = ttk.Frame(self.root, padding=8)
        bar.pack(fill="x")
        ttk.Label(bar, text="Mic:").pack(side="left")
        self.devices = input_devices()
        self.device_box = ttk.Combobox(bar, state="readonly", width=42, values=[f"{i}: {n}" for i, n in self.devices])
        self.device_box.pack(side="left", padx=6)
        self.device_box.bind("<<ComboboxSelected>>", lambda _e: self.open_device())
        self.test_btn = ttk.Button(bar, text="Test mic (T)", command=self.test_mic)
        self.test_btn.pack(side="left", padx=6)
        self.meter = tk.Canvas(bar, width=self.px(260), height=self.px(18), bg="#222", highlightthickness=0)
        self.meter.pack(side="left", padx=6)
        self.meter_label = ttk.Label(bar, width=22)
        self.meter_label.pack(side="left")

        body = ttk.PanedWindow(self.root, orient="horizontal")
        body.pack(fill="both", expand=True, padx=8)

        left = ttk.Frame(body)
        body.add(left, weight=3)
        top = ttk.Frame(left)
        top.pack(fill="x", pady=(0, 4))
        ttk.Label(top, text="Show:").pack(side="left")
        self.filter = ttk.Combobox(top, state="readonly", width=12, values=["all", *self.data["npcs"]])
        self.filter.set("all")
        self.filter.pack(side="left", padx=6)
        self.filter.bind("<<ComboboxSelected>>", lambda _e: self.fill_tree())
        self.progress = ttk.Label(top)
        self.progress.pack(side="right")
        self.tree = ttk.Treeview(left, columns=("done", "npc", "category", "text"), show="headings", selectmode="browse")
        for col, title, width in (("done", "", 30), ("npc", "NPC", 80), ("category", "Category", 80), ("text", "Line", 400)):
            self.tree.heading(col, text=title)
            self.tree.column(col, width=width, stretch=col == "text", anchor="center" if col == "done" else "w")
        scroll = ttk.Scrollbar(left, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=scroll.set)
        self.tree.pack(side="left", fill="both", expand=True)
        scroll.pack(side="left", fill="y")
        self.tree.bind("<<TreeviewSelect>>", lambda _e: self.select(self.tree.selection()[0] if self.tree.selection() else None))

        right = ttk.Frame(body, padding=(12, 0, 0, 0))
        body.add(right, weight=2)
        self.voice = ttk.Label(right, wraplength=self.px(380), foreground="#555")
        self.voice.pack(fill="x", pady=(0, 8))
        self.title = ttk.Label(right, font=("TkDefaultFont", 11, "bold"))
        self.title.pack(anchor="w")
        cat_row = ttk.Frame(right)
        cat_row.pack(fill="x", pady=4)
        ttk.Label(cat_row, text="Category:").pack(side="left")
        self.category = ttk.Combobox(cat_row, width=14)
        self.category.pack(side="left", padx=6)
        self.category.bind("<<ComboboxSelected>>", lambda _e: self.edited())
        self.category.bind("<KeyRelease>", lambda _e: self.edited())
        ttk.Label(right, text="Say this (click to change it):").pack(anchor="w", pady=(6, 0))
        self.text = tk.Text(right, width=30, height=4, wrap="word", font=("TkDefaultFont", 16), undo=True)
        self.text.pack(fill="x")
        self.text.bind("<KeyRelease>", lambda _e: self.edited())
        ttk.Label(right, text="Acting note:").pack(anchor="w", pady=(6, 0))
        self.note = ttk.Entry(right)
        self.note.pack(fill="x")
        self.note.bind("<KeyRelease>", lambda _e: self.edited())

        buttons = ttk.Frame(right)
        buttons.pack(fill="x", pady=12)
        self.rec_btn = tk.Button(buttons, text="● Record (Space)", width=16, bg="#c33", fg="white", command=self.toggle_record)
        self.rec_btn.pack(side="left")
        ttk.Button(buttons, text="▶ Play (P)", command=self.play).pack(side="left", padx=6)
        nav = ttk.Frame(right)
        nav.pack(fill="x")
        ttk.Button(nav, text="◀ Prev", command=lambda: self.step(-1)).pack(side="left")
        ttk.Button(nav, text="Next ▶", command=lambda: self.step(1)).pack(side="left", padx=6)
        self.autoplay = tk.BooleanVar(value=True)
        ttk.Checkbutton(nav, text="Play back after recording", variable=self.autoplay).pack(side="left", padx=6)
        edit = ttk.Frame(right)
        edit.pack(fill="x", pady=12)
        ttk.Button(edit, text="+ Add line", command=self.add_line).pack(side="left")
        ttk.Button(edit, text="Delete line", command=self.delete_line).pack(side="left", padx=6)
        self.status = ttk.Label(right, wraplength=self.px(380))
        self.status.pack(fill="x", pady=8)

        self.root.after(100, lambda: body.sashpos(0, self.px(600)))

        bottom = ttk.Frame(self.root, padding=8)
        bottom.pack(fill="x")
        self.finish_btn = tk.Button(
            bottom, text="✔ Finish: save and export everything", bg="#2a7", fg="white", font=("TkDefaultFont", 12, "bold"),
            command=self.finish,
        )
        self.finish_btn.pack(fill="x", ipady=6)

        self.root.bind_all("<space>", lambda e: self.key(e, self.toggle_record))
        self.root.bind_all("<KeyPress-p>", lambda e: self.key(e, self.play))
        self.root.bind_all("<KeyPress-t>", lambda e: self.key(e, self.test_mic))
        self.root.bind_all("<Up>", lambda e: self.key(e, lambda: self.step(-1), tree_too=False))
        self.root.bind_all("<Down>", lambda e: self.key(e, lambda: self.step(1), tree_too=False))
        self.root.bind_all("<Escape>", lambda _e: self.tree.focus_set())

    def key(self, event, action, tree_too=True):
        """Shortcuts work everywhere except while typing (and the tree already handles Up/Down itself)."""
        typing = (tk.Text, tk.Entry, ttk.Entry, tk.Button, ttk.Button, ttk.Checkbutton)
        if isinstance(event.widget, str) or isinstance(event.widget, typing):
            return  # typing, or a focused button that handles Space itself
        if not tree_too and event.widget is self.tree:
            return
        action()
        return "break"

    # lines
    def line(self, line_id):
        return next((entry for entry in self.data["lines"] if entry["id"] == line_id), None)

    def row(self, line):
        done = "✔" if take_path(line["id"]).exists() else ""
        return (done, self.data["npcs"][line["npc"]]["name"], line["category"], line["text"])

    def fill_tree(self):
        shown = self.filter.get()
        self.tree.delete(*self.tree.get_children())
        for line in self.data["lines"]:
            if shown in ("all", line["npc"]):
                self.tree.insert("", "end", iid=line["id"], values=self.row(line))
        self.count()
        rows = self.tree.get_children()
        pick = self.current if self.current in rows else (rows[0] if rows else None)
        self.current = None  # force the editor to reload
        if pick:
            self.tree.selection_set(pick)
            self.tree.see(pick)
            self.select(pick)

    def count(self):
        done = sum(take_path(line["id"]).exists() for line in self.data["lines"])
        self.progress.config(text=f"{done} / {len(self.data['lines'])} recorded")

    def select(self, line_id):
        if line_id is None or line_id == self.current:
            return
        self.current = line_id
        line = self.line(line_id)
        npc = self.data["npcs"][line["npc"]]
        self.voice.config(text=f"{npc['name']} voice: {npc['voice']}")
        self.title.config(text=f"{npc['name']}  ·  {line['id']}")
        self.category.config(values=sorted({entry["category"] for entry in self.data["lines"] if entry["npc"] == line["npc"]}))
        self.category.set(line["category"])
        self.text.delete("1.0", "end")
        self.text.insert("1.0", line["text"])
        self.text.edit_reset()
        self.note.delete(0, "end")
        self.note.insert(0, line.get("note", ""))
        self.status.config(text="Recorded. Space to redo it." if take_path(line_id).exists() else "Not recorded yet.")

    def edited(self):
        line = self.line(self.current) if self.current else None
        if line is None:
            return
        line["text"] = self.text.get("1.0", "end").strip()
        line["note"] = self.note.get().strip()
        line["category"] = re.sub(r"\W+", "_", self.category.get().strip().lower()) or line["category"]
        if self.tree.exists(line["id"]):
            self.tree.item(line["id"], values=self.row(line))
        if self.save_job:
            self.root.after_cancel(self.save_job)
        self.save_job = self.root.after(400, self.save)

    def save(self):
        self.save_job = None
        save_lines(self.data)

    def step(self, delta):
        rows = self.tree.get_children()
        if not rows:
            return
        index = rows.index(self.current) if self.current in rows else 0
        pick = rows[max(0, min(len(rows) - 1, index + delta))]
        self.tree.selection_set(pick)
        self.tree.see(pick)

    def add_line(self):
        base = self.line(self.current) if self.current else self.data["lines"][-1]
        n = 1
        while self.line(f"{base['npc']}_{base['category']}_{n}"):
            n += 1
        new = {"id": f"{base['npc']}_{base['category']}_{n}", "npc": base["npc"], "category": base["category"],
               "text": "New line, type it here", "note": ""}
        self.data["lines"].insert(self.data["lines"].index(base) + 1, new)
        self.save()
        self.current = new["id"]
        self.fill_tree()
        self.text.focus_set()
        self.text.tag_add("sel", "1.0", "end")

    def delete_line(self):
        line = self.line(self.current) if self.current else None
        if line is None or not messagebox.askyesno("Delete line", f"Delete \"{line['text']}\"?\nIts take moves to takes/trash."):
            return
        if take_path(line["id"]).exists():
            (TAKES / "trash").mkdir(exist_ok=True)
            take_path(line["id"]).replace(TAKES / "trash" / f"{line['id']}.wav")
        rows = self.tree.get_children()
        index = rows.index(line["id"]) if line["id"] in rows else 0
        self.data["lines"].remove(line)
        self.save()
        self.current = rows[index + 1] if index + 1 < len(rows) else (rows[index - 1] if index > 0 else None)
        self.fill_tree()

    # audio
    def pick_device(self):
        default = sd.default.device[0]
        ids = [i for i, _n in self.devices]
        if not ids:
            messagebox.showerror("No microphone", "No input device found. Plug in a mic and restart.")
            return
        self.device_box.current(ids.index(default) if default in ids else 0)
        self.open_device()

    def open_device(self):
        if self.rec_id:
            self.stop_record()
        device = self.devices[self.device_box.current()][0]
        try:
            self.mic.open(device)
            self.status.config(text=f"Mic ready ({self.mic.rate} Hz). Press T to test it.")
        except Exception as err:
            messagebox.showerror("Mic error", f"Could not open this mic:\n{err}\n\nPick another one in the list.")

    def tick(self):
        """Level meter, 20 times a second."""
        peak = self.mic.read_peak()
        level = db(peak)
        width = max(0, min(1, (level + 60) / 60)) * self.px(260)
        color = "#e33" if level > -1 else "#eb3" if level > -9 else "#3c5"
        self.meter.delete("all")
        self.meter.create_rectangle(0, 0, width, self.px(18), fill=color, width=0)
        hint = "TOO LOUD, back off" if level > -1 else "too quiet" if level < -40 and self.mic.busy else ""
        self.meter_label.config(text=f"{level:5.0f} dB  {hint}")
        self.root.after(50, self.tick)

    def toggle_record(self):
        if self.testing or self.current is None or self.mic.stream is None:
            return
        if self.rec_id:
            self.stop_record()
        else:
            sd.stop()
            self.rec_id = self.current
            self.mic.start()
            self.rec_btn.config(text="■ Stop (Space)", bg="#900")
            self.status.config(text="● RECORDING... wait a beat, say the line, wait a beat, then Space.")

    def stop_record(self):
        line_id, self.rec_id = self.rec_id, None
        audio = self.mic.stop()
        self.rec_btn.config(text="● Record (Space)", bg="#c33")
        if len(audio) < self.mic.rate * 0.4:
            self.status.config(text="Too short, nothing saved. Try again.")
            return
        save_wav(take_path(line_id), audio, self.mic.rate)
        peak = db(float(np.max(np.abs(audio))))
        warn = "  Clipped! Move back from the mic and redo it." if peak > -0.5 else "  Very quiet, get closer." if peak < -30 else ""
        self.status.config(text=f"Saved {line_id} ({len(audio) / self.mic.rate:.1f} s, peak {peak:.0f} dB).{warn}")
        line = self.line(line_id)
        if line and self.tree.exists(line_id):
            self.tree.item(line_id, values=self.row(line))
        self.count()
        if self.autoplay.get():
            self.play(line_id)

    def play(self, line_id=None):
        line_id = line_id or self.current
        if self.rec_id or line_id is None or not take_path(line_id).exists():
            return
        audio, rate = load_wav(take_path(line_id))
        sd.play(audio, rate)

    def test_mic(self):
        if self.rec_id or self.testing or self.mic.stream is None:
            return
        sd.stop()
        self.testing = True
        self.mic.start()
        self.test_btn.config(text="Speak now...")
        self.status.config(text=f"Testing: say something for {TEST_SECONDS} seconds, then you hear it back.")
        self.root.after(TEST_SECONDS * 1000, self.end_test)

    def end_test(self):
        audio = self.mic.stop()
        self.testing = False
        self.test_btn.config(text="Test mic (T)")
        if len(audio) == 0:
            return
        peak = db(float(np.max(np.abs(audio))))
        floor = db(float(np.percentile(np.abs(audio), 10)))
        verdict = (
            "Total silence. Wrong mic, or on Windows: Settings > Privacy > Microphone > let desktop apps use it."
            if peak < -90
            else "Too loud, it clips. Turn the mic gain down or move back." if peak > -1
            else "Too quiet. Turn the gain up or get closer." if peak < -25
            else "Noisy room, the background is loud." if floor > -45
            else "Sounds good."
        )
        self.status.config(text=f"Test: peak {peak:.0f} dB, background {floor:.0f} dB. {verdict}")
        sd.play(audio, self.mic.rate)

    def finish(self):
        if self.rec_id:
            self.stop_record()
        if FFMPEG is None:
            messagebox.showerror("ffmpeg missing", "pip install imageio-ffmpeg (see docs/VOICE.md). Your takes are safe in takes/.")
            return
        self.save()
        self.finish_btn.config(state="disabled")

        def progress(text):
            self.status.config(text=text)
            self.root.update_idletasks()

        try:
            entries, missing, silent, reupload = export_all(self.data, progress)
        except Exception as err:
            messagebox.showerror("Export failed", f"{err}\n\nYour takes are safe in takes/.")
            return
        finally:
            self.finish_btn.config(state="normal")
        report = [f"Exported {len(entries)} lines to audio/voice/exports/."]
        if reupload:
            report.append("Upload these to Roblox: " + ", ".join(reupload))
        if missing:
            report.append(f"Not recorded yet ({len(missing)}): " + ", ".join(missing[:12]) + (" ..." if len(missing) > 12 else ""))
        if silent:
            report.append("Silent takes, redo them: " + ", ".join(silent))
        progress("Finished. " + report[0])
        if messagebox.askyesno("Finished", "\n\n".join(report) + "\n\nOpen the exports folder?"):
            open_folder(OUT)

    def close(self):
        if self.rec_id:
            self.stop_record()
        if self.save_job:  # only an unsaved edit gets written, so closing never undoes outside changes to lines.json
            self.root.after_cancel(self.save_job)
            self.save()
        sd.stop()
        self.mic.close()
        self.root.destroy()


if __name__ == "__main__":
    if sys.platform.startswith("win"):
        try:
            import ctypes

            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError, OSError):
            pass
    root = tk.Tk()
    App(root)
    root.mainloop()
