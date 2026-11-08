#!/usr/bin/env python3
"""Render Back2Earth's 30-second opening story. Owner: D.

    pip install pillow numpy scipy     # and ffmpeg with libtheora + libvorbis on PATH
    python3 tools/make_intro.py                    # all four suits + soundtrack
    python3 tools/make_intro.py --preview DIR      # key frames as PNGs (classic only)

Writes
    assets/video/intro_<suit>.ogv   640x360, 30 fps, 30 s, no audio track
    assets/audio/intro.ogg          soundtrack; scripts/ui/intro_cutscene.gd plays
                                    it alongside the video

The player wears the suit they picked. The crewmate who survives wears the same
suit as the in-game crewmate (SUIT_PREFERENCE in scripts/interactables/crewmate.gd)
and the lost crewmate wears the next one. Everything is drawn here from the
game's own sprites at 320x180 "art pixels" (shown 2x2, like the rest of the
game). Retime beats or rewrite lines in CAPTIONS / MONITOR_LINES and re-run.

Beats (script by the team):
  0-2.4   ship cruises toward Earth          2.4-8   cabin: crew asleep, monitor,
  8-13    impact, lights out, red alarm,             one wakes: "Real food. Finally."
          "Hull damage. Evacuate.", crew       13-16  corridor: second impact, breach,
          heads for the pods                         the player reaches and misses
  16-19   outside: one tiny astronaut drifts   19-24  crewmate pulls the player through,
          against Earth. Silence.                    emergency control, door slams, breathing
  24-28   MAIN POWER OFFLINE, face the door,   28-30  black, logo
          "Power first. Then we find them."
"""
from __future__ import annotations

import argparse
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
LENGTH = 30.0
LB = 16                  # letterbox bar height
FEET = 131               # floor line for standing crew (cabin + corridor)
SUITS = ["classic", "hazard", "nebula", "mint"]
SUIT_PREFERENCE = ["hazard", "mint", "nebula", "classic"]   # keep in sync with crewmate.gd
SR = 22050

CAPTIONS = [  # start, end, speaker, line, style
    (5.6, 8.0, "CREWMATE:", "REAL FOOD. FINALLY.", "crew"),
    (9.2, 12.8, "SYSTEM:", "HULL DAMAGE. EVACUATE.", "system"),
    (25.4, 28.0, "CREWMATE:", "POWER FIRST. THEN WE FIND THEM.", "crew"),
]
CPS = 30.0               # caption typing speed (chars per second)
MONITOR_LINES = [(2.8, "LUNAR STATION: REPAIRS COMPLETE"), (4.15, "RETURNING HOME")]
MONITOR_CPS = 26.0
FLICKER = [(24.0, 24.08), (24.16, 24.22), (24.35, 24.7), (24.76, 24.8),
           (24.9, 26.4), (26.47, 26.52), (26.6, 28.0)]   # terminal on-times

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
    "_": "00000 00000 00000 00000 00000 00000 11111",
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
    others = [s for s in SUIT_PREFERENCE if s != player]
    return others[0], others[1]  # survivor (matches the in-game crewmate), lost


# --- Exterior ship ------------------------------------------------------------------------

