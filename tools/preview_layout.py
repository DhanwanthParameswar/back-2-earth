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
    SOLID_ALL = "#wW"
    tiles = {k: load(f"tiles/{k}.png") for k in
             ["floor", "wall", "wall_face", "wall_face_upper", "wall_face_single", "rail", "door_closed"]}
    floor = tiles["floor"]

    # Space windows (W): a still of the nebula video behind the glass.
    wins = [(c, r) for r in range(h) for c in range(w) if cell(c, r) == "W"]
    if wins:
        x0, x1 = min(c for c, _ in wins) * T, (max(c for c, _ in wins) + 1) * T
        y0, y1 = min(r for _, r in wins) * T, (max(r for _, r in wins) + 1) * T
        still_path = ROOT / "art_source/nebula_frame0.png"
        if still_path.exists():
            still = Image.open(still_path).convert("RGBA")
            # Same framing as SpaceWindow.FOCUS at the start of a run.
            focus_x, focus_y = 330, 40
            ox = min(max(focus_x - (x1 - x0) // 2, 0), still.width - (x1 - x0))
            oy = min(max(focus_y - (y1 - y0) // 2, 0), still.height - (y1 - y0))
            im.alpha_composite(still.crop((ox, oy, ox + x1 - x0, oy + y1 - y0)), (x0, y0))

    for r in range(h):
        for c in range(w):
            ch = cell(c, r)
            if ch in "wW":
                continue  # glass (frames drawn below)
            if ch == "#":
                if cell(c, r + 1) not in SOLID_ALL:
                    key = "wall_face" if cell(c, r - 1) == "#" else "wall_face_single"
                elif cell(c, r + 1) == "#" and cell(c, r + 2) not in SOLID_ALL:
                    key = "wall_face_upper"
                else:
                    key = "wall"
            elif ch in "|CS":
                key = "rail"
            else:
                key = "floor"
            if key == "floor":  # one continuous floor, sampled by world position
                sx, sy = (c * T) % floor.width, (r * T) % floor.height
                im.alpha_composite(floor.crop((sx, sy, sx + T, sy + T)), (c * T, r * T))
                if ch in "123K":
                    im.alpha_composite(tiles["door_closed"], (c * T, r * T))
            else:
                im.alpha_composite(tiles[key], (c * T, r * T))

    d = ImageDraw.Draw(im)
    # Debris lane guide lines.
    for c in sorted({c for r in range(h) for c in range(w) if cell(c, r) == "x"}):
        x = c * T + 16
        for r in range(h):
            if cell(c, r) not in "#wW|CS":
                for side in (-11, 11):
                    d.rectangle([x + side - 1, r * T, x + side, r * T + T - 1], fill=(160, 0, 50, 255))
    # Window frames, one pane per group (mirrors ShipBuilder._draw_window_frame).
    def frame(ch: str) -> None:
        cells = [(c, r) for r in range(h) for c in range(w) if cell(c, r) == ch]
        if not cells:
            return
        fx0, fx1 = min(c for c, _ in cells) * T, (max(c for c, _ in cells) + 1) * T
        fy0, fy1 = min(r for _, r in cells) * T, (max(r for _, r in cells) + 1) * T
        d.rectangle([fx0, fy0, fx1 - 1, fy0 + 5], fill=(58, 56, 72, 255))
        d.rectangle([fx0, fy0, fx0 + 5, fy1 - 1], fill=(58, 56, 72, 255))
        d.rectangle([fx1 - 6, fy0, fx1 - 1, fy1 - 1], fill=(58, 56, 72, 255))
        d.rectangle([fx0, fy1 - 8, fx1 - 1, fy1 - 1], fill=(95, 92, 112, 255))
        d.rectangle([fx0, fy1 - 2, fx1 - 1, fy1 - 1], fill=(40, 44, 64, 255))
        d.rectangle([fx0 + 6, fy0 + 6, fx1 - 7, fy0 + 7], fill=(112, 122, 156, 255))

    frame("W")
    frame("w")

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
