#!/usr/bin/env python3
"""Render the base footage for Back2Earth's opening story (41.2 s). Owner: D.

The game doesn't play this directly: the team edited it (voices added, retimed) into
the final cut, which lives in the game as assets/video/intro.ogv + assets/audio/intro.ogg
(see README "Opening story"). Use this to re-render the base for a new edit.

    pip install pillow numpy scipy     # and ffmpeg with libtheora + libvorbis on PATH
    python3 tools/make_intro.py                    # classic suit + soundtrack + timing
    python3 tools/make_intro.py --suits classic hazard nebula mint
    python3 tools/make_intro.py --preview DIR      # key frames as PNGs (classic only)
    python3 tools/make_intro.py --export-godot     # art + data for the in-game film

--export-godot writes assets/intro/ and data/intro_film.json for scripts/ui/intro_film.gd, which draws the
film live in Godot (crisp at any size) instead of playing a video: the static
backgrounds and sprites as PNGs, and everything this script picks at random
(stars, air, debris, sparks, camera shake) as numbers, so both draw the same film.

Writes to art_source/intro_base/ (git-ignored; never touches the game's copy)
    intro_<suit>.ogv          640x360, 30 fps, no audio track
    intro_soundtrack.ogg      music and effects, no voices
    intro_timing.json         film length and when each caption starts/ends

Voice-over: nothing in the soundtrack plays under the spoken lines (effects are left
out and the rest is turned down), so recorded voices sit on top cleanly when editing.

Four astronauts, one per suit: Johnny (the player) wears the suit they picked; Aaron,
who pulls him to safety, wears the in-game crewmate's suit (SUIT_PREFERENCE in
scripts/interactables/crewmate.gd); Kien is pulled out into space; Dhan reaches the
safe side of the barrier first and waits, facing back toward the rescue.

Beats (script by the team):
  0-3.2     THE YEAR 2126, slowly dissolving into space
  2-5.2     the ship cruises past stars and small, far-off planets
  5.2-9     cabin: four crew asleep; monitor: MARS SPACE STATION / REPAIRS MISSION: SUCCESS /
            RETURNING HOME
  9-11.4    dashboard: nav map, DISTANCE TO EARTH 676,767 MI
  11.4-19.3 Kien wakes ("Real food. Finally."), impact, lights fail, red alarm,
            "Collision detected. Evacuate now.", crew unbuckle and hurry aft
  19.3-24.2 corridor: Dhan stops beyond the barrier and looks back; the second impact
            tears the hull open; Kien is pulled out (*Sucked out of the ship*),
            Johnny reaches and misses
  24.2-27.2 outside: the same ship, breached; Kien tumbles away. Silence.
  27.2-41.2 Aaron pulls Johnny through the bulkhead, door slams, breathing, MAIN POWER
            OFFLINE; Johnny turns to Aaron: "That was a close one! We need to fix power
            first. Then find Dhan." All three then enter the cabin; fade to black.
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy import signal as sps

ROOT = Path(__file__).resolve().parent.parent
W, H = 320, 180          # art pixels; the video is 2x (640x360)
FPS = 30
LB = 16                  # top letterbox bar height
LB_BOTTOM = 20           # bottom bar (captions, up to two lines)
FEET = 131               # floor line for standing crew (cabin + corridor)
SUITS = ["classic", "hazard", "nebula", "mint"]
SUIT_PREFERENCE = ["hazard", "mint", "nebula", "classic"]   # keep in sync with crewmate.gd
SR = 22050

# --- Timeline (seconds). Retime here; captions and voice cues are separate below. --------
T_YEAR_IN = 0.3          # "THE YEAR 2126" starts to appear
T_EXT_IN = 2.0           # ...and starts dissolving into space
T_EXT_FULL = 3.2         # space shot fully up
T_CABIN_A = 5.2          # crew asleep, monitor types
T_NAV = 9.0              # dashboard insert
T_CABIN_B = 11.4         # back in the cabin
T_WAKE = 11.7            # front-seat crewmate wakes
T_IMPACT = 14.7          # first impact
T_STAND = 17.3           # restraints off, everyone up
T_WALK = 17.7            # hurrying aft
T_CORR = 19.3            # corridor
T_HIT2 = 21.4            # second impact, breach
T_OUT = 24.2             # outside, silence
T_SEAL = 27.2            # pulled through the bulkhead
LENGTH = 41.2
T_FADE_OUT = LENGTH - 0.4  # last caption done; fade to black, then gameplay
SEAL_OFF = T_SEAL - 19.0  # the seal shot keeps its original 19.0-30.0 clock + this

# start, end, speaker, line, style, caption id (for lining up voice-over when editing).
# Style "action" is a stage direction: shown, but the soundtrack isn't cleared for it.
CAPTIONS = [
    (12.2, 14.5, "KIEN:", "REAL FOOD. FINALLY.", "crew", "crew_1"),
    (15.9, 19.4, "SYSTEM:", "COLLISION DETECTED. EVACUATE NOW.", "system", "system_1"),
    (21.7, 24.2, "KIEN:", "*SUCKED OUT OF THE SHIP*", "action", "kien_1"),
    (33.6, 37.6, "JOHNNY:", "THAT WAS A CLOSE ONE! WE NEED TO FIX POWER FIRST. THEN FIND DHAN.", "crew", "crew_2"),
]
JOHNNY_TURNS = 33.6      # Johnny turns to face Aaron as he starts talking
CPS = 30.0               # caption typing speed (chars per second)
MONITOR_LINES = [(5.6, "MARS SPACE STATION"), (6.45, "REPAIRS MISSION:"), (7.9, "RETURNING HOME")]
SUCCESS_AT = 7.2         # "SUCCESS" lights up, glowing green, after line 2
MONITOR_CPS = 26.0
DISTANCE_MI = 676767     # nav dashboard readout
FLICKER = [(24.0, 24.08), (24.16, 24.22), (24.35, 24.7), (24.76, 24.8),
           (24.9, 26.4), (26.47, 26.52), (26.6, 30.0)]   # terminal on-times (seal-shot clock)

# --- Palette (PICO-8 based, like the game) -------------------------------------------
SPACE = (5, 6, 20)
NAVY = (29, 43, 83)
NAVY_D = (22, 32, 64)
NAVY_L = (40, 56, 104)
STEEL_D = (40, 44, 64)
STEEL = (58, 56, 72)
STEEL_L = (95, 92, 112)
STEEL_LL = (126, 126, 140)
WHITE = (255, 241, 232)
GRAY = (194, 195, 199)
CYAN = (61, 240, 255)
BLUE = (41, 173, 255)
AMBER = (255, 163, 0)
YELLOW = (255, 236, 39)
RED = (255, 0, 77)
GREEN = (0, 228, 54)
INK = (10, 10, 14)

# --- 5x7 pixel font -------------------------------------------------------------------
FONT = {
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01110 10001 10000 10000 10000 10001 01110", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01110 10001 10000 10111 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "01110 00100 00100 00100 00100 00100 01110", "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 10001 11001 10101 10011 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11111 00010 00100 00010 00001 10001 01110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    ".": "00000 00000 00000 00000 00000 01100 01100", ",": "00000 00000 00000 00000 01100 00100 01000",
    ":": "00000 01100 01100 00000 01100 01100 00000", "!": "00100 00100 00100 00100 00100 00000 00100",
    "?": "01110 10001 00001 00010 00100 00000 00100", "-": "00000 00000 00000 11111 00000 00000 00000",
    "'": "00100 00100 01000 00000 00000 00000 00000", " ": "00000 00000 00000 00000 00000 00000 00000",
    "_": "00000 00000 00000 00000 00000 00000 11111", "/": "00001 00010 00010 00100 01000 01000 10000",
    "*": "00000 00100 10101 01110 10101 00100 00000",
}
GLYPHS = {k: np.array([[c == "1" for c in row] for row in v.split()]) for k, v in FONT.items()}


def text_w(s: str) -> int:
    return 6 * len(s) - 1 if s else 0


def _stamp(img, mask, x, y, color):
    h, w = mask.shape
    ih, iw = img.shape[:2]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(iw, x + w), min(ih, y + h)
    if x0 >= x1 or y0 >= y1:
        return
    m = mask[y0 - y:y1 - y, x0 - x:x1 - x]
    img[y0:y1, x0:x1][m] = color


def draw_text(img, x, y, s, color, shadow=None):
    for i, ch in enumerate(s.upper()):
        g = GLYPHS.get(ch)
        if g is None:
            continue
        if shadow is not None:
            _stamp(img, g, x + 6 * i + 1, y + 1, shadow)
        _stamp(img, g, x + 6 * i, y, color)


def draw_text_big(img, x, y, s, color, k):
    """The same font with every pixel k x k."""
    for i, ch in enumerate(s.upper()):
        g = GLYPHS.get(ch)
        if g is not None:
            _stamp(img, np.kron(g, np.ones((k, k), bool)).astype(bool), x + 6 * k * i, y, color)


def glow_text(img, x, y, s, core, glow, a):
    """Text with a soft two-step halo (a = halo strength 0-1)."""
    pad = 3
    layer = np.zeros((7 + 2 * pad, text_w(s) + 2 * pad, 3), np.uint8)
    draw_text(layer, pad, pad, s, (255, 255, 255))
    m = layer[..., 0] > 0
    near = ndimage.binary_dilation(m, iterations=1) & ~m
    far = ndimage.binary_dilation(m, iterations=2) & ~m & ~near
    for mask, alpha in ((far, a * 0.45), (near, a)):
        for yy, xx in zip(*np.where(mask)):
            blend_px(img, x - pad + xx, y - pad + yy, glow, min(1.0, alpha))
    draw_text(img, x, y, s, core)


# --- Drawing helpers ------------------------------------------------------------------

def rect(img, x0, y0, x1, y1, color):
    ih, iw = img.shape[:2]
    x0, x1 = max(0, int(x0)), min(iw, int(x1))
    y0, y1 = max(0, int(y0)), min(ih, int(y1))
    if x0 < x1 and y0 < y1:
        img[y0:y1, x0:x1] = color


def blend_px(img, x, y, color, a):
    ih, iw = img.shape[:2]
    if 0 <= x < iw and 0 <= y < ih:
        img[y, x] = (img[y, x] * (1 - a) + np.array(color) * a).astype(np.uint8)


def blit(img, spr, x, y, clip=None):
    """Copy the opaque pixels of an RGBA sprite; partial alpha is blended."""
    h, w = spr.shape[:2]
    ih, iw = img.shape[:2]
    cx0, cy0, cx1, cy1 = clip if clip else (0, 0, iw, ih)
    x, y = int(round(x)), int(round(y))
    dx0, dy0 = max(cx0, x), max(cy0, y)
    dx1, dy1 = min(cx1, x + w), min(cy1, y + h)
    if dx0 >= dx1 or dy0 >= dy1:
        return
    s = spr[dy0 - y:dy1 - y, dx0 - x:dx1 - x]
    a = s[..., 3:4].astype(np.float32) / 255.0
    region = img[dy0:dy1, dx0:dx1].astype(np.float32)
    img[dy0:dy1, dx0:dx1] = (region * (1 - a) + s[..., :3] * a).astype(np.uint8)


def tint_color(c, m):
    if m is None:
        return c
    return tuple(int(min(255, c[i] * m[i])) for i in range(3))


def mul(img, m):
    return np.clip(img.astype(np.float32) * np.array(m, np.float32), 0, 255).astype(np.uint8)


BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def bayer(h, w):
    return np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]


def ease_out(u):
    u = min(1.0, max(0.0, u))
    return 1 - (1 - u) ** 2


def ease_io(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def lerp(a, b, u):
    return a + (b - a) * u


def shake(t, t0, dur, amp, seed=0):
    if not (t0 <= t < t0 + dur):
        return 0, 0
    a = amp * (1 - (t - t0) / dur)
    rng = np.random.default_rng(int(t * FPS) * 7 + seed)
    return int(round(rng.uniform(-a, a))), int(round(rng.uniform(-a, a)))


def view(img, x0, dx=0, dy=0):
    """Camera crop W wide starting at x0, shifted by a shake offset."""
    out = np.zeros((H, W, 3), np.uint8)
    x0 = int(round(x0)) + dx
    sx0, sx1 = max(0, x0), min(img.shape[1], x0 + W)
    if sx0 >= sx1:
        return out
    part = img[:, sx0:sx1]
    ox = sx0 - x0
    if dy > 0:
        out[dy:, ox:ox + part.shape[1]] = part[:H - dy]
    elif dy < 0:
        out[:H + dy, ox:ox + part.shape[1]] = part[-dy:]
    else:
        out[:, ox:ox + part.shape[1]] = part
    return out


# --- Planets --------------------------------------------------------------------------

def _noise3(lat, X, Y, Z):
    n = lat.shape[0]
    xi, yi, zi = np.floor(X).astype(int), np.floor(Y).astype(int), np.floor(Z).astype(int)
    xf, yf, zf = X - xi, Y - yi, Z - zi
    u, v, w = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf), zf * zf * (3 - 2 * zf)

    def c(dx, dy, dz):
        return lat[(xi + dx) % n, (yi + dy) % n, (zi + dz) % n]

    a = c(0, 0, 0) * (1 - u) + c(1, 0, 0) * u
    b = c(0, 1, 0) * (1 - u) + c(1, 1, 0) * u
    d = c(0, 0, 1) * (1 - u) + c(1, 0, 1) * u
    e = c(0, 1, 1) * (1 - u) + c(1, 1, 1) * u
    return (a * (1 - v) + b * v) * (1 - w) + (d * (1 - v) + e * v) * w


def _fbm(seed, X, Y, Z, octaves):
    lat = np.random.default_rng(seed).random((32, 32, 32))
    total, amp, norm, f = 0.0, 1.0, 0.0, 1.0
    for o in range(octaves):
        total = total + amp * _noise3(lat, X * f + o * 7.1, Y * f + o * 3.7, Z * f + o * 5.3)
        norm += amp
        amp *= 0.5
        f *= 2.0
    return total / norm


OCEAN = [(8, 18, 52), (16, 44, 112), (26, 80, 170), (44, 122, 212)]
LAND = [(6, 34, 22), (0, 92, 52), (0, 135, 81), (62, 178, 74)]
DESERT = [(52, 32, 22), (124, 78, 46), (171, 118, 66), (208, 160, 98)]
ICE = [(70, 82, 112), (168, 178, 200), (220, 226, 236), (255, 255, 255)]
CLOUD = [(60, 70, 104), (160, 170, 192), (222, 228, 238), (255, 255, 255)]
MOON = [(40, 40, 52), (95, 92, 112), (150, 150, 160), (210, 210, 216)]
MOON_D = [(28, 28, 38), (70, 68, 84), (112, 110, 124), (160, 160, 170)]
MARS = [(46, 16, 14), (120, 44, 28), (176, 80, 42), (222, 128, 76)]
MARS_D = [(30, 10, 10), (84, 30, 22), (132, 58, 34), (178, 96, 58)]
GAS_A = [(36, 26, 42), (104, 74, 84), (166, 126, 112), (218, 188, 156)]
GAS_B = [(28, 26, 54), (74, 66, 116), (124, 106, 156), (186, 166, 206)]
ICE_P = [(26, 46, 70), (60, 110, 140), (120, 180, 200), (200, 236, 240)]


def render_planet(R, kind="earth", lon=0.5, light=(-0.62, -0.5, 0.6), tilt=0.3):
    S = 2 * R + 6
    c = S / 2.0
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
    nx, ny = (xx - c) / R, (yy - c) / R
    rr = nx * nx + ny * ny
    inside = rr <= 1.0
    nz = np.sqrt(np.clip(1 - rr, 0, 1))
    ca, sa = math.cos(lon), math.sin(lon)
    X, Y, Z = nx * ca + nz * sa, ny, -nx * sa + nz * ca
    ct, st = math.cos(tilt), math.sin(tilt)  # tilt so the poles are not always on top
    Y, Z = Y * ct - Z * st, Y * st + Z * ct
    L = np.array(light) / np.linalg.norm(light)
    lam = nx * L[0] + ny * L[1] + nz * L[2]
    lvl = np.clip(lam * 1.3 + 0.2, 0, 0.999) * 4 + (bayer(S, S) - 0.5) * 0.9
    idx = np.clip(np.floor(lvl), 0, 3).astype(int)
    rgb = np.zeros((S, S, 3), np.float32)
    if kind == "earth":
        ln = _fbm(3, X * 2.0 + 9, Y * 2.0 + 9, Z * 2.0 + 9, 5)
        cn = _fbm(8, X * 2.6 + 4, Y * 5.5 + 4, Z * 2.6 + 4, 4)
        land = ln > 0.55
        desert = land & (ln > 0.63) & (np.abs(ny) < 0.5)
        ice = np.abs(Y) > 0.86
        cloud = cn > 0.6
        rgb[:] = np.array(OCEAN, np.float32)[idx]
        rgb[land] = np.array(LAND, np.float32)[idx][land]
        rgb[desert] = np.array(DESERT, np.float32)[idx][desert]
        rgb[ice] = np.array(ICE, np.float32)[idx][ice]
        rgb[cloud] = np.array(CLOUD, np.float32)[idx][cloud]
        rng = np.random.default_rng(11)
        city = land & ~cloud & (lam < -0.12) & (rng.random((S, S)) < 0.035)
        rgb[city] = (255, 214, 120)
    elif kind == "mars":
        mn = _fbm(41, X * 2.2 + 5, Y * 2.2 + 5, Z * 2.2 + 5, 4)
        rgb[:] = np.array(MARS, np.float32)[idx]
        dark = mn > 0.56
        rgb[dark] = np.array(MARS_D, np.float32)[idx][dark]
    elif kind == "gas":
        bn = _fbm(31, X * 1.5 + 3, Y * 1.5 + 3, Z * 1.5 + 3, 3)
        band = np.sin(Y * 10 + bn * 4) > 0.2
        rgb[:] = np.array(GAS_A, np.float32)[idx]
        rgb[band] = np.array(GAS_B, np.float32)[idx][band]
    elif kind == "ice":
        rgb[:] = np.array(ICE_P, np.float32)[idx]
    else:  # moon
        mn = _fbm(21, X * 2.5 + 2, Y * 2.5 + 2, Z * 2.5 + 2, 4)
        rgb[:] = np.array(MOON, np.float32)[idx]
        maria = mn > 0.56
        rgb[maria] = np.array(MOON_D, np.float32)[idx][maria]
    dist = np.sqrt(rr) * R
    edge_lit = (nx * L[0] + ny * L[1]) > -0.15
    out = np.zeros((S, S, 4), np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = np.where(inside, 255, 0)
    if kind == "earth":
        rim = inside & (dist > R - 1.6) & edge_lit
        out[rim, :3] = (0.5 * out[rim, :3] + 0.5 * np.array([140, 210, 255])).astype(np.uint8)
        ring = (dist > R) & (dist <= R + 1.7)
        out[ring & edge_lit] = (110, 190, 255, 255)
        out[ring & ~edge_lit] = (40, 70, 140, 120)
    return out


# --- Stars ------------------------------------------------------------------------------

def make_stars(n, w, h, seed):
    rng = np.random.default_rng(seed)
    return np.stack([rng.uniform(0, w, n), rng.uniform(0, h, n),
                     rng.choice([0, 0, 0, 1, 1, 2], n), rng.uniform(0, 6.28, n)], 1)


STAR_COLORS = [(64, 72, 112), (150, 160, 200), (255, 241, 232)]


def draw_stars(img, stars, t, offx=0.0, offy=0.0, wrap_w=None, clip=None):
    ih, iw = img.shape[:2]
    cx0, cy0, cx1, cy1 = clip if clip else (0, 0, iw, ih)
    ww = wrap_w or iw
    for sx, sy, b, ph in stars:
        x = int((sx + offx) % ww)
        y = int(sy + offy)
        if not (cx0 <= x < cx1 and cy0 <= y < cy1):
            continue
        b = int(b)
        if b == 2 and math.sin(t * 3 + ph) < -0.6:
            b = 1
        img[y, x] = STAR_COLORS[b]
        if b == 2 and ph > 5.6:  # a few bright crosses
            for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if cx0 <= x + ddx < cx1 and cy0 <= y + ddy < cy1:
                    img[y + ddy, x + ddx] = STAR_COLORS[1]


# --- Crew sprites ------------------------------------------------------------------------

class Astro:
    """One crew member: walk frames (art px) and drawing helpers."""

    def __init__(self, skin):
        sheet = np.asarray(Image.open(ROOT / f"assets/sprites/astronaut_{skin}.png").convert("RGBA"))
        a = sheet[::2, ::2].copy()  # back to art pixels
        fw = a.shape[1] // 6
        self.frames = [a[:, i * fw:(i + 1) * fw].copy() for i in range(6)]
        alpha = np.any(np.stack([f[..., 3] > 0 for f in self.frames]), 0)
        cols = np.where(alpha.any(0))[0]
        self.bx0, self.bx1 = int(cols[0]), int(cols[-1])
        self.h, self.w = self.frames[0].shape[:2]
        torso = self.frames[5][12:20].reshape(-1, 4)
        torso = torso[(torso[:, 3] > 0) & (torso[:, :3].astype(int).sum(1) > 200)]
        vals, counts = np.unique(torso[:, :3], axis=0, return_counts=True)
        self.color = tuple(int(v) for v in vals[counts.argmax()])
        self.dark = tuple(int(v * 0.55) for v in self.color)
        self.tiny = [self._tiny(p) for p in TINY]

    def frame(self, t_anim, walking, facing_left):
        f = self.frames[int(t_anim * 10) % 6] if walking else self.frames[5]
        return f[:, ::-1] if facing_left else f

    def draw(self, img, cx, feet, t_anim=0.0, walking=False, left=False, rows=None, rot=0, lift=0, clip=None,
             tint=None):
        """cx = visual centre; feet = y of the bottom pixel (or of `rows` cut-off)."""
        f = self.frame(t_anim, walking, left)
        if tint is not None:
            f = f.copy()
            f[..., :3] = mul(f[..., :3], tint)
        if rows is not None:
            f = f[:rows]
        mid = (self.bx0 + self.bx1) / 2.0
        if left:
            mid = self.w - 1 - mid
        if rot:
            f = np.rot90(f, rot)
            mid = f.shape[1] / 2.0
        top = feet - f.shape[0] + 1 - lift
        blit(img, f, cx - mid, top, clip)
        return top

    def arm(self, img, cx, top, length, left=False, tint=None):
        """Arm reaching forward from the shoulder; returns the hand tip x."""
        y = top + 14
        suit, glove = tint_color(self.color, tint), tint_color(GRAY, tint)
        if left:
            x1 = int(round(cx)) - 4
            x0 = x1 - length
            rect(img, x0, y, x1, y + 2, suit)
            rect(img, x0, y, x0 + 2, y + 2, glove)
            return x0
        x0 = int(round(cx)) + 4
        rect(img, x0, y, x0 + length, y + 2, suit)
        rect(img, x0 + length - 2, y, x0 + length, y + 2, glove)
        return x0 + length

    def _tiny(self, pattern):
        rows = pattern.split()
        out = np.zeros((len(rows), len(rows[0]), 4), np.uint8)
        cmap = {"o": INK, "H": self.color, "V": (14, 16, 30), "B": STEEL_L, "D": self.dark}
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in cmap:
                    out[y, x] = (*cmap[ch], 255)
        return out


TINY = [  # the lost crewmate, far away (big -> small)
    """..ooooo.. .oHHHHHo. oHHVVVVHo oHHVVVVHo oBHHHHHHo oBoHHHHHo .ooHHHHHo ..oHHHHHo
       ..oHDoDHo ..oHo.oHo ...o...o.""",
    """.oooo. oHHVVo oHHVVo oBHHHo oBHHHo .oHHHo .oHoHo ..o.o.""",
    """.HH. HVVH BHHH .HH. .H.H""",
]


def crew_for(player):
    """Who wears which suit: (survivor, lost, ahead). The survivor matches the in-game crewmate."""
    others = [s for s in SUIT_PREFERENCE if s != player]
    return others[0], others[1], others[2]


# --- Exterior ship ------------------------------------------------------------------------

def make_ship(s=1):
    """The ship, drawn at s art px per design px with 1 px outlines, so the close-up
    outside the breach is the same ship that flies through the opening."""
    im = Image.new("RGBA", (62 * s, 24 * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def P(pts):
        return [(x * s, y * s) for x, y in pts]

    def R(x0, y0, x1, y1, **kw):  # design-px box, inclusive
        d.rectangle([x0 * s, y0 * s, (x1 + 1) * s - 1, (y1 + 1) * s - 1], **kw)

    d.polygon(P([(12, 8), (22, 8), (16, 3)]), fill=STEEL_L, outline=INK)          # dorsal fin
    d.polygon(P([(12, 16), (22, 16), (15, 21)]), fill=STEEL_L, outline=INK)       # ventral fin
    R(4, 10, 9, 15, fill=STEEL_D, outline=INK)                                    # nozzle
    d.polygon(P([(8, 9), (38, 7), (50, 9), (57, 12), (50, 15), (38, 17), (8, 16)]), fill=GRAY, outline=INK)
    d.polygon(P([(9, 13), (54, 13), (50, 15), (38, 16), (9, 15)]), fill=STEEL_LL)
    if s > 1:  # panel seams, only visible up close
        for x in (16, 27, 35):
            d.line([(x * s, int(8.4 * s)), (x * s, 13 * s - 1)], fill=(160, 160, 170))
        d.line(P([(9, 15), (38, 16)]), fill=STEEL, width=1)
    d.line(P([(10, 9), (38, 8)]), fill=WHITE, width=max(1, s // 2))
    d.line(P([(14, 13), (40, 13)]), fill=RED, width=s)
    d.polygon(P([(43, 9), (50, 10), (54, 12), (43, 12)]), fill=BLUE)
    R(46, 10, 46, 10, fill=WHITE)
    for px in (19, 25, 31):
        R(px, 10, px + 1, 11, fill=BLUE)
    return np.asarray(im).copy()


def draw_engine(img, sx, sy, s, t):
    """Engine glow and trail behind a ship drawn at (sx, sy) with make_ship(s)."""
    for k in range(10 + 4 * (s - 1)):
        blend_px(img, int(sx + 2 * s - k * 3), int(sy + 12 * s), AMBER, 0.5 * (1 - k / (10 + 4 * (s - 1))))
        if s > 1:
            blend_px(img, int(sx + 2 * s - k * 3), int(sy + 12 * s + 1), AMBER, 0.35 * (1 - k / (10 + 4 * (s - 1))))
    fl = (4 + (int(t * FPS) % 3)) * s
    for k in range(fl):
        rect(img, int(sx + 3 * s - k), int(sy + 11 * s), int(sx + 4 * s - k), int(sy + 14 * s),
             AMBER if k > s else YELLOW)


def ringed_planet(R, ring_rx, ring_ry):
    """A small banded gas giant with a thin ring (RGBA sprite)."""
    body = render_planet(R, kind="gas", lon=0.7, tilt=0.25)
    S = body.shape[0]
    pad = ring_rx - S // 2 + 2
    out = np.zeros((S + 2 * max(0, pad), S + 2 * max(0, pad), 4), np.uint8)
    o = max(0, pad)
    c = out.shape[0] / 2.0
    ring = [(c + ring_rx * math.cos(a), c + ring_ry * math.sin(a) + 0.25 * ring_rx * math.cos(a) * 0.3)
            for a in np.linspace(0, 2 * math.pi, 220)]
    for x, y in ring:  # back half
        if y < c:
            out[int(y), int(x)] = (150, 132, 110, 255)
    m = body[..., 3] > 0
    out[o:o + S, o:o + S][m] = body[m]
    for x, y in ring:  # front half
        if y >= c:
            out[int(y), int(x)] = (200, 178, 146, 255)
    return out


# --- Static scenes --------------------------------------------------------------------------

CABIN_W = 420
ROLES = ("ahead", "survivor", "player", "lost")                      # rear -> front (facing right)
SEAT_X = {"ahead": 104, "survivor": 168, "player": 232, "lost": 296}
MONITOR = (112, 35, 322, 77)
NAVSCR = (341, 49, 409, 101)          # the nav screen at the front of the cabin
CAB_DOOR = (15, 69, 49, 132)          # door leaf to the corridor (aft)
PORTHOLES = (136, 200, 264)


def build_cabin():
    global PORT_MASK
    img = np.zeros((H, CABIN_W, 3), np.uint8)
    img[:] = SPACE
    rect(img, 0, 16, CABIN_W, 31, STEEL_D)
    rect(img, 0, 30, CABIN_W, 31, STEEL)
    for x0 in (60, 170, 270):
        rect(img, x0, 31, x0 + 40, 32, WHITE)
    rect(img, 0, 32, CABIN_W, 132, NAVY)
    for x in range(24, CABIN_W, 48):
        rect(img, x, 32, x + 1, 124, NAVY_D)
    rect(img, 0, 76, CABIN_W, 78, NAVY_L)
    rect(img, 0, 124, CABIN_W, 132, NAVY_D)
    for x in range(40, 330, 48):
        rect(img, x, 82, x + 1, 83, GREEN)
    yy, xx = np.mgrid[0:H, 0:CABIN_W]
    PORT_MASK = np.zeros((H, CABIN_W), bool)
    stars = make_stars(60, CABIN_W, H, 4)
    for px in PORTHOLES:  # little windows between the seats: just stars
        d2 = (xx - px) ** 2 + (yy - 92) ** 2
        img[d2 <= 49] = STEEL_L
        img[d2 <= 25] = SPACE
        PORT_MASK |= d2 <= 25
        rect(img, px - 3, 89, px - 1, 90, (60, 70, 110))
    glass = img.copy()
    draw_stars(glass, stars, 0)
    img[PORT_MASK] = glass[PORT_MASK]
    rect(img, 0, 132, CABIN_W, H, STEEL)
    rect(img, 0, 132, CABIN_W, 133, STEEL_L)
    for x in range(0, CABIN_W, 8):
        rect(img, x, 137, x + 1, H, (48, 46, 60))
    # Aft door to the corridor (the pods are further on, past the corridor).
    rect(img, 12, 66, 52, 132, STEEL_L)
    draw_cabin_door(img, 0.0)
    draw_text(img, 32 - text_w("CORRIDOR") // 2, 56, "CORRIDOR", AMBER)
    # Front: nav console and screen (screen contents drawn per frame).
    rect(img, 334, 40, 418, 108, STEEL_L)
    rect(img, 337, 43, 415, 105, STEEL)
    rect(img, NAVSCR[0] - 1, NAVSCR[1] - 1, NAVSCR[2] + 1, NAVSCR[3] + 1, INK)
    rect(img, 330, 106, 420, 132, STEEL)
    rect(img, 330, 106, 420, 108, STEEL_L)
    for i, x in enumerate(range(338, 414, 7)):
        rect(img, x, 113, x + 3, 115, (GREEN, AMBER, CYAN, RED)[i % 4])
    rect(img, 344, 120, 404, 122, STEEL_D)
    # Overhead monitor.
    rect(img, 140, 31, 143, MONITOR[1], STEEL)
    rect(img, 290, 31, 293, MONITOR[1], STEEL)
    mx0, my0, mx1, my1 = MONITOR
    rect(img, mx0, my0, mx1, my1, STEEL)
    rect(img, mx0 + 1, my0 + 1, mx1 - 1, my1 - 1, (20, 22, 34))
    rect(img, mx0 + 3, my0 + 3, mx1 - 3, my1 - 3, (5, 14, 20))
    # Seat backs, cushions, pedestals.
    for sx in SEAT_X.values():
        rect(img, sx - 15, 98, sx - 8, 126, STEEL)
        rect(img, sx - 14, 101, sx - 9, 125, (41, 60, 120))
        rect(img, sx - 14, 101, sx - 13, 125, (61, 90, 160))
        rect(img, sx - 14, 94, sx - 9, 99, STEEL)
        rect(img, sx - 15, 123, sx + 6, 127, STEEL)
        rect(img, sx - 14, 123, sx + 5, 124, (61, 90, 160))
        rect(img, sx - 7, 127, sx - 3, 132, STEEL_D)
    return img


def draw_cabin_door(img, u, m=None):
    """Aft door, u = how far open (0 shut, 1 open: the leaves slide into the wall)."""
    x0, y0, x1, y1 = CAB_DOOR
    half = (x1 - x0) // 2
    rect(img, x0, y0, x1, y1, tint_color((8, 10, 16), m))
    gap = int(round(half * u))
    if gap < half:
        rect(img, x0, y0, x0 + half - gap, y1, tint_color(STEEL, m))
        rect(img, x0 + half + gap, y0, x1, y1, tint_color(STEEL, m))
        rect(img, x0 + half - gap - 1, y0, x0 + half - gap, y1, tint_color(STEEL_D, m))
        rect(img, x0 + half + gap, y0, x0 + half + gap + 1, y1, tint_color(STEEL_D, m))
        if gap == 0:
            rect(img, x0 + 4, 80, x0 + 12, 92, tint_color(STEEL_D, m))
            rect(img, x1 - 12, 80, x1 - 4, 92, tint_color(STEEL_D, m))


def nav_point(u, p0, p1, p2):
    """Point u along a quadratic curve (the route from Mars to Earth)."""
    return ((1 - u) ** 2 * p0[0] + 2 * (1 - u) * u * p1[0] + u * u * p2[0],
            (1 - u) ** 2 * p0[1] + 2 * (1 - u) * u * p1[1] + u * u * p2[1])


NAV_SHIP_U = 0.9   # where the ship marker sits along the route (not to scale: "almost home")


def draw_nav_mini(img, t):
    """The small nav screen at the front of the cabin."""
    x0, y0, x1, y1 = NAVSCR
    rect(img, x0, y0, x1, y1, (4, 12, 18))
    for gx in range(x0 + 8, x1, 12):
        rect(img, gx, y0, gx + 1, y1, (10, 26, 34))
    p0, p1, p2 = (x0 + 7, y0 + 34), (x0 + 30, y0 + 4), (x1 - 8, y0 + 18)
    for k in range(40):
        u = k / 39
        if u > NAV_SHIP_U and k % 2:
            continue
        px, py = nav_point(u, p0, p1, p2)
        img[int(py), int(px)] = CYAN if u <= NAV_SHIP_U else (40, 110, 130)
    rect(img, int(p0[0]) - 1, int(p0[1]) - 1, int(p0[0]) + 2, int(p0[1]) + 2, (200, 80, 44))
    rect(img, int(p2[0]) - 2, int(p2[1]) - 2, int(p2[0]) + 2, int(p2[1]) + 2, BLUE)
    if int(t * 3) % 2 == 0:
        sx, sy = nav_point(NAV_SHIP_U, p0, p1, p2)
        rect(img, int(sx) - 1, int(sy) - 1, int(sx) + 2, int(sy) + 2, WHITE)
    label = f"{DISTANCE_MI:,} MI"
    draw_text(img, (x0 + x1) // 2 - text_w(label) // 2, y1 - 10, label, CYAN)


def draw_console(img, sx, t, m=None):
    rect(img, sx + 7, 117, sx + 18, 132, tint_color(STEEL, m))
    rect(img, sx + 7, 117, sx + 18, 118, tint_color(STEEL_L, m))
    if t < T_IMPACT:
        rect(img, sx + 8, 120, sx + 10, 121, GREEN if int(t * 2 + sx) % 3 else STEEL_D)
        rect(img, sx + 12, 120, sx + 14, 121, AMBER)
    rect(img, sx + 8, 124, sx + 17, 125, tint_color(STEEL_D, m))


CORR_DOOR = (144, 164)              # bulkhead frame x range
CORR_PANEL = (128, 113, 140, 125)   # emergency control
CORR_TERM = (50, 50, 118, 82)       # MAIN POWER OFFLINE terminal
BREACH = [(292, 41), (284, 52), (288, 64), (276, 78), (284, 92), (276, 106), (286, 120),
          (298, 131), (320, 131), (320, 41)]


def build_corridor():
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = SPACE
    rect(img, 0, 16, W, 41, STEEL_D)
    rect(img, 0, 27, W, 31, STEEL_L)
    rect(img, 0, 27, W, 28, STEEL_LL)
    for x in range(10, W, 30):
        rect(img, x, 25, x + 3, 33, STEEL)
    rect(img, 0, 40, W, 41, STEEL)
    rect(img, 0, 41, W, 132, NAVY)
    for x in range(20, W, 40):
        rect(img, x, 41, x + 3, 124, NAVY_L)
    rect(img, 0, 88, W, 90, NAVY_L)
    rect(img, 0, 124, W, 132, NAVY_D)
    rect(img, 0, 132, W, H, STEEL)
    rect(img, 0, 132, W, 133, STEEL_L)
    for x in range(0, W, 8):
        rect(img, x, 137, x + 1, H, (48, 46, 60))
    # Cabin door (left); the leaf is drawn per frame (draw_hatch).
    rect(img, 4, 72, 32, 132, STEEL_L)
    draw_text(img, 4, 62, "CABIN", AMBER)
    # Terminal frame (screen drawn per frame).
    tx0, ty0, tx1, ty1 = CORR_TERM
    rect(img, tx0, ty0, tx1, ty1, STEEL)
    rect(img, tx0 + 2, ty0 + 2, tx1 - 2, ty1 - 2, (8, 10, 16))
    rect(img, tx0 + 34, ty1, tx0 + 42, ty1 + 6, STEEL_D)
    # Emergency control panel.
    px0, py0, px1, py1 = CORR_PANEL
    rect(img, px0, py0, px1, py1, AMBER)
    for i in range(0, 14, 4):
        rect(img, px0 + i, py0, px0 + i + 2, py0 + 2, INK)
        rect(img, px0 + i, py1 - 2, px0 + i + 2, py1, INK)
    rect(img, px0 + 2, py0 + 2, px1 - 2, py1 - 2, STEEL_D)
    # Bulkhead frame.
    d0, d1 = CORR_DOOR
    rect(img, d0, 41, d0 + 4, 132, STEEL_L)
    rect(img, d1 - 4, 41, d1, 132, STEEL_L)
    rect(img, d0, 41, d1, 47, STEEL_L)
    for i in range(0, d1 - d0, 4):
        rect(img, d0 + i, 43, d0 + i + 2, 45, AMBER)
    return img


HATCH = (7, 75, 29, 132)
HATCH_OPEN = (37.6, 37.85)   # opens after Johnny finishes speaking
T_CABIN_ENTRY = 37.9
AHEAD_WAIT_X = 58.0
CABIN_ENTRY = {"ahead": (58.0, 0.0, 1.2), "survivor": (90.0, 0.22, 1.6), "player": (124.0, 0.44, 2.0)}


def hatch_open_amount(t):
    return ease_out(max(0.0, min(1.0, (t - HATCH_OPEN[0]) / (HATCH_OPEN[1] - HATCH_OPEN[0]))))


def draw_hatch(img, t):
    """Cabin hatch leaf (slides up). Takes film time."""
    x0, y0, x1, y1 = HATCH
    u = hatch_open_amount(t)
    rect(img, x0, y0, x1, y1, (8, 10, 16))
    bottom = int(round(y1 - u * (y1 - y0)))
    if bottom > y0:
        rect(img, x0, y0, x1, bottom, STEEL)
        rect(img, x0, bottom - 1, x1, bottom, STEEL_D)
        wy = 84 - (y1 - bottom)
        if wy + 10 > y0:
            rect(img, 13, max(y0, wy), 23, max(y0, wy + 10), STEEL_D)


def draw_hatch_light(img, t):
    """Window lamp in the cabin hatch before it opens."""
    u = hatch_open_amount(t)
    if u > 0:
        return
    if t < HATCH_OPEN[0]:
        col = (20, 120, 70)
    else:
        col = RED if int((t - T_HIT2) * 2.5) % 2 == 0 else (90, 0, 30)
    rect(img, 15, 86, 21, 92, col)


def draw_breach(img, t, m=None):
    """The torn hull at the corridor's far end. Space shows through, unlit."""
    img[BREACH_MASK] = BREACH_SKY_BASE[BREACH_MASK]
    sky = BREACH_SKY_BASE.copy()
    draw_stars(sky, BREACH_STARS, t)
    img[BREACH_MASK] = sky[BREACH_MASK]
    img[BREACH_EDGE] = tint_color(STEEL_LL, m)
    for x0, y0, x1, y1 in ((284, 52, 277, 49), (276, 78, 269, 82), (276, 106, 268, 103), (286, 120, 280, 125)):
        for k in range(8):
            u = k / 7
            blend_px(img, int(lerp(x0, x1, u)), int(lerp(y0, y1, u)), tint_color(GRAY, m), 1.0)


