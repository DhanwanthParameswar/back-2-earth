# Back2Earth

*Your spaceship is being pulled toward a black hole. Use its failing gravity to navigate wreckage, work with a damaged AI companion, and launch the last escape pod home.*

UBhacks 2026 · Godot 4 · GDScript · top-down 2D · retro pixel art

> **Starter build status:** every system below is written, and every GDScript file passes a syntax parser. The backend has 12 passing tests. **Nobody has launched this in Godot yet**: the build machine couldn't download Godot. Do the "First launch" check below before anyone branches off.

![Ship layout preview](docs/map_preview.png)

*Cockpit → Engineering → Cargo (sled channel, core compartment) → Pod Bay. Static preview from `tools/preview_layout.py`, not a Godot screenshot.*

---

## Engine (pinned)

| | |
|---|---|
| Engine | **Godot 4.7.x stable**, standard build (not .NET) |
| Exact patch the team uses | `4.7.__` ← fill this in at hour 0; everyone installs the same one |
| Renderer | Compatibility (works for native + web) |
| Language | GDScript only |

If you open the project in a different version, Godot asks to convert it. Say no and install the pinned version instead.

---

## First launch (5 minutes, do this once)

1. Open Godot 4.7 → **Import** → pick this folder's `project.godot`. The first open imports all PNG/WAV files; wait for it to finish.
2. Watch the **Output** and **Debugger → Errors** panels. They should show no red errors.
3. Press **F5**. You should see the black-hole briefing screen. Press **E**.
4. Walk to the blue terminal (top of the cockpit) and press **E**. The cockpit door opens and the timer starts.
5. Run the automated checks from a terminal in this folder:
   ```bash
   godot --headless --path . res://tests/test_runner.tscn
   ```
   It ends with `=== N passed, 0 failed ===`. It plays a full run by script (sled puzzle, core, clamp, pod), restarts 3 times, and exits with the failure count.

If anything errors, paste the exact error into chat (with the file and line) and fix that first.

---

## Controls

| Key | Action |
|---|---|
| WASD / arrows | Move |
| E | Interact (prompt appears only near a valid target; nearest wins) |
| Hold SPACE | Mag-boots: walk 60 px/s, drift only 18 px/s instead of 90 |
| H | Ask ECHO for help |
| Esc / P | Pause (then R restart, M mute, V reduced shake/flash) |
| R | Restart on the end screens |

Input actions are registered in code (`scripts/core/input_setup.gd`). If you add an action with the same name in Project Settings → Input Map, yours wins.

---

## How a run plays

```
Briefing ─E─▶ Cockpit ──▶ Engineering ──▶ Cargo ──────────────▶ Pod Bay ──▶ Earth
              terminal     power console   sled slides on a      clamp,
              (timer       (doors 2 open,  DOWN surge → plate    board pod
              starts)      sled powered)   → compartment → core
```

| # | Objective id | Done by | Opens |
|---|---|---|---|
| 1 | `start_evacuation` | Cockpit terminal `T` | Door `1`, starts the 6:00 timer |
| 2 | `restore_power` | Power console `P` | Door `2`, powers the cargo sled |
| 3 | `open_compartment` | Sled reaches plate `S` during a DOWN pull | Door `K` |
| 4 | `collect_core` | Core `N` (adds `navigation_core`) | Door `3` |
| 5 | `release_clamp` | Clamp console `L` | — |
| 6 | `board_pod` | Pod `O` (needs power + core + clamp) | Win → launch sequence |

**Gravity:** 6 s calm at the start, then repeating **3 s warning → 6 s pull → 7 s calm**, alternating **DOWN, UP**. The HUD shows a blinking amber arrow and frame during the warning, and a red arrow during the pull.

**Failure:** debris contact = −10 s, followed by a 1 s hit cooldown. Reaching 0:00 loses the run.

---

## Who owns what

Plan lanes A–D. Edit your own files; flag a teammate before touching theirs.

```
project.godot                      A   engine/display settings, autoloads
scenes/main.tscn, scripts/main.gd  A   mission root; restart = reload this scene
scripts/core/game_state.gd         A   rules: objectives, timer, damage, win/lose (autoload GameState)
scripts/core/gravity_director.gd   A   surge cycle + drift
scripts/core/input_setup.gd        A   input actions
scenes/player/, scripts/player/    A   movement, boots, interaction targeting, camera

data/ship_layout.txt               B   THE LEVEL: edit the ASCII and press F5 (legend: data/LAYOUT_LEGEND.md)
tools/preview_layout.py            B   re-render docs/map_preview.png after editing the layout
scripts/ship/ship_builder.gd       B   turns the ASCII into walls, doors, objects
scripts/interactables/             B   consoles, sled puzzle, core, pod, doors, debris

scripts/ai/companion_client.gd     C   ECHO client: requests, validation, fallbacks
data/dialogue_fallbacks.json       C   authored ECHO lines (offline mode)
server/                            C   /companion backend (Python stdlib)

scripts/ui/hud.gd                  D   HUD, briefing, pause, lose/win screens
scripts/core/settings.gd           D   mute, reduced shake (autoload Settings)
scripts/core/sfx.gd                D   sound player (autoload Sfx)
scripts/ship/art.gd                D   palette + texture helpers
assets/, tools/gen_placeholder_assets.py, CREDITS.md   D
```

