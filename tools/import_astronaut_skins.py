#!/usr/bin/env python3
"""Turn the AI-drawn astronaut art into clean, grid-true game sprites.

Owner: D.  Inputs (keep these in the repo):
    art_source/astronaut_walk_sheet.png   4 rows (skins) x 6 walk frames, black background
    art_source/skin_concepts.png          4 front-facing concepts on a navy grid

Outputs:
    assets/sprites/astronaut_<skin>.png   6-frame walk strip, each art pixel = 2x2 px
    assets/ui/portrait_<skin>.png         front portrait for the skin picker (1x, scaled in-game)

Why: generated "pixel art" is not on a real pixel grid (pixels vary in size,
edges are blended, colors drift). For the walk sheet this:
  - uses the sheet's own transparency to tell the astronaut from the background
    (its outlines and visors are black, like the empty background looks, so
    color alone can't separate them);
  - finds where each frame's pixel grid actually sits (one grid size per suit,
    a best-fitting offset per frame) and takes the most common color per cell,
    mapped to a small per-skin palette;
  - lines every frame up on the same spot: the front of the helmet at one x and
    the feet on the bottom row, so the walk cycle doesn't slide and every suit
    stands on its shadow.

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
PITCHES = np.arange(8.2, 9.61, 0.05)   # source px per art pixel to try (one per suit)
OPAQUE = 128             # source alpha at or above this is the astronaut
COLOR_BIAS = 0.35        # inside the suit, a color covering this much of a cell beats the outline
EDGE_INK = 0.25          # on the silhouette's edge, this much outline in a cell makes it outline
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


def _integral(x: np.ndarray) -> np.ndarray:
    out = np.zeros((x.shape[0] + 1, x.shape[1] + 1) + x.shape[2:])
    out[1:, 1:] = x.cumsum(0).cumsum(1)
    return out


def _grid(pitch: float, offset: float, size: int) -> np.ndarray:
    return np.round(np.arange(offset, size + 0.01, pitch)).astype(int)


def grid_score(I: np.ndarray, I2: np.ndarray, pitch: float, ox: float, oy: float) -> float:
    """How badly grid cells mix colors (lower = cells line up with the art's pixels).
    Cells are shrunk by 1 px a side to ignore blended edges; only mostly-opaque cells count."""
    xs, ys = _grid(pitch, ox, WALK_CELL), _grid(pitch, oy, WALK_CELL)
    Y0, Y1 = (ys[:-1] + 1)[:, None], (ys[1:] - 1)[:, None]
    X0, X1 = (xs[:-1] + 1)[None, :], (xs[1:] - 1)[None, :]
    area = ((Y1 - Y0) * (X1 - X0))[..., None].astype(float)
    S = I[Y1, X1] - I[Y0, X1] - I[Y1, X0] + I[Y0, X0]
    S2 = I2[Y1, X1] - I2[Y0, X1] - I2[Y1, X0] + I2[Y0, X0]
    var = (S2 / area - (S / area) ** 2).sum(-1)
    solid = S[..., 3] / area[..., 0] > OPAQUE
    return float(var[solid].mean()) if solid.any() else 1e9


def best_offsets(cell: np.ndarray, pitch: float):
    """(score, ox, oy) of the best grid offset for one frame at this pitch."""
    feat = np.dstack([cell[..., :3] * (cell[..., 3:] / 255.0), cell[..., 3:]])
    I, I2 = _integral(feat), _integral(feat ** 2)
    steps = np.arange(0, pitch, 0.5)
    return min((grid_score(I, I2, pitch, ox, oy), ox, oy) for ox in steps for oy in steps)


def snap_frame(labels: np.ndarray, alpha: np.ndarray, pitch: float, ox: float, oy: float):
    """Art pixels for one frame: transparent unless the cell's middle is mostly opaque;
    otherwise the most common palette color among its opaque source pixels."""
    xs, ys = _grid(pitch, ox, WALK_CELL), _grid(pitch, oy, WALK_CELL)
    h, w = len(ys) - 1, len(xs) - 1
    out = np.zeros((h, w), dtype=int)
    clear = np.ones((h, w), dtype=bool)
    ink_share = np.zeros((h, w))
    for j in range(h):
        for i in range(w):
            y0, y1, x0, x1 = ys[j], ys[j + 1], xs[i], xs[i + 1]
            my, mx = max(1, (y1 - y0) // 5), max(1, (x1 - x0) // 5)
            a = alpha[y0 + my:y1 - my, x0 + mx:x1 - mx]
            if a.size == 0 or (a >= OPAQUE).mean() < 0.5:
                continue
            lab = labels[y0 + my:y1 - my, x0 + mx:x1 - mx][a >= OPAQUE]
            counts = np.bincount(lab)
            ink_share[j, i] = counts[0] / counts.sum()
            pick = counts.argmax()
            if pick == 0 and len(counts) > 1 and counts[1:].max() >= COLOR_BIAS * counts.sum():
                pick = 1 + counts[1:].argmax()  # keep thin colored parts (legs, boots) over the outline
            out[j, i] = pick
            clear[j, i] = False
    # The art is outlined everywhere: put the outline back on the silhouette's edge
    # wherever the source has a fair amount of it there.
    pad = np.pad(clear, 1, constant_values=True)
    edge = ~clear & (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:])
    out[edge & (ink_share >= EDGE_INK)] = 0
    return out, clear


def anchor(clear: np.ndarray):
    """(front of the helmet x, feet y) for one frame. The helmet is the band a few rows
    below the top of the sprite (below the antenna); facing right, its front is the
    rightmost solid pixel there. Feet = lowest solid row."""
    solid = ~clear
    rows = np.where(solid.any(1))[0]
    top, bottom = rows.min(), rows.max()
    band = solid[top + 3:top + 11]
    return int(np.where(band.any(0))[0].max()), int(bottom)


def build_walk_sheets() -> None:
    src = np.asarray(Image.open(SRC_WALK).convert("RGBA")).astype(int)
    rgb_all, alpha_all = src[..., :3], src[..., 3]
    frames_by_skin = []   # per skin: list of (labels, clear) art-pixel frames
    palettes = []
    for row, skin in enumerate(SKINS):
        rows = slice(row * WALK_CELL, (row + 1) * WALK_CELL)
        region, alpha = rgb_all[rows], alpha_all[rows]
        palette = make_palette(region, alpha < OPAQUE, seed=row)
        labels = quantize(region, palette)
        cells = [src[rows, c * WALK_CELL:(c + 1) * WALK_CELL].astype(float) for c in range(6)]
        # One grid size for the whole suit (so frames keep the same size), best offset per frame.
        best = None
        for pitch in PITCHES:
            fits = [best_offsets(cell, pitch) for cell in cells]
            total = sum(f[0] for f in fits)
            if best is None or total < best[0]:
                best = (total, pitch, fits)
        _, pitch, fits = best
        print(f"{skin}: {pitch:.2f} source px per art pixel")
        frames = []
        for c, (_, ox, oy) in enumerate(fits):
            cols = slice(c * WALK_CELL, (c + 1) * WALK_CELL)
            frames.append(snap_frame(labels[:, cols], alpha[:, cols], pitch, ox, oy))
        frames_by_skin.append(frames)
        palettes.append(palette)

    # Line every frame of every suit up: helmet front at FRONT_X, feet on the bottom row.
    anchors = [[anchor(clear) for _, clear in frames] for frames in frames_by_skin]
    placed = []
    for frames, anc in zip(frames_by_skin, anchors):
        placed.append([(lab, clear, -fx, -fy) for (lab, clear), (fx, fy) in zip(frames, anc)])
    # Shared box (relative to the anchor) that fits every frame.
    lo_x = min(np.where((~c).any(0))[0].min() + dx for p in placed for _, c, dx, _ in p)
    hi_x = max(np.where((~c).any(0))[0].max() + dx for p in placed for _, c, dx, _ in p)
    lo_y = min(np.where((~c).any(1))[0].min() + dy for p in placed for _, c, _, dy in p)
    fw, fh = hi_x - lo_x + 1, 1 - lo_y   # feet (dy = 0) sit on the last row
    fw += fw % 2  # even width keeps the sprite centered on whole pixels
    print(f"walk frame: {fw}x{fh} art px -> {fw * WORLD_SCALE}x{fh * WORLD_SCALE} world px")

    for skin, frames, palette in zip(SKINS, placed, palettes):
        strip = np.zeros((fh, fw * 6, 4), dtype=np.uint8)
        for i, (lab, clear, dx, dy) in enumerate(frames):
            ys, xs = np.where(~clear)
            ty, tx = ys + dy - lo_y, xs + dx - lo_x + i * fw
            rgbv = np.clip(np.round(palette[lab[ys, xs]]), 0, 255).astype(np.uint8)
            strip[ty, tx, :3] = rgbv
            strip[ty, tx, 3] = 255
        img = Image.fromarray(strip, "RGBA")
        out = ROOT / f"assets/sprites/astronaut_{skin}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        img.resize((img.width * WORLD_SCALE, img.height * WORLD_SCALE), Image.NEAREST).save(out)
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
    if "--portraits" in __import__("sys").argv:  # portraits were for the old suit picker
        build_portraits()
