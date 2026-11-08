# Ship layout legend (`data/ship_layout.txt`)

Owner: B. Edit the text file, save, press F5. Each character is one 32×32 tile.
The game builds walls, doors, and objects from it at startup.

| Char | Meaning | Notes |
|---|---|---|
| `~` | Open space | Outside the hull. Blocks everything, drawn as nothing: the starfield shows through. Shape the ship with it |
| `#` | Wall | Blocks player and debris. A wall with `~` below it draws the hull's side (red stripe) |
| `w` | Side window | Wall you can see through to space (one frame per group) |
| `W` | Space window | Wall with glass showing the looping nebula video; put it in the 2-row back wall |
| `.` | Floor | |
| `@` | Player start | Exactly one |
| `T` | Cockpit terminal | Completes `start_evacuation` |
| `P` | Power console | Completes `restore_power` |
| `C` | Cargo sled start | Sled channel; the player cannot walk on `C`, `\|`, `S` |
| `\|` | Sled rail | Must form a straight line from `C` to `S` |
| `S` | Pressure plate | Sled reaching it completes `open_compartment` |
| `K` | Core compartment door | Opens after `open_compartment` |
| `N` | Navigation core | Completes `collect_core` |
| `L` | Clamp console | Completes `release_clamp` |
| `O` | Escape pod | Completes `board_pod` (launch) |
| `1` | Door Cockpit → Engineering | Opens after `start_evacuation` |
| `2` | Door Engineering → Cargo | Opens after `restore_power` |
| `3` | Door Cargo → Pod Bay | Opens after `collect_core` |
| `x` | Debris | Slides with each pull; −10 s on contact |
| `M` | Crewmate (NPC) | Greets the player out loud; E opens a chat (AI reply + voice). Solid at her feet, so leave a free tile beside her |

Rooms can be any shape. They're found by walking the floor: everything you can
reach from `@` without crossing a door is the cockpit; beyond door `1` is
engineering, beyond `2` cargo, beyond `3` the pod bay (door `K` stays inside cargo).

The current map is the ship from the opening film, nose on the right: cockpit in
the nose, engineering in the widest section, cargo with the sled shaft in the top
fin and the core compartment in the bottom fin, pod bay in the tail.
`docs/map_preview.png` shows it (`python3 tools/preview_layout.py`).

3/4 view notes:
- Keep the top edge of each room two walls thick: that makes a 2-tile-tall back
  wall face, like a Stardew interior.
- Any wall with floor directly below it shows its front face automatically.
- Each connected group of `W` (or `w`) cells becomes ONE window with one frame,
  so a 7x2 block of `W` is a single wide pane. Each `W` group plays its own
  copy of the video, so keep it to one or two windows.
- Consoles (`T`, `P`, `L`) and the pod (`O`) are solid at their base. Leave a
  free tile beside or below them so the player can reach them.

Rules that keep the game fair:
- The sled channel (`C`, rails, `S`) must not cross the walking route. The player
  cannot enter it, so the sled can never trap the player or block an exit.
- The sled slides toward `S` when the pull points from `C` to `S`
  (currently DOWN). Keep `C` above `S` unless you also change gravity directions.
- Debris moves only along the pull axis (up/down), so it stays in its column.
  Don't put debris in a column that has the only way to an objective with no
  calm-time gap.
