#!/usr/bin/env python3
"""Pixel art for the ship interior (the escape prototype's map). Owner: D.
Needs: pip install pillow

Everything is drawn here in code with the opening film's palette (PICO-8 based),
at 16 art pixels per 32 px tile, and saved at 2x so the game draws it 1:1:
  assets/ship/floor_<style>.png        64x64: four 16x16 variants (2x2), 2x
  assets/ship/wall_cap.png, wall_face_<kind>.png, window*.png    32x32 tiles
  assets/ship/<prop>.png               furniture, machines, decals, gameplay props

Each drawing is a small function below. A 1 px dark outline is added to solid
props automatically (decals stay flat). Rerun after editing:
    python3 tools/make_ship_art.py      # writes assets/ship/ + docs/ship_art.png
"""
from __future__ import annotations

import math
import random
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ship"
SCALE = 2

# --- Palette (PICO-8 + the film's steels/navies) --------------------------------------
INK = (10, 10, 14)
SPACE = (5, 6, 20)
NAVY = (29, 43, 83)
NAVY_D = (22, 32, 64)
NAVY_L = (40, 56, 104)
STEEL_D = (40, 44, 64)
STEEL = (58, 56, 72)
STEEL_L = (95, 92, 112)
STEEL_LL = (126, 126, 140)
GRAY = (194, 195, 199)
WHITE = (255, 241, 232)
CYAN = (61, 240, 255)
BLUE = (41, 173, 255)
AMBER = (255, 163, 0)
YELLOW = (255, 236, 39)
RED = (255, 0, 77)
RED_D = (126, 37, 83)
GREEN = (0, 228, 54)
GREEN_D = (0, 135, 81)
BROWN = (171, 82, 54)
BROWN_D = (95, 57, 47)
DGRAY = (95, 87, 79)
LAVENDER = (131, 118, 156)
PINK = (255, 119, 168)
PEACH = (255, 204, 170)
PURPLE = (110, 82, 214)


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


