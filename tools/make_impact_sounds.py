#!/usr/bin/env python3
"""Synthesize the hull-impact sounds used by scripts/prototype/escape_impacts.gd.

    python3 tools/make_impact_sounds.py      (needs numpy; ~1 s)

Writes, 44.1 kHz mono 16-bit:
  assets/audio/hull_impact.wav   a chunk of debris hitting the hull: a sharp crack,
                                 a deep thud through the frame, the hull ringing
                                 like a struck metal plate, a long structural groan
                                 and loose bits rattling down afterwards (~3 s)
  assets/audio/sparks.wav        an electrical short: a buzzing arc, then crackling
                                 pops that die away (~1.3 s)

Seeded, so it writes the same files every time. Original work of the team.
"""
import math
import os
import wave

import numpy as np

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def env_exp(t, tau):
    return np.exp(-t / tau)


def onepole_lowpass(x, cutoff):
    a = math.exp(-2.0 * math.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def resonator(x, freqs, q):
    """Two-pole band-pass whose centre frequency can change per sample."""
    y = np.zeros_like(x)
    y1 = y2 = 0.0
    for i, v in enumerate(x):
        w = 2.0 * math.pi * freqs[i] / RATE
        r = math.exp(-w / (2.0 * q))
        out = (1.0 - r) * v + 2.0 * r * math.cos(w) * y1 - r * r * y2
        y2, y1 = y1, out
        y[i] = out
    return y


def write(name, samples, peak_db):
    samples = samples / (np.max(np.abs(samples)) + 1e-9) * (10 ** (peak_db / 20.0))
    fade = int(0.12 * RATE)
    samples[-fade:] *= np.linspace(1.0, 0.0, fade)
    data = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    path = os.path.normpath(os.path.join(OUT, name))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print("wrote", path, f"{len(samples) / RATE:.2f} s")


def hull_impact(rng):
    dur = 3.0
    t = np.arange(int(dur * RATE)) / RATE
    out = np.zeros_like(t)

    # 1. The crack of the strike: a very short, bright noise burst.
    crack = rng.standard_normal(t.size) * env_exp(t, 0.006)
    out += 0.9 * np.diff(crack, prepend=0.0) * 3.0

    # 2. The thud through the frame: a falling low tone, slightly overdriven.
    f = 38.0 + 34.0 * env_exp(t, 0.09)
    phase = 2.0 * np.pi * np.cumsum(f) / RATE
    thud = np.sin(phase) + 0.35 * np.sin(2.0 * phase)
    out += 1.1 * np.tanh(2.2 * thud * env_exp(t, 0.32))

    # 3. The hull rings: inharmonic partials of a struck metal plate, low ones long.
    base = 97.0
    for k, ratio in enumerate([1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.16, 3.50, 4.15, 5.40, 6.21, 7.83]):
        freq = base * ratio * (1.0 + rng.uniform(-0.004, 0.004))
        tau = 1.5 / (1.0 + 0.55 * k)
        amp = 0.32 / (1.0 + 0.35 * k)
        beat = 1.0 + 0.04 * np.sin(2.0 * np.pi * rng.uniform(0.5, 2.0) * t)
        out += amp * beat * np.sin(2.0 * np.pi * freq * t + rng.uniform(0, 2 * np.pi)) * env_exp(t, tau)

    # 4. Structural rumble: low, dark noise that dies away.
    rumble = onepole_lowpass(rng.standard_normal(t.size), 140.0)
    out += 2.4 * rumble * env_exp(t, 0.7)

    # 5. The groan of the frame settling: resonant noise sliding in pitch, 0.5 s in.
    groan_env = np.clip((t - 0.45) / 0.5, 0, 1) * np.clip((2.7 - t) / 1.4, 0, 1)
    sweep = 210.0 + 70.0 * np.sin(2.0 * np.pi * 0.45 * t) + 40.0 * np.sin(2.0 * np.pi * 1.7 * t)
    groan = resonator(rng.standard_normal(t.size) * 0.6, sweep, 18.0)
    out += 0.55 * groan * groan_env / (np.max(np.abs(groan)) + 1e-9)

    # 6. Loose bits rattling down: small metallic ticks, fewer and quieter later.
    for _ in range(14):
        at = rng.uniform(0.12, 1.9)
        n = int(0.05 * RATE)
        i0 = int(at * RATE)
        if i0 + n >= t.size:
            continue
        tt = np.arange(n) / RATE
        tick = np.sin(2.0 * np.pi * rng.uniform(1800, 4200) * tt) * env_exp(tt, 0.006)
        out[i0:i0 + n] += rng.uniform(0.05, 0.16) * (1.2 - at / 2.0) * tick

    return out


def sparks(rng):
    dur = 1.3
    t = np.arange(int(dur * RATE)) / RATE
    out = np.zeros_like(t)

    # The arc: a harsh mains buzz with noise, for the first moment.
    buzz = np.sign(np.sin(2.0 * np.pi * 120.0 * t)) * 0.5 + np.sin(2.0 * np.pi * 240.0 * t) * 0.3
    arc_env = np.clip(t / 0.005, 0, 1) * env_exp(t, 0.09)
    out += 0.35 * (buzz + 0.8 * rng.standard_normal(t.size)) * arc_env

    # Crackles: many tiny pops, densest at the start.
    at = 0.0
    while at < dur - 0.03:
        at += rng.exponential(0.006 + 0.08 * (at / dur) ** 1.5)
        n = int(rng.uniform(0.002, 0.014) * RATE)
        i0 = int(at * RATE)
        if i0 + n >= t.size:
            break
        pop = np.diff(rng.standard_normal(n + 1)) * env_exp(np.arange(n) / RATE, n / RATE / 3.0)
        out[i0:i0 + n] += rng.uniform(0.2, 1.0) * (1.0 - at / dur) ** 1.2 * pop

    return out


def main():
    write("hull_impact.wav", hull_impact(np.random.default_rng(2126)), -1.0)
    write("sparks.wav", sparks(np.random.default_rng(676767)), -4.0)


if __name__ == "__main__":
    main()
