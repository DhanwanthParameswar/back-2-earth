# Ship layout legend (`data/ship_layout.txt`)

Owner: B. Edit the text file, save, press F5. Each character is one 32×32 tile.
The game builds walls, doors, and objects from it at startup.

| Char | Meaning | Notes |
|---|---|---|
| `#` | Wall | Blocks player and debris |
| `w` | Window | Wall you can see the black hole through |
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

Rooms are split by the columns of doors `1`, `2`, `3`
(left of `1` = cockpit, `1`–`2` = engineering, `2`–`3` = cargo, right of `3` = pod bay).

Rules that keep the game fair:
- The sled channel (`C`, rails, `S`) must not cross the walking route. The player
  cannot enter it, so the sled can never trap the player or block an exit.
- The sled slides toward `S` when the pull points from `C` to `S`
  (currently DOWN). Keep `C` above `S` unless you also change gravity directions.
- Debris moves only along the pull axis (up/down), so it stays in its column.
  Don't put debris in a column that has the only way to an objective with no
  calm-time gap.
