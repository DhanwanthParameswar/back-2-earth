# Opening story voice-over

Drop recordings here (`.ogg`, `.wav` or `.mp3`). Godot plays each one when its caption appears:

| File | Line | Starts | Caption ends |
|---|---|---|---|
| `crew_1` | KIEN: "Real food. Finally." | 12.2 s | 14.5 s |
| `system_1` | SYSTEM: "Collision detected. Evacuate now." | 15.9 s | 19.4 s |
| `kien_1` (optional) | KIEN: \*Sucked out of the ship\* (effects keep playing under it) | 21.7 s | 24.2 s |
| `crew_2` | JOHNNY (gasping): "That was a close one! We need to fix power first. Then find Dhan." | 33.6 s | 37.6 s |

Or one full-length track aligned to the video from 0:00: `full.ogg` (plays instead of the ones above).

Times come from `data/intro_timing.json` (written by `tools/make_intro.py`).