def make_ship():
    im = Image.new("RGBA", (62, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon([(12, 8), (22, 8), (16, 3)], fill=STEEL_L, outline=INK)          # dorsal fin
    d.polygon([(12, 16), (22, 16), (15, 21)], fill=STEEL_L, outline=INK)       # ventral fin
    d.rectangle([4, 10, 9, 15], fill=STEEL_D, outline=INK)                     # nozzle
    d.polygon([(8, 9), (38, 7), (50, 9), (57, 12), (50, 15), (38, 17), (8, 16)], fill=GRAY, outline=INK)
    d.polygon([(9, 13), (54, 13), (50, 15), (38, 16), (9, 15)], fill=STEEL_LL)
    d.line([(10, 9), (38, 8)], fill=WHITE)
    d.line([(14, 13), (40, 13)], fill=RED)
    d.polygon([(43, 9), (50, 10), (54, 12), (43, 12)], fill=BLUE)
    d.point((46, 10), fill=WHITE)
    for px in (19, 25, 31):
        d.rectangle([px, 10, px + 1, 11], fill=BLUE)
    return np.asarray(im).copy()


# --- Static scenes --------------------------------------------------------------------------

CABIN_W = 420
SEAT_X = {"survivor": 150, "player": 214, "lost": 278}   # rear -> front (facing right)
MONITOR = (112, 38, 322, 70)
WINDOW = (356, 40, 420, 130)
CAB_GLASS = (WINDOW[0] + 4, WINDOW[1] + 4, WINDOW[2], WINDOW[3] - 4)


def build_cabin():
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
    for x in range(40, 340, 48):
        rect(img, x, 82, x + 1, 83, GREEN)
    yy, xx = np.mgrid[0:H, 0:CABIN_W]
    for px in (180, 244):  # portholes between the seats
        d2 = (xx - px) ** 2 + (yy - 92) ** 2
        img[d2 <= 49] = STEEL_L
        img[d2 <= 25] = SPACE
        img[(d2 <= 25) & ((xx + yy) % 11 == 0) & ((xx * 3 + yy) % 7 == 0)] = GRAY
        rect(img, px - 3, 89, px - 1, 90, (60, 70, 110))
    rect(img, 0, 132, CABIN_W, H, STEEL)
    rect(img, 0, 132, CABIN_W, 133, STEEL_L)
    for x in range(0, CABIN_W, 8):
        rect(img, x, 137, x + 1, H, (48, 46, 60))
    # Rear door to the pods.
    rect(img, 12, 66, 52, 132, STEEL_L)
    rect(img, 15, 69, 49, 132, STEEL)
    rect(img, 31, 69, 33, 132, STEEL_D)
    rect(img, 19, 80, 27, 92, STEEL_D)
    rect(img, 37, 80, 45, 92, STEEL_D)
    draw_text(img, 21, 56, "PODS", AMBER)
    # Front window with Earth.
    wx0, wy0, wx1, wy1 = WINDOW
    rect(img, wx0, wy0, wx1, wy1, STEEL_L)
    gx0, gy0, gx1, gy1 = CAB_GLASS
    rect(img, gx0, gy0, gx1, gy1, SPACE)
    draw_stars(img, make_stars(40, CABIN_W, H, 4), 0, clip=CAB_GLASS)
    earth = render_planet(54, lon=0.9)
    blit(img, earth, 434 - earth.shape[1] // 2, 98 - earth.shape[0] // 2, clip=CAB_GLASS)
    rect(img, gx0, gy0, gx1, gy0 + 1, STEEL_LL)
    # Overhead monitor.
    rect(img, 140, 31, 143, 38, STEEL)
    rect(img, 290, 31, 293, 38, STEEL)
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


def draw_console(img, sx, t, m=None):
    rect(img, sx + 7, 117, sx + 18, 132, tint_color(STEEL, m))
    rect(img, sx + 7, 117, sx + 18, 118, tint_color(STEEL_L, m))
    if t < 8.0:
        rect(img, sx + 8, 120, sx + 10, 121, GREEN if int(t * 2 + sx) % 3 else STEEL_D)
        rect(img, sx + 12, 120, sx + 14, 121, AMBER)
    rect(img, sx + 8, 124, sx + 17, 125, tint_color(STEEL_D, m))


CORR_DOOR = (144, 164)              # bulkhead frame x range
CORR_PANEL = (128, 113, 140, 125)   # emergency control
CORR_TERM = (36, 50, 112, 82)       # MAIN POWER OFFLINE terminal
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
    # Pod hatch (left).
    rect(img, 4, 72, 32, 132, STEEL_L)
    rect(img, 7, 75, 29, 132, STEEL)
    rect(img, 13, 84, 23, 94, STEEL_D)
    rect(img, 15, 86, 21, 92, (20, 40, 80))
    draw_text(img, 6, 62, "PODS", AMBER)
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


AIR1 = make_flow(13.25, 16.0, 80, (120, 300), (46, 128), 1)
AIR2 = make_flow(19.0, 22.4, 80, (10, 300), (46, 128), 2)
DEB1 = make_flow(13.25, 14.2, 60, (200, 290), (50, 128), 3, (140, 280))
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


SPARK_T = [8.05, 8.9, 9.7, 10.5, 11.6, 12.4]


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
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = SPACE
    draw_stars(img, EXT_STARS_FAR, t, offx=-4 * t, wrap_w=W)
    draw_stars(img, EXT_STARS_NEAR, t, offx=-10 * t, wrap_w=W)
    blit(img, MOON_IMG, 54 - MOON_IMG.shape[1] // 2, 46 - MOON_IMG.shape[0] // 2)
    blit(img, EARTH_EXT, 330 - EARTH_EXT.shape[1] // 2, 98 - EARTH_EXT.shape[0] // 2)
    sx = lerp(18, 120, t / 2.4)
    sy = 84 + round(math.sin(t * 2.2))
    # Engine trail and flame.
    for k in range(10):
        blend_px(img, int(sx + 2 - k * 3), int(sy + 12), AMBER, 0.5 * (1 - k / 10))
    fl = 4 + (int(t * FPS) % 3)
    for k in range(fl):
        rect(img, int(sx + 3 - k), int(sy + 11), int(sx + 4 - k), int(sy + 14), AMBER if k > 1 else YELLOW)
    blit(img, SHIP, sx, sy)
    return img, 0, 0


def monitor_text(img, t):
    mx0, my0, mx1, my1 = MONITOR
    if t < 8.0:
        for i, (t0, line) in enumerate(MONITOR_LINES):
            n = int(max(0.0, t - t0) * MONITOR_CPS)
            if n > 0:
                draw_text(img, mx0 + 8, my0 + 8 + 12 * i, line[:n], CYAN)
        last_t0, last = MONITOR_LINES[-1]
        done = last_t0 + len(last) / MONITOR_CPS
        if t > done and int(t * 2) % 2 == 0:
            rect(img, mx0 + 8 + text_w(last) + 3, my0 + 20, mx0 + 8 + text_w(last) + 8, my0 + 27, CYAN)


def monitor_alert(img, t):
    mx0, my0, mx1, my1 = MONITOR
    rect(img, mx0 + 3, my0 + 3, mx1 - 3, my1 - 3, (40, 4, 12))
    if int(t * 2.5) % 2 == 0:
        s = "! HULL DAMAGE !"
        draw_text(img, (mx0 + mx1) // 2 - text_w(s) // 2, my0 + 13, s, RED)


def cabin_camera(t):
    if t < 4.9:
        return lerp(4, 20, (t - 2.4) / 2.5)
    if t < 8.0:
        return lerp(20, 100, ease_io((t - 4.9) / 3.1))
    if t < 10.8:
        return 100
    return lerp(100, 0, ease_io((t - 10.8) / 1.8))


def cabin_light(t):
    """(room multiplier, crew multiplier); None = normal light."""
    if t < 8.15:
        return None, None
    if t < 8.8:
        k = 0.55 if 8.35 <= t < 8.42 else 0.1
        return (k, k, k), (max(k, 0.2),) * 3
    k = min(1.0, (t - 8.8) / 0.2)
    pulse = 0.86 + 0.1 * math.sin(2 * math.pi * 1.6 * (t - 8.8))
    room = np.array([1.0, 0.4, 0.44]) * pulse * k + 0.1 * (1 - k)
    crew = np.array([1.0, 0.68, 0.7]) * pulse * k + 0.2 * (1 - k)
    return tuple(room), tuple(crew)


def shot_cabin(t, cast):
    img = CABIN_BG.copy()
    monitor_text(img, t)
    room, crew = cabin_light(t)
    if room is not None:
        gx0, gy0, gx1, gy1 = CAB_GLASS
        glass = img[gy0:gy1, gx0:gx1].copy()
        img = mul(img, room)
        img[gy0:gy1, gx0:gx1] = glass  # outside isn't lit by the alarm
        if t >= 8.8:
            monitor_alert(img, t)
            on = int(t * 3.2) % 2 == 0
            for bx in (120, 240, 360):
                rect(img, bx, 31, bx + 5, 34, (255, 40, 60) if on else (90, 10, 20))
    roles = ("survivor", "player", "lost")
    seated = t < 10.6
    for role in roles:
        a, sx = cast[role], SEAT_X[role]
        if seated:
            asleep = t < (5.0 if role == "lost" else 8.0)
            top = a.draw(img, sx, 124 + (1 if asleep else 0), rows=20, tint=crew)
            if role == "lost" and not asleep:
                rect(img, sx + 3, top + 6, sx + 5, top + 7, tint_color(BLUE, crew))  # Earth in her visor
            if t < 10.4:  # harness
                for k in range(7):
                    blend_px(img, sx + 3 - k, top + 12 + k, tint_color(AMBER, crew), 1.0)
                rect(img, sx, top + 15, sx + 2, top + 17, tint_color(GRAY, crew))
            if asleep and t >= 2.6:  # floating z's
                ph = (t + {"survivor": 0.0, "player": 0.5, "lost": 0.9}[role]) % 1.6
                zx, zy = sx + 6 + int(ph * 3), top - 2 - int(ph * 8)
                for dy, row in enumerate(("1111", "..1.", ".1..", "1111")):
                    for dx, ch in enumerate(row):
                        if ch == "1":
                            blend_px(img, zx + dx, zy + dy, GRAY, 0.9)
    for sx in SEAT_X.values():
        draw_console(img, sx, t, room)
    if not seated:
        for role in roles:
            a, sx = cast[role], SEAT_X[role]
            if t < 11.0:
                a.draw(img, sx, FEET, left=t >= 10.85, tint=crew)
            else:
                walk = t - 11.0
                a.draw(img, sx - 42 * walk, FEET, t_anim=walk, walking=True, left=True, tint=crew)
    if t >= 8.0:
        draw_sparks(img, t, 232, 31)
    if 8.0 <= t < 8.067:  # impact flash
        img = (img.astype(np.float32) * 0.15 + 255 * 0.85).astype(np.uint8)
    cx = cabin_camera(t)
    dx, dy = shake(t, 8.0, 0.9, 3, 1)
    return view(img, cx, dx, dy), 0, 0


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


def shot_breach(t, cast):
    """13.0-16.0: second impact, the lost crewmate is pulled out."""
    room, crew = corridor_light(t)
    img = CORR_BG.copy()
    draw_slab(img, 0)
    img = mul(img, room)
    draw_button(img, t)
    hit = t >= 13.25
    if hit:
        draw_breach(img, t, room)
    A, P, B = cast["survivor"], cast["player"], cast["lost"]
    walk = min(t, 13.25) - 13.0
    # Survivor: walks, stumbles, braces by the door facing back.
    if not hit:
        A.draw(img, 178 - 30 * walk, FEET, t_anim=walk, walking=True, left=True, tint=crew)
    else:
        A.draw(img, 170, FEET, left=t < 13.4, lift=-1 if t < 13.6 else 0, tint=crew)
    # Player: lunges toward the lost crewmate, reaches, misses.
    px, p_left = 214 - 30 * walk, True
    if hit:
        p_left = t < 13.3
        if t < 13.45:
            px = 206.5
        elif t < 14.05:
            px = lerp(206.5, 243, ease_out((t - 13.45) / 0.6))
        else:
            px = 243 + 7 * (t - 14.05) / 1.95
    p_top = P.draw(img, px, FEET, t_anim=walk, walking=not hit, left=p_left, tint=crew)
    if 13.5 <= t < 15.4:
        P.arm(img, px, p_top, 9, tint=crew)
    # Lost crewmate: jolted back, then pulled out through the breach.
    bx, rot, lift = 254 - 30 * walk, 0, 0
    if hit:
        if t < 13.4:
            bx = lerp(246.5, 262, ease_out((t - 13.25) / 0.15))
        else:
            bx = 262 + 0.5 * 33 * (t - 13.4) ** 2
        lift = int(min(6, max(0, (t - 14.2) * 6)))
        if t >= 14.9:
            rot = int((t - 14.9) / 0.22) % 4 + 1
    b_top = B.draw(img, bx, FEET, t_anim=walk, walking=not hit, left=True, rot=rot % 4, lift=lift, tint=crew)
    if 13.5 <= t < 14.9:
        B.arm(img, bx, b_top, 7, left=True, tint=crew)
    if hit:
        draw_flow(img, AIR1, t, False)
        draw_flow(img, DEB1, t, True)
    if 13.25 <= t < 13.317:
        img = (img.astype(np.float32) * 0.2 + 255 * 0.8).astype(np.uint8)
    dx, dy = shake(t, 13.25, 0.9, 3, 2)
    return view(img, 0, dx, dy), 0, 0


def shot_outside(t, cast):
    """16.0-19.0: the lost crewmate drifts away against Earth. Silence."""
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = SPACE
    draw_stars(img, EXT_STARS_FAR, t)
    draw_stars(img, EXT_STARS_NEAR, t)
    blit(img, EARTH_BIG, 200 - EARTH_BIG.shape[1] // 2, 336 - EARTH_BIG.shape[0] // 2)
    # Hull of the ship, top-left, with the breach.
    hull = Image.new("L", (W, H), 0)
    ImageDraw.Draw(hull).polygon([(0, 16), (118, 16), (112, 30), (96, 46), (70, 60), (36, 68), (0, 72)], fill=255)
    hm = np.asarray(hull) > 0
    img[hm] = STEEL
    hole = Image.new("L", (W, H), 0)
    ImageDraw.Draw(hole).polygon([(70, 30), (80, 26), (90, 32), (94, 42), (86, 50), (76, 48), (68, 40)], fill=255)
    om = np.asarray(hole) > 0
    img[om] = (60, 6, 18) if int(t * 3) % 2 else (90, 10, 26)
    edge = ndimage.binary_dilation(om, iterations=1) & ~om
    img[edge] = STEEL_LL
    for x in range(0, 112, 18):
        rect(img, x, 20, x + 1, 64, STEEL_D)
    rect(img, 0, 18, 110, 19, STEEL_L)
    # Debris specks drifting out with her.
    rng = np.random.default_rng(9)
    for _ in range(14):
        sx0, sy0 = rng.uniform(78, 92), rng.uniform(34, 46)
        vx, vy = rng.uniform(8, 40), rng.uniform(4, 26)
        dt = t - 16.0 + rng.uniform(0, 1.0)
        rect(img, int(sx0 + vx * dt), int(sy0 + vy * dt), int(sx0 + vx * dt) + 1, int(sy0 + vy * dt) + 1, GRAY)
    # Her: tumbling, getting smaller.
    u = ease_out((t - 16.0) / 3.0)
    x, y = lerp(96, 214, u), lerp(44, 118, u)
    B = cast["lost"]
    size = 0 if t < 17.0 else (1 if t < 18.1 else 2)
    spr = np.rot90(B.tiny[size], int((t - 16.0) / 0.4) % 4)
    blit(img, spr, x - spr.shape[1] / 2, y - spr.shape[0] / 2)
    return img, 0, 0


def shot_seal(t, cast):
    """19.0-28.0: pulled through the bulkhead, door slams, MAIN POWER OFFLINE."""
    room, crew = corridor_light(t)
    img = CORR_BG.copy()
    draw_slab(img, t)
    img = mul(img, room)
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
    if t < 19.65:  # A runs back for the player; the player slides toward the breach
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
        a_left = 24.3 <= t < 25.3
        p_left = 24.3 <= t < 24.9
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
    return view(img, 0, dx, dy), 0, 0


def _vignette_base():
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.sqrt(((xx - W / 2) / (W * 0.58)) ** 2 + ((yy - H / 2) / (H * 0.62)) ** 2)
    return np.clip((d - 0.55) / 0.45, 0, 1)


_VIG = _vignette_base()


def VIGNETTE(strength):  # noqa: N802 (reads like a constant-ish helper)
    return (1 - strength * _VIG)[..., None]


# --- Captions and frame assembly -----------------------------------------------------------

def draw_captions(frame, t):
    for t0, t1, who, line, style in CAPTIONS:
        if not t0 <= t < t1:
            continue
        n = int((t - t0) * CPS)
        full = f"{who} {line}"
        x = W // 2 - text_w(full) // 2
        y = H - LB + (LB - 7) // 2
        draw_text(frame, x, y, who, CYAN if style == "crew" else RED)
        draw_text(frame, x + 6 * (len(who) + 1), y, line[:n], WHITE)


def scene_frame(t, cast):
    if t < 2.4:
        img, _, _ = shot_exterior(t, cast)
    elif t < 13.0:
        img, _, _ = shot_cabin(t, cast)
    elif t < 16.0:
        img, _, _ = shot_breach(t, cast)
    elif t < 19.0:
        img, _, _ = shot_outside(t, cast)
    else:
        img, _, _ = shot_seal(t, cast)
    if t < 0.6:  # dithered fade in from black
        mask = bayer(H, W) >= t / 0.6
        img[mask] = 0
    img[:LB] = 0
    img[H - LB:] = 0
    draw_captions(img, t)
    return img


def frame_at(t, cast):
    if t >= 28.0:
        return logo_frame(t)
    f = scene_frame(t, cast)
    return np.repeat(np.repeat(f, 2, 0), 2, 1)


def logo_frame(t):
    out = np.zeros((360, 640, 3), np.uint8)
    lh, lw = LOGO.shape[:2]
    x0, y0 = 320 - lw // 2, 176 - lh // 2
    p = (t - 28.3) / 0.6
    if p > 0:
        th = np.repeat(np.repeat(bayer((lh + 1) // 2, (lw + 1) // 2), 2, 0), 2, 1)[:lh, :lw]
        show = th < p
        region = out[y0:y0 + lh, x0:x0 + lw]
        region[show] = LOGO[show]
    if 29.0 <= t < 29.9:  # two sparkles
        for k, (sx, sy) in enumerate(((x0 + 30, y0 + 22), (x0 + lw - 26, y0 + lh - 30))):
            ph = math.sin((t - 29.0) * 7 + k * 2)
            if ph > 0:
                r = 2 + int(ph * 3)
                rect(out, sx - r, sy, sx + r + 1, sy + 1, WHITE)
                rect(out, sx, sy - r, sx + 1, sy + r + 1, WHITE)
    return out


def load_logo():
    with tempfile.TemporaryDirectory() as tmp:
        fpath = Path(tmp) / "menu0.png"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(ROOT / "art_source/menu_loop_1080p.ogv"),
                        "-vf", "select=eq(n\\,0)", "-vsync", "0", str(fpath)], check=True)
        a = np.asarray(Image.open(fpath).convert("RGB")).astype(np.int32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    cyan = (b > 200) & (g > 190) & (r < 140)
    cyan[:, :640] = False
    cyan[:, 1300:] = False
    cyan[480:] = False
    ys, xs = np.where(cyan)
    gcx, gcy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    gr = (xs.max() - xs.min()) / 2 + 2
    x0, y0, x1, y1 = 400, int(max(0, gcy - gr - 10)), 1480, int(gcy + gr + 10)
    crop = a[y0:y1, x0:x1].copy()
    yy, xx = np.mgrid[y0:y1, x0:x1]
    globe = (xx - gcx) ** 2 + (yy - gcy) ** 2 <= gr ** 2
    lum = crop.mean(2)
    text_box = (yy > gcy - 110) & (yy < gcy + 110)
    letters = ndimage.binary_dilation((lum > 120) & text_box & ~globe, iterations=9)
    keep = globe | letters
    crop[~keep] = 0
    crop[~globe & (lum < 55)] = 0
    im = Image.fromarray(crop.astype(np.uint8))
    im = im.resize((im.width // 3, im.height // 3), Image.LANCZOS)
    return np.asarray(im)


# --- Soundtrack -------------------------------------------------------------------------------

def soundtrack():
    n = int(SR * LENGTH)
    out = np.zeros(n)
    rng = np.random.default_rng(5)

    def tt(d):
        return np.arange(int(SR * d)) / SR

    def add(t0, sig, gain=1.0):
        i = int(t0 * SR)
        if i >= n:
            return
        j = min(n, i + len(sig))
        out[i:j] += sig[:j - i] * gain

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

    # 0-2.4 engine rumble outside; 2.4-8.15 cabin hum.
    rumble = filt(noise(2.4), "low", 140) * 2.2 + 0.25 * sine(45, 2.4)
    add(0.0, fade(rumble, 0.6, 0.02), 0.32)
    hum = 0.5 * sine(60, 5.75) + 0.2 * sine(120, 5.75) + filt(noise(5.75), "low", 220) * 0.8
    add(2.4, fade(hum, 0.05, 0.01), 0.22)
    add(8.15, fade(sweep(60, 18, 0.35) * decay(0.35, 6), 0.002, 0.05), 0.25)
    # Monitor typing and caption voice blips.
    for t0, line in MONITOR_LINES:
        for i, ch in enumerate(line):
            if ch != " ":
                add(t0 + i / MONITOR_CPS, fade(sq(1150, 0.012), 0.001, 0.004), 0.06)
    for t0, _t1, _who, line, style in CAPTIONS:
        for i, ch in enumerate(line):
            if ch in " .,":
                continue
            if style == "crew":
                f = 620 + 90 * ((i * 7) % 5)
                add(t0 + i / CPS, fade(sq(f, 0.028), 0.002, 0.01), 0.07)
            else:
                add(t0 + i / CPS, fade(sweep(260, 220, 0.03, "sq"), 0.002, 0.01), 0.09)
    # 8.0 impact.
    boom = sweep(95, 28, 1.2) * decay(1.2, 3.2)
    crash = filt(noise(0.8), "low", 900) * decay(0.8, 5) * 2.0
    clang = sum(np.sin(2 * np.pi * f * tt(1.4)) * decay(1.4, 2.5 + i) for i, f in enumerate((233, 367, 521, 690)))
    add(8.0, boom, 0.9)
    add(8.0, crash, 0.55)
    add(8.02, clang, 0.07)
    for t0 in (8.15, 8.35, 8.42):  # lights fail
        add(t0, fade(filt(noise(0.06), "high", 2500), 0.001, 0.02), 0.35)
    # Alarm.
    def alarm(t0, t1, gain, muffle=False):
        cyc = fade(sweep(520, 880, 0.5, "sq"), 0.01, 0.05)
        t = t0
        while t < t1:
            seg = cyc[:int(SR * min(0.5, t1 - t))]
            if muffle:
                seg = filt(seg, "low", 600)
            add(t, seg, gain)
            t += 0.75
    alarm(8.8, 13.0, 0.09)
    alarm(13.25, 16.0, 0.05)
    alarm(19.0, 21.45, 0.08, muffle=True)
    for t0 in (10.40, 10.46, 10.52):  # restraints release
        add(t0, fade(filt(noise(0.008), "high", 3000), 0.0005, 0.004), 0.4)
    for k, t0 in enumerate(np.arange(11.0, 13.0, 0.23)):  # footsteps
        add(t0 + 0.03 * (k % 3), fade(filt(noise(0.04), "low", 300), 0.001, 0.02), 0.5)
    # 13.25 second impact: boom + tearing metal + rushing air.
    add(13.25, sweep(110, 25, 1.3) * decay(1.3, 2.6), 1.0)
    tear = filt(noise(1.0), "band", [300, 2200]) * decay(1.0, 2.2) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 23 * tt(1.0))))
    add(13.27, tear, 0.6)

    def wind(t0, t1, gain):
        d = t1 - t0
        w = filt(noise(d), "band", [180, 1400]) * 2.2
        swell = 0.75 + 0.25 * np.sin(2 * np.pi * 0.7 * tt(d))
        add(t0, fade(w * swell, 0.15, 0.003), gain)
    wind(13.3, 16.0, 0.5)
    wind(19.0, 21.45, 0.45)
    # 21.3 button, 21.45 door slam.
    add(21.3, fade(sq(988, 0.09), 0.002, 0.02), 0.18)
    add(21.45, sweep(75, 32, 0.6) * decay(0.6, 5), 1.0)
    add(21.45, filt(noise(0.35), "low", 500) * decay(0.35, 9) * 2, 0.6)
    add(21.46, sum(np.sin(2 * np.pi * f * tt(0.9)) * decay(0.9, 4 + i) for i, f in enumerate((180, 287, 410))), 0.08)
    # Helmet breathing.
    t = 21.8
    while t < 27.6:
        inhale = filt(noise(1.1), "band", [500, 2400]) * np.sin(np.pi * tt(1.1) / 1.1) ** 2
        exhale = filt(noise(1.4), "band", [240, 1200]) * np.sin(np.pi * tt(1.4) / 1.4) ** 2
        add(t, inhale, 0.55)
        add(t + 1.3, exhale, 0.7)
        t += 3.2
    # Terminal buzz, in time with its flicker.
    for a, b in FLICKER:
        d = b - a
        add(a, fade((sq(100, d) * 0.6 + sq(200, d) * 0.2), 0.002, 0.004), 0.05)
    for t0 in (24.95, 25.18):
        add(t0, fade(filt(noise(0.04), "low", 300), 0.001, 0.02), 0.5)
    # Hard silences from the script.
    out[int(16.0 * SR):int(19.0 * SR)] = 0
    out[int(28.0 * SR):] = 0
    # 28.4 logo chime.
    for k, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        note = fade(sq(f, 0.6) * decay(0.6, 5), 0.003, 0.05)
        add(28.4 + 0.12 * k, note, 0.12)
        add(28.4 + 0.12 * k + 0.18, note, 0.05)
    out = out / max(1e-6, np.abs(out).max()) * 0.89
    return out


# --- Main -----------------------------------------------------------------------------------

def build_globals():
    global CABIN_BG, CORR_BG, SHIP, EARTH_EXT, EARTH_BIG, MOON_IMG, EXT_STARS_FAR, EXT_STARS_NEAR
    global BREACH_STARS, BREACH_EARTH, BREACH_MASK, BREACH_EDGE, BREACH_SKY_BASE, LOGO
    SHIP = make_ship()
    EARTH_EXT = render_planet(108, lon=0.4)
    EARTH_BIG = render_planet(255, lon=1.1, tilt=-1.2)
    MOON_IMG = render_planet(10, kind="moon")
    EXT_STARS_FAR = make_stars(90, W, H, 1)
    EXT_STARS_NEAR = make_stars(30, W, H, 2)
    BREACH_STARS = make_stars(40, W, H, 3)
    BREACH_EARTH = render_planet(60, lon=2.0)
    poly = Image.new("L", (W, H), 0)
    ImageDraw.Draw(poly).polygon(BREACH, fill=255)
    BREACH_MASK = np.asarray(poly) > 0
    BREACH_EDGE = ndimage.binary_dilation(BREACH_MASK, iterations=2) & ~BREACH_MASK
    BREACH_SKY_BASE = np.zeros((H, W, 3), np.uint8)
    BREACH_SKY_BASE[:] = SPACE
    blit(BREACH_SKY_BASE, BREACH_EARTH, 332 - BREACH_EARTH.shape[1] // 2, 150 - BREACH_EARTH.shape[0] // 2)
    CABIN_BG = build_cabin()
    CORR_BG = build_corridor()
    LOGO = load_logo()


def cast_for(player):
    survivor, lost = crew_for(player)
    return {"player": Astro(player), "survivor": Astro(survivor), "lost": Astro(lost)}


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", help="write key frames (classic suit) to this folder instead")
    ap.add_argument("--suits", nargs="*", default=SUITS)
    ap.add_argument("--quality", type=int, default=7, help="Theora quality 0-10 (7 = ~1.9 MB per suit)")
    args = ap.parse_args()
    build_globals()
    if args.preview:
        out = Path(args.preview)
        out.mkdir(parents=True, exist_ok=True)
        cast = cast_for("classic")
        for t in (0.3, 1.6, 3.4, 4.6, 6.4, 7.6, 8.03, 8.5, 9.6, 10.3, 11.8, 12.9, 13.1, 13.3, 13.95, 14.6,
                  15.3, 16.4, 17.6, 18.6, 19.5, 20.3, 21.2, 21.48, 22.8, 24.5, 25.1, 26.5, 28.7, 29.5):
            Image.fromarray(frame_at(t, cast)).save(out / f"t{t:05.2f}.png")
        return
    video_dir = ROOT / "assets/video"
    for suit in args.suits:
        path = video_dir / f"intro_{suit}.ogv"
        encode_video(path, cast_for(suit), args.quality)
        print("wrote", path.relative_to(ROOT))
    write_audio(ROOT / "assets/audio/intro.ogg")
    print("wrote assets/audio/intro.ogg")


if __name__ == "__main__":
    main()
