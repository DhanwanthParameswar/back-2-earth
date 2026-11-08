#!/usr/bin/env python3
"""Turn the original painted title-screen sprites into clean pixel art.
Owner: D. Needs ffmpeg on PATH and: pip install pillow numpy scipy

The floating pieces (astronaut, debris, ship, planets) keep the look of the
original menu art (art_source/menu_loop_1080p.ogv), but that art was AI-made:
smudgy edges, soft gradients, pixels that don't sit on a grid. This script:
  1. takes frame 0 and cuts each piece out of the background,
  2. snaps it to a true pixel grid (CELL source px per art pixel),
  3. reduces it to a small palette, and drops lone stray pixels,
  4. saves assets/menu/<name>.png (1 image px = 1 art px) and its spot in
     data/menu_layout.json (merged with what tools/make_menu_art.py writes).
The menu draws them with nearest filtering at CELL / 3 menu px per art pixel.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as nd

ROOT = Path(__file__).resolve().parent.parent
VIDEO = ROOT / "art_source/menu_loop_1080p.ogv"
OUT = ROOT / "assets/menu"
LAYOUT = ROOT / "data/menu_layout.json"
SCALE = 3   # 1080p source px per menu px
CELL = 3    # source px per art pixel -> 1 menu px per art pixel

# name: (x, y, w, h) box in 1080p source px, and palette size.
SPRITES = {
    "planet": ((1600, 128, 160, 110), 16),
    "satellite": ((1498, 264, 131, 110), 14),
    "hull": ((1709, 347, 128, 107), 14),
    "astronaut": ((1494, 399, 216, 288), 22),
    "antenna": ((1728, 484, 124, 100), 12),
    "canister": ((1672, 600, 118, 98), 16),
    "rock_a": ((1648, 322, 40, 35), 6),
    "rock_b": ((1451, 659, 46, 37), 6),
    "rock_c": ((1622, 690, 42, 33), 6),
    "ship": ((176, 800, 180, 160), 18),
    "moon": ((124, 841, 56, 55), 8),
}
# Pieces this script owns; make_menu_art.py no longer draws them.
STALE = ["rock_d", "rock_e"]


def grab_frame() -> np.ndarray:
    with tempfile.TemporaryDirectory() as tmp:
        png = Path(tmp) / "f0.png"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(VIDEO),
                        "-frames:v", "1", str(png)], check=True)
        return np.asarray(Image.open(png).convert("RGB")).astype(np.float32)


def cut_mask(px: np.ndarray, keep_small: bool) -> np.ndarray:
    """Pixels that belong to the object: clearly different from the space
    around the box. Drops pieces cut by the box edge and stray stars."""
    ring = np.concatenate([px[0], px[-1], px[:, 0], px[:, -1]])
    bg = np.median(ring, axis=0)
    sub = nd.binary_dilation(np.abs(px - bg).max(2) > 16, iterations=1)
    lab, n = nd.label(sub)
    if not n:
        return sub
    sizes = nd.sum(sub, lab, range(1, n + 1))
    h, w = sub.shape
    min_area = 12 if keep_small else max(40, 0.02 * sizes.max())
    keep = []
    for i, sl in enumerate(nd.find_objects(lab)):
        touches = sl[0].start == 0 or sl[1].start == 0 or sl[0].stop == h or sl[1].stop == w
        if not touches and sizes[i] >= min_area:
            keep.append(i + 1)
    mask = np.isin(lab, keep)
    return nd.binary_fill_holes(nd.binary_closing(mask, iterations=2))


def kmeans(colors: np.ndarray, k: int, iters: int = 20) -> np.ndarray:
    """Small deterministic k-means; returns the palette."""
    k = min(k, len(np.unique(colors, axis=0)))
    # Seed with the most different colors (farthest-point), starting at the darkest.
    centers = [colors[np.argmin(colors.sum(1))]]
    for _ in range(1, k):
        d = np.min([((colors - c) ** 2).sum(1) for c in centers], axis=0)
        centers.append(colors[np.argmax(d)])
    centers = np.array(centers, np.float32)
    for _ in range(iters):
        idx = np.argmin(((colors[:, None] - centers[None]) ** 2).sum(2), axis=1)
        for j in range(k):
            if np.any(idx == j):
                centers[j] = colors[idx == j].mean(0)
    return centers


def to_pixel_art(px: np.ndarray, mask: np.ndarray, colors: int) -> np.ndarray:
    """Snap to the CELL grid: average color and coverage per cell, keep cells
    that are mostly object, then map to a small palette."""
    h, w = mask.shape
    gh, gw = -(-h // CELL), -(-w // CELL)
    pad = ((0, gh * CELL - h), (0, gw * CELL - w))
    m = np.pad(mask.astype(np.float32), pad)
    p = np.pad(px, pad + ((0, 0),))
    m4 = m.reshape(gh, CELL, gw, CELL)
    p4 = p.reshape(gh, CELL, gw, CELL, 3)
    cover = m4.mean((1, 3))
    weight = m4[..., None]
    col = (p4 * weight).sum((1, 3)) / np.maximum(weight.sum((1, 3)), 1e-6)
    solid = cover >= 0.5
    pal = kmeans(col[solid], colors)
    idx = np.argmin(((col[..., None, :] - pal[None, None]) ** 2).sum(-1), axis=-1)
    # A lone pixel unlike all 4 neighbours is AI noise: take the most common neighbour.
    for y in range(gh):
        for x in range(gw):
            if not solid[y, x]:
                continue
            nb = [idx[yy, xx] for yy, xx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1))
                  if 0 <= yy < gh and 0 <= xx < gw and solid[yy, xx]]
            if len(nb) >= 3 and idx[y, x] not in nb:
                idx[y, x] = max(set(nb), key=nb.count)
    out = np.zeros((gh, gw, 4), np.uint8)
    out[..., :3] = pal[idx].round().astype(np.uint8)
    out[..., 3] = np.where(solid, 255, 0)
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    im = grab_frame()
    layout = json.loads(LAYOUT.read_text()) if LAYOUT.exists() else {}
    for name in STALE:
        layout.pop(name, None)
        (OUT / f"{name}.png").unlink(missing_ok=True)
    for name, ((x, y, w, h), colors) in SPRITES.items():
        px = im[y:y + h, x:x + w]
        mask = cut_mask(px, keep_small=name == "ship")
        art = to_pixel_art(px, mask, colors)
        # Trim empty rows/columns, keeping the grid aligned.
        ys, xs = np.nonzero(art[..., 3])
        art = art[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        Image.fromarray(art, "RGBA").save(OUT / f"{name}.png")
        layout[name] = {
            "x": round((x + xs.min() * CELL) / SCALE),
            "y": round((y + ys.min() * CELL) / SCALE),
            "w": art.shape[1] * CELL / SCALE,
            "h": art.shape[0] * CELL / SCALE,
        }
    LAYOUT.write_text(json.dumps(layout, indent=1) + "\n")
    print(f"wrote {len(SPRITES)} sprites to {OUT.relative_to(ROOT)} ({CELL / SCALE:g} menu px per art px)")


if __name__ == "__main__":
    main()