# --- Particles ---------------------------------------------------------------------------

def make_flow(t0, t1, rate, xr, yr, seed, vr=(60, 150)):
    rng = np.random.default_rng(seed)
    n = int((t1 - t0) * rate)
    return {"ts": rng.uniform(t0, t1, n), "x": rng.uniform(*xr, n), "y": rng.uniform(*yr, n),
            "v": rng.uniform(*vr, n), "ln": rng.integers(3, 8, n), "sz": rng.integers(1, 4, n)}


AIR1 = make_flow(T_HIT2, T_OUT, 80, (120, 300), (46, 128), 1)              # film time
DEB1 = make_flow(T_HIT2, T_HIT2 + 0.95, 60, (200, 290), (50, 128), 3, (140, 280))
AIR2 = make_flow(19.0, 22.4, 80, (10, 300), (46, 128), 2)                  # seal-shot clock
DEB2 = make_flow(19.0, 21.4, 14, (60, 300), (60, 128), 4, (120, 220))


def draw_flow(img, flow, t, debris, x_min=None):
    for ts, x0, y0, v, ln, sz in zip(flow["ts"], flow["x"], flow["y"], flow["v"], flow["ln"], flow["sz"]):
        dt = t - ts
        if dt < 0 or dt > 2.4:
            continue
        x = x0 + v * dt + 70 * dt * dt
        if x > W or (x_min is not None and x < x_min):
            continue
        xi, yi = int(x), int(y0 + (math.sin(ts * 9) * 4 * dt))
        if debris:
            rect(img, xi, yi, xi + int(sz), yi + int(sz), STEEL_LL if sz > 1 else GRAY)
        else:
            for k in range(int(ln)):
                blend_px(img, xi - k, yi, (175, 195, 225), 0.55 * (1 - k / ln))