---

## Contracts (agree before splitting work)

| Contract | Where |
|---|---|
| `interact(player)` and `can_interact(player)` on every interactable; it asks GameState and never sets state itself | `scripts/interactables/interactable.gd` |
| `GameState.complete_objective(id) -> bool` is idempotent and rejects out-of-order completion | `game_state.gd` |
| Signals `objective_changed(id)`, `inventory_changed()`, `time_changed(seconds)`, `run_ended(won)`, plus `phase_changed`, `damaged`, `room_changed`, `paused_changed`, `game_event(event_id)` | `game_state.gd` |
| `gravity_warning(direction)`, `gravity_changed(direction, drift_speed)`; `get_drift(braced)` | `gravity_director.gd` |
| `GameState.get_canonical()` returns `{id, text, hint}`: the authoritative objective and hint, never from the model | `game_state.gd` |
| Phases: BRIEFING, PLAYING, WON, LOST. Pause stops the countdown and the gravity cycle | `game_state.gd` |
| Launch and timer expiry are validated centrally; after PLAYING ends, damage and launch are ignored | `game_state.gd` |

Restart reloads `scenes/main.tscn`, and `main.gd` calls `GameState.new_run()`. That resets the timer, objectives, sled, doors, debris, hit cooldown, gravity phase, pending dialogue, and run id together.

---

## ECHO (AI companion)

Two separate text channels:

1. **Objective and hint** (top bar). These come from game rules only.
2. **ECHO's caption** (bottom). This is flavor only, and every caption is labeled by source:
   - `ECHO · LIVE`: the model answered.
   - `ECHO · MOCK SERVER`: the server's canned test lines.
   - `ECHO · OFFLINE (scripted line)`: an authored fallback from `data/dialogue_fallbacks.json`.

**Rules (already implemented):** one request in flight; 15 s cooldown; max 12 requests per run; repeated events coalesced within 10 s; 3 s timeout. Pending replies are dropped on objective change, pause, game over, or restart. Replies whose `run_id`, `state_version`, or `event_id` don't match are discarded. Gameplay never waits on a reply.

**Run the backend** (Python 3.10+, no packages needed):

```bash
python3 server/companion_server.py                 # mock mode: no key, no cost
export ANTHROPIC_API_KEY=...                        # set a small spending limit first
python3 server/companion_server.py                 # live mode
python3 -m unittest server/test_companion_server.py
```

Optional environment variables: `COMPANION_MODEL` (default `claude-haiku-5-5`), `COMPANION_PORT` (8787), `COMPANION_MOCK=1`.

The game posts to `http://127.0.0.1:8787/companion`. With no server running, the HUD shows `ECHO: OFFLINE` and the game is fully playable.

**Request snapshot:** `run_id`, `state_version`, `event_id` (unique, e.g. `help#4`), `room_id`, `objective_id`, `time_band` (`not_started|plenty|ok|low|critical`), `inventory`, `recent_event`, `boots_use_count`, `canonical_hint`.

**Response:** `run_id`, `state_version`, `event_id` (echoed), `line` (≤180 chars, plain text), `source` (`model|mock`). Anything else is rejected and the game shows the fallback.

The API key lives only in the server's environment. Never put it in Godot, the repo, or a web build.

---

## Exporting (D)

1. Install the export templates for the **exact** pinned version (Editor → Manage Export Templates).
2. Project → Export → add your OS (primary deliverable) and optionally Web.
3. **Resources tab → "Filters to export non-resource files"**: add `data/*.txt, data/*.json`.
   Without this, the build can't read the level or ECHO's lines. Both have built-in fallbacks, but edits to the files would be silently ignored.
4. Test the exported build on the demo laptop: sound plays, Wi-Fi off still works, a full run reaches Earth.
5. Web build: ECHO stays offline unless the backend is on HTTPS with CORS. That's fine; it's labeled.

---

## Art and sound

All placeholders are generated by `tools/gen_placeholder_assets.py` (PICO-8 palette, 32 px grid). To replace one, draw a new file **at the same size** with the same name; collisions never depend on art. See `CREDITS.md`.

Display settings: 640×360 base, `canvas_items` stretch, integer scaling, nearest filtering, 2D pixel snap. Don't rotate sprites (use flip). For a pixel font, add a theme with antialiasing off and log its license in `CREDITS.md`.

---

## Known limitations (be honest in the demo)

- Not yet launched in the Godot editor (see the top of this file).
- Room layout is generated from ASCII at runtime, so the editor's 2D view of `main.tscn` is empty. Run the game to see it.
- The cargo sled ignores the player and the player can't enter its channel. That's deliberate: the sled can't trap anyone.
- One placeholder walk frame pair; no up/down-facing sprites yet.
- HUD uses Godot's default font until D adds a pixel font.
