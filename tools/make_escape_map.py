#!/usr/bin/env python3
"""The ship interior for the escape prototype (what Start Game plays). Owner: D.
Needs: pip install pillow   (art from tools/make_ship_art.py)

Edit the ROOMS / DOORS / DECOR / ANCHORS tables below and rerun:
    python3 tools/make_escape_map.py
It writes data/escape_map.json (read by scripts/prototype/escape_mission.gd) and
docs/escape_map_preview.png, and checks that every story step can be reached.

Geography (matches the opening film): the crew sleeps in the CABIN (the film's
seating room, forward), runs aft down the corridor, and the barrier seals the
cabin and the breach off behind them. The film ends with them in the hallway
on the safe side, facing a locker that the impact threw across it; gameplay
starts right there. Past the locker the hallway runs on aft to everything
else: the story rooms (junction, engineering, laboratory, shuttle bay) and
rooms that are just there to explore (crew quarters, galley, ...).

Coordinates are tiles (32 px). Decor/anchor positions are the bottom-centre
point of the thing, in tiles (fractions allowed).
"""
from __future__ import annotations

import json
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets/ship"
OUT = ROOT / "data/escape_map.json"
PREVIEW = ROOT / "docs/escape_map_preview.png"
TILE = 32
W, H = 66, 40

# name: (floor rect x, y, w, h), floor style, colour, sealed (visible but not walkable)
ROOMS = {
    "CREW QUARTERS": ((2, 14, 10, 13), "carpet", "bc9c83", False),
    "CORRIDOR": ((14, 19, 35, 3), "deck", "8fa1c4", False),
    "JUNCTION": ((26, 19, 10, 9), "deck", "81c5d9", False),
    "GALLEY": ((15, 8, 8, 9), "galley", "e6c27a", False),
    "STORAGE": ((4, 6, 8, 5), "deck", "a89f8a", False),
    "ENGINEERING": ((25, 6, 11, 11), "grate", "e0ad65", False),
    "OBSERVATION": ((37, 8, 7, 9), "carpet", "b4a7ff", False),
    "MEDBAY": ((15, 24, 7, 7), "med", "ef8a81", False),
    "LABORATORY": ((25, 30, 11, 8), "lab", "87d5b3", False),
    "HYDROPONICS": ((15, 33, 8, 6), "hydro", "7ed87a", False),
    "SHUTTLE BAY": ((39, 24, 16, 11), "hangar", "9bace8", False),
    "SUIT ROOM": ((57, 26, 4, 6), "deck", "f4a259", False),
    "BREACH": ((51, 19, 5, 3), "breach", "ff4d6d", True),
    "CABIN": ((56, 14, 8, 8), "breach", "ff4d6d", True),
}
# Later rooms win where they overlap (the junction is a widening of the corridor).
ROOM_ORDER = list(ROOMS)

# Openings through walls: (x, y, w, h, kind). kind: door | locker (blocked until
# the jammed locker is cleared) | bulkhead (sealed barrier, drawn as the film's slab)
DOORS = [
    (41, 19, 2, 3, "locker"),      # the locker thrown across the hallway (jammed)
    (12, 20, 2, 2, "door"),        # corridor -> crew quarters
    (12, 8, 3, 2, "door"),         # galley -> storage
    (18, 17, 2, 2, "door"),        # corridor -> galley
    (30, 17, 2, 2, "door"),        # junction -> engineering
    (37, 17, 2, 2, "door"),        # corridor -> observation
    (17, 22, 2, 2, "door"),        # corridor -> medbay
    (30, 28, 2, 2, "door"),        # junction -> laboratory
    (23, 34, 2, 2, "door"),        # laboratory -> hydroponics
    (39, 22, 2, 2, "door"),        # corridor -> shuttle bay
    (55, 28, 2, 2, "door"),        # shuttle bay -> suit room
    (49, 19, 2, 3, "bulkhead"),    # the sealed barrier from the film
]
# Wall cells that are windows (only top walls show; two rows make a tall pane).
WINDOWS = [(9, 12, 2, 2), (19, 6, 2, 2), (37, 6, 7, 2), (4, 4, 2, 2)]
# Where the hull is torn open beyond the barrier (open to space).
TORN = [(52, 17, 3, 2)]

