#!/usr/bin/env python3
"""Synthesize the footstep sounds used by scripts/core/footsteps.gd.

    python3 tools/make_footstep_sounds.py      (needs numpy; a few seconds)

Writes, 44.1 kHz mono 16-bit, six variations per floor so a walk never sounds
like a loop (footsteps.gd also varies pitch and level, and alternates feet):
  assets/audio/steps/metal_1..6.wav   space boots on deck plating: the heel's thud
                                      and hard click, the plate's short metallic knock,
                                      then the toe coming down with a scuff
  assets/audio/steps/grate_1..6.wav   on open grating (engineering): a hollow, ringing
                                      clank and the grate's loose rattle
  assets/audio/steps/soft_1..6.wav    on carpet and mats (observation, hydroponics):
                                      a muffled thud and a brush of fabric

Each step is built like a real one: heel strike, then the toe landing 30-55 ms
later, each exciting the floor's own resonances (a few damped modes, randomly
detuned per variation). Seeded, so it writes the same files every time.
Original work of the team.
"""
import math
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "steps")
VARIATIONS = 6
rng = np.random.default_rng(2126)


def t_axis(d):
    return np.arange(int(RATE * d)) / RATE


def biquad(x, kind, f, q=0.707):
    """RBJ cookbook low/high/band-pass."""
    w = 2.0 * math.pi * f / RATE
    alpha = math.sin(w) / (2.0 * q)
    cw = math.cos(w)
    if kind == "low":
        b = ((1 - cw) / 2, 1 - cw, (1 - cw) / 2)
    elif kind == "high":
        b = ((1 + cw) / 2, -(1 + cw), (1 + cw) / 2)
    else:  # band, 0 dB peak
        b = (alpha, 0.0, -alpha)
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2 = b[0] / a0, b[1] / a0, b[2] / a0
    a1, a2 = a1 / a0, a2 / a0
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        out = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, out
        y[i] = out
    return y


def noise(d):
    return rng.uniform(-1.0, 1.0, int(RATE * d))


def burst(d, tau, kind, f, q=0.707):
    """A filtered noise burst with an exponential decay."""
    return biquad(noise(d), kind, f, q) * np.exp(-t_axis(d) / tau)


def thump(d, f0, f1, tau):
    """The low body of an impact: a short downward pitch sweep."""
    t = t_axis(d)
    f = f1 + (f0 - f1) * np.exp(-t / 0.02)
    return np.sin(2 * math.pi * np.cumsum(f) / RATE) * np.exp(-t / tau)


def modes(d, freqs, taus, amps, detune):
    """Damped resonances of the floor (a struck plate), each randomly detuned."""
    t = t_axis(d)
    out = np.zeros(len(t))
    for f, tau, a in zip(freqs, taus, amps):
        f *= 1 + rng.uniform(-detune, detune)
        out += a * np.sin(2 * math.pi * f * t + rng.uniform(0, 2 * math.pi)) * np.exp(-t / tau)
    return out


def place(out, sig, at, gain=1.0):
    i = int(at * RATE)
    j = min(len(out), i + len(sig))
    out[i:j] += sig[:j - i] * gain


def metal():
    d = 0.42
    out = np.zeros(int(RATE * d))
    toe = rng.uniform(0.03, 0.055)
    heel_gain = rng.uniform(0.85, 1.0)
    plate = ([310, 790, 1460, 2630, 3900], [0.05, 0.035, 0.024, 0.016, 0.01], [0.5, 0.34, 0.24, 0.14, 0.07])
    # Heel: thud, a hard click, the plate knocking.
    place(out, thump(0.12, 160, 80, 0.022), 0.0, 0.35 * heel_gain)
    place(out, burst(0.1, 0.012, "low", 750), 0.0, 0.6 * heel_gain)
    place(out, burst(0.02, 0.0035, "band", 3200, 1.2), 0.0, 1.0 * heel_gain)
    place(out, modes(0.3, *plate, 0.08), 0.001, 0.65 * heel_gain)
    # Toe: lighter, and a short scuff of the sole.
    place(out, thump(0.08, 140, 85, 0.016), toe, 0.18)
    place(out, burst(0.02, 0.003, "band", 3600, 1.2), toe, 0.55)
    place(out, modes(0.25, *plate, 0.08), toe + 0.001, 0.3)
    place(out, burst(0.06, 0.02, "band", 1800, 0.8), toe + 0.005, 0.25)
    return out


def grate():
    d = 0.55
    out = np.zeros(int(RATE * d))
    toe = rng.uniform(0.03, 0.05)
    bars = ([180, 520, 1240, 2210, 3480], [0.06, 0.13, 0.095, 0.07, 0.045], [0.2, 0.42, 0.32, 0.22, 0.12])
    place(out, thump(0.1, 150, 85, 0.018), 0.0, 0.25)
    place(out, burst(0.02, 0.003, "band", 3000, 1.0), 0.0, 0.8)
    place(out, modes(0.45, *bars, 0.06), 0.001, 0.7)
    place(out, burst(0.02, 0.003, "band", 3400, 1.0), toe, 0.35)
    place(out, modes(0.4, *bars, 0.06), toe + 0.001, 0.35)
    # The grate rattling in its frame: a few small, quickly fading ticks.
    for k in range(rng.integers(3, 7)):
        at = rng.uniform(0.02, 0.16)
        place(out, burst(0.012, 0.0018, "band", rng.uniform(2500, 4500), 2.0), at, 0.35 * math.exp(-at / 0.08))
    return out


def soft():
    d = 0.32
    out = np.zeros(int(RATE * d))
    toe = rng.uniform(0.035, 0.06)
    place(out, thump(0.12, 180, 100, 0.024), 0.0, 0.45)
    place(out, burst(0.12, 0.02, "low", 1100), 0.0, 1.0)
    place(out, burst(0.12, 0.018, "band", 420, 0.9), 0.0, 0.5)     # the boot sinking in
    place(out, thump(0.08, 160, 100, 0.018), toe, 0.22)
    place(out, burst(0.12, 0.035, "band", 1500, 0.6), toe, 0.4)    # fabric brushing
    return out


def level(x, target_rms):
    """Scale so the step's first 150 ms has the given loudness, peaks kept under 0.95."""
    head = x[:int(0.15 * RATE)]
    x = x * (target_rms / (np.sqrt(np.mean(head ** 2)) + 1e-9))
    peak = np.max(np.abs(x))
    if peak > 0.95:
        x *= 0.95 / peak
    fade = int(0.04 * RATE)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    x[:16] *= np.linspace(0.0, 1.0, 16)
    return x


def write(name, samples):
    data = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    path = os.path.normpath(os.path.join(OUT, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    # Loudness per floor: grating rings a little louder, carpet is quieter.
    for surface, make, rms in (("metal", metal, 0.16), ("grate", grate, 0.17), ("soft", soft, 0.11)):
        for k in range(1, VARIATIONS + 1):
            path = write("%s_%d.wav" % (surface, k), level(make(), rms))
        print("wrote", os.path.relpath(os.path.dirname(path)), surface, "x%d" % VARIATIONS)


if __name__ == "__main__":
    main()
