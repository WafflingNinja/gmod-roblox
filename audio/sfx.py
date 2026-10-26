"""Synthesizes the game's sound effects from scratch (oscillators + noise, no samples), so they are
original and license-clean. Writes audio/exports/<name>.ogg for upload to Roblox.

Run: python3 audio/sfx.py        (needs numpy and ffmpeg)
"""

import subprocess
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).parent / "exports"
rng = np.random.default_rng(7)


def time(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def sweep(start, end, seconds, curve=1.0):
    """Phase of a sine whose pitch glides from start to end Hz."""
    t = time(seconds)
    freq = start + (end - start) * (t / seconds) ** curve
    return 2 * np.pi * np.cumsum(freq) / RATE


def decay(seconds, rate):
    return np.exp(-time(seconds) * rate)


def noise(seconds):
    return rng.uniform(-1, 1, int(RATE * seconds))


def lowpass(signal, cutoff):
    """One-pole lowpass; cutoff may be a number or an array (per-sample Hz)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), signal.shape)
    alpha = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    out = np.empty_like(signal)
    acc = 0.0
    for i, (x, a) in enumerate(zip(signal, alpha)):
        acc += a * (x - acc)
        out[i] = acc
    return out


def saw(phase):
    return 2 * ((phase / (2 * np.pi)) % 1) - 1


def square(phase):
    return np.sign(np.sin(phase))


def pad(*parts):
    """Sum signals of different lengths."""
    n = max(len(p) for p in parts)
    return sum(np.pad(p, (0, n - len(p))) for p in parts)


def fade(signal, ms=5):
    n = int(RATE * ms / 1000)
    ramp = np.linspace(0, 1, n)
    signal[:n] *= ramp
    signal[-n:] *= ramp[::-1]
    return signal


def physgun_grab():
    s = 0.3
    zap = saw(sweep(180, 900, s, 0.6)) * 0.5 + np.sin(sweep(360, 1800, s, 0.6)) * 0.4
    return fade(lowpass(zap, 4000) * decay(s, 9) + noise(s) * decay(s, 30) * 0.15)


def hum(base, buzz):
    # 2 s with whole cycles of every partial and the wobble, so it loops without a seam.
    t = time(2)
    tone = np.sin(2 * np.pi * base * t) + 0.6 * np.sin(2 * np.pi * (base + 0.5) * t)
    tone += buzz * saw(2 * np.pi * base * 2 * t) + 0.3 * np.sin(2 * np.pi * base * 3 * t)
    wobble = 0.75 + 0.25 * np.sin(2 * np.pi * 6 * t)
    return lowpass(tone * wobble, 1800)


def physgun_hold():
    return hum(110, 0.15)


def gravgun_hold():
    return hum(80, 0.35)


def physgun_release():
    s = 0.25
    return fade(np.sin(sweep(700, 150, s)) * decay(s, 12))


def physgun_freeze():
    s = 0.4
    ring = sum(np.sin(2 * np.pi * f * time(s)) / (i + 1) for i, f in enumerate([1200, 1870, 2650, 3420]))
    click = noise(0.01) * 0.8
    return fade(pad(ring * decay(s, 14) * 0.6, click))


def gravgun_pull():
    s = 0.45
    air = lowpass(noise(s), np.linspace(300, 3500, int(RATE * s))) * 1.6
    tone = np.sin(sweep(150, 420, s)) * 0.4
    env = np.sin(np.pi * time(s) / s) ** 0.7
    return fade((air + tone) * env)


def gravgun_punt():
    s = 0.35
    thump = np.sin(sweep(95, 38, s)) * decay(s, 10)
    burst = lowpass(noise(s), 2500) * decay(s, 25) * 1.2
    zap = saw(sweep(650, 180, s)) * decay(s, 14) * 0.35
    return fade(thump + burst + zap)


def toolgun_fire():
    s = 0.18
    pew = square(sweep(1500, 450, s, 0.5)) * 0.5 + np.sin(sweep(3000, 900, s, 0.5)) * 0.3
    return fade(lowpass(pew, 5000) * decay(s, 18))


def weld():
    s = 0.2
    click = noise(0.006) * 0.9
    ping = (np.sin(2 * np.pi * 2200 * time(s)) + 0.5 * np.sin(2 * np.pi * 3100 * time(s))) * decay(s, 35)
    return fade(pad(ping * 0.5, click))


def deny():
    s = 0.12
    beep = lowpass(square(2 * np.pi * 180 * time(s)), 1500) * 0.5
    gap = np.zeros(int(RATE * 0.06))
    return fade(np.concatenate([fade(beep.copy()), gap, fade(beep.copy())]))


def spawn():
    s = 0.18
    return fade(np.sin(sweep(280, 900, s, 0.4)) * decay(s, 16) + lowpass(noise(s), 1500) * decay(s, 40) * 0.3)


def remove():
    s = 0.28
    tone = np.sin(sweep(900, 180, s, 0.7)) * decay(s, 10) * 0.6
    poof = lowpass(noise(s), np.linspace(4000, 400, int(RATE * s))) * decay(s, 9) * 0.9
    return fade(tone + poof)


def shot(seconds, crack_hz, body_hz, rate):
    """Gunshot: bright noise crack over a low thump, fast decay."""
    crack = lowpass(noise(seconds), crack_hz) * decay(seconds, rate)
    thump = np.sin(2 * np.pi * sweep_hz(body_hz, body_hz * 0.4, seconds)) * decay(seconds, rate * 0.6)
    return fade(crack + 0.8 * thump)


def sweep_hz(start, end, seconds):
    return np.cumsum(np.linspace(start, end, int(RATE * seconds))) / RATE


def pistol_fire():
    return shot(0.35, 5000, 140, 18)


def smg_fire():
    return shot(0.22, 6500, 180, 26)


def ar2_fire():
    zap = np.sin(2 * np.pi * sweep_hz(1400, 300, 0.25)) * decay(0.25, 22)
    return fade(pad(shot(0.3, 3500, 110, 16), 0.6 * zap))


def rpg_fire():
    s = 0.9
    whoosh = lowpass(noise(s), np.linspace(1500, 400, int(RATE * s))) * decay(s, 3)
    return fade(pad(shot(0.3, 2500, 90, 12), whoosh))


def reload():
    click = lambda: lowpass(noise(0.04), 6000) * decay(0.04, 120)
    gap = np.zeros(int(RATE * 0.25))
    return fade(np.concatenate([click(), gap, click(), np.zeros(int(RATE * 0.1)), click()]))


def dry_fire():
    return fade(lowpass(noise(0.05), 4000) * decay(0.05, 100), ms=2)


def ui_tick():
    s = 0.05
    return fade(np.sin(2 * np.pi * 2400 * time(s)) * decay(s, 90), ms=2)


SOUNDS = {
    f.__name__: f
    for f in [
        physgun_grab,
        physgun_hold,
        physgun_release,
        physgun_freeze,
        gravgun_hold,
        gravgun_pull,
        gravgun_punt,
        toolgun_fire,
        weld,
        deny,
        spawn,
        remove,
        ui_tick,
        pistol_fire,
        smg_fire,
        ar2_fire,
        rpg_fire,
        reload,
        dry_fire,
    ]
}


def write(name, signal):
    peak = np.max(np.abs(signal))
    pcm = (signal / peak * 0.9 * 32767).astype("<i2")
    path = OUT / f"{name}.ogg"
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "6", str(path)],
        input=pcm.tobytes(),
        check=True,
    )
    return path


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for name, make in SOUNDS.items():
        signal = make()
        assert np.all(np.isfinite(signal)) and len(signal) > 0, name
        path = write(name, signal)
        print(f"{path.name}: {len(signal) / RATE:.2f} s")
