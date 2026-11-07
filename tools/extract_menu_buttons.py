#!/usr/bin/env python3
"""Cut the painted menu buttons out of the menu video for the 'pressed' effect.

Owner: D. Needs ffmpeg on PATH and: pip install pillow numpy

The menu buttons are painted into art_source/menu_loop_1080p.ogv and never
move. Each one has a face and a darker 3D strip (shadow) under it. When a
button is pressed, scripts/ui/main_menu.gd covers the button with background
color and redraws the face lower by the shadow depth, so it looks pushed in.

This script grabs frame 0, crops each button FACE (top edge to where the
shadow starts) at full 1080p, and saves assets/ui/menu_btn_<id>.png.
The rects below are in 640x360 menu pixels (1080p / 3); keep them in sync with
HOTSPOTS in main_menu.gd if the video is redrawn.
"""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
VIDEO = ROOT / "art_source/menu_loop_1080p.ogv"

# id: (x, y, width, full height incl. shadow, face height)  -- 640x360 px
BUTTONS = {
    "start": (204, 173, 230, 45, 39),
    "how": (202, 228, 233, 43, 36),
    "settings": (202, 280, 233, 44, 37),
    "credits": (10, 321, 74, 29, 26),
    "sound": (588, 315, 40, 34, 31),
}
SCALE = 3  # source is 1920x1080


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        frame = Path(tmp) / "frame0.png"
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-i", str(VIDEO), "-vf", "select=eq(n\\,0)", "-vsync", "0", str(frame)],
            check=True,
        )
        im = Image.open(frame).convert("RGB")
    a = np.asarray(im).astype(int)
    out_dir = ROOT / "assets/ui"
    out_dir.mkdir(parents=True, exist_ok=True)
    for bid, (x, y, w, h, face_h) in BUTTONS.items():
        box = (x * SCALE, y * SCALE, (x + w) * SCALE, (y + face_h) * SCALE)
        im.crop(box).save(out_dir / f"menu_btn_{bid}.png")
        # Background just above the button: the patch color while pressed.
        strip = a[max(0, y * SCALE - 6):y * SCALE - 1, x * SCALE:(x + w) * SCALE].reshape(-1, 3)
        r, g, b = np.median(strip, axis=0).astype(int)
        print(f"{bid}: wrote assets/ui/menu_btn_{bid}.png  depth={h - face_h}px  bg=#{r:02x}{g:02x}{b:02x}")


if __name__ == "__main__":
    main()