SPARK_T = [T_IMPACT + d for d in (0.05, 0.9, 1.7, 2.5, 3.6, 4.4)]


def draw_sparks(img, t, ox, oy):
    for i, t0 in enumerate(SPARK_T):
        dt = t - t0
        if not 0 <= dt <= 0.7:
            continue
        rng = np.random.default_rng(40 + i)
        for _ in range(9):
            vx, vy = rng.uniform(-40, 40), rng.uniform(-10, 25)
            x = int(ox + vx * dt)
            y = int(oy + vy * dt + 180 * dt * dt)
            rect(img, x, y, x + 1, y + 1, YELLOW if rng.random() < 0.5 else AMBER)


# --- Shots -------------------------------------------------------------------------------------

def shot_exterior(t, cast):
    """0-5.2: the ship cruises past stars and small, far-off planets."""
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = SPACE
    draw_stars(img, EXT_STARS_FAR, t, offx=-3 * t, wrap_w=W)
    draw_stars(img, EXT_STARS_NEAR, t, offx=-8 * t, wrap_w=W)
    for spr, (x, y) in FAR_PLANETS:
        blit(img, spr, x - spr.shape[1] // 2, y - spr.shape[0] // 2)
    sx = lerp(-130, 150, (t - T_EXT_IN) / (T_CABIN_A - T_EXT_IN))
    sy = 66 + round(math.sin(t * 2.2))
    draw_engine(img, sx, sy, 2, t)
    blit(img, SHIP2, sx, sy)
    return img


def year_card(img, t):
    """THE YEAR 2126 over black; space fades up behind it, then it dissolves away."""
    if t < T_EXT_IN:
        k = 0.3 * ease_io((t - 0.6) / (T_EXT_IN - 0.6))
    else:
        k = lerp(0.3, 1.0, ease_io((t - T_EXT_IN) / (T_EXT_FULL - T_EXT_IN)))
    out = (img.astype(np.float32) * k).astype(np.uint8)
    text, kk = "THE YEAR 2126", 3
    tw = (6 * len(text) - 1) * kk
    layer = np.zeros_like(out)
    draw_text_big(layer, (W - tw) // 2, 80, text, WHITE, kk)
    th = np.repeat(np.repeat(bayer((H + 1) // 2, (W + 1) // 2), 2, 0), 2, 1)[:H, :W]  # 2x2 dither cells
    shown = layer.any(2) & (th < (t - T_YEAR_IN) / 0.8) & (th >= (t - T_EXT_IN) / 1.0)
    out[shown] = WHITE
    return out


def monitor_text(img, t):
    mx0, my0, mx1, my1 = MONITOR
    if t >= T_IMPACT:
        return
    for i, (t0, line) in enumerate(MONITOR_LINES):
        n = int(max(0.0, t - t0) * MONITOR_CPS)
        if n > 0:
            draw_text(img, mx0 + 8, my0 + 6 + 11 * i, line[:n], CYAN)
    if t >= SUCCESS_AT:  # "SUCCESS", glowing green
        x = mx0 + 8 + text_w(MONITOR_LINES[1][1] + " ") + 1
        pop = max(0.0, 1.0 - (t - SUCCESS_AT) / 0.5)
        glow = 0.45 + 0.2 * math.sin(2 * math.pi * 1.1 * (t - SUCCESS_AT)) + 0.4 * pop
        glow_text(img, x, my0 + 17, "SUCCESS", (150, 255, 170), GREEN, glow)
    last_t0, last = MONITOR_LINES[-1]
    done = last_t0 + len(last) / MONITOR_CPS
    if t > done and int(t * 2) % 2 == 0:
        cx = mx0 + 8 + text_w(last) + 3
        rect(img, cx, my0 + 28, cx + 5, my0 + 35, CYAN)


def monitor_alert(img, t):
    mx0, my0, mx1, my1 = MONITOR
    rect(img, mx0 + 3, my0 + 3, mx1 - 3, my1 - 3, (40, 4, 12))
    if int(t * 2.5) % 2 == 0:
        s = "! COLLISION DETECTED !"
        draw_text(img, (mx0 + mx1) // 2 - text_w(s) // 2, my0 + 17, s, RED)


def cabin_camera(t):
    if t < T_NAV:
        return lerp(0, 50, ease_io((t - T_CABIN_A) / (T_NAV - T_CABIN_A)))
    if t < T_IMPACT + 2.1:
        return 100
    return lerp(100, 0, ease_io((t - (T_IMPACT + 2.1)) / 1.9))


def cabin_light(t):
    """(room multiplier, crew multiplier); None = normal light."""
    t0 = T_IMPACT
    if t < t0 + 0.15:
        return None, None
    if t < t0 + 0.8:
        k = 0.55 if t0 + 0.35 <= t < t0 + 0.42 else 0.1
        return (k, k, k), (max(k, 0.2),) * 3
    k = min(1.0, (t - t0 - 0.8) / 0.2)
    pulse = 0.86 + 0.1 * math.sin(2 * math.pi * 1.6 * (t - t0 - 0.8))
    room = np.array([1.0, 0.4, 0.44]) * pulse * k + 0.1 * (1 - k)
    crew = np.array([1.0, 0.68, 0.7]) * pulse * k + 0.2 * (1 - k)
    return tuple(room), tuple(crew)


CABIN_RUN = 55.0                       # px/s hurrying aft
CAB_DOOR_OPEN = (T_WALK + 0.85, T_WALK + 1.15)


def shot_cabin(t, cast):
    img = CABIN_BG.copy()
    monitor_text(img, t)
    draw_nav_mini(img, t)
    if t >= CAB_DOOR_OPEN[0]:
        draw_cabin_door(img, ease_out((t - CAB_DOOR_OPEN[0]) / (CAB_DOOR_OPEN[1] - CAB_DOOR_OPEN[0])))
    room, crew = cabin_light(t)
    if room is not None:
        glass = img[PORT_MASK].copy()
        img = mul(img, room)
        img[PORT_MASK] = glass  # outside isn't lit by the alarm
        if t >= T_IMPACT + 0.8:
            monitor_alert(img, t)
            on = int(t * 3.2) % 2 == 0
            for bx in (120, 240, 360):
                rect(img, bx, 31, bx + 5, 34, (255, 40, 60) if on else (90, 10, 20))
    seated = t < T_STAND
    for role in ROLES:
        if not seated:
            break
        a, sx = cast[role], SEAT_X[role]
        asleep = t < (T_WAKE if role == "lost" else T_IMPACT)
        top = a.draw(img, sx, 124 + (1 if asleep else 0), rows=20, tint=crew)
        if role == "lost" and not asleep:
            rect(img, sx + 3, top + 6, sx + 5, top + 7, tint_color(CYAN, crew))  # nav screen in her visor
        if t < T_STAND - 0.2:  # harness
            for k in range(7):
                blend_px(img, sx + 3 - k, top + 12 + k, tint_color(AMBER, crew), 1.0)
            rect(img, sx, top + 15, sx + 2, top + 17, tint_color(GRAY, crew))
        if asleep and t >= T_CABIN_A + 0.2:  # floating z's
            ph = (t + {"ahead": 1.2, "survivor": 0.0, "player": 0.5, "lost": 0.9}[role]) % 1.6
            zx, zy = sx + 6 + int(ph * 3), top - 2 - int(ph * 8)
            for dy, row in enumerate(("1111", "..1.", ".1..", "1111")):
                for dx, ch in enumerate(row):
                    if ch == "1":
                        blend_px(img, zx + dx, zy + dy, GRAY, 0.9)
    for sx in SEAT_X.values():
        draw_console(img, sx, t, room)
    if not seated:
        for i, role in enumerate(ROLES):  # the rear seat goes first
            a, sx = cast[role], SEAT_X[role]
            t0 = T_WALK + 0.08 * i
            if t < t0:
                a.draw(img, sx, FEET, left=t >= T_STAND + 0.25, tint=crew)
            else:
                walk = t - t0
                x = sx - CABIN_RUN * walk
                clip = (CAB_DOOR[0], 0, CABIN_W, H) if x < CAB_DOOR[2] - 4 else None  # out through the door
                a.draw(img, x, FEET, t_anim=walk * 1.3, walking=True, left=True, tint=crew, clip=clip)
    if t >= T_IMPACT:
        draw_sparks(img, t, 232, 31)
    if T_IMPACT <= t < T_IMPACT + 0.067:  # impact flash
        img = (img.astype(np.float32) * 0.15 + 255 * 0.85).astype(np.uint8)
    dx, dy = shake(t, T_IMPACT, 0.9, 3, 1)
    return view(img, cabin_camera(t), dx, dy)


def build_nav():
    """Static parts of the dashboard close-up."""
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = (14, 16, 26)
    sx0, sy0, sx1, sy1 = NAV_SCREEN
    rect(img, sx0 - 4, sy0 - 4, sx1 + 4, sy1 + 4, STEEL_L)
    rect(img, sx0 - 2, sy0 - 2, sx1 + 2, sy1 + 2, STEEL)
    rect(img, sx0, sy0, sx1, sy1, (4, 12, 18))
    for gx in range(sx0 + 12, sx1, 16):
        rect(img, gx, sy0, gx + 1, sy1, (9, 26, 34))
    for gy in range(sy0 + 12, sy1, 16):
        rect(img, sx0, gy, sx1, gy + 1, (9, 26, 34))
    draw_text(img, sx0 + 6, sy0 + 5, "NAV // RETURN TO EARTH", CYAN)
    rect(img, sx0 + 6, sy0 + 14, sx1 - 6, sy0 + 15, (30, 90, 110))
    for spr, (x, y), name in ((NAV_MARS, NAV_P0, "MARS"), (NAV_EARTH, NAV_P2, "EARTH")):
        blit(img, spr, x - spr.shape[1] // 2, y - spr.shape[0] // 2)
        draw_text(img, x - text_w(name) // 2, y + spr.shape[0] // 2 + 2, name, (90, 170, 190))
    blit(img, NAV_MOON, NAV_P2[0] + 14, NAV_P2[1] - 12)
    # Dashboard strip under the screen.
    rect(img, 0, sy1 + 6, W, H, (22, 24, 36))
    rect(img, 0, sy1 + 6, W, sy1 + 7, STEEL)
    draw_text(img, 24, sy1 + 12, "HULL OK  O2 OK", GREEN)
    draw_text(img, W - 24 - text_w("COURSE EARTH"), sy1 + 12, "COURSE EARTH", CYAN)
    return img


NAV_SCREEN = (34, 22, 286, 134)
NAV_P0, NAV_P1, NAV_P2 = (70, 92), (150, 30), (250, 74)


def shot_nav(t):
    """9.0-11.4: the dashboard. The route from Mars, and how far is left."""
    lt = t - T_NAV
    img = NAV_BG.copy()
    sx0, sy0, sx1, sy1 = NAV_SCREEN
    for k in range(120):  # route: flown part solid, the rest dotted
        u = k / 119
        x, y = nav_point(u, NAV_P0, NAV_P1, NAV_P2)
        if u <= NAV_SHIP_U:
            rect(img, int(x), int(y), int(x) + 1, int(y) + 1, CYAN)
        elif k % 3 == 0:
            rect(img, int(x), int(y), int(x) + 1, int(y) + 1, (60, 140, 160))
    x, y = nav_point(NAV_SHIP_U, NAV_P0, NAV_P1, NAV_P2)
    if int(lt * 3) % 2 == 0:  # ship marker
        for dy in range(-2, 3):
            rect(img, int(x) - 2 + abs(dy), int(y) + dy, int(x) + 3 - abs(dy), int(y) + dy + 1, WHITE)
        r = 4 + int(lt * 6) % 4
        for a in np.linspace(0, 2 * math.pi, 24):
            blend_px(img, int(x + r * math.cos(a)), int(y + r * math.sin(a)), CYAN, 0.5)
    # Distance readout: rolls down to the figure, then holds.
    d = DISTANCE_MI + int(round(30 * (1 - ease_out(lt / 0.7)))) if lt < 0.7 else DISTANCE_MI
    label = "DISTANCE TO EARTH"
    draw_text(img, (sx0 + sx1) // 2 - text_w(label) // 2, sy1 - 31, label, (90, 170, 190))
    figure = f"{d:,} MI"
    fw = (6 * len(figure) - 1) * 2
    draw_text_big(img, (sx0 + sx1) // 2 - fw // 2, sy1 - 20, figure, WHITE, 2)
    for i, x0 in enumerate(range(140, 190, 8)):  # blinking dashboard lights
        on = (int(lt * 4) + i) % 3 != 0
        rect(img, x0, sy1 + 14, x0 + 4, sy1 + 17, (GREEN, AMBER, CYAN)[i % 3] if on else STEEL_D)
    if lt < 0.15:  # screen wakes up
        img = (img.astype(np.float32) * (0.3 + lt / 0.15 * 0.7)).astype(np.uint8)
    return img


def corridor_light(t):
    pulse = 0.88 + 0.1 * math.sin(2 * math.pi * 1.6 * t)
    return (1.0 * pulse, 0.42 * pulse, 0.46 * pulse), (1.0 * pulse, 0.7 * pulse, 0.72 * pulse)


def terminal_on(t):
    return any(a <= t < b for a, b in FLICKER)


def draw_terminal(img, t):
    tx0, ty0, tx1, ty1 = CORR_TERM
    if terminal_on(t):
        rect(img, tx0 + 2, ty0 + 2, tx1 - 2, ty1 - 2, (46, 6, 14))
        for i, s in enumerate(("MAIN POWER", "OFFLINE")):
            draw_text(img, (tx0 + tx1) // 2 - text_w(s) // 2, ty0 + 7 + 11 * i, s, RED)
        for x in range(tx0 - 6, tx1 + 6):  # red spill on the wall below
            for y in range(ty1 + 1, ty1 + 6):
                if (x + y) % 2 == 0:
                    blend_px(img, x, y, (120, 10, 30), 0.25)


def draw_slab(img, t):
    d0, d1 = CORR_DOOR
    if t < 21.4:
        bottom = 47
    else:
        bottom = int(lerp(47, 132, ease_out((t - 21.4) / 0.1) if t < 21.5 else 1.0))
    rect(img, d0 + 4, 41, d1 - 4, bottom, STEEL_L)
    rect(img, d0 + 9, 41, d0 + 11, bottom, STEEL)
    for i in range(0, d1 - d0 - 8, 4):
        rect(img, d0 + 4 + i, bottom - 4, d0 + 6 + i, bottom, AMBER)
    rect(img, d0 + 4, bottom - 1, d1 - 4, bottom, INK)


def draw_button(img, t):
    px0, py0, px1, py1 = CORR_PANEL
    btn = WHITE if 21.3 <= t < 21.5 else ((255, 30, 70) if t < 21.3 else (120, 0, 30))
    rect(img, px0 + 4, py0 + 4, px1 - 4, py1 - 4, btn)


# Corridor run-in: (x as the shot opens, x at the second impact). They come in from the
# cabin on the right, in the order they left it; the one in front is already well ahead.
CORR_RUN = {"survivor": (330, 170), "player": (362, 206.5), "lost": (400, 246.5)}
AHEAD_X0, AHEAD_V = 150, 82.0


def shot_breach(t, cast):
    """19.3-24.2: the 4th crewmate reaches the pods; second impact; one is pulled out."""
    room, crew = corridor_light(t)
    img = CORR_BG.copy()
    draw_slab(img, 0)
    draw_hatch(img, t)
    img = mul(img, room)
    draw_hatch_light(img, t)
    draw_button(img, 0.0)
    hit = t >= T_HIT2
    if hit:
        draw_breach(img, t, room)
    lc = t - T_CORR
    # Dhan clears the barrier, stops before the cabin, and looks back at the others.
    D = cast["ahead"]
    dx_ = max(AHEAD_WAIT_X, AHEAD_X0 - AHEAD_V * lc)
    dhan_walking = dx_ > AHEAD_WAIT_X
    D.draw(img, dx_, FEET, t_anim=lc * 1.4, walking=dhan_walking, left=dhan_walking, tint=crew)
    A, P, B = cast["survivor"], cast["player"], cast["lost"]
    run = min(lc, T_HIT2 - T_CORR) / (T_HIT2 - T_CORR)
    walk = min(lc, T_HIT2 - T_CORR) * 1.3
    to = 13.25 + (t - T_HIT2)  # the struggle keeps the original timings
    # Survivor: runs in, stumbles at the impact, braces by the door facing back.
    if not hit:
        A.draw(img, lerp(*CORR_RUN["survivor"], run), FEET, t_anim=walk, walking=True, left=True, tint=crew)
    else:
        A.draw(img, 170, FEET, left=to < 13.4, lift=-1 if to < 13.6 else 0, tint=crew)
    # Player: lunges toward the lost crewmate, reaches, misses.
    px, p_left = lerp(*CORR_RUN["player"], run), True
    if hit:
        p_left = to < 13.3
        if to < 13.45:
            px = 206.5
        elif to < 14.05:
            px = lerp(206.5, 243, ease_out((to - 13.45) / 0.6))
        else:
            px = 243 + 7 * (to - 14.05) / 1.95
    p_top = P.draw(img, px, FEET, t_anim=walk, walking=not hit, left=p_left, tint=crew)
    if 13.5 <= to < 15.4:
        P.arm(img, px, p_top, 9, tint=crew)
    # Lost crewmate: jolted back, then pulled out through the breach.
    bx, rot, lift = lerp(*CORR_RUN["lost"], run), 0, 0
    if hit:
        if to < 13.4:
            bx = lerp(246.5, 262, ease_out((to - 13.25) / 0.15))
        else:
            bx = 262 + 0.5 * 33 * (to - 13.4) ** 2
        lift = int(min(6, max(0, (to - 14.2) * 6)))
        if to >= 14.9:
            rot = int((to - 14.9) / 0.22) % 4 + 1
    b_top = B.draw(img, bx, FEET, t_anim=walk, walking=not hit, left=True, rot=rot % 4, lift=lift, tint=crew)
    if 13.5 <= to < 14.9:
        B.arm(img, bx, b_top, 7, left=True, tint=crew)
    if hit:
        draw_flow(img, AIR1, t, False)
        draw_flow(img, DEB1, t, True)
    if T_HIT2 <= t < T_HIT2 + 0.067:
        img = (img.astype(np.float32) * 0.2 + 255 * 0.8).astype(np.uint8)
    dx, dy = shake(t, T_HIT2, 0.9, 3, 2)
    return view(img, 0, dx, dy)


# The breach as seen from outside, in make_ship(4) pixels: over the corridor, aft of the windows.
OUT_SCALE = 4
OUT_HOLE = [(140, 33), (147, 30), (153, 34), (160, 32), (163, 40), (159, 47), (162, 53),
            (152, 55), (146, 51), (139, 53), (137, 45), (141, 40)]


def shot_outside(t, cast):
    """24.2-27.2: the same ship from outside, breached; the lost crewmate tumbles away. Silence."""
    lt = t - T_OUT
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = SPACE
    draw_stars(img, EXT_STARS_FAR, t)
    draw_stars(img, EXT_STARS_NEAR, t)
    spr, (gx, gy) = FAR_PLANETS[0]
    blit(img, spr, 276 - spr.shape[1] // 2, 40 - spr.shape[0] // 2)
    ox, oy = -44 + 3 * lt, 28
    draw_engine(img, ox, oy, OUT_SCALE, t)
    blit(img, SHIP4, ox, oy)
    # The hole: dark inside with the corridor's red emergency light, torn edges.
    hole = Image.new("L", (W, H), 0)
    ImageDraw.Draw(hole).polygon([(ox + x, oy + y) for x, y in OUT_HOLE], fill=255)
    hm = np.asarray(hole) > 0
    pulse = 0.86 + 0.1 * math.sin(2 * math.pi * 1.6 * t)
    img[hm] = tint_color((90, 12, 28), (pulse,) * 3)
    inner = ndimage.binary_erosion(hm, iterations=3)
    img[inner] = tint_color((150, 20, 44), (pulse,) * 3)
    edge = ndimage.binary_dilation(hm, iterations=1) & ~hm
    img[edge] = STEEL_LL
    for x0, y0, x1, y1 in ((140, 33, 134, 28), (160, 32, 166, 27), (162, 53, 168, 58), (139, 53, 133, 57)):
        for k in range(6):  # bent plates
            u = k / 5
            blend_px(img, int(ox + lerp(x0, x1, u)), int(oy + lerp(y0, y1, u)), GRAY, 1.0)
    hx, hy = ox + 150, oy + 43
    # Air and debris streaming out with her.
    rng = np.random.default_rng(9)
    for _ in range(26):
        vx, vy = rng.uniform(10, 46), rng.uniform(4, 30)
        dt = (lt + rng.uniform(0, 1.6)) % 1.6
        x, y = hx + vx * dt, hy + vy * dt
        if rng.random() < 0.5:
            rect(img, int(x), int(y), int(x) + 1, int(y) + 1, GRAY)
        else:
            for k in range(3):
                blend_px(img, int(x) - k, int(y), (175, 195, 225), 0.5 * (1 - k / 3))
    # Her: tumbling away, getting smaller.
    u = ease_out(lt / 3.0)
    x, y = lerp(hx + 4, 262, u), lerp(hy + 6, 146, u)
    B = cast["lost"]
    size = 0 if lt < 1.0 else (1 if lt < 2.1 else 2)
    tiny = np.rot90(B.tiny[size], int(lt / 0.4) % 4)
    blit(img, tiny, x - tiny.shape[1] / 2, y - tiny.shape[0] / 2)
    return img


def shot_seal(tf, cast):
    """27.2-41.2: rescue, barrier seals, Johnny speaks, all three enter the cabin.
    Inside, t runs on the original 19.0-28.0 clock (t = film time - SEAL_OFF)."""
    t = tf - SEAL_OFF
    room, crew = corridor_light(t)
    img = CORR_BG.copy()
    draw_slab(img, t)
    draw_hatch(img, tf)
    img = mul(img, room)
    draw_hatch_light(img, tf)  # cabin stays closed until the crew is ready
    slammed = t >= 21.45
    if slammed:  # the breach side goes dark behind the door
        dark = min(0.6, (t - 21.5) / 1.5 * 0.6) if t > 21.5 else 0.0
        img[:, CORR_DOOR[1]:] = mul(img[:, CORR_DOOR[1]:], (1 - dark,) * 3)
    draw_breach(img, t, room)
    if slammed and t > 21.5:
        dark = min(0.6, (t - 21.5) / 1.5 * 0.6)
        img[BREACH_MASK] = mul(img[BREACH_MASK][None], (1 - dark * 0.7,) * 3)[0]
    draw_button(img, t)
    draw_terminal(img, t)
    A, P = cast["survivor"], cast["player"]
    breath = ((t - 21.8) % 3.2) if t >= 21.8 else 0.0
    bob = 1 if 0.2 < breath < 1.1 else 0
    if tf < T_CABIN_ENTRY:
        cast["ahead"].draw(img, AHEAD_WAIT_X, FEET, left=False, lift=bob, tint=crew)
    if tf >= T_CABIN_ENTRY:
        draw_cabin_entry(img, tf, cast, crew)
    elif t < 19.65:  # A runs back for the player; the player slides toward the breach
        ax = lerp(170, 226, ease_io((t - 19.0) / 0.65))
        a_top = A.draw(img, ax, FEET, t_anim=t, walking=True, tint=crew)
        pxx = 250 + 6 * (t - 19.0)
        p_top = P.draw(img, pxx, FEET, left=t >= 19.35, tint=crew)
        if t >= 19.35:
            A.arm(img, ax, a_top, 10, tint=crew)
        if t >= 19.4:
            P.arm(img, pxx, p_top, 10, left=True, tint=crew)
    elif t < 21.0:  # hands joined; A drags the player through the bulkhead
        u = ease_io((t - 19.7) / 1.3) if t >= 19.7 else 0.0
        ax, pxx = lerp(226, 90, u), lerp(254, 118, u)
        a_top = A.draw(img, ax, FEET, t_anim=-(t - 19.7), walking=t >= 19.7, tint=crew)
        p_top = P.draw(img, pxx, FEET, left=True, lift=1 if 19.8 < t < 20.8 else 0, tint=crew)
        A.arm(img, ax, a_top, 10, tint=crew)
        P.arm(img, pxx, p_top, 10, left=True, tint=crew)
    else:  # safe side: hit the control, breathe, look at the terminal, face the door
        ax, pxx = 90, 118
        a_left = 24.3 <= t < 25.3                                         # Aaron reads the terminal
        p_left = 24.3 <= t < 24.9 or t >= JOHNNY_TURNS - SEAL_OFF         # ...then they face each other
        p_walk = 24.9 <= t < 25.3
        if t >= 24.9:
            pxx = lerp(118, 124, min(1.0, (t - 24.9) / 0.4))
        A.draw(img, ax, FEET, left=a_left, lift=bob, tint=crew)
        p_top = P.draw(img, pxx, FEET, t_anim=t, walking=p_walk, left=p_left, lift=bob, tint=crew)
        if 21.15 <= t < 21.45:
            P.arm(img, pxx, p_top, 10, tint=crew)
    if not slammed:
        draw_flow(img, AIR2, t, False)
        draw_flow(img, DEB2, t, True)
    else:
        draw_flow(img, AIR2, t, False, x_min=CORR_DOOR[1])
        dt = t - 21.45
        if dt < 0.5:  # dust where the door hits the floor
            for k in range(6):
                for side in (-1, 1):
                    x = int((CORR_DOOR[0] + CORR_DOOR[1]) / 2 + side * (6 + k * 3 + dt * 30))
                    blend_px(img, x, int(130 - k % 2 - dt * 6), GRAY, 0.7 * (1 - dt * 2))
    if t >= 21.6:  # helmet vignette, breathing with the player
        strength = min(0.5, (t - 21.6) * 0.5) + (0.04 if bob else 0.0)
        img = (img.astype(np.float32) * VIGNETTE(strength)).astype(np.uint8)
    dx, dy = shake(t, 21.47, 0.35, 2, 3)
    return view(img, 0, dx, dy)


def cabin_entry_x(role, film_time):
    x, delay, duration = CABIN_ENTRY[role]
    progress = max(0.0, min(1.0, (film_time - T_CABIN_ENTRY - delay) / duration))
    return lerp(x, -14.0, progress)


def draw_cabin_entry(img, film_time, cast, crew):
    for role in ("ahead", "survivor", "player"):
        _, delay, _ = CABIN_ENTRY[role]
        walking = film_time >= T_CABIN_ENTRY + delay
        x = cabin_entry_x(role, film_time)
        if x <= -10:
            continue
        clip = (HATCH[0], 0, W, H) if x < HATCH[2] + 5 else None
        cast[role].draw(img, x, FEET, t_anim=film_time * 1.4, walking=walking,
                        left=walking, tint=crew, clip=clip)


def _vignette_base():
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xx - W / 2) / (W * 0.58)) ** 2 + ((yy - H / 2) / (H * 0.62)) ** 2)
    return np.clip((d - 0.55) / 0.45, 0, 1)


_VIG = _vignette_base()


def VIGNETTE(strength):  # noqa: N802 (reads like a constant-ish helper)
    return (1 - strength * _VIG)[..., None]


# --- Captions and frame assembly -----------------------------------------------------------

def caption_lines(who, line):
    """Speaker + line as one or two rows that fit the frame; prefers breaking after
    a sentence. Returns [(speaker_or_empty, text), ...]."""
    max_w = W - 12
    if text_w(f"{who} {line}") <= max_w:
        return [(who, line)]
    words = line.split(" ")
    best = None
    for i in range(1, len(words)):
        a, b = " ".join(words[:i]), " ".join(words[i:])
        wa, wb = text_w(f"{who} {a}"), text_w(b)
        if max(wa, wb) > max_w:
            continue
        score = max(wa, wb) - (1000 if a[-1] in ".!?" else 0)
        if best is None or score < best[0]:
            best = (score, a, b)
    if best is None:
        return [(who, line)]
    return [(who, best[1]), ("", best[2])]


def draw_captions(frame, t):
    for t0, t1, who, line, style, _vo in CAPTIONS:
        if not t0 <= t < t1:
            continue
        n = int((t - t0) * CPS)
        rows = caption_lines(who, line)
        top = H - LB_BOTTOM + (LB_BOTTOM - (9 * len(rows) - 2)) // 2
        for k, (spk, text) in enumerate(rows):
            full = f"{spk} {text}" if spk else text
            x = W // 2 - text_w(full) // 2
            y = top + 9 * k
            if spk:
                draw_text(frame, x, y, spk, CYAN if style != "system" else RED)
                x += 6 * (len(spk) + 1)
            draw_text(frame, x, y, text[:max(0, n)], WHITE if style != "action" else GRAY)
            n -= len(text) + 1


def scene_frame(t, cast):
    if t < T_CABIN_A:
        img = shot_exterior(t, cast)
    elif t < T_NAV:
        img = shot_cabin(t, cast)
    elif t < T_CABIN_B:
        img = shot_nav(t)
    elif t < T_CORR:
        img = shot_cabin(t, cast)
    elif t < T_OUT:
        img = shot_breach(t, cast)
    elif t < T_SEAL:
        img = shot_outside(t, cast)
    else:
        img = shot_seal(t, cast)
    if t < T_EXT_FULL:
        img = year_card(img, t)
    img[:LB] = 0
    img[H - LB_BOTTOM:] = 0
    draw_captions(img, t)
    if t >= T_FADE_OUT:  # out to black, then the game takes over
        img = (img.astype(np.float32) * max(0.0, 1 - (t - T_FADE_OUT) / (LENGTH - T_FADE_OUT - 0.05))).astype(np.uint8)
    return img


def frame_at(t, cast):
    f = scene_frame(t, cast)
    return np.repeat(np.repeat(f, 2, 0), 2, 1)


# --- Soundtrack -------------------------------------------------------------------------------

def soundtrack():
    """Music and effects only. Spoken lines get a clear lane: no one-shot effects
    overlap a caption, and everything else is turned down under it."""
    n = int(SR * LENGTH)
    out = np.zeros(n)
    rng = np.random.default_rng(5)
    lines = [(c[0], c[1]) for c in CAPTIONS if c[4] != "action"]
    last_line = CAPTIONS[-1][0]

    def tt(d):
        return np.arange(int(SR * d)) / SR

    def add(t0, sig, gain=1.0):
        i = int(t0 * SR)
        if i >= n:
            return
        j = min(n, i + len(sig))
        out[i:j] += sig[:j - i] * gain

    def fx(t0, sig, gain=1.0):
        """A one-shot effect; dropped if it would play over a spoken line."""
        t1 = t0 + len(sig) / SR
        if any(t0 < b + 0.1 and t1 > a - 0.1 for a, b in lines):
            return
        add(t0, sig, gain)

    def filt(x, kind, fc):
        b, a = sps.butter(2, np.array(fc) / (SR / 2), kind)
        return sps.lfilter(b, a, x)

    def noise(d):
        return rng.uniform(-1, 1, int(SR * d))

    def sq(f, d):
        return np.sign(np.sin(2 * np.pi * f * tt(d)))

    def sine(f, d):
        return np.sin(2 * np.pi * f * tt(d))

    def sweep(f0, f1, d, wave="sine"):
        f = np.linspace(f0, f1, int(SR * d))
        ph = 2 * np.pi * np.cumsum(f) / SR
        return np.sin(ph) if wave == "sine" else np.sign(np.sin(ph))

    def fade(x, a=0.005, r=0.02):
        e = np.ones(len(x))
        na, nr = max(1, int(SR * a)), max(1, int(SR * r))
        e[:na] = np.linspace(0, 1, na)
        e[-nr:] = np.minimum(e[-nr:], np.linspace(1, 0, nr))
        return x * e

    def decay(d, k):
        return np.exp(-tt(d) * k)

    def alarm(t0, t1, gain, muffle=False):
        cyc = fade(sweep(520, 880, 0.5, "sq"), 0.01, 0.05)
        t = t0
        while t < t1:
            seg = cyc[:int(SR * min(0.5, t1 - t))]
            if muffle:
                seg = filt(seg, "low", 600)
            add(t, seg, gain)
            t += 0.75

    def wind(t0, t1, gain):
        d = t1 - t0
        w = filt(noise(d), "band", [180, 1400]) * 2.2
        swell = 0.75 + 0.25 * np.sin(2 * np.pi * 0.7 * tt(d))
        add(t0, fade(w * swell, 0.15, 0.003), gain)

    def steps(t0, t1, every, gain):
        for k, t in enumerate(np.arange(t0, t1, every)):
            fx(t + 0.03 * (k % 3), fade(filt(noise(0.04), "low", 300), 0.001, 0.02), gain)

    # The year: a low pad swelling in, handing over to the engine as the ship passes.
    d = T_EXT_FULL + 0.8
    pad = (0.6 * sine(55, d) + 0.35 * sine(82.4, d) + 0.15 * sine(164.8, d)) * (0.8 + 0.2 * sine(0.5, d))
    add(0.0, fade(pad, 1.4, 1.2), 0.2)
    d = T_CABIN_A - T_EXT_IN + 0.1
    rumble = filt(noise(d), "low", 140) * 2.2 + 0.25 * sine(45, d)
    add(T_EXT_IN - 0.1, fade(rumble * np.sin(np.pi * tt(d) / d) ** 0.7, 0.4, 0.02), 0.32)
    # Cabin hum (also under the dashboard), until the power dies.
    d = T_IMPACT + 0.15 - T_CABIN_A
    hum = 0.5 * sine(60, d) + 0.2 * sine(120, d) + filt(noise(d), "low", 220) * 0.8
    add(T_CABIN_A, fade(hum, 0.05, 0.01), 0.22)
    add(T_IMPACT + 0.15, fade(sweep(60, 18, 0.35) * decay(0.35, 6), 0.002, 0.05), 0.25)
    # Monitor typing, then a bright two-note chime for SUCCESS.
    for t0, line in MONITOR_LINES:
        for i, ch in enumerate(line):
            if ch != " ":
                fx(t0 + i / MONITOR_CPS, fade(sq(1150, 0.012), 0.001, 0.004), 0.06)
    fx(SUCCESS_AT, fade(sq(784, 0.09) * decay(0.09, 8), 0.002, 0.02), 0.08)
    fx(SUCCESS_AT + 0.1, fade(sq(1047, 0.22) * decay(0.22, 7), 0.002, 0.05), 0.08)
    # Dashboard wakes up; the distance digits roll.
    fx(T_NAV + 0.02, fade(sweep(900, 1500, 0.08), 0.002, 0.02), 0.06)
    for k in range(12):
        fx(T_NAV + 0.1 + k * 0.05, fade(sq(1800, 0.008), 0.001, 0.003), 0.035)
    # First impact.
    boom = sweep(95, 28, 1.2) * decay(1.2, 3.2)
    crash = filt(noise(0.8), "low", 900) * decay(0.8, 5) * 2.0
    clang = sum(np.sin(2 * np.pi * f * tt(1.4)) * decay(1.4, 2.5 + i) for i, f in enumerate((233, 367, 521, 690)))
    add(T_IMPACT, boom, 0.9)
    add(T_IMPACT, crash, 0.55)
    add(T_IMPACT + 0.02, clang, 0.07)
    for dt in (0.15, 0.35, 0.42):  # lights fail
        fx(T_IMPACT + dt, fade(filt(noise(0.06), "high", 2500), 0.001, 0.02), 0.35)
    alarm(T_IMPACT + 0.8, T_HIT2, 0.09)
    fx(T_STAND - 0.2, fade(filt(noise(0.008), "high", 3000), 0.0005, 0.004), 0.4)  # restraints
    steps(T_WALK, T_CORR, 0.2, 0.5)
    # Running feet during the breach; the cabin door opens after the final line.
    steps(T_CORR, T_HIT2, 0.17, 0.55)
    fx(HATCH_OPEN[0], fade(filt(noise(0.25), "band", [400, 2500]) * decay(0.25, 6), 0.01, 0.05), 0.25)
    # Second impact: boom, tearing metal, the hatch slamming shut, rushing air.
    add(T_HIT2, sweep(110, 25, 1.3) * decay(1.3, 2.6), 1.0)
    tear = filt(noise(1.0), "band", [300, 2200]) * decay(1.0, 2.2) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 23 * tt(1.0))))
    add(T_HIT2 + 0.02, tear, 0.6)
    add(T_HIT2 + 0.03, sum(np.sin(2 * np.pi * f * tt(0.6)) * decay(0.6, 6 + i) for i, f in enumerate((210, 330))), 0.06)
    wind(T_HIT2 + 0.05, T_OUT, 0.5)
    alarm(T_HIT2, T_OUT, 0.05)
    # Seal (original 19.0-28.0 timings + SEAL_OFF): muffled alarm, wind, button, door slam.
    o = SEAL_OFF
    alarm(19.0 + o, 21.45 + o, 0.08, muffle=True)
    wind(19.0 + o, 21.45 + o, 0.45)
    fx(21.3 + o, fade(sq(988, 0.09), 0.002, 0.02), 0.18)
    add(21.45 + o, sweep(75, 32, 0.6) * decay(0.6, 5), 1.0)
    add(21.45 + o, filt(noise(0.35), "low", 500) * decay(0.35, 9) * 2, 0.6)
    add(21.46 + o, sum(np.sin(2 * np.pi * f * tt(0.9)) * decay(0.9, 4 + i) for i, f in enumerate((180, 287, 410))), 0.08)
    # Helmet breathing (only breathing), stopping before the last line.
    t = 21.8 + o
    while t + 2.7 < last_line:
        inhale = filt(noise(1.1), "band", [500, 2400]) * np.sin(np.pi * tt(1.1) / 1.1) ** 2
        exhale = filt(noise(1.4), "band", [240, 1200]) * np.sin(np.pi * tt(1.4) / 1.4) ** 2
        add(t, inhale, 0.55)
        add(t + 1.3, exhale, 0.7)
        t += 3.2
    for a, b in FLICKER:  # terminal buzz, in time with its flicker
        add(a + o, fade((sq(100, b - a) * 0.6 + sq(200, b - a) * 0.2), 0.002, 0.004), 0.05)
    for t0 in (24.95, 25.18):
        fx(t0 + o, fade(filt(noise(0.04), "low", 300), 0.001, 0.02), 0.5)
    # Under each spoken line: everything down to a fifth, eased in and out.
    env = np.ones(n)
    ramp = int(0.15 * SR)
    for a, b in lines:
        i0, i1 = int(a * SR), min(n, int(b * SR))
        env[i0:i1] = np.minimum(env[i0:i1], 0.2)
        env[max(0, i0 - ramp):i0] = np.minimum(env[max(0, i0 - ramp):i0], np.linspace(1, 0.2, i0 - max(0, i0 - ramp)))
        env[i1:min(n, i1 + ramp)] = np.minimum(env[i1:min(n, i1 + ramp)], np.linspace(0.2, 1, min(n, i1 + ramp) - i1))
    out *= env
    # Hard silence from the script; fade out with the picture.
    out[int(T_OUT * SR):int(T_SEAL * SR)] = 0
    i0 = int(T_FADE_OUT * SR)
    out[i0:] *= np.linspace(1, 0, n - i0)
    out = out / max(1e-6, np.abs(out).max()) * 0.89
    return out


# --- Main -----------------------------------------------------------------------------------

def build_globals():
    global CABIN_BG, CORR_BG, NAV_BG, SHIP2, SHIP4, FAR_PLANETS, EXT_STARS_FAR, EXT_STARS_NEAR
    global NAV_MARS, NAV_EARTH, NAV_MOON
    global BREACH_STARS, BREACH_MASK, BREACH_EDGE, BREACH_SKY_BASE
    SHIP2 = make_ship(2)
    SHIP4 = make_ship(OUT_SCALE)
    # Small and far away: a ringed gas giant, a red dot (Mars, behind them), an icy speck.
    FAR_PLANETS = [(ringed_planet(9, 17, 4), (252, 46)),
                   (render_planet(4, kind="mars", lon=1.3), (54, 138)),
                   (render_planet(2, kind="ice"), (176, 32))]
    EXT_STARS_FAR = make_stars(90, W, H, 1)
    EXT_STARS_NEAR = make_stars(30, W, H, 2)
    NAV_MARS = render_planet(7, kind="mars", lon=1.3)
    NAV_EARTH = render_planet(9, lon=0.6)
    NAV_MOON = render_planet(2, kind="moon")
    BREACH_STARS = make_stars(40, W, H, 3)
    poly = Image.new("L", (W, H), 0)
    ImageDraw.Draw(poly).polygon(BREACH, fill=255)
    BREACH_MASK = np.asarray(poly) > 0
    BREACH_EDGE = ndimage.binary_dilation(BREACH_MASK, iterations=2) & ~BREACH_MASK
    BREACH_SKY_BASE = np.zeros((H, W, 3), np.uint8)
    BREACH_SKY_BASE[:] = SPACE  # just space through the hole
    CABIN_BG = build_cabin()
    CORR_BG = build_corridor()
    NAV_BG = build_nav()


def cast_for(player):
    survivor, lost, ahead = crew_for(player)
    return {"player": Astro(player), "survivor": Astro(survivor), "lost": Astro(lost), "ahead": Astro(ahead)}


def write_timing(path):
    """What intro_cutscene.gd needs: the film length and when each line is spoken."""
    data = {
        "_note": "Generated by tools/make_intro.py; edit the timings there and re-run.",
        "length": round(LENGTH, 2),
        "lines": [{"id": vo, "at": round(a, 2), "end": round(b, 2), "speaker": who.rstrip(":"), "text": line,
                   "clear_soundtrack": style != "action"}
                  for a, b, who, line, style, vo in sorted(CAPTIONS)],
    }
    path.write_text(json.dumps(data, indent=2) + "\n")


def encode_video(path, cast, quality):
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "640x360",
           "-r", str(FPS), "-i", "-", "-c:v", "libtheora", "-q:v", str(quality), "-g", "60", "-pix_fmt", "yuv420p",
           str(path)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for k in range(int(LENGTH * FPS)):
        proc.stdin.write(frame_at(k / FPS, cast).tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        sys.exit(f"ffmpeg failed for {path}")


def write_audio(path):
    pcm = (soundtrack() * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "intro.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5",
                        str(path)], check=True)


def _rgba(img_rgb, mask=None):
    """RGB array -> RGBA image (opaque, or alpha from a mask)."""
    a = np.full(img_rgb.shape[:2], 255, np.uint8) if mask is None else np.where(mask, 255, 0).astype(np.uint8)
    return Image.fromarray(np.dstack([img_rgb, a]), "RGBA")


def _mask_png(mask):
    """Bool mask -> white RGBA with the mask as alpha (tinted when drawn)."""
    m = np.asarray(mask, bool)
    out = np.zeros((*m.shape, 4), np.uint8)
    out[m] = (255, 255, 255, 255)
    return Image.fromarray(out, "RGBA")


def export_godot(out: Path):
    """Everything intro_film.gd needs to draw the film itself."""
    out.mkdir(parents=True, exist_ok=True)
    build_globals()
    data = {"_note": "Generated by tools/make_intro.py --export-godot; re-run instead of editing."}
    # Backgrounds and sprites (1 px = 1 art px).
    Image.fromarray(CABIN_BG).save(out / "cabin_bg.png")
    _rgba(CABIN_BG, PORT_MASK).save(out / "cabin_glass.png")   # portholes: not lit by the alarm
    Image.fromarray(CORR_BG).save(out / "corridor_bg.png")
    Image.fromarray(NAV_BG).save(out / "nav_bg.png")
    Image.fromarray(SHIP2, "RGBA").save(out / "ship2.png")
    Image.fromarray(SHIP4, "RGBA").save(out / "ship4.png")
    data["far_planets"] = []
    for k, (spr, (x, y)) in enumerate(FAR_PLANETS):
        Image.fromarray(spr, "RGBA").save(out / f"far_planet_{k}.png")
        data["far_planets"].append([x, y])
    _mask_png(BREACH_MASK).save(out / "breach_mask.png")
    _mask_png(BREACH_EDGE).save(out / "breach_edge.png")
    vig = np.zeros((H, W, 4), np.uint8)
    vig[..., 3] = np.round(_VIG * 255).astype(np.uint8)
    Image.fromarray(vig, "RGBA").save(out / "vignette.png")
    # "SUCCESS" halo masks (2 px and 1 px around the letters).
    pad = 3
    layer = np.zeros((7 + 2 * pad, text_w("SUCCESS") + 2 * pad, 3), np.uint8)
    draw_text(layer, pad, pad, "SUCCESS", (255, 255, 255))
    m = layer[..., 0] > 0
    near = ndimage.binary_dilation(m, iterations=1) & ~m
    far = ndimage.binary_dilation(m, iterations=2) & ~m & ~near
    _mask_png(near).save(out / "glow_near.png")
    _mask_png(far).save(out / "glow_far.png")
    # Crew: walk frames per suit in art px, plus the far-away tumbling sprites.
    data["crew"] = {}
    for skin in SUITS:
        a = Astro(skin)
        Image.fromarray(np.concatenate(a.frames, 1), "RGBA").save(out / f"astro_{skin}.png")
        for k, tiny in enumerate(a.tiny):
            Image.fromarray(tiny, "RGBA").save(out / f"tiny_{skin}_{k}.png")
        data["crew"][skin] = {"w": a.w, "h": a.h, "bx0": a.bx0, "bx1": a.bx1,
                              "color": list(a.color), "dark": list(a.dark)}
    survivor, lost, ahead = crew_for("classic")
    data["cast"] = {"player": "classic", "survivor": survivor, "lost": lost, "ahead": ahead}
    # Random picks, frozen.
    rnd = lambda a: [float(v) for v in a]  # noqa: E731  (full precision: positions are truncated to pixels)
    data["stars"] = {name: [rnd(s) for s in st] for name, st in
                     (("ext_far", EXT_STARS_FAR), ("ext_near", EXT_STARS_NEAR), ("breach", BREACH_STARS))}
    data["flows"] = {name: {k: rnd(v) for k, v in f.items()} for name, f in
                     (("air1", AIR1), ("deb1", DEB1), ("air2", AIR2), ("deb2", DEB2))}
    sparks = []
    for i in range(len(SPARK_T)):
        rng = np.random.default_rng(40 + i)
        burst = []
        for _ in range(9):
            vx, vy = rng.uniform(-40, 40), rng.uniform(-10, 25)
            burst.append([float(vx), float(vy), bool(rng.random() < 0.5)])
        sparks.append(burst)
    data["sparks"] = {"at": rnd(SPARK_T), "bursts": sparks}
    rng = np.random.default_rng(9)
    out_debris = []
    for _ in range(26):
        vx, vy = rng.uniform(10, 46), rng.uniform(4, 30)
        ph = rng.uniform(0, 1.6)
        out_debris.append([float(vx), float(vy), float(ph), bool(rng.random() < 0.5)])
    data["outside_debris"] = out_debris
    # Camera shake per film frame (it is re-rolled every frame from the frame number).
    n = int(round(LENGTH * FPS))
    shakes = {}
    for k in range(n):
        t = k / FPS
        for key, (tt, t0, dur, amp, seed) in {
                "cabin": (t, T_IMPACT, 0.9, 3, 1), "breach": (t, T_HIT2, 0.9, 3, 2),
                "seal": (t - SEAL_OFF, 21.47, 0.35, 2, 3)}.items():
            dx, dy = shake(tt, t0, dur, amp, seed)
            if dx or dy:
                shakes.setdefault(key, {})[str(k)] = [dx, dy]
    data["shakes"] = shakes
    # The breach seen from outside: hole, inner glow and torn edge for each frame of the shot.
    hole_frames = []
    tiles = []
    for k in range(int(round(T_OUT * FPS)), int(round(T_SEAL * FPS))):
        lt = k / FPS - T_OUT
        ox, oy = -44 + 3 * lt, 28
        hole = Image.new("L", (W, H), 0)
        ImageDraw.Draw(hole).polygon([(ox + x, oy + y) for x, y in OUT_HOLE], fill=255)
        hm = np.asarray(hole) > 0
        inner = ndimage.binary_erosion(hm, iterations=3)
        edge = ndimage.binary_dilation(hm, iterations=1) & ~hm
        ys, xs = np.nonzero(edge | hm)
        x0, y0 = int(xs.min()), int(ys.min())
        tiles.append((x0, y0, hm[y0:ys.max() + 1, x0:xs.max() + 1], inner[y0:ys.max() + 1, x0:xs.max() + 1],
                      edge[y0:ys.max() + 1, x0:xs.max() + 1]))
    tw_ = max(t[2].shape[1] for t in tiles)
    th_ = max(t[2].shape[0] for t in tiles)
    cols = 10
    rows = -(-len(tiles) // cols)
    for name, idx in (("hole", 2), ("hole_inner", 3), ("hole_edge", 4)):
        atlas = np.zeros((rows * th_, cols * tw_), bool)
        for i, t in enumerate(tiles):
            r, c = divmod(i, cols)
            mk = t[idx]
            atlas[r * th_:r * th_ + mk.shape[0], c * tw_:c * tw_ + mk.shape[1]] = mk
        _mask_png(atlas).save(out / f"{name}_atlas.png")
    for i, t in enumerate(tiles):
        hole_frames.append([t[0], t[1]])
    data["hole"] = {"first_frame": int(round(T_OUT * FPS)), "tile": [tw_, th_], "cols": cols, "pos": hole_frames}
    # Text and timing the film uses.
    data["font"] = FONT
    data["captions"] = [{"t0": a, "t1": b, "who": who, "line": line, "style": style,
                         "rows": caption_lines(who, line)} for a, b, who, line, style, _ in CAPTIONS]
    (ROOT / "data/intro_film.json").write_text(json.dumps(data) + "\n")  # data/: in the export filter
    print("wrote", out.relative_to(ROOT), "and data/intro_film.json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="write key frames (classic suit) to this folder instead")
    ap.add_argument("--suits", nargs="*", default=["classic"], choices=SUITS)
    ap.add_argument("--quality", type=int, default=7, help="Theora quality 0-10 (7 = ~1.9 MB per suit)")
    ap.add_argument("--export-godot", action="store_true", help="write assets/intro/ for the in-game film")
    args = ap.parse_args()
    if args.export_godot:
        export_godot(ROOT / "assets/intro")
        return
    build_globals()
    if args.preview:
        out = Path(args.preview)
        out.mkdir(parents=True, exist_ok=True)
        cast = cast_for("classic")
        for t in (0.6, 1.5, 2.6, 3.4, 4.6, 6.3, 7.6, 8.8, 9.5, 10.6, 12.6, 14.73, 15.2, 16.4, 17.5, 18.4, 19.1,
                  19.6, 20.5, 20.9, 21.3, 21.45, 22.1, 23.4, 24.6, 25.6, 26.8, 27.7, 28.5, 29.7, 31.0, 33.2, 34.4,
                  35.9, 37.0, 37.8):
            Image.fromarray(frame_at(t, cast)).save(out / f"t{t:05.2f}.png")
        return
    out = ROOT / "art_source/intro_base"
    out.mkdir(parents=True, exist_ok=True)
    for suit in args.suits:
        path = out / f"intro_{suit}.ogv"
        encode_video(path, cast_for(suit), args.quality)
        print("wrote", path.relative_to(ROOT))
    write_audio(out / "intro_soundtrack.ogg")
    write_timing(out / "intro_timing.json")
    print("wrote", (out / "intro_soundtrack.ogg").relative_to(ROOT), "and intro_timing.json")


if __name__ == "__main__":
    main()
