# Opening story voice-over

Drop recordings here (`.ogg`, `.wav` or `.mp3`). Godot plays each one when its caption appears:

| File | Line | Starts | Caption ends |
|---|---|---|---|
| `crew_1` | CREWMATE: "Real food. Finally." | 12.2 s | 14.5 s |
| `system_1` | SYSTEM: "Collision detected. Evacuate now." | 15.9 s | 19.4 s |
| `crew_2` | CREWMATE: "Power first. Then we find them." | 33.6 s | 36.2 s |

Or one full-length track aligned to the video from 0:00: `full.ogg` (plays instead of the three above).

Times come from `data/intro_timing.json` (written by `tools/make_intro.py`).