class Art:
    """A small RGBA canvas with pixel-art drawing helpers (art pixels)."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = {}

    def dot(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.px[(x, y)] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.dot(xx, yy, c)

    def box(self, x, y, w, h, fill, light=None, dark=None):
        """Filled box with a lit top/left edge and a dark bottom/right edge."""
        self.rect(x, y, w, h, fill)
        self.rect(x, y, w, 1, light or shade(fill, 1.25))
        self.rect(x, y, 1, h, light or shade(fill, 1.25))
        self.rect(x, y + h - 1, w, 1, dark or shade(fill, 0.7))
        self.rect(x + w - 1, y, 1, h, dark or shade(fill, 0.7))

    def hline(self, x0, x1, y, c):
        for x in range(x0, x1 + 1):
            self.dot(x, y, c)

    def vline(self, x, y0, y1, c):
        for y in range(y0, y1 + 1):
            self.dot(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            self.dot(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), c)

    def disc(self, cx, cy, r, c):
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    self.dot(x, y, c)

    def text(self, x, y, s, c):
        for ch in s:
            g = TINY_FONT.get(ch)
            if g:
                for gy, row in enumerate(g):
                    for gx, b in enumerate(row):
                        if b == "#":
                            self.dot(x + gx, y + gy, c)
            x += 4

    def outline(self, c=INK):
        add = {}
        for (x, y) in list(self.px):
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in self.px and 0 <= n[0] < self.w and 0 <= n[1] < self.h:
                    add[n] = c
        self.px.update(add)
        return self

    def image(self):
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        for (x, y), c in self.px.items():
            img.putpixel((x, y), (*c[:3], c[3] if len(c) == 4 else 255))
        return img.resize((self.w * SCALE, self.h * SCALE), Image.NEAREST)


TINY_FONT = {  # 3x5 for little labels drawn into the art
    "A": ["###", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": ["###", "#..", "#..", "#..", "###"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
    "G": ["###", "#..", "#.#", "#.#", "###"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"], "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "###"], "M": ["#.#", "###", "###", "#.#", "#.#"],
    "N": ["##.", "#.#", "#.#", "#.#", "#.#"], "O": ["###", "#.#", "#.#", "#.#", "###"],
    "P": ["###", "#.#", "###", "#..", "#.."], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": ["###", "#..", "###", "..#", "###"], "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W": ["#.#", "#.#", "###", "###", "#.#"], "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["##.", "..#", ".#.", "#..", "###"], "3": ["##.", "..#", ".#.", "..#", "##."],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "6": ["###", "#..", "###", "#.#", "###"],
    "!": [".#.", ".#.", ".#.", "...", ".#."], "-": ["...", "...", "###", "...", "..."],
    "+": ["...", ".#.", "###", ".#.", "..."], " ": ["...", "...", "...", "...", "..."],
}

ART = {}      # name -> Art (props, decals)
TILES = {}    # name -> Image (already 2x)


def prop(name, w, h, solid=True):
    """Decorator: register a drawing function as a sprite."""
    def wrap(fn):
        a = Art(w, h)
        fn(a)
        if solid:
            a.outline()
        ART[name] = a
        return fn
    return wrap


# --- Floors (16x16 art per tile; 4 variants per style in a 2x2 sheet) -------------------

def floor_sheet(name, draw):
    sheet = Image.new("RGBA", (32 * SCALE, 32 * SCALE))
    for v in range(4):
        a = Art(16, 16)
        draw(a, v, random.Random(zlib.crc32(f"{name}/{v}".encode())))  # same art every run
        sheet.paste(a.image(), ((v % 2) * 16 * SCALE, (v // 2) * 16 * SCALE))
    TILES[f"floor_{name}"] = sheet


def deck(a, v, r):  # steel plates with seams and rivets
    a.rect(0, 0, 16, 16, (52, 52, 68))
    a.rect(0, 0, 16, 1, (66, 66, 84))
    a.rect(0, 0, 1, 16, (66, 66, 84))
    a.rect(0, 15, 16, 1, (38, 38, 52))
    a.rect(15, 0, 1, 16, (38, 38, 52))
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        a.dot(x, y, (84, 84, 102))
    if v == 1:
        a.rect(4, 6, 8, 4, (44, 44, 58))
        for x in range(5, 12, 2):
            a.vline(x, 7, 8, (30, 30, 42))
    if v == 2:
        a.hline(3, 12, 8, (46, 46, 60))
    if v == 3:
        a.dot(r.randrange(4, 12), r.randrange(4, 12), (64, 64, 80))


def carpet(a, v, r):  # warm cabin carpet
    base, alt = (72, 44, 58), (82, 52, 66)
    a.rect(0, 0, 16, 16, base)
    for y in range(16):
        for x in range(16):
            if (x + y * 3 + v) % 7 == 0:
                a.dot(x, y, alt)
    if v == 2:
        a.rect(0, 7, 16, 2, (96, 58, 70))


def galley(a, v, r):  # checkered tiles
    for y in range(16):
        for x in range(16):
            light = ((x // 8) + (y // 8) + v) % 2 == 0
            a.dot(x, y, (150, 150, 160) if light else (98, 98, 112))
    a.hline(0, 15, 0, (170, 170, 178))
    a.vline(0, 0, 15, (170, 170, 178))


def lab(a, v, r):  # clean white-blue tiles
    a.rect(0, 0, 16, 16, (168, 182, 200))
    a.hline(0, 15, 15, (130, 144, 166))
    a.vline(15, 0, 15, (130, 144, 166))
    a.hline(0, 15, 7, (150, 164, 184))
    a.vline(7, 0, 15, (150, 164, 184))
    if v == 3:
        a.dot(3, 3, (196, 206, 220))


def med(a, v, r):
    a.rect(0, 0, 16, 16, (156, 196, 200))
    a.hline(0, 15, 15, (120, 160, 168))
    a.vline(15, 0, 15, (120, 160, 168))
    if v == 1:
        a.rect(6, 6, 4, 4, (136, 178, 186))


def grate(a, v, r):  # engineering grating over darkness
    a.rect(0, 0, 16, 16, (30, 30, 40))
    for x in range(0, 16, 3):
        a.vline(x, 0, 15, (70, 66, 78))
    a.hline(0, 15, 0, (84, 80, 94))
    a.hline(0, 15, 15, (24, 24, 32))
    if v == 2:
        a.rect(5, 5, 6, 6, (60, 40, 30))  # an old oil stain under the grate


def hydro(a, v, r):
    a.rect(0, 0, 16, 16, (44, 66, 58))
    for x in range(1, 16, 4):
        a.vline(x, 0, 15, (34, 52, 46))
    a.hline(0, 15, 0, (60, 88, 76))
    if v == 1:
        a.disc(8, 8, 2.5, (40, 90, 110))  # drain puddle


def hangar(a, v, r):
    deck(a, 0, r)
    a.rect(0, 0, 16, 16, (60, 60, 74))
    a.rect(0, 0, 16, 1, (74, 74, 90))
    a.rect(0, 15, 16, 1, (44, 44, 56))
    if v == 1:
        a.rect(0, 6, 16, 4, (78, 78, 92))
    if v == 2:
        for x in range(2, 15, 4):
            a.dot(x, 8, (90, 90, 106))


def breach_floor(a, v, r):  # vacuum side: dark deck lit red, scattered debris
    a.rect(0, 0, 16, 16, (34, 22, 34))
    a.rect(0, 0, 16, 1, (46, 28, 40))
    a.rect(0, 15, 16, 1, (24, 14, 24))
    for _ in range(2 + v):
        a.dot(r.randrange(16), r.randrange(16), (72, 40, 52))


for _name, _fn in (("deck", deck), ("carpet", carpet), ("galley", galley), ("lab", lab), ("med", med),
                   ("grate", grate), ("hydro", hydro), ("hangar", hangar), ("breach", breach_floor)):
    floor_sheet(_name, _fn)


# --- Walls --------------------------------------------------------------------------

def wall_cap():
    a = Art(16, 16)
    a.rect(0, 0, 16, 16, (34, 36, 52))
    a.rect(0, 0, 16, 1, (58, 60, 80))
    a.rect(0, 15, 16, 1, (26, 26, 38))
    a.dot(4, 4, (48, 50, 68))
    a.dot(11, 11, (48, 50, 68))
    TILES["wall_cap"] = a.image()


def face(kind, accent=NAVY_L):
    """One 16x16 wall face (the front of a wall with floor below it)."""
    a = Art(16, 16)
    a.rect(0, 0, 16, 16, NAVY)
    a.rect(0, 0, 16, 2, NAVY_D)                  # shadow under the ceiling edge
    a.rect(0, 9, 16, 1, accent)                  # the film's light stripe
    a.rect(0, 13, 16, 3, NAVY_D)                 # baseboard
    a.hline(0, 15, 13, STEEL_L)
    a.vline(0, 2, 12, (36, 52, 96))
    if kind == "vent":
        a.rect(4, 3, 8, 5, STEEL_D)
        for y in range(4, 8, 2):
            a.hline(5, 10, y, INK)
    elif kind == "screen":
        a.rect(3, 2, 10, 6, STEEL)
        a.rect(4, 3, 8, 4, (8, 30, 40))
        a.hline(5, 9, 4, CYAN)
        a.hline(5, 7, 5, (40, 140, 160))
    elif kind == "pipe":
        a.rect(0, 4, 16, 2, STEEL_L)
        a.hline(0, 15, 4, STEEL_LL)
        a.rect(6, 3, 2, 4, STEEL)
    elif kind == "light":
        a.rect(5, 3, 6, 2, (255, 230, 170))
        a.hline(5, 10, 5, (180, 150, 100))
    elif kind == "panel":
        a.rect(3, 3, 10, 5, NAVY_L)
        a.rect(4, 4, 2, 1, GREEN)
        a.rect(7, 4, 2, 1, AMBER)
    elif kind == "alarm":  # red emergency lamp (corridor)
        a.rect(6, 2, 4, 3, RED)
        a.dot(7, 2, PINK)
    TILES[f"wall_face_{kind}"] = a.image()


def face_upper():
    """The upper half of a two-tile wall face: panels up to the ceiling trim."""
    a = Art(16, 16)
    a.rect(0, 0, 16, 16, NAVY)
    a.rect(0, 0, 16, 3, STEEL_D)
    a.hline(0, 15, 3, STEEL_L)
    a.vline(0, 4, 15, (36, 52, 96))
    a.vline(8, 4, 15, NAVY_D)
    a.dot(3, 6, NAVY_L)
    a.dot(12, 6, NAVY_L)
    TILES["wall_face_upper"] = a.image()


def window_face(earth=False):
    a = Art(16, 16)
    a.rect(0, 0, 16, 16, STEEL_L)
    a.rect(1, 1, 14, 11, SPACE)
    rng = random.Random(7 if not earth else 9)
    for _ in range(7):
        a.dot(rng.randrange(2, 14), rng.randrange(2, 11), rng.choice([GRAY, STEEL_LL, WHITE, LAVENDER]))
    a.rect(0, 12, 16, 4, NAVY_D)
    a.hline(0, 15, 12, STEEL)
    a.vline(0, 0, 15, STEEL)
    a.vline(15, 0, 15, STEEL_D)
    TILES["window" if not earth else "window_b"] = a.image()


wall_cap()
for _k in ("plain", "vent", "screen", "pipe", "light", "panel", "alarm"):
    face(_k)
face_upper()
window_face()
window_face(True)


# --- Furniture and decor ------------------------------------------------------------

def bunk(a, blanket, made=False):
    a.box(0, 0, 16, 30, STEEL)
    a.rect(1, 2, 14, 26, (200, 196, 190))          # mattress
    a.rect(2, 3, 12, 5, WHITE)                    # pillow
    a.hline(2, 13, 7, GRAY)
    if made:
        a.rect(1, 12, 14, 15, blanket)
        a.hline(1, 14, 12, shade(blanket, 1.3))
    else:
        a.rect(1, 11, 14, 16, blanket)
        a.line(2, 11, 12, 15, shade(blanket, 1.3))
        a.rect(9, 9, 5, 3, shade(blanket, 0.8))
    a.rect(0, 28, 16, 2, STEEL_D)


@prop("bunk_red", 16, 30)
def _bunk_red(a):
    bunk(a, (190, 60, 70))


@prop("bunk_blue", 16, 30)
def _bunk_blue(a):
    bunk(a, (60, 100, 200))


@prop("bunk_green", 16, 30)
def _bunk_green(a):
    bunk(a, (40, 150, 90))


@prop("bunk_kien", 16, 30)
def _bunk_kien(a):  # the lost crewmate's bunk, made up neatly, a photo on the pillow
    bunk(a, (120, 200, 170), made=True)
    a.rect(5, 5, 6, 4, WHITE)
    a.rect(6, 6, 4, 2, (90, 130, 180))
    a.dot(7, 6, PEACH)


@prop("locker", 14, 26)
def _locker(a):
    a.box(0, 0, 14, 26, STEEL_L)
    a.vline(7, 1, 24, STEEL)
    for y in (4, 6, 8):
        a.hline(2, 5, y, STEEL_D)
        a.hline(9, 12, y, STEEL_D)
    a.rect(5, 12, 1, 3, GRAY)
    a.rect(8, 12, 1, 3, GRAY)
    a.rect(2, 20, 4, 2, AMBER)


@prop("locker_open", 14, 26)
def _locker_open(a):
    a.box(0, 0, 14, 26, STEEL_L)
    a.rect(1, 1, 12, 23, (20, 20, 30))
    a.rect(2, 3, 4, 12, (60, 100, 200))            # a jacket
    a.rect(8, 3, 4, 10, (190, 190, 200))           # a shirt
    a.rect(2, 19, 10, 4, BROWN)                    # boots


@prop("jammed_locker", 16, 32)
def _jammed_locker(a):  # gameplay: the locker wedged across the doorway, tilted
    a.box(0, 2, 16, 30, STEEL_L)
    a.vline(8, 3, 30, STEEL)
    for y in (6, 8, 10):
        a.hline(2, 6, y, STEEL_D)
        a.hline(10, 14, y, STEEL_D)
    a.rect(3, 22, 10, 3, AMBER)
    a.rect(4, 23, 8, 1, INK)
    a.line(0, 2, 15, 0, STEEL_LL)                 # bent top edge
    a.dot(14, 1, YELLOW)


@prop("fallen_locker", 22, 50)
def _fallen_locker(a):  # gameplay: the locker the impact threw across the hallway (seen from above)
    a.rect(2, 4, 20, 46, (0, 0, 0, 90))                # its shadow on the deck
    a.box(0, 0, 18, 46, STEEL_L)
    a.vline(9, 1, 44, STEEL)                          # the seam between its doors
    for y in range(5, 14, 3):                         # vent slots
        a.hline(3, 6, y, STEEL_D)
        a.hline(12, 15, y, STEEL_D)
    a.rect(6, 22, 1, 5, GRAY)                         # handles
    a.rect(11, 22, 1, 5, GRAY)
    a.rect(4, 36, 10, 3, AMBER)                       # name label
    a.rect(5, 37, 8, 1, INK)
    a.line(13, 28, 16, 33, STEEL_D)                   # a dent from the impact
    a.hline(1, 16, 0, STEEL_LL)


@prop("helm_console", 44, 22)
def _helm_console(a):  # flight deck: the long console under the cockpit window
    a.box(0, 8, 44, 14, STEEL)
    a.box(0, 4, 44, 6, STEEL_L)                       # sloped top
    for x, c in ((3, CYAN), (17, GREEN), (31, AMBER)):  # three screens
        a.rect(x, 0, 11, 7, STEEL_D)
        a.rect(x + 1, 1, 9, 5, (8, 30, 40))
        a.hline(x + 2, x + 7, 3, c)
        a.dot(x + 3, 2, c)
    for x in range(3, 42, 3):                          # button rows
        a.dot(x, 12, (GREEN, AMBER, RED, CYAN)[(x // 3) % 4])
        a.dot(x + 1, 15, STEEL_LL)
    a.rect(19, 16, 6, 3, STEEL_D)                      # throttle
    a.rect(21, 14, 2, 3, RED)
    a.rect(0, 20, 44, 2, STEEL_D)


@prop("pilot_chair", 16, 20)
def _pilot_chair(a):  # seen from behind, facing the console
    a.box(1, 0, 14, 12, (41, 60, 120))
    a.rect(2, 1, 12, 2, (61, 90, 160))
    a.rect(6, 4, 4, 6, (30, 44, 96))                   # headrest seam
    a.box(0, 10, 16, 5, STEEL)                         # armrests and seat
    a.rect(6, 15, 4, 3, STEEL_D)                       # post
    a.rect(3, 18, 10, 2, STEEL_D)                      # base


@prop("nav_table", 32, 24)
def _nav_table(a):  # holographic route table: Mars to Earth, like the film's dashboard
    a.box(2, 12, 28, 12, STEEL)
    a.rect(0, 10, 32, 4, STEEL_L)
    a.rect(1, 10, 30, 1, STEEL_LL)
    for i in range(16):                                # the route, projected above it
        x = 4 + i * 24 // 15
        y = 8 - round(5 * math.sin(i / 15 * math.pi))
        a.dot(x, y, (CYAN[0], CYAN[1], CYAN[2], 200) if i < 14 else (60, 140, 160, 200))
    a.disc(4, 8, 1.5, (200, 80, 44))                   # Mars
    a.disc(28, 7, 2.0, BLUE)                           # Earth
    a.rect(25, 3, 3, 3, WHITE)                         # the ship, almost home
    a.rect(6, 16, 20, 2, (8, 30, 40))
    a.hline(7, 18, 16, CYAN)


@prop("route_map", 30, 14, solid=False)
def _route_map(a):  # wall screen: DISTANCE TO EARTH
    a.rect(0, 0, 30, 14, STEEL)
    a.rect(1, 1, 28, 12, (4, 12, 18))
    for i in range(12):
        a.dot(3 + i * 2, 9 - round(4 * math.sin(i / 11 * math.pi)), CYAN)
    a.dot(3, 9, (200, 80, 44))
    a.rect(26, 7, 2, 2, BLUE)
    a.text(3, 2, "EARTH", (90, 170, 190))


@prop("table", 24, 16)
def _table(a):
    a.box(0, 0, 24, 12, BROWN)
    a.rect(1, 1, 22, 1, shade(BROWN, 1.3))
    a.rect(2, 12, 2, 4, BROWN_D)
    a.rect(20, 12, 2, 4, BROWN_D)
    a.rect(4, 3, 3, 3, WHITE)                      # a mug
    a.dot(5, 4, BROWN_D)
    a.rect(14, 4, 6, 4, GRAY)                      # a tablet
    a.rect(15, 5, 4, 2, BLUE)


@prop("stool", 8, 10)
def _stool(a):
    a.box(0, 0, 8, 4, STEEL_LL)
    a.rect(3, 4, 2, 6, STEEL)


@prop("duffel", 14, 8)
def _duffel(a):
    a.box(0, 1, 14, 7, (60, 90, 70))
    a.hline(2, 11, 0, (40, 60, 50))
    a.rect(6, 3, 2, 2, AMBER)


@prop("guitar", 10, 22)
def _guitar(a):
    a.disc(5, 16, 4.5, BROWN)
    a.disc(5, 11, 3.5, BROWN)
    a.disc(5, 15, 1.2, INK)
    a.rect(4, 0, 2, 11, BROWN_D)
    a.rect(3, 0, 4, 2, INK)


@prop("rug", 48, 30, solid=False)
def _rug(a):
    a.rect(0, 0, 48, 30, (100, 60, 50))
    a.rect(2, 2, 44, 26, (130, 80, 60))
    a.rect(6, 6, 36, 18, (100, 60, 50))
    for x in range(8, 41, 6):
        a.rect(x, 13, 3, 4, AMBER)


@prop("photo_wall", 10, 8, solid=False)
def _photo(a):  # crew photo on the wall
    a.rect(0, 0, 10, 8, WHITE)
    a.rect(1, 1, 8, 6, (90, 130, 180))
    for i, c in enumerate((PEACH, (120, 200, 170), AMBER, PEACH)):
        a.dot(2 + i * 2, 4, c)
        a.dot(2 + i * 2, 5, shade(c, 0.7))


@prop("poster_earth", 12, 14, solid=False)
def _poster_earth(a):
    a.rect(0, 0, 12, 14, (16, 20, 44))
    a.disc(6, 6, 4, BLUE)
    a.rect(4, 4, 3, 2, GREEN_D)
    a.rect(6, 7, 2, 2, GREEN_D)
    a.text(1, 9, "HOM", WHITE)


@prop("poster_mars", 12, 14, solid=False)
def _poster_mars(a):
    a.rect(0, 0, 12, 14, (40, 16, 20))
    a.disc(6, 6, 4, (200, 80, 44))
    a.dot(4, 5, (150, 50, 30))
    a.text(1, 9, "MRS", PEACH)


@prop("mess_table", 40, 18)
def _mess_table(a):
    a.box(0, 2, 40, 12, STEEL_LL)
    a.rect(1, 3, 38, 1, GRAY)
    a.rect(3, 14, 3, 4, STEEL)
    a.rect(34, 14, 3, 4, STEEL)
    for x in (4, 16, 28):  # food trays
        a.box(x, 5, 8, 6, (70, 80, 100))
        a.rect(x + 1, 6, 3, 2, (120, 180, 80))
        a.rect(x + 4, 7, 3, 3, (220, 160, 90))


@prop("bench", 40, 8)
def _bench(a):
    a.box(0, 0, 40, 5, NAVY_L)
    a.rect(4, 5, 2, 3, STEEL)
    a.rect(34, 5, 2, 3, STEEL)


@prop("counter", 32, 22)
def _counter(a):
    a.box(0, 6, 32, 16, STEEL)
    a.box(0, 4, 32, 4, GRAY)
    a.rect(3, 4, 9, 3, STEEL_D)                    # sink
    a.rect(6, 1, 1, 4, STEEL_LL)
    a.rect(4, 12, 10, 1, STEEL_D)
    a.rect(18, 12, 10, 1, STEEL_D)
    a.rect(16, 7, 1, 14, STEEL_D)


@prop("coffee", 12, 18)
def _coffee(a):  # the coffee machine that should have been replaced months ago
    a.box(0, 0, 12, 18, (40, 40, 48))
    a.rect(2, 2, 8, 3, (60, 60, 70))
    a.dot(3, 3, RED)
    a.dot(5, 3, GREEN)
    a.rect(3, 8, 6, 6, INK)
    a.rect(4, 11, 4, 3, WHITE)                     # a cup
    a.rect(9, 0, 3, 2, AMBER)                      # a sticky note: FIX ME


@prop("fridge", 16, 28)
def _fridge(a):
    a.box(0, 0, 16, 28, (210, 214, 220))
    a.hline(1, 14, 10, (150, 154, 166))
    a.rect(12, 3, 1, 5, STEEL)
    a.rect(12, 13, 1, 8, STEEL)
    a.rect(3, 14, 4, 3, YELLOW)                    # magnets / notes
    a.rect(4, 4, 3, 3, (90, 130, 180))


@prop("food_crate", 14, 12)
def _food_crate(a):
    a.box(0, 0, 14, 12, (120, 160, 90))
    a.hline(1, 12, 5, (90, 120, 70))
    a.text(3, 6, "RAT", (60, 80, 50))


@prop("med_bed", 16, 30)
def _med_bed(a):
    a.box(0, 0, 16, 30, STEEL_LL)
    a.rect(1, 1, 14, 27, (230, 236, 240))
    a.rect(2, 2, 12, 5, WHITE)
    a.rect(1, 12, 14, 14, (150, 200, 220))
    a.rect(0, 28, 16, 2, STEEL)


@prop("iv_stand", 8, 24)
def _iv(a):
    a.rect(3, 4, 1, 18, STEEL_LL)
    a.box(1, 0, 6, 6, (200, 230, 240))
    a.rect(2, 2, 4, 3, (120, 200, 230))
    a.rect(0, 22, 8, 2, STEEL)


@prop("med_cabinet", 16, 22)
def _med_cabinet(a):
    a.box(0, 0, 16, 22, (230, 232, 236))
    a.rect(6, 4, 4, 10, RED)
    a.rect(3, 7, 10, 4, RED)
    a.hline(1, 14, 17, (180, 184, 190))


@prop("scanner", 24, 20)
def _scanner(a):
    a.box(0, 6, 24, 14, STEEL)
    a.box(2, 0, 20, 9, STEEL_L)
    a.rect(4, 2, 16, 5, (8, 30, 40))
    a.hline(5, 18, 4, CYAN)
    for x in range(5, 19, 3):
        a.dot(x, 3 + (x % 2), GREEN)


@prop("sofa", 40, 16)
def _sofa(a):
    a.box(0, 0, 40, 8, (70, 70, 140))
    a.box(0, 6, 40, 10, (90, 90, 170))
    a.box(0, 2, 5, 14, (70, 70, 140))
    a.box(35, 2, 5, 14, (70, 70, 140))
    a.vline(20, 7, 14, (70, 70, 140))


@prop("coffee_table", 20, 10)
def _coffee_table(a):
    a.box(0, 0, 20, 7, (60, 50, 70))
    a.rect(2, 7, 2, 3, STEEL_D)
    a.rect(16, 7, 2, 3, STEEL_D)
    a.rect(4, 2, 4, 3, PEACH)                      # a book


@prop("telescope", 14, 22)
def _telescope(a):
    a.line(3, 2, 11, 8, STEEL_LL)
    a.line(3, 3, 11, 9, STEEL_L)
    a.line(4, 3, 12, 9, STEEL_L)
    a.rect(2, 1, 3, 3, INK)
    a.line(7, 9, 3, 21, STEEL)
    a.line(7, 9, 11, 21, STEEL)
    a.vline(7, 9, 21, STEEL)


@prop("plant", 12, 18)
def _plant(a):
    a.box(2, 11, 8, 7, BROWN)
    for x, y, h in ((5, 2, 9), (3, 5, 6), (8, 4, 7), (6, 0, 4)):
        a.rect(x, y, 2, h, GREEN_D)
        a.dot(x, y, GREEN)
    a.rect(1, 6, 3, 2, GREEN)
    a.rect(8, 7, 3, 2, GREEN)


@prop("plant_tall", 14, 26)
def _plant_tall(a):
    a.box(3, 19, 8, 7, (60, 60, 80))
    for i in range(7):
        y = 18 - i * 3
        a.rect(6, y - 2, 2, 4, GREEN_D)
        a.rect(2 + (i % 2) * 6, y - 1, 5, 2, GREEN if i % 3 else (120, 220, 90))


@prop("grow_bed", 32, 18)
def _grow_bed(a):
    a.box(0, 6, 32, 12, (60, 70, 90))
    a.rect(1, 6, 30, 4, (70, 50, 40))             # soil
    for x in range(2, 30, 4):
        a.rect(x, 1, 3, 6, GREEN_D)
        a.rect(x, 1, 1, 2, GREEN)
        a.dot(x + 2, 3, (120, 220, 90))
    a.rect(0, 0, 32, 1, (200, 120, 255))           # grow light bar
    a.dot(31, 12, BLUE)


@prop("water_tank", 16, 24)
def _water_tank(a):
    a.box(0, 0, 16, 24, (90, 140, 170))
    a.rect(2, 4, 12, 16, (60, 110, 160))
    a.rect(2, 10, 12, 10, (40, 120, 200))
    a.hline(2, 13, 10, (120, 200, 240))
    a.rect(6, 0, 4, 2, STEEL)


@prop("crates", 16, 20)
def _crates(a):
    a.box(0, 8, 16, 12, BROWN)
    a.line(1, 9, 14, 18, BROWN_D)
    a.line(14, 9, 1, 18, BROWN_D)
    a.box(3, 0, 11, 9, (190, 110, 60))
    a.hline(4, 12, 4, BROWN_D)


@prop("barrel", 12, 16)
def _barrel(a):
    a.box(0, 0, 12, 16, (60, 90, 160))
    a.hline(1, 10, 4, (40, 60, 120))
    a.hline(1, 10, 11, (40, 60, 120))
    a.rect(4, 6, 4, 3, YELLOW)
    a.dot(5, 7, INK)


@prop("shelf", 32, 26)
def _shelf(a):
    a.box(0, 0, 32, 26, STEEL)
    for y in (8, 17):
        a.rect(1, y, 30, 1, STEEL_LL)
    for x, y, w, h, c in ((2, 3, 6, 5, BROWN), (10, 4, 5, 4, (60, 100, 200)), (18, 2, 8, 6, (190, 110, 60)),
                          (3, 12, 9, 5, GRAY), (15, 13, 5, 4, (120, 160, 90)), (22, 11, 7, 6, BROWN),
                          (4, 20, 6, 5, (60, 90, 160)), (13, 21, 12, 4, STEEL_LL)):
        a.box(x, y, w, h, c)


@prop("tool_board", 24, 14, solid=False)
def _tool_board(a):
    a.rect(0, 0, 24, 14, (60, 50, 40))
    a.rect(2, 2, 1, 9, STEEL_LL)                  # screwdriver
    a.rect(1, 2, 3, 3, RED)
    a.line(6, 2, 10, 10, STEEL_LL)                # wrench
    a.disc(6, 3, 1.5, STEEL_LL)
    a.rect(13, 3, 8, 3, STEEL_LL)                 # hammer
    a.rect(16, 6, 2, 6, BROWN)


@prop("generator", 32, 30)
def _generator(a):
    a.box(0, 6, 32, 24, STEEL)
    a.box(2, 0, 28, 10, STEEL_L)
    for x in range(4, 28, 4):
        a.vline(x, 12, 26, STEEL_D)
    a.rect(6, 2, 8, 5, (8, 30, 40))
    a.hline(7, 12, 4, AMBER)
    a.disc(23, 4, 2.5, RED_D)
    a.rect(0, 26, 32, 4, STEEL_D)
    a.rect(13, 14, 6, 6, (40, 40, 52))
    a.text(13, 15, "6", YELLOW)


@prop("reactor", 40, 40)
def _reactor(a):
    a.box(2, 10, 36, 30, STEEL)
    a.disc(20, 18, 13, STEEL_L)
    a.disc(20, 18, 10, (20, 40, 60))
    a.disc(20, 18, 7, (40, 120, 200))
    a.disc(20, 18, 4, CYAN)
    a.disc(20, 18, 2, WHITE)
    for x in (6, 34):
        a.rect(x - 2, 6, 4, 34, STEEL_L)
        a.hline(x - 2, x + 1, 6, STEEL_LL)
    a.rect(2, 36, 36, 4, STEEL_D)
    for x in range(6, 36, 6):
        a.rect(x, 37, 3, 1, (x // 6) % 2 and YELLOW or INK)


@prop("workbench", 32, 20)
def _workbench(a):
    a.box(0, 4, 32, 10, BROWN)
    a.rect(2, 14, 3, 6, STEEL)
    a.rect(27, 14, 3, 6, STEEL)
    a.rect(4, 1, 6, 4, STEEL_LL)                   # a vice
    a.rect(13, 5, 7, 4, (60, 100, 200))            # a circuit board
    for x in range(14, 19, 2):
        a.dot(x, 6, GREEN)
    a.rect(23, 3, 6, 3, RED)                       # a toolbox


@prop("pipes", 32, 10, solid=False)
def _pipes(a):  # floor pipe run (decal)
    for y, c in ((1, STEEL_L), (5, (110, 80, 60))):
        a.rect(0, y, 32, 3, c)
        a.hline(0, 31, y, shade(c, 1.3))
        for x in range(4, 32, 10):
            a.rect(x, y - 1, 2, 5, STEEL)


@prop("cable", 32, 8, solid=False)
def _cable(a):
    for x in range(32):
        y = 3 + round(2 * math.sin(x / 4))
        a.dot(x, y, (30, 30, 34))
        a.dot(x, y + 1, (60, 60, 70))


@prop("hazard_strip", 32, 4, solid=False)
def _hazard(a):
    for x in range(32):
        a.rect(x, 0, 1, 4, YELLOW if (x // 2) % 2 == 0 else INK)


@prop("vent_floor", 16, 10, solid=False)
def _vent_floor(a):
    a.rect(0, 0, 16, 10, (30, 30, 40))
    for y in range(1, 10, 2):
        a.hline(1, 14, y, (60, 60, 74))


@prop("puddle", 20, 10, solid=False)
def _puddle(a):
    for y in range(10):
        for x in range(20):
            if ((x - 10) / 10) ** 2 + ((y - 5) / 5) ** 2 < 1 and (x * 7 + y * 3) % 11:
                a.dot(x, y, (30, 50, 80, 170))


@prop("scorch", 20, 14, solid=False)
def _scorch(a):
    rng = random.Random(3)
    for y in range(14):
        for x in range(20):
            d = ((x - 10) / 10) ** 2 + ((y - 7) / 7) ** 2
            if d < 1 and rng.random() < 1.1 - d:
                a.dot(x, y, (20, 16, 20, 200))


@prop("debris", 16, 10)
def _debris(a):
    a.box(0, 4, 7, 5, STEEL_L)
    a.line(8, 2, 14, 6, STEEL_LL)
    a.line(8, 3, 14, 7, STEEL)
    a.rect(4, 0, 3, 3, GRAY)


@prop("papers", 14, 8, solid=False)
def _papers(a):
    for x, y in ((0, 2), (5, 0), (8, 4)):
        a.rect(x, y, 5, 4, WHITE)
        a.hline(x + 1, x + 3, y + 1, LAVENDER)


@prop("lab_bench", 32, 20)
def _lab_bench(a):
    a.box(0, 6, 32, 14, (220, 224, 232))
    a.rect(0, 6, 32, 2, WHITE)
    a.rect(3, 0, 4, 7, STEEL)                      # microscope
    a.rect(2, 6, 6, 1, STEEL_D)
    a.rect(4, 0, 3, 2, INK)
    for i, c in enumerate((GREEN, PINK, BLUE, YELLOW)):  # sample tubes
        a.rect(12 + i * 3, 2, 2, 5, (200, 220, 230))
        a.rect(12 + i * 3, 4, 2, 3, c)
    a.box(25, 3, 5, 4, (60, 100, 200))


@prop("server_rack", 14, 28)
def _server_rack(a):
    a.box(0, 0, 14, 28, (30, 30, 40))
    for y in range(3, 26, 4):
        a.rect(2, y, 10, 2, (50, 50, 64))
        a.dot(3, y, GREEN if y % 8 else AMBER)
        a.dot(5, y, BLUE)


@prop("whiteboard", 26, 14, solid=False)
def _whiteboard(a):
    a.rect(0, 0, 26, 14, STEEL_LL)
    a.rect(1, 1, 24, 12, WHITE)
    a.line(3, 9, 8, 4, BLUE)
    a.line(8, 4, 12, 7, BLUE)
    a.line(12, 7, 20, 3, RED)
    a.text(3, 2, "DNA", (60, 100, 200))


@prop("suit_rack", 32, 30)
def _suit_rack(a):
    a.box(0, 0, 32, 30, STEEL_D)
    for x, c in ((2, (230, 230, 236)), (17, (255, 150, 50))):
        a.disc(x + 6, 6, 5, c)                     # helmet
        a.disc(x + 6, 6, 3, INK)
        a.dot(x + 5, 5, CYAN)
        a.box(x + 1, 11, 11, 13, c)                # suit body
        a.rect(x + 3, 24, 3, 5, shade(c, 0.8))
        a.rect(x + 7, 24, 3, 5, shade(c, 0.8))
        a.rect(x + 4, 14, 5, 3, CYAN)


@prop("airlock", 32, 32, solid=False)
def _airlock(a):  # the outer airlock hatch, on the wall
    a.disc(16, 16, 15, STEEL_L)
    a.disc(16, 16, 12, STEEL)
    a.disc(16, 16, 8, STEEL_D)
    a.rect(15, 4, 2, 24, STEEL_LL)
    a.rect(4, 15, 24, 2, STEEL_LL)
    a.disc(16, 16, 3, RED)
    for ang in range(0, 360, 45):
        x = 16 + 13.5 * math.cos(math.radians(ang))
        y = 16 + 13.5 * math.sin(math.radians(ang))
        a.dot(round(x), round(y), YELLOW)


@prop("shuttle", 96, 56)
def _shuttle(a):  # top-down-ish 3/4 view of the escape shuttle, nose right
    a.rect(14, 18, 66, 24, GRAY)                   # body
    for i in range(14):                            # tapered nose
        a.vline(80 + i, 18 + i * 12 // 14, 41 - i * 12 // 14, GRAY)
    a.rect(14, 18, 66, 3, WHITE)
    a.rect(14, 38, 66, 4, STEEL_LL)
    a.rect(20, 28, 60, 2, RED)                     # stripe
    a.rect(70, 22, 14, 7, BLUE)                    # canopy
    a.rect(71, 23, 5, 2, (160, 220, 255))
    for x in (30, 40, 50):
        a.rect(x, 22, 4, 4, BLUE)
    a.rect(4, 22, 10, 16, STEEL_D)                 # engine block
    a.rect(0, 25, 4, 10, (60, 40, 30))
    a.rect(1, 27, 3, 6, AMBER)
    for (x0, y0, x1, y1) in ((24, 18, 40, 4), (24, 41, 40, 54)):  # fins
        a.line(x0, y0, x1, y1, STEEL_L)
        a.line(x0 + 10, y0, x1 + 6, y1, STEEL_L)
        a.line(x1, y1, x1 + 6, y1, STEEL_L)
    for y in range(5, 18):
        a.hline(28 + (18 - y) * 12 // 13, 38 + (18 - y) * 8 // 13, y, STEEL_L)
    for y in range(42, 54):
        a.hline(28 + (y - 41) * 12 // 13, 38 + (y - 41) * 8 // 13, y, STEEL_L)


@prop("seats", 40, 20)
def _seats(a):  # the forward seating deck from the film (seen past the breach)
    for x in (0, 13, 26):
        a.box(x, 0, 12, 6, STEEL)
        a.box(x + 1, 6, 10, 10, (41, 60, 120))
        a.rect(x + 1, 6, 10, 2, (61, 90, 160))
        a.rect(x + 4, 16, 4, 4, STEEL_D)


@prop("bulkhead", 32, 48)
def _bulkhead(a):  # the sealed barrier from the film (vertical slab across the corridor)
    a.box(0, 0, 32, 48, STEEL_L)
    a.rect(4, 0, 4, 48, STEEL)
    for y in range(2, 46, 4):
        a.rect(26, y, 4, 2, AMBER)
    a.rect(10, 14, 12, 10, STEEL_D)                # small view port
    a.rect(11, 15, 10, 8, (60, 10, 24))
    a.dot(14, 18, RED)
    a.dot(17, 20, PINK)
    a.rect(0, 46, 32, 2, INK)


@prop("power_terminal", 36, 22, solid=False)
def _power_terminal(a):  # MAIN POWER OFFLINE (wall screen from the film)
    a.box(0, 0, 36, 18, STEEL)
    a.rect(2, 2, 32, 14, (46, 6, 14))
    a.text(3, 3, "MAIN PWR", RED)
    a.text(5, 10, "OFFLINE", RED)
    a.rect(14, 18, 8, 4, STEEL_D)


@prop("emergency_panel", 14, 14)
def _emergency_panel(a):  # amber hazard panel with the big button
    a.rect(0, 0, 14, 14, AMBER)
    for i in range(0, 14, 4):
        a.rect(i, 0, 2, 2, INK)
        a.rect(i, 12, 2, 2, INK)
    a.rect(2, 2, 10, 10, STEEL_D)
    a.disc(7, 7, 3, (120, 0, 30))


@prop("breach_edge", 16, 48, solid=False)
def _breach_edge(a):  # the torn hull, looking out to space
    rng = random.Random(5)
    for y in range(48):
        edge = 6 + round(4 * math.sin(y / 3.0) + rng.randint(-1, 1))
        a.hline(0, edge, y, SPACE)
        a.dot(edge + 1, y, STEEL_LL)
        if rng.random() < 0.15:
            a.dot(rng.randrange(0, max(1, edge)), y, GRAY)


# --- Gameplay props (same ids as escape_mission.gd) -------------------------------------------

@prop("launch_terminal", 24, 26)
def _launch_terminal(a):
    a.box(2, 10, 20, 16, STEEL)
    a.box(0, 0, 24, 12, STEEL_L)
    a.rect(2, 2, 20, 8, (8, 30, 40))
    a.text(3, 3, "LNCH", CYAN)
    a.hline(3, 20, 8, (40, 140, 160))
    a.rect(5, 15, 3, 2, GREEN)
    a.rect(10, 15, 3, 2, AMBER)
    a.rect(15, 15, 3, 2, RED)


@prop("circuit_cutoff", 18, 24)
def _cutoff(a):
    a.box(0, 0, 18, 24, (200, 140, 30))
    a.rect(2, 2, 14, 20, STEEL_D)
    a.rect(7, 4, 4, 12, STEEL_LL)                  # the big lever
    a.rect(6, 4, 6, 3, RED)
    a.text(3, 18, "CUT", YELLOW)


@prop("fuse_rack", 18, 20)
def _fuse_rack(a):
    a.box(0, 4, 18, 16, STEEL)
    for x in (2, 7, 12):
        a.box(x, 0, 4, 9, (220, 200, 120))
        a.rect(x + 1, 2, 2, 4, AMBER)


@prop("distribution", 32, 30)
def _distribution(a):
    a.box(0, 0, 32, 30, STEEL)
    a.rect(2, 2, 28, 18, STEEL_D)
    for x in range(4, 28, 5):
        a.rect(x, 4, 3, 8, (30, 30, 40))
        a.rect(x, 4, 3, 2, AMBER if x % 2 else GREEN)
    a.rect(4, 14, 24, 4, (40, 40, 52))
    a.text(5, 14, "DIST", YELLOW)
    a.rect(0, 22, 32, 2, YELLOW)
    a.rect(0, 26, 32, 4, STEEL_D)


@prop("aux_panel", 18, 22)
def _aux_panel(a):
    a.box(0, 0, 18, 22, STEEL_L)
    a.rect(2, 2, 14, 10, (20, 26, 40))
    for y in (4, 7, 10):
        a.hline(4, 13, y, (60, 140, 160))
    a.rect(4, 14, 4, 4, RED)
    a.rect(10, 14, 4, 4, GREEN_D)


@prop("freezer", 26, 30)
def _freezer(a):
    a.box(0, 0, 26, 30, (220, 228, 236))
    a.rect(2, 2, 22, 12, (150, 200, 230))
    a.rect(3, 3, 20, 10, (180, 230, 250))
    for x in range(5, 21, 4):  # sample racks behind the glass
        a.rect(x, 5, 2, 6, (120, 200, 160))
    a.rect(2, 17, 10, 3, (8, 30, 40))
    a.text(3, 17, "-80", CYAN)
    a.rect(18, 18, 4, 2, GREEN)


@prop("battery", 24, 20)
def _battery(a):
    a.box(0, 4, 24, 16, (40, 120, 90))
    a.rect(2, 0, 4, 5, STEEL_LL)                   # handles
    a.rect(18, 0, 4, 5, STEEL_LL)
    a.rect(4, 9, 16, 6, (20, 60, 50))
    for x in range(5, 19, 3):
        a.rect(x, 10, 2, 4, GREEN)
    a.rect(9, 16, 6, 2, YELLOW)


@prop("cart", 28, 18)
def _cart(a):
    a.box(0, 2, 28, 10, STEEL_LL)
    a.rect(1, 3, 26, 1, GRAY)
    a.rect(24, 0, 2, 4, STEEL)                     # push bar
    for x in (3, 21):
        a.disc(x + 2, 15, 2.5, INK)
        a.dot(x + 2, 15, STEEL_L)


@prop("sample_case", 18, 14)
def _case(a):
    a.box(0, 2, 18, 12, (230, 236, 244))
    a.rect(6, 0, 6, 3, STEEL)
    a.rect(2, 6, 14, 2, (60, 160, 220))
    a.rect(7, 9, 4, 3, (120, 200, 160))


@prop("socket", 20, 24)
def _socket(a):
    a.box(0, 0, 20, 24, STEEL)
    a.rect(2, 2, 16, 12, (40, 40, 52))
    a.disc(10, 8, 4, (20, 20, 28))
    a.dot(8, 8, AMBER)
    a.dot(12, 8, AMBER)
    a.rect(2, 16, 16, 3, YELLOW)
    a.rect(2, 20, 16, 2, INK)


@prop("clamp_console", 24, 26)
def _clamp_console(a):
    a.box(2, 10, 20, 16, STEEL)
    a.box(0, 0, 24, 12, STEEL_L)
    a.rect(2, 2, 20, 8, (40, 30, 10))
    a.text(3, 3, "CLMP", AMBER)
    a.disc(12, 17, 3, RED)
    a.rect(4, 22, 16, 2, YELLOW)


@prop("clamp_arm", 16, 24)
def _clamp_arm(a):  # the docking clamps holding the shuttle
    a.box(4, 0, 8, 16, STEEL_L)
    a.box(0, 14, 16, 10, STEEL)
    a.rect(2, 18, 12, 2, YELLOW)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, img in TILES.items():
        img.save(OUT / f"{name}.png")
    for name, a in ART.items():
        a.image().save(OUT / f"{name}.png")
    # Contact sheet for review.
    items = list(TILES.items()) + [(n, a.image()) for n, a in ART.items()]
    cols, cell = 10, 112
    rows = -(-len(items) // cols)
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (20, 22, 36, 255))
    for i, (name, img) in enumerate(items):
        im = img.copy()
        im.thumbnail((cell - 8, cell - 8), Image.NEAREST)
        sheet.alpha_composite(im, ((i % cols) * cell + 4, (i // cols) * cell + 4))
    (ROOT / "docs").mkdir(exist_ok=True)
    sheet.save(ROOT / "docs/ship_art.png")
    print(f"wrote {len(TILES)} tiles + {len(ART)} props to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
