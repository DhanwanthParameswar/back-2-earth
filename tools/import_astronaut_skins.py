#!/usr/bin/env python3
"""Turn the AI-drawn astronaut art into clean, grid-true game sprites.

Owner: D.  Inputs (keep these in the repo):
    art_source/astronaut_walk_sheet.png   4 rows (skins) x 6 walk frames, black background
    art_source/skin_concepts.png          4 front-facing concepts on a navy grid

Outputs:
    assets/sprites/astronaut_<skin>.png   6-frame walk strip, each art pixel = 2x2 px
    assets/ui/portrait_<skin>.png         front portrait for the skin picker (1x, scaled in-game)

Why: generated "pixel art" is not on a real pixel grid (pixels vary in size,
edges are blended, colors drift). This snaps each sprite to a grid by taking
the most common color in each cell, maps colors to a small per-skin palette,
and keeps outlines/visors while making the real background transparent.

    pip install pillow numpy
    python3 tools/import_astronaut_skins.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_WALK = ROOT / "art_source/astronaut_walk_sheet.png"
SRC_CONCEPTS = ROOT / "art_source/skin_concepts.png"

SKINS = ["classic", "hazard", "nebula", "mint"]   # row order in both sources
WALK_CELL = 256          # source cell size (6 x 4 grid on a 1536 x 1024 sheet)
WALK_GRID = 28           # art pixels per source cell (~9.1 source px per art pixel)
CONCEPT_CARDS = [(23, 431), (463, 871), (903, 1311), (1343, 1751)]
CONCEPT_ROWS = (272, 728)
CONCEPT_BLOCK = 20.4     # source px per art pixel on the concept sheet
WORLD_SCALE = 2          # in-game: 1 art pixel = 2x2 world pixels (matches the 16-px-art tiles)
INK = np.array([10, 10, 14])   # outlines and visors
PALETTE_SIZE = 8         # colors per skin besides ink


def kmeans(points: np.ndarray, k: int, seed: int, iters: int = 40) -> np.ndarray:
    rng = np.random.default_rng(seed)
    pts = points.astype(float)
    centers = pts[rng.choice(len(pts), k, replace=False)]
    for _ in range(iters):
        lab = ((pts[:, None, :] - centers[None]) ** 2).sum(2).argmin(1)
        for j in range(k):
            sel = pts[lab == j]
            if len(sel):
                centers[j] = sel.mean(0)
    return centers


def merge_close(palette: np.ndarray, dist: float = 28.0) -> np.ndarray:
    kept: list[np.ndarray] = []
    for c in palette:
        if all(np.abs(c - k).sum() > dist for k in kept):
            kept.append(c)
    return np.array(kept)


def make_palette(region: np.ndarray, bgmask: np.ndarray, seed: int) -> np.ndarray:
    fg = region[~bgmask]
    light = fg[fg.sum(1) >= 110]
    rng = np.random.default_rng(seed)
    sample = light[rng.choice(len(light), min(40000, len(light)), replace=False)]
    return np.vstack([INK, merge_close(kmeans(sample, PALETTE_SIZE, seed))])


def quantize(region: np.ndarray, palette: np.ndarray) -> np.ndarray:
    flat = region.reshape(-1, 3).astype(float)
    out = np.empty(len(flat), dtype=int)
    for i in range(0, len(flat), 200000):
        out[i:i + 200000] = ((flat[i:i + 200000, None, :] - palette[None]) ** 2).sum(2).argmin(1)
    return out.reshape(region.shape[:2])


def snap(labels: np.ndarray, bgmask: np.ndarray, out_w: int, out_h: int, k: int):
    """Most common color in the middle 60% of each cell; background if mostly bg."""
    h, w = labels.shape
    res = np.zeros((out_h, out_w), dtype=int)
    is_bg = np.zeros((out_h, out_w), dtype=bool)
    ys, xs = np.linspace(0, h, out_h + 1), np.linspace(0, w, out_w + 1)
    for j in range(out_h):
        for i in range(out_w):
            y0, y1, x0, x1 = ys[j], ys[j + 1], xs[i], xs[i + 1]
            sy = slice(int(y0 + (y1 - y0) * 0.2), int(np.ceil(y1 - (y1 - y0) * 0.2)))
            sx = slice(int(x0 + (x1 - x0) * 0.2), int(np.ceil(x1 - (x1 - x0) * 0.2)))
            cell, bgc = labels[sy, sx].ravel(), bgmask[sy, sx].ravel()
            if bgc.mean() >= 0.5:
                is_bg[j, i] = True
            else:
                res[j, i] = np.bincount(cell[~bgc], minlength=k).argmax()
    return res, is_bg


def border_connected(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    seen = np.zeros_like(mask)
    stack = [(y, x) for y in range(h) for x in (0, w - 1)] + [(y, x) for x in range(w) for y in (0, h - 1)]
    while stack:
        y, x = stack.pop()
        if 0 <= y < h and 0 <= x < w and mask[y, x] and not seen[y, x]:
            seen[y, x] = True
            stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    return seen


def to_image(labels: np.ndarray, palette: np.ndarray, transparent: np.ndarray) -> Image.Image:
    rgb = np.clip(np.round(palette[labels]), 0, 255).astype(np.uint8)
    alpha = np.where(transparent, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([rgb, alpha]), "RGBA")


def build_walk_sheets() -> None:
    a = np.asarray(Image.open(SRC_WALK).convert("RGB")).astype(int)
    bgmask_all = a.sum(2) <= 4  # the background is pure black; outlines/visors are not
    frames_by_skin: list[list[Image.Image]] = []
    for row, skin in enumerate(SKINS):
        rows = slice(row * WALK_CELL, (row + 1) * WALK_CELL)
        region, bgmask = a[rows], bgmask_all[rows]
        palette = make_palette(region, bgmask, seed=row)
        labels = quantize(region, palette)
        frames = []
        for col in range(6):
            cols = slice(col * WALK_CELL, (col + 1) * WALK_CELL)
            small, is_bg = snap(labels[:, cols], bgmask[:, cols], WALK_GRID, WALK_GRID, len(palette))
            frames.append(to_image(small, palette, is_bg))
        frames_by_skin.append(frames)

    # One frame box shared by every skin and frame, so the code can use fixed offsets.
    boxes = [f.getbbox() for frames in frames_by_skin for f in frames]
    left = min(b[0] for b in boxes)
    top = min(b[1] for b in boxes)
    right = max(b[2] for b in boxes)
    bottom = max(b[3] for b in boxes)
    fw, fh = right - left, bottom - top
    fw += fw % 2  # even width keeps the sprite centered on whole pixels
    print(f"walk frame: {fw}x{fh} art px -> {fw * WORLD_SCALE}x{fh * WORLD_SCALE} world px")

    for skin, frames in zip(SKINS, frames_by_skin):
        strip = Image.new("RGBA", (fw * 6, fh), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            strip.alpha_composite(f.crop((left, top, left + fw, bottom)), (i * fw, 0))
        out = ROOT / f"assets/sprites/astronaut_{skin}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        strip.resize((strip.width * WORLD_SCALE, strip.height * WORLD_SCALE), Image.NEAREST).save(out)
        print("wrote", out.relative_to(ROOT))


def build_portraits() -> None:
    a = np.asarray(Image.open(SRC_CONCEPTS).convert("RGB")).astype(int)
    y0, y1 = CONCEPT_ROWS
    for i, (skin, (x0, x1)) in enumerate(zip(SKINS, CONCEPT_CARDS)):
        region = a[y0:y1, x0 + 3:x1 - 3]
        r, g, b = region[..., 0], region[..., 1], region[..., 2]
        bgmask = (b > r + 15) & (b > g + 8) & (r < 60) & (b < 95)   # navy + grid lines
        palette = make_palette(region, bgmask, seed=i)
        labels = quantize(region, palette)
        w = round(region.shape[1] / CONCEPT_BLOCK)
        h = round(region.shape[0] / CONCEPT_BLOCK)
        small, is_bg = snap(labels, bgmask, w, h, len(palette))
        im = to_image(small, palette, border_connected(is_bg))
        im = im.crop(im.getbbox())
        out = ROOT / f"assets/ui/portrait_{skin}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out)
        print("wrote", out.relative_to(ROOT), im.size)


if __name__ == "__main__":
    build_walk_sheets()
    build_portraits()