# Decor: (sprite, x, y, layer). layer: obj (solid, y-sorted), soft (y-sorted, walk
# through), floor (decal under everything), wall (decal on a wall face).
DECOR = [
    # Crew quarters: four bunks (Johnny, Aaron, Dhan, and Kien's, still made up), lockers, a table.
    ("bunk_blue", 2.5, 16.0, "obj"), ("bunk_red", 2.5, 18.6, "obj"), ("bunk_green", 2.5, 21.2, "obj"),
    ("bunk_kien", 2.5, 23.8, "obj"), ("photo_wall", 3.6, 13.5, "wall"),
    ("locker", 5.0, 15.7, "obj"), ("locker_open", 6.0, 15.7, "obj"), ("locker", 7.0, 15.7, "obj"),
    ("poster_earth", 8.2, 13.5, "wall"), ("guitar", 11.4, 15.6, "soft"),
    ("rug", 7.4, 22.4, "floor"), ("table", 7.4, 21.3, "obj"), ("stool", 6.2, 21.6, "soft"),
    ("stool", 8.6, 21.6, "soft"), ("duffel", 10.6, 26.6, "soft"), ("papers", 5.2, 25.4, "floor"),
    ("plant", 11.4, 26.8, "obj"),
    # Storage closet.
    ("shelf", 5.5, 6.9, "obj"), ("shelf", 9.0, 6.9, "obj"), ("tool_board", 7.2, 5.4, "wall"),
    ("crates", 4.6, 10.9, "obj"), ("barrel", 6.0, 10.9, "obj"), ("crates", 11.2, 10.9, "obj"),
    ("food_crate", 10.0, 10.9, "obj"),
    # Galley.
    ("counter", 16.0, 9.6, "obj"), ("coffee", 18.0, 9.4, "obj"), ("fridge", 21.5, 9.9, "obj"),
    ("poster_mars", 20.0, 7.5, "wall"),
    ("bench", 18.5, 12.2, "soft"), ("mess_table", 18.5, 13.6, "obj"), ("bench", 18.5, 14.5, "soft"),
    ("food_crate", 15.6, 16.8, "obj"), ("plant", 22.4, 16.8, "obj"),
    # The hallway where the film ends (gameplay starts): MAIN POWER OFFLINE screen and
    # the emergency panel by the barrier, debris from the impact.
    ("power_terminal", 46.4, 18.9, "wall"), ("emergency_panel", 48.4, 18.6, "wall"),
    ("debris", 47.4, 21.7, "soft"), ("scorch", 48.0, 21.2, "floor"), ("papers", 44.6, 21.5, "floor"),
    ("debris", 38.4, 21.6, "soft"),
    ("vent_floor", 22.0, 20.6, "floor"), ("vent_floor", 37.0, 20.6, "floor"), ("cable", 15.5, 21.8, "floor"),
    ("papers", 24.5, 21.4, "floor"),
    # Junction: the launch-status terminal (gameplay) sits in the middle.
    ("vent_floor", 27.0, 26.0, "floor"), ("plant_tall", 26.4, 27.9, "obj"), ("plant_tall", 35.6, 27.9, "obj"),
    ("bench", 33.6, 26.6, "soft"), ("hazard_strip", 30.5, 24.3, "floor"),
    # Engineering.
    ("generator", 26.6, 13.6, "obj"), ("workbench", 33.6, 12.0, "obj"), ("reactor", 33.8, 17.0, "obj"),
    ("pipes", 30.0, 10.6, "floor"), ("pipes", 26.5, 10.6, "floor"), ("hazard_strip", 33.8, 14.3, "floor"),
    ("cable", 29.0, 15.4, "floor"), ("scorch", 31.6, 13.8, "floor"), ("tool_board", 34.6, 5.4, "wall"),
    # Observation lounge: a sofa facing the big window.
    ("rug", 40.5, 13.6, "floor"), ("coffee_table", 40.5, 11.3, "obj"), ("sofa", 40.5, 13.0, "obj"),
    ("telescope", 37.8, 10.6, "obj"), ("plant_tall", 43.4, 16.8, "obj"), ("plant", 39.8, 16.8, "obj"),
    ("shelf", 42.6, 10.0, "obj"), ("stool", 38.6, 13.6, "soft"),
    # Medbay.
    ("med_bed", 16.0, 27.0, "obj"), ("med_bed", 19.5, 27.0, "obj"), ("iv_stand", 17.3, 26.4, "soft"),
    ("med_cabinet", 21.4, 25.5, "obj"), ("scanner", 18.0, 30.9, "obj"), ("plant", 15.5, 30.9, "obj"),
    # Laboratory.
    ("server_rack", 35.4, 31.9, "obj"), ("whiteboard", 27.6, 29.5, "wall"),
    ("lab_bench", 34.2, 34.6, "obj"), ("lab_bench", 33.8, 37.9, "obj"), ("plant", 25.5, 37.9, "obj"), ("papers", 30.6, 33.6, "floor"),
    # Hydroponics.
    ("grow_bed", 17.0, 35.2, "obj"), ("grow_bed", 20.5, 35.2, "obj"), ("grow_bed", 17.0, 38.0, "obj"),
    ("grow_bed", 20.5, 38.0, "obj"), ("water_tank", 22.4, 33.9, "obj"), ("puddle", 19.0, 36.4, "floor"),
    ("plant_tall", 15.4, 33.9, "obj"),
    # Shuttle bay.
    ("hazard_strip", 45.5, 28.2, "floor"), ("hazard_strip", 50.5, 28.2, "floor"),
    ("hazard_strip", 45.5, 33.3, "floor"), ("hazard_strip", 50.5, 33.3, "floor"),
    ("clamp_arm", 46.0, 28.6, "soft"), ("clamp_arm", 50.0, 28.6, "soft"),
    ("barrel", 53.6, 25.6, "obj"), ("barrel", 54.4, 25.6, "obj"), ("crates", 53.8, 34.9, "obj"),
    ("crates", 39.6, 34.9, "obj"), ("pipes", 52.0, 30.4, "floor"), ("vent_floor", 40.4, 30.0, "floor"),
    # Suit room and the outer airlock.
    ("suit_rack", 58.6, 27.9, "obj"), ("airlock", 59.6, 25.4, "wall"), ("bench", 58.6, 31.6, "soft"),
    # Past the barrier (sealed): the breach, then the cabin where the crew slept in the film.
    ("debris", 52.2, 20.5, "soft"), ("debris", 54.5, 21.6, "soft"), ("scorch", 53.0, 20.4, "floor"),
    ("seats", 59.6, 16.8, "soft"), ("seats", 59.6, 20.4, "soft"), ("debris", 57.2, 18.4, "soft"),
    ("papers", 61.6, 19.0, "floor"), ("scorch", 58.0, 21.4, "floor"),
]

