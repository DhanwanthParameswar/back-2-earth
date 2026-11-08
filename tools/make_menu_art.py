#!/usr/bin/env python3
"""Draw the title-screen buttons as true pixel art. Owner: D.
Needs: pip install pillow

Labels are drawn with Monocraft (assets/fonts/Monocraft.ttf, the game's font)
at its native pixel size, so 1 font pixel = 1 art pixel. The menu draws the
buttons 3x with nearest filtering, matching the logo
(tools/make_logo.py). The floating sprites (astronaut, debris, ship, planets)
come from tools/import_menu_sprites.py instead.

Writes to assets/menu/:
  btn_<id>.png / btn_<id>_pressed.png   the five menu buttons
and their spots in data/menu_layout.json (merged with the sprites' spots).
Edit a label, size or position and rerun.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/menu"
LAYOUT = ROOT / "data/menu_layout.json"
PIXEL = 3  # menu px per art pixel
FONT_PATH = ROOT / "assets/fonts/Monocraft.ttf"
FONT_SIZE = 9   # Monocraft's native size: 7 px capitals, 6 px per letter

PALETTE = {
    "o": (18, 10, 51),      # outline
    "W": (244, 244, 255),   # white
    "w": (200, 200, 226),   # light gray (shade)
    "g": (128, 128, 164),   # gray
    "d": (78, 78, 116),     # dark gray
    "c": (61, 240, 255),    # cyan
    "C": (24, 150, 200),    # dark cyan
    "k": (10, 10, 26),      # visor black
    "v": (96, 112, 168),    # visor shine
    "b": (40, 58, 160),     # panel blue
    "B": (110, 140, 236),   # panel light blue
    "p": (110, 82, 214),    # purple
    "P": (160, 138, 244),   # light purple
    "q": (66, 46, 150),     # dark purple
    "L": (200, 190, 255),   # lavender (planet ring)
    "r": (110, 104, 140),   # rock
    "R": (160, 154, 190),   # rock light
    "m": (34, 40, 96),      # moon shadow
    "M": (176, 192, 255),   # moon light
}

# Menu positions (top-left, menu px) for each button.
POSITIONS = {
    "btn_start": (203, 166),
    "btn_how": (203, 223),
    "btn_settings": (203, 280),
    "btn_credits": (10, 305),
    "btn_sound": (585, 311),
}

# --- Button icons (one character = one art pixel) ------------------------------
GEAR = ["...#...", ".#####.", ".##.##.", "##...##", ".##.##.", ".#####.", "...#..."]
SPEAKER = ["...#...#.", "..##.#..#", "####..#.#", "####..#.#", "####..#.#", "..##.#..#", "...#...#."]

BUTTONS = {
    # id: (width art px incl. outline, label, face height, icon, primary?)
    "start": (78, "START GAME", 11, None, True),
    "how": (78, "HOW TO PLAY", 11, None, False),
    "settings": (78, "SETTINGS", 11, GEAR, False),
    "credits": (51, "CREDITS", 9, None, False),
    "sound": (15, "", 7, SPEAKER, False),
}
STRIP = 2  # 3D depth under each button


def text_bitmap(text: str) -> list[str]:
    """Render capitals in Monocraft as a 7-row '#'/'.' bitmap, trimmed to the ink."""
    font = ImageFont.truetype(str(FONT_PATH), FONT_SIZE)
    img = Image.new("L", (len(text) * 8 + 8, 16), 0)
    draw = ImageDraw.Draw(img)
    draw.fontmode = "1"  # no antialiasing: whole pixels only
    draw.text((2, 0), text, font=font, fill=255)
    top = font.getbbox("H")[1]  # first row of a capital
    rows = ["".join("#" if img.getpixel((x, y)) else "." for x in range(img.width))
            for y in range(top, top + 7)]
    cols = [x for x in range(img.width) if any(r[x] == "#" for r in rows)]
    return [r[cols[0]:cols[-1] + 1] for r in rows]


def button(bid: str) -> tuple[Image.Image, Image.Image]:
    """A rounded pixel button: outline, light border, face, and a purple 3D
    strip under it. The pressed image drops the face onto the strip."""
    w, label, face_h, icon, primary = BUTTONS[bid]
    h = 1 + 1 + face_h + 1 + STRIP + 1
    border = PALETTE["W"] if primary else PALETTE["c"]
    face = PALETTE["c"] if primary else (21, 20, 71)
    face_top = (168, 250, 255) if primary else (32, 30, 96)
    ink = PALETTE["o"] if primary else PALETTE["W"]
    strip = [(91, 68, 200), (58, 42, 143)]

    def draw(pressed: bool) -> Image.Image:
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dim = 0.82 if pressed else 1.0
        top = STRIP if pressed else 0      # where the outline's top row lands
        bottom = h - 1                     # bottom outline row (fixed)

        def put(x, y, col, shade=True):
            k = dim if shade else 1.0
            img.putpixel((x, y), tuple(int(c * k) for c in col) + (255,))

        for y in range(top, h):
            for x in range(w):
                corner = x in (0, w - 1) and y in (top, bottom)
                if corner:
                    continue
                if x in (0, w - 1) or y in (top, bottom):
                    col = PALETTE["o"]
                elif y > top + 2 + face_h:          # strip rows (normal only)
                    col = strip[min(y - (top + 3 + face_h), STRIP - 1)]
                elif x in (1, w - 2) or y in (top + 1, top + 2 + face_h):
                    inner_corner = x in (1, w - 2) and y in (top + 1, top + 2 + face_h)
                    col = PALETTE["o"] if inner_corner else border
                else:
                    col = face_top if y == top + 2 else face
                put(x, y, col, shade=col != PALETTE["o"])
        # Label (and icon), centered in the face.
        rows = text_bitmap(label) if label else []
        tw = len(rows[0]) if rows else 0
        iw = len(icon[0]) if icon else 0
        total = tw + iw + (3 if icon and label else 0)
        x0 = (w - total) // 2
        if icon:
            iy = top + 2 + (face_h - len(icon)) // 2
            for y, row in enumerate(icon):
                for x, ch in enumerate(row):
                    if ch == "#":
                        put(x0 + x, iy + y, ink)
            x0 += iw + 3
        ty = top + 2 + (face_h - len(rows)) // 2 if rows else 0
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch == "#":
                    put(x0 + x, ty + y, ink)
        return img

    return draw(False), draw(True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    layout = json.loads(LAYOUT.read_text()) if LAYOUT.exists() else {}

    def save(name: str, img: Image.Image) -> None:
        img.save(OUT / f"{name}.png")
        x, y = POSITIONS[name]
        layout[name] = {"x": x, "y": y, "w": img.width * PIXEL, "h": img.height * PIXEL}

    for bid in BUTTONS:
        normal, pressed = button(bid)
        save(f"btn_{bid}", normal)
        pressed.save(OUT / f"btn_{bid}_pressed.png")

    LAYOUT.write_text(json.dumps(layout, indent=1) + "\n")
    print(f"wrote {len(BUTTONS)} buttons (+ pressed) to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
