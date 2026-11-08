#!/usr/bin/env python3
"""Ship tiles in the opening film's look. Owner: D.

    python3 tools/make_ship_tiles.py        # needs: pip install pillow

Draws every map tile with the palette from tools/make_intro.py, so the level
matches the cutscene: navy cabin walls with the light stripe, green lights and
ceiling light strips; steel decking; bulkhead doors with amber dashes. Tops of
walls are the light-gray hull plating of the ship seen outside, and where the
hull meets space ("hull") you see its side with the red stripe, so the outline
of the map reads as the ship itself.

Tiles are 16x16 art px saved at 2x (32x32 world px); the floor is one seamless
128x128 art px texture (256x256 world px). Writes assets/tiles/*.png.
(These used to come from gen_placeholder_assets.py, which no longer draws tiles.)
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from make_intro import (AMBER, BLUE, GRAY, GREEN, INK, NAVY, NAVY_D, NAVY_L, RED,  # noqa: E402
                        STEEL, STEEL_D, STEEL_L, STEEL_LL, WHITE)

OUT = ROOT / "assets/tiles"
GROOVE = (48, 46, 60)        # floor grooves in the cutscene
SEAM = (160, 160, 170)       # hull panel seams in the cutscene
CAP = (170, 171, 181)        # hull plating seen from above
CAP_HI = GRAY
CAP_LO = STEEL_LL


def new(w=16, h=16):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def save(im: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(OUT / f"{name}.png")
    print("wrote", (OUT / f"{name}.png").relative_to(ROOT))


def box(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def cap(d, top=0, bottom=15) -> None:
    """Hull plating seen from above."""
    box(d, 0, top, 15, bottom, CAP)
    box(d, 0, top, 15, top, CAP_HI)
    box(d, 0, bottom, 15, bottom, CAP_LO)
    box(d, 0, top, 0, bottom, SEAM)
    for x, y in ((4, top + 3), (11, top + 3)):
        if y < bottom:
            d.point((x, y), fill=CAP_LO)


def wall() -> None:
    im, d = new()
    cap(d)
    box(d, 7, 6, 8, 9, SEAM)  # a panel join
    save(im, "wall")


def hull() -> None:
    """A wall with space below it: the side of the hull, like the ship outside."""
    im, d = new()
    cap(d, 0, 3)
    box(d, 0, 4, 15, 14, STEEL_LL)
    box(d, 0, 4, 15, 4, GRAY)
    box(d, 0, 8, 15, 9, RED)              # the red stripe along the lower hull
    box(d, 0, 4, 0, 14, SEAM)
    box(d, 0, 15, 15, 15, INK)
    save(im, "hull")


def navy_panel(d, top: int, bottom: int, stripe: bool, light: bool, base: bool) -> None:
    box(d, 0, top, 15, bottom, NAVY)
    box(d, 11, top, 11, bottom, NAVY_D)           # panel seam
    box(d, 12, top, 12, bottom, NAVY_L)
    if stripe:
        box(d, 0, top + 4, 15, top + 5, NAVY_L)    # the cabin's light stripe
    if light:
        box(d, 4, top + 8, 5, top + 8, GREEN)      # indicator light
    if base:
        box(d, 0, bottom - 3, 15, bottom - 2, NAVY_D)
        box(d, 0, bottom - 1, 15, bottom, STEEL)


def ceiling(d, top: int) -> int:
    """Ceiling band under the lip: steel with a white light strip. Returns next free row."""
    box(d, 0, top, 15, top + 3, STEEL_D)
    box(d, 0, top + 2, 15, top + 2, STEEL_L)
    box(d, 3, top + 3, 12, top + 3, WHITE)         # ceiling light, as in the cabin
    return top + 4


def wall_faces() -> None:
    # Upper half of a 2-tall back wall: lip, ceiling band, navy.
    im, d = new()
    cap(d, 0, 2)
    t = ceiling(d, 3)
    navy_panel(d, t, 15, stripe=False, light=False, base=False)
    save(im, "wall_face_upper")
    # Lower half: navy with the stripe, a green light, baseboard.
    im, d = new()
    navy_panel(d, 0, 15, stripe=True, light=True, base=True)
    save(im, "wall_face")
    # One tile tall: lip, navy with stripe, baseboard.
    im, d = new()
    cap(d, 0, 2)
    navy_panel(d, 3, 15, stripe=False, light=False, base=True)
    box(d, 0, 6, 15, 6, NAVY_L)
    box(d, 4, 9, 5, 9, GREEN)
    save(im, "wall_face_single")


def floor() -> None:
    """Seamless steel decking: staggered plates, grooves like the cutscene floor."""
    S = 128
    im, d = new(S, S)
    box(d, 0, 0, S - 1, S - 1, STEEL)
    rng = random.Random(7)
    for row in range(S // 16):
        y0 = row * 16
        shift = 16 if row % 2 else 0
        for x in range(0, S, 4):                     # fine grooves
            box(d, x, y0 + 2, x, y0 + 13, GROOVE)
        box(d, 0, y0, S - 1, y0, STEEL_D)            # plate seams
        box(d, 0, y0 + 1, S - 1, y0 + 1, STEEL_L)
        for x in range(shift, S + shift, 32):
            xx = x % S
            box(d, xx, y0, xx, y0 + 15, STEEL_D)
            box(d, (xx + 1) % S, y0 + 1, (xx + 1) % S, y0 + 15, (70, 68, 86))
            for dx, dy in ((3, 4), (3, 12), (28, 4), (28, 12)):   # rivets
                d.point(((xx + dx) % S, y0 + dy), fill=STEEL_LL)
    for _ in range(3):                                # a few service grates
        gx, gy = rng.randrange(0, S // 32) * 32 + 8, rng.randrange(0, S // 16) * 16 + 3
        box(d, gx, gy, gx + 15, gy + 9, STEEL_D)
        for x in range(gx + 1, gx + 15, 2):
            box(d, x, gy + 1, x, gy + 8, INK)
    save(im, "floor")


def rail() -> None:
    im, d = new()
    box(d, 0, 0, 15, 15, STEEL_D)
    box(d, 2, 0, 13, 15, (24, 28, 44))
    for x in (4, 11):
        box(d, x, 0, x, 15, STEEL_LL)
        box(d, x + 1, 0, x + 1, 15, STEEL)
    for y in range(0, 16, 4):                         # amber dashes on both edges
        box(d, 0, y, 1, y + 1, AMBER)
        box(d, 14, y + 2, 15, y + 3, AMBER)
    save(im, "rail")


def doors() -> None:
    im, d = new()
    box(d, 0, 0, 15, 15, STEEL_L)
    box(d, 0, 0, 15, 0, STEEL_LL)
    box(d, 5, 0, 6, 15, STEEL)
    for x in range(0, 16, 4):                         # amber dashes, like the bulkhead
        box(d, x, 12, x + 1, 13, AMBER)
    box(d, 0, 14, 15, 15, INK)
    box(d, 10, 4, 12, 6, RED)                         # locked lamp
    save(im, "door_closed")
    im, d = new()
    box(d, 0, 0, 15, 15, (8, 10, 16))
    box(d, 0, 0, 1, 15, STEEL_L)
    box(d, 14, 0, 15, 15, STEEL_L)
    box(d, 3, 0, 12, 1, STEEL)
    for x in range(2, 14, 4):
        box(d, x, 14, x + 1, 15, AMBER)
    box(d, 7, 4, 8, 5, GREEN)
    save(im, "door_open")


if __name__ == "__main__":
    wall(); hull(); wall_faces(); floor(); rail(); doors()
    _ = BLUE  # palette import kept whole on purpose