# Gameplay props (ids as in escape_mission.gd): sprite, position.
PROPS = {
    "locker": ("fallen_locker", 43.2, 21.3),
    "terminal": ("launch_terminal", 30.5, 23.6),
    "isolate": ("circuit_cutoff", 27.6, 7.9),
    "cabinet": ("distribution", 30.5, 8.1),
    "fuse": ("fuse_rack", 33.2, 7.9),
    "aux": ("aux_panel", 25.6, 9.7),
    "freezer": ("freezer", 26.8, 31.9),
    "battery": ("battery", 32.8, 31.6),
    "cart": ("cart", 30.5, 35.6),
    "case": ("sample_case", 27.0, 34.6),
    "socket": ("socket", 42.4, 25.8),
    "release": ("clamp_console", 46.8, 25.8),
    "shuttle": ("shuttle", 48.0, 31.6),
}

# Named spots the story uses (bottom-centre, tiles).
ANCHORS = {
    "player_start": (47.8, 20.6),          # where the film leaves the crew: facing the locker
    "aaron_start": (44.6, 21.8),
    "dhan_start": (43.8, 20.2),
    "locker_visual": (42.0, 21.95),        # the locker lying across the hallway
    "locker_cleared": (40.6, 19.95),       # stood back up against the wall once pushed
    "locker_hold": (43.4, 20.0),           # Aaron holds the top here
    "locker_push": (43.6, 21.5),           # the player pushes from here
    "junction": (28.5, 21.5),
    "bay_watch": (45.2, 26.6),             # Dhan checks the shuttle after the assessment
    "shuttle_side": (44.4, 30.6),          # where the sample case is fetched
    "case_drop": (28.0, 34.6),             # Dhan delivers the case beside the freezer
    "cart_lift": (29.4, 35.4),             # Aaron lifts the battery onto the cart
    "board_aaron": (43.8, 31.4),
    "board_dhan": (44.8, 32.6),
}


