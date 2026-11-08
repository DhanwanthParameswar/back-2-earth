#!/usr/bin/env python3
"""Draw the Back2Earth logo as true pixel art. Owner: D. Needs: pip install pillow

Writes to assets/menu/ (all 1 image px = 1 art px; the menu draws them 3x
with nearest filtering so every art pixel is a crisp square):
  title.png      "Back2Earth" with outline and a 2 px purple extrusion
  title_two.png  just the cyan "2" face (pulsed as an additive glow)
  earth_map.png  48x24 world map (equirectangular) the spinning Earth shader
                 wraps around a sphere (scripts/ui/menu_earth.gdshader)
and the site/app icon, the same pixel Earth drawn natively at each size:
  assets/icon.png    32 art px, saved 8x (Godot's project icon; the web export
                     makes the page's favicon and home-screen icon from it)
  web/favicon.ico    16 and 32 px drawn natively (+ 48, 64 scaled), served at
                     the site root for browsers that ask for /favicon.ico

Edit the GLYPHS / WORLD drawings below and rerun to change the art.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/menu"

# --- Title glyphs: 15 rows, '#' = filled. Lowercase letters sit on the baseline.
GLYPHS = {
    "B": [
        "#########..",
        "##########.",
        "###....####",
        "###.....###",
        "###.....###",
        "###....###.",
        "#########..",
        "##########.",
        "###....####",
        "###.....###",
        "###.....###",
        "###.....###",
        "###....####",
        "##########.",
        "#########..",
    ],
    "a": [
        "..######..",
        ".########.",
        ".......###",
        "...#######",
        ".#########",
        "###....###",
        "###....###",
        "###...####",
        ".#########",
        "..####.###",
    ],
    "c": [
        "..######.",
        ".########",
        "####...##",
        "###......",
        "###......",
        "###......",
        "###......",
        "####...##",
        ".########",
        "..######.",
    ],
    "k": [
        "###.......",
        "###.......",
        "###.......",
        "###.......",
        "###.......",
        "###....###",
        "###...###.",
        "###..###..",
        "######....",
        "#####.....",
        "######....",
        "###.###...",
        "###..###..",
        "###...###.",
        "###....###",
    ],
    "2": [
        "..#######..",
        ".#########.",
        "####...####",
        "###.....###",
        "........###",
        ".......####",
        ".....#####.",
        "...#####...",
        "..####.....",
        ".####......",
        "####.......",
        "###........",
        "###........",
        "###########",
        "###########",
    ],
    "E": [
        "##########",
        "##########",
        "###.......",
        "###.......",
        "###.......",
        "###.......",
        "########..",
        "########..",
        "###.......",
        "###.......",
        "###.......",
        "###.......",
        "###.......",
        "##########",
        "##########",
    ],
    "r": [
        "###.#####",
        "#########",
        "#####....",
        "####.....",
        "###......",
        "###......",
        "###......",
        "###......",
        "###......",
        "###......",
    ],
    "t": [
        "........",
        "..###...",
        "..###...",
        "..###...",
        "########",
        "########",
        "..###...",
        "..###...",
        "..###...",
        "..###...",
        "..###...",
        "..###...",
        "..####..",
        "...#####",
        "....####",
    ],
    "h": [
        "###.......",
        "###.......",
        "###.......",
        "###.......",
        "###.......",
        "###.#####.",
        "##########",
        "####...###",
        "###....###",
        "###....###",
        "###....###",
        "###....###",
        "###....###",
        "###....###",
        "###....###",
    ],
}
WORD = "Back2Earth"
CAP = 15        # glyph height in art px
GAP = 2         # space between letters
DEPTH = 2       # extrusion below the letters

# Palette (title).
OUTLINE = (18, 10, 51)
FACE = [(250, 250, 255)] * 10 + [(222, 218, 255)] * 3 + [(186, 176, 248)] * 2  # by glyph row
EXTRUDE = [(108, 82, 216), (70, 51, 158)]
CYAN_FACE = [(150, 250, 255)] * 2 + [(61, 240, 255)] * 9 + [(31, 184, 224)] * 4
CYAN_EXTRUDE = [(26, 111, 176), (18, 76, 133)]

# --- World map: 48 x 24 cells (7.5 degrees each), lon -180..180, lat 90..-90.
# . ocean   # land   s desert   * ice
WORLD = [
    "************************************************",
    "..........######..****......#..................",
    "..####.##########..****.....##..##############..",
    ".######.########...****..#.####################.",
    ".....##########.##.......#.##..#################",
    ".......##########......##.#######.###########...",
    ".......#########........##.##.###########.#.#...",
    "........#######........ss#sss##sss######.#......",
    ".........###.#.........ssssssssssss#####.#......",
    "...........##.##.......ssssssss.ss.###.###......",
    ".............##.##.....#########....#.##..#.....",
    "..............####.......######.....##.##.......",
    ".............########.....#####......#.####.....",
    ".............#######......#####.......##........",
    "..............#####.......####.#.....######.....",
    "...............####........###......#sssss#.....",
    "...............###.........##.......#######.#...",
    "...............##.........................#..#..",
    "...............##...............................",
    "...............#................................",
    "................................................",
    "......********************************..........",
    "************************************************",
    "************************************************",
]
MAP_COLORS = {
    ".": (36, 98, 214),    # ocean
    "#": (72, 176, 62),    # forest / grass
    "s": (204, 178, 102),  # desert
    "*": (236, 244, 255),  # ice
}


def render_title() -> None:
    cols = []
    x = 0
    for ch in WORD:
        rows = GLYPHS[ch]
        pad = CAP - len(rows)
        cols.append((x, ch, [""] * pad + rows if pad else rows))
        x += len(rows[0]) + GAP
    width = x - GAP + 2
    height = CAP + DEPTH + 2
    faces = {}     # (x, y) -> color, letter fronts
    extrude = {}   # (x, y) -> color, the purple depth under them
    for x0, ch, rows in cols:
        cyan = ch == "2"
        for gy, row in enumerate(rows):
            for gx, c in enumerate(row):
                if c != "#":
                    continue
                x, y = x0 + gx + 1, gy + 1
                faces[(x, y)] = (CYAN_FACE if cyan else FACE)[gy]
                for d in range(1, DEPTH + 1):
                    extrude.setdefault((x, y + d), (CYAN_EXTRUDE if cyan else EXTRUDE)[d - 1])
    solid = {**extrude, **faces}
    img = Image.new("RGBA", (width + 2, height + 2), (0, 0, 0, 0))
    # 1 px outline around faces + extrusion.
    for (x, y) in list(solid):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (x + dx, y + dy)
                if n not in solid:
                    img.putpixel((n[0] + 1, n[1] + 1), OUTLINE + (255,))
    for (x, y), col in solid.items():
        img.putpixel((x + 1, y + 1), col + (255,))
    img.save(OUT / "title.png")

    two = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for x0, ch, rows in cols:
        if ch != "2":
            continue
        for gy, row in enumerate(rows):
            for gx, c in enumerate(row):
                if c == "#":
                    two.putpixel((x0 + gx + 2, gy + 2), (120, 250, 255, 255))
    two.save(OUT / "title_two.png")
    print(f"title.png {img.size[0]}x{img.size[1]} art px")


def render_map() -> None:
    w, h = 48, len(WORLD)
    img = Image.new("RGB", (w, h))
    for y, row in enumerate(WORLD):
        row = (row + "." * w)[:w]
        for x, c in enumerate(row):
            img.putpixel((x, y), MAP_COLORS[c])
    img.save(OUT / "earth_map.png")


def earth_icon(size: int) -> Image.Image:
    """The logo's Earth as a size x size pixel-art icon: dark outline, cyan
    atmosphere ring, then the planet lit from the upper left in stepped shades,
    turned to show the Atlantic with both Americas and Africa."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2.0
    r = size / 2.0 - 2.0                       # planet radius; ring + outline outside it
    lon0 = math.radians(-30)                   # which longitude faces us
    tilt = 0.35
    w, h = 48, len(WORLD)
    for y in range(size):
        for x in range(size):
            dx, dy = x + 0.5 - c, y + 0.5 - c
            d = math.hypot(dx, dy)
            if d > r + 2.0:
                continue
            if d > r + 1.0:
                img.putpixel((x, y), (18, 10, 51, 255))
                continue
            if d > r:
                lit = (-dx - dy) / max(d, 1e-6) > -0.4
                img.putpixel((x, y), (61, 240, 255, 255) if lit else (26, 140, 204, 255))
                continue
            nx, ny = dx / r, dy / r
            nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            tx = nx * math.cos(tilt) - ny * math.sin(tilt)
            ty = nx * math.sin(tilt) + ny * math.cos(tilt)
            lat = math.asin(max(-1.0, min(1.0, -ty)))
            lon = math.atan2(tx, nz) + lon0
            u = (lon / (2 * math.pi) + 0.5) % 1.0
            v = 0.5 - lat / math.pi
            mx, my = min(w - 1, int(u * w)), min(h - 1, int(v * h))
            ch = ((WORLD[my] + "." * w)[:w])[mx]
            col = MAP_COLORS[ch]
            light = -0.5 * nx - 0.55 * ny + 0.67 * nz
            k = 1.18 if light > 0.72 else (1.0 if light > 0.12 else (0.62 if light > -0.25 else 0.4))
            col = tuple(min(255, int(v_ * k)) for v_ in col)
            img.putpixel((x, y), col + (255,))
    return img


def render_icon() -> None:
    icon32 = earth_icon(32)
    icon32.resize((256, 256), Image.NEAREST).save(ROOT / "assets/icon.png")
    icon16 = earth_icon(16)
    web = ROOT / "web"
    web.mkdir(exist_ok=True)
    icon64 = icon32.resize((64, 64), Image.NEAREST)
    icon48 = icon16.resize((48, 48), Image.NEAREST)
    # Pillow picks each size from the closest larger image; give it exact ones.
    icon64.save(web / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64)],
                append_images=[icon16, icon32, icon48])
    print("icon.png + web/favicon.ico")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    render_title()
    render_map()
    render_icon()
