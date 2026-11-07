#!/usr/bin/env python3
"""Render data/ship_layout.txt with the current art to docs/map_preview.png.

Owner: B. A quick look at the level without opening Godot (static: no HUD,
no lighting, doors drawn closed). Needs: pip install pillow
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "assets"
T = 32


def load(rel: str) -> Image.Image:
    return Image.open(A / rel).convert("RGBA")


def main() -> None:
    rows = [r for r in (ROOT / "data/ship_layout.txt").read_text().split("\n") if r]
    w, h = max(len(r) for r in rows), len(rows)
    rows = [r.ljust(w, "#") for r in rows]
    im = Image.new("RGBA", (w * T, h * T), (0, 0, 0, 255))
    tiles = {k: load(f"tiles/{k}.png") for k in ["floor", "wall", "window", "rail", "door_closed"]}
    sprites = {"T": "terminal", "P": "power_console", "L": "clamp_console", "O": "pod",
               "x": "debris", "N": "core", "S": "plate", "C": "crate"}
    sprites = {k: load(f"sprites/{v}.png") for k, v in sprites.items()}
    player = load("sprites/player.png").crop((0, 0, 32, 32))

    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            key = {"#": "wall", "w": "window", "|": "rail", "C": "rail", "S": "rail"}.get(ch, "floor")
            if ch in "123K":
                key = "door_closed"
            im.alpha_composite(tiles[key], (c * T, r * T))
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            spr = player if ch == "@" else sprites.get(ch)
            if spr is not None:
                im.alpha_composite(spr, (c * T + 16 - spr.width // 2, r * T + 16 - spr.height // 2))
    out = ROOT / "docs/map_preview.png"
    out.parent.mkdir(exist_ok=True)
    im.save(out)
    print("wrote", out.relative_to(ROOT))


if __name__ == "__main__":
    main()