def build_grid():
    grid = [[" "] * W for _ in range(H)]
    room = [["-"] * W for _ in range(H)]
    keys = {}
    for i, name in enumerate(ROOM_ORDER):
        (x, y, w, h), _style, _col, sealed = ROOMS[name]
        keys[name] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i]
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                grid[yy][xx] = "s" if sealed else "."
                room[yy][xx] = keys[name]
    floor = {(x, y) for y in range(H) for x in range(W) if grid[y][x] in ".s"}
    # Walls around every floor; top walls two thick (a tall face in the 3/4 view).
    for (x, y) in floor:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                n = (x + dx, y + dy)
                if 0 <= n[0] < W and 0 <= n[1] < H and grid[n[1]][n[0]] == " ":
                    grid[n[1]][n[0]] = "#"
        if y >= 2 and grid[y - 2][x] == " " and grid[y - 1][x] == "#":
            grid[y - 2][x] = "#"
    for (x, y, w, h, kind) in DOORS:
        ch = {"door": "D", "locker": "L", "bulkhead": "B"}[kind]
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                grid[yy][xx] = ch
    for (x, y, w, h) in WINDOWS:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if grid[yy][xx] == "#":
                    grid[yy][xx] = "w"
    for (x, y, w, h) in TORN:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                grid[yy][xx] = " "
    # Doorways belong to the room on their far side for the HUD; give them the nearest room.
    for y in range(H):
        for x in range(W):
            if grid[y][x] in "DLB" and room[y][x] == "-":
                for d in range(1, 4):
                    for nx, ny in ((x, y + d), (x, y - d), (x + d, y), (x - d, y)):
                        if 0 <= nx < W and 0 <= ny < H and room[ny][nx] != "-" and grid[ny][nx] == ".":
                            room[y][x] = room[ny][nx]
                            break
                    if room[y][x] != "-":
                        break
    return grid, room, keys


def sprite_size(name):
    im = Image.open(ART / f"{name}.png")
    return im.width, im.height


