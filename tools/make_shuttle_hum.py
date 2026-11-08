#!/usr/bin/env python3
"""Make assets/audio/shuttle_hum.wav: the shuttle cabin's engine drone under the ending film.

A seamless 8-second loop: a low engine tone with a slow beat, a soft rumble (filtered
noise, crossfaded so the loop has no seam) and a faint air-vent hiss. Run: python3 tools/make_shuttle_hum.py
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
SECONDS = 8  # every tone below fits a whole number of cycles in this, so the loop is seamless
OUT = Path(__file__).resolve().parent.parent / "assets/audio/shuttle_hum.wav"


def lowpassed_noise(n: int, cutoff: float, rng: random.Random) -> list[float]:
    a = 1.0 - math.exp(-2 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for _ in range(n):
        y += a * (rng.uniform(-1, 1) - y)
        out.append(y)
    peak = max(abs(v) for v in out) or 1.0
    return [v / peak for v in out]


def looped(sig: list[float], fade: int) -> list[float]:
    """Crossfade the tail into the head so the end runs straight back into the start."""
    body = sig[: len(sig) - fade]
    for i in range(fade):
        w = i / fade
        body[i] = body[i] * w + sig[len(sig) - fade + i] * (1 - w)
    return body


def main() -> None:
    rng = random.Random(2126)
    n = RATE * SECONDS
    fade = RATE // 2
    rumble = looped(lowpassed_noise(n + fade, 90, rng), fade)
    hiss = looped(lowpassed_noise(n + fade, 2400, rng), fade)
    frames = bytearray()
    for i in range(n):
        t = i / RATE
        beat = 0.75 + 0.25 * math.sin(2 * math.pi * t / 4)  # swells every 4 s
        tone = (math.sin(2 * math.pi * 55 * t) * 0.5 + math.sin(2 * math.pi * 110.25 * t) * 0.25
                + math.sin(2 * math.pi * 165 * t) * 0.08)
        v = tone * 0.42 * beat + rumble[i] * 0.45 + hiss[i] * 0.05
        frames += struct.pack("<h", int(max(-1.0, min(1.0, v * 0.8)) * 32767))
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))
    print(f"wrote {OUT.name}: {SECONDS}s loop")


if __name__ == "__main__":
    main()
