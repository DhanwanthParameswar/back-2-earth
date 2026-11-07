#!/usr/bin/env python3
"""Render data/ship_layout.txt with the current art to docs/map_preview.png.

Owner: B. A quick look at the level without opening Godot. It mirrors the
game's 3/4 rules (wall faces where a wall has floor below it, props and the
astronaut sorted by their feet, soft shadows) but it is still a static
approximation: no HUD, doors drawn closed. Needs: pip install pillow
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "assets"
T = 32
SOLID = "#w"


def load(rel: str) -> Image.Image:
    return Image.open(A / rel).convert("RGBA")


def main(skin: str = "classic") -> None:
    rows = [r for r in (ROOT / "data/ship_layout.txt").read_text().split("\n") if r]
    w, h = max(len(r) for r in rows), len(rows)
    rows = [r.ljust(w, "#") for r in rows]

    def cell(c: int, r: int) -> str:
        return rows[r][c] if 0 <= r < h and 0 <= c < w else "#"

    im = Image.new("RGBA", (w * T, h * T), (2, 2, 8, 255))
    tiles = {k: load(f"tiles/{k}.png") for k in ["floor", "wall", "wall_face", "wall_face_upper", "wall_face_single", "window", "rail", "door_closed"]}
    for r in range(h):
        for c in range(w):
            ch = cell(c, r)
            if ch == "#":
                if cell(c, r + 1) not in SOLID:
                    key = "wall_face" if cell(c, r - 1) == "#" else "wall_face_single"
                elif cell(c, r + 1) == "#" and cell(c, r + 2) not in SOLID:
                    key = "wall_face_upper"
                else:
                    key = "wall"
            elif ch == "w":
                key = "window"
            elif ch in "|CS":
                key = "rail"
            elif ch in "123K":
                key = "door_closed"
            else:
                key = "floor"
            im.alpha_composite(tiles[key], (c * T, r * T))

    # Props: (feet_y, sprite, x, y) sorted by feet, like Godot's y-sort.
    props = []
    drop = {"T": 12, "P": 12, "L": 12, "O": 28, "x": 8, "N": 4, "C": 12, "@": 14}
    names = {"T": "terminal", "P": "power_console", "L": "clamp_console", "O": "pod",
             "x": "debris", "N": "core", "C": "crate"}
    skin_sheet = load(f"sprites/astronaut_{skin}.png")
    fw = skin_sheet.width // 6
    player = skin_sheet.crop((5 * fw, 0, 6 * fw, skin_sheet.height))
    for r in range(h):
        for c in range(w):
            ch = cell(c, r)
            cx, cy = c * T + 16, r * T + 16
            if ch == "S":
                plate = load("sprites/plate.png")
                im.alpha_composite(plate, (cx - 16, cy - 16))
            if ch in names or ch == "@":
                spr = player if ch == "@" else load(f"sprites/{names[ch]}.png")
                base = cy + drop[ch]
                props.append((base, spr, cx, ch))
    shadow_layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow_layer)
    for base, spr, cx, ch in props:
        rw = max(8, spr.width // 2 - 2)
        sd.ellipse([cx - rw, base - 4, cx + rw, base + 3], fill=(0, 0, 0, 90))
    im.alpha_composite(shadow_layer)
    for base, spr, cx, ch in sorted(props, key=lambda p: p[0]):
        im.alpha_composite(spr, (cx - spr.width // 2, base - spr.height))
    out = ROOT / "docs/map_preview.png"
    out.parent.mkdir(exist_ok=True)
    im.save(out)
    print("wrote", out.relative_to(ROOT))


if __name__ == "__main__":
    main()