def footprint(name, x, y):
    """Solid base of an object (px rect), the bottom strip of its sprite."""
    w, h = sprite_size(name)
    fw = max(12, w - 8)
    fh = min(20, max(10, h // 3))
    cx, by = x * TILE, y * TILE
    return (cx - fw / 2, by - fh, fw, fh)


def walkable(grid, solids, locker_open=True):
    ok = set()
    for y in range(H):
        for x in range(W):
            ch = grid[y][x]
            if ch in ".D" or (ch == "L" and locker_open):
                cx, cy = x * TILE + 16, y * TILE + 16
                if not any(rx <= cx <= rx + rw and ry <= cy <= ry + rh for rx, ry, rw, rh in solids):
                    ok.add((x, y))
    return ok


def reachable(ok, start):
    seen, q = {start}, deque([start])
    while q:
        x, y = q.popleft()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if n in ok and n not in seen:
                seen.add(n)
                q.append(n)
    return seen


def check(grid, solids):
    cell = lambda p: (int(p[0]), int(p[1] - 0.01))  # noqa: E731  bottom-centre -> tile
    ok = walkable(grid, solids)
    start = cell(ANCHORS["player_start"])
    assert start in ok, f"player_start {start} is not walkable"
    seen = reachable(ok, start)
    problems = []
    for name, p in ANCHORS.items():
        if name.startswith("locker_visual"):
            continue
        if cell(p) not in seen:
            problems.append(f"anchor {name} at {cell(p)} unreachable")
    for pid, (_s, x, y) in PROPS.items():
        near = [(int(x) + dx, int(y - 0.01) + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1, 2)]
        if not any(n in seen for n in near):
            problems.append(f"prop {pid} has no reachable tile next to it")
    closed = reachable(walkable(grid, solids, locker_open=False), start)
    if cell(ANCHORS["junction"]) in closed:
        problems.append("the jammed locker does not block the hallway aft of the start")
    if problems:
        raise SystemExit("map check failed:\n  " + "\n  ".join(problems))
    rooms_reached = len(seen)
    print(f"map check ok: {rooms_reached} walkable tiles reachable from the start")


def preview(grid, room, keys, solids):
    img = Image.new("RGBA", (W * TILE, H * TILE), (5, 6, 20, 255))
    tex = {}

    def load(name):
        if name not in tex:
            tex[name] = Image.open(ART / f"{name}.png").convert("RGBA")
        return tex[name]

    style_of = {keys[n]: ROOMS[n][1] for n in ROOMS}
    for y in range(H):
        for x in range(W):
            ch = grid[y][x]
            if ch in ".sDLB":
                sheet = load(f"floor_{style_of.get(room[y][x], 'deck')}")
                v = (x * 7 + y * 13) % 4 if (x * 31 + y * 17) % 5 == 0 else 0
                img.alpha_composite(sheet.crop(((v % 2) * 32, (v // 2) * 32, (v % 2) * 32 + 32, (v // 2) * 32 + 32)),
                                    (x * TILE, y * TILE))
            if ch in "#w":
                below = grid[y + 1][x] if y + 1 < H else " "
                if below in ".DLs":
                    img.alpha_composite(load("window" if ch == "w" else "wall_face_plain"), (x * TILE, y * TILE))
                elif below in "#w" and y + 2 < H and grid[y + 2][x] in ".DLs":
                    img.alpha_composite(load("window" if ch == "w" else "wall_face_plain"), (x * TILE, y * TILE))
                else:
                    img.alpha_composite(load("wall_cap"), (x * TILE, y * TILE))
    items = [(n, x, y, layer) for n, x, y, layer in DECOR] + [(s, x, y, "obj") for s, x, y in PROPS.values()]
    order = {"floor": 0, "wall": 1, "soft": 2, "obj": 2}
    for n, x, y, layer in sorted(items, key=lambda t: (order[t[3]], t[2])):
        im = load(n)
        img.alpha_composite(im, (int(x * TILE - im.width / 2), int(y * TILE - im.height)))
    for name, p in ANCHORS.items():
        px, py = int(p[0] * TILE), int(p[1] * TILE)
        for d in range(-3, 4):
            img.putpixel((px + d, py), (255, 255, 0, 255))
            img.putpixel((px, py + d), (255, 255, 0, 255))
    PREVIEW.parent.mkdir(exist_ok=True)
    img.save(PREVIEW)


def main():
    grid, room, keys = build_grid()
    solids = [footprint(n, x, y) for n, x, y, layer in DECOR if layer == "obj"]
    solids += [footprint(s, x, y) for pid, (s, x, y) in PROPS.items() if pid not in ("locker", "case")]
    check(grid, solids)
    data = {
        "_note": "Generated by tools/make_escape_map.py; edit the tables there and rerun.",
        "tile": TILE,
        "size": [W, H],
        "grid": ["".join(r) for r in grid],
        "room_grid": ["".join(r) for r in room],
        "rooms": [{"key": keys[n], "name": n, "style": ROOMS[n][1], "color": ROOMS[n][2],
                   "rect": list(ROOMS[n][0]), "sealed": ROOMS[n][3]} for n in ROOM_ORDER],
        "decor": [{"sprite": n, "pos": [x * TILE, y * TILE], "layer": layer,
                   "solid": list(footprint(n, x, y)) if layer == "obj" else None} for n, x, y, layer in DECOR],
        "props": {pid: {"sprite": s, "pos": [x * TILE, y * TILE]} for pid, (s, x, y) in PROPS.items()},
        "anchors": {k: [x * TILE, y * TILE] for k, (x, y) in ANCHORS.items()},
    }
    OUT.write_text(json.dumps(data, indent=1) + "\n")
    preview(grid, room, keys, solids)
    print(f"wrote {OUT.relative_to(ROOT)} and {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
