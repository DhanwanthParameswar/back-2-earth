# Back2Earth

> **New playable design prototype:** Start Game now opens the branching crew escape
> after the unchanged opening film. Engineering and battery routes, optional sample
> rescue, crew cooperation and three endings are implemented. See
> [Escape Prototype](docs/Escape%20Prototype.md) for controls, walkthroughs and live
> AI setup. The older mission and its documentation below are retained for reference.

*Your spaceship is being pulled toward a black hole. Use its failing gravity to navigate wreckage, work with a damaged AI companion, and launch the last escape pod home.*

UBhacks 2026 · Godot 4 · GDScript · top-down 2D · retro pixel art

> **Starter build status:** every system below is written, and every GDScript file passes a syntax parser. The backend has 12 passing tests. **Nobody has launched this in Godot yet**: the build machine couldn't download Godot. Do the "First launch" check below before anyone branches off.

![Ship layout preview](docs/map_preview.png)

*Cockpit → Engineering → Cargo (sled channel, core compartment) → Pod Bay, in the 3/4 view. Static preview from `tools/preview_layout.py`, not a Godot screenshot.*

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
3. Press **F5**. The animated title menu plays. Hold the mouse down on each button: it should sink in (the face drops onto its shadow and dims), and act when you let go. Open **How to Play**, **Settings**, and **Credits** (Esc or BACK closes them). Click the speaker icon: a red slash shows it's muted. Then click **Start Game** (or press Enter).
4. The opening story plays (36.8 s, with voices). Watch it through once, then restart and press **E** to check it skips.
5. Gameplay starts on the RESTORE EMERGENCY POWER card. You're Johnny, in the classic suit.
6. Walk to the blue terminal (top of the cockpit) and press **E**. The cockpit door opens and the timer starts. Walk behind the terminal: your astronaut should be hidden behind it, then drawn in front when you walk below it.
7. Run the automated checks from a terminal in this folder:
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
| H | Ask ECHO for help |
| Esc / P | Pause (then R restart, M mute, V reduced shake/flash) |
| R | Restart on the end screens |
| E / Enter / Space / Esc / click | Skip the opening story |
| Q | Main menu (from pause, win, or lose) |
| Menu | Mouse for every button; Enter/E = Start Game, M = mute, Esc = close a panel |

Input actions are registered in code (`scripts/core/input_setup.gd`). If you add an action with the same name in Project Settings → Input Map, yours wins.

---

## How a run plays

```
Title menu ─Start Game─▶ Opening story (36.8 s, skippable) ─▶ run
   ▲                                                         │
   └──── Q from pause / win / lose (R restarts the run, no story) ───┘
```

```
Story ──▶ Cockpit ──▶ Engineering ──▶ Cargo ──────────────▶ Pod Bay ──▶ Earth
              terminal     power console   sled slides on a      clamp,
              (timer       (doors 2 open,  DOWN surge → plate    board pod
              starts)      sled powered)   → compartment → core
```

| # | Objective id | Done by | Opens |
|---|---|---|---|
| 1 | `start_evacuation` ("Restore emergency power") | Cockpit terminal `T` | Door `1`, starts the 6:00 timer |
| 2 | `restore_power` ("Restore main power") | Power console `P` | Door `2`, powers the cargo sled |
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
tools/make_ship_tiles.py           D   map tiles in the opening film's look (navy walls, steel deck, hull)
scripts/ship/starfield.gd          D   space around the ship (shows through `~` cells)
scripts/ship/ship_builder.gd       B   turns the ASCII into walls, doors, objects
scripts/interactables/             B   consoles, sled puzzle, core, pod, doors, debris

scripts/ai/companion_client.gd     C   ECHO client: requests, validation, fallbacks
data/dialogue_fallbacks.json       C   authored ECHO lines (offline mode)
server/                            C   /companion backend (Python stdlib)

scripts/ui/hud.gd                  D   HUD, objective card, pause, lose/win screens
scripts/ui/press_button.gd         D   panel button that sinks when pressed
tools/extract_menu_buttons.py      D   cuts the painted button faces out of the menu video
scenes/menu.tscn, scripts/ui/main_menu.gd   D   title menu over the menu video
scripts/ui/ui_style.gd             D   shared navy/cyan panel + button style
data/credits.json                  D   names on the CREDITS panel
scripts/core/settings.gd           D   mute, reduced shake (autoload Settings)
scripts/core/sfx.gd                D   sound player (autoload Sfx)
scripts/ship/art.gd                D   palette + texture helpers
assets/, tools/gen_placeholder_assets.py, CREDITS.md   D
art_source/, tools/import_astronaut_skins.py           D   suit drawings -> grid-true sprites
```

---

## Contracts (agree before splitting work)

| Contract | Where |
|---|---|
| `interact(player)` and `can_interact(player)` on every interactable; it asks GameState and never sets state itself | `scripts/interactables/interactable.gd` |
| `GameState.complete_objective(id) -> bool` is idempotent and rejects out-of-order completion | `game_state.gd` |
| Signals `objective_changed(id)`, `inventory_changed()`, `time_changed(seconds)`, `run_ended(won)`, plus `phase_changed`, `damaged`, `room_changed`, `paused_changed`, `game_event(event_id)` | `game_state.gd` |
| `gravity_warning(direction)`, `gravity_changed(direction, drift_speed)`; `get_drift()` | `gravity_director.gd` |
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
python3 server/companion_server.py                 # mock mode: no keys, no cost
export GEMINI_API_KEY=...                           # Google Gemini writes ECHO's and the crewmate's lines
export ELEVENLABS_API_KEY=sk_...                    # ElevenLabs speaks the crewmate's lines
python3 server/companion_server.py                 # live mode
python3 -m unittest server/test_companion_server.py
```

Optional environment variables: `GEMINI_MODEL` (default `gemini-3.5-flash-lite`), `NPC_VOICE_ID` (default Katie, `HXrznjtuwc7KlmunddH7`), `ELEVENLABS_MODEL` (`eleven_flash_v2_5`), `TEXT_CALLS_PER_DAY` (3000), `TTS_CHARS_PER_DAY` (40000), `COMPANION_PORT` (8787), `COMPANION_MOCK=1` (force mock). On the hosted server the keys live only in `/etc/back2earth/companion.env`.

The endpoints are public, so the server rate-limits each player and stops calling Gemini/ElevenLabs once a daily budget is used up (the game then falls back to scripted lines).

### Leaderboard and accounts (Tiger Cloud database)

Everyone plays as a **guest**; no login needed. Each device gets a random guest id, and guest wins go on the leaderboard as **GuestXXXX** automatically. After a **win**, the win screen shows the **top 10** (left; ranks 1-10 always listed, `---` when empty) and **your time** plus the name it was saved under (right). To put your own name on it, create an account (username + password) or log in right there: that run moves to your username, the game stays logged in on that device, and later wins save under your name. Losses count in the stats.

- Database: Tiger Cloud `back2earth-db` (PostgreSQL + TimescaleDB). Schema: `server/schema.sql` (safe to rerun). The backend reads `DATABASE_URL` from its environment; the game never talks to the database.
- Endpoints: `/auth/register`, `/auth/login`, `/auth/logout`, `/auth/me`, `/runs/start`, `/runs/end`, `/runs/claim`, `/leaderboard` (see `server/game_db.py`).
- Fair play: the **server** times each run (start to end), a run ends once, and wins under 12 s are refused (real speedruns take ~20 s). Run reports can be up to 64 KB (a full run's event log is ~20 KB).
- Accounts: usernames 3-16 letters/numbers/_ (unique, basic bad-word filter); passwords 8+ characters, stored as scrypt hashes only; 5 wrong passwords lock that username for 5 minutes. No email, so no password reset.
- Stats views: `leaderboard`, `run_stats` (plays, wins, fails, best time), `events_by_room` (where players struggle).
- Tests: `python3 -m unittest server/test_game_db.py` (uses an in-memory fake database).

### Crewmate (talk to an NPC)

Layout char `M` places the surviving crewmate (top-left of the cockpit). Walk up and she says the pre-recorded greeting (`assets/voice/crewmate_greeting.mp3`, works offline). Press **E** to open the chat box, type anything, **Enter** to send, **Esc** to close.

Pipeline: game `POST /npc/talk` (message + last few turns + the canonical objective/hint) → Gemini writes a 1-2 sentence in-character reply → the text shows at once → game `GET /npc/audio/<id>.mp3` → ElevenLabs reads it in Katie's voice (cached on the server and by Cloudflare). If the server is unreachable, she answers with a scripted line built from the real hint. She can't change game state: replies are flavor and paraphrased hints only.

To add another NPC: add an entry to `NPCS` in `server/companion_server.py` (persona prompt + voice id), a script like `scripts/interactables/crewmate.gd` with its `npc_id`, and a layout char in `ship_builder.gd`. To pre-record a scripted line in the same voice, run on the server: `python3 /opt/back2earth/server/companion_server.py --tts "Your line." > line.mp3` (with the env file loaded).

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

## Hosting (web build)

| Address | What | Served by |
|---|---|---|
| `https://back2earth.pp.ua` | The web build | Caddy on the team server, `/var/www/back2earth` |
| `https://www.back2earth.pp.ua` | Redirects to the address above | Caddy |
| `https://api.back2earth.pp.ua/companion` | ECHO backend (web builds call this, see `Settings.WEB_COMPANION_URL`) | Caddy → `back2earth-companion` service on `127.0.0.1:8787` |

Cloudflare proxies all three DNS records (orange cloud), with SSL mode **Full (strict)** and a Cloudflare Origin CA certificate on the server. The server's firewall allows port 443 from Cloudflare's IP ranges only, so it can't be reached directly.

**Automatic deploys:** every push to `main` (except docs-only changes) builds the Web export on GitHub Actions in the `barichello/godot-ci` image (keep its tag equal to the project's Godot version) and puts it live (`.github/workflows/deploy-web.yml`, a few minutes; watch it in the repo's Actions tab, or run it by hand there with "Run workflow"). It needs four repository secrets: `DEPLOY_SSH_KEY` (the server's private key), `DEPLOY_HOST`, `DEPLOY_USER`, and `DEPLOY_KNOWN_HOSTS` (the server's public host keys from `ssh-keyscan`). The site's favicon is the pixel Earth from `tools/make_logo.py` (`assets/icon.png`, plus `web/favicon.ico` served at the site root).

**Redeploy by hand:** copy `.env.example` to `.env` (gitignored) and fill in the server login, SSH key path, and Godot path, then run `tools/deploy_web.sh` (exports, gzips the wasm, uploads, swaps in). Ask a teammate for the server details; they are never committed.

**Update the backend:** copy `server/companion_server.py` to `/opt/back2earth/server/` on the server, then `sudo systemctl restart back2earth-companion`. Secrets (e.g. `ANTHROPIC_API_KEY`) go in `/etc/back2earth/companion.env`, never in the repo. The endpoint is public: add rate limiting before switching ECHO to live mode.

---

## View and camera (Stardew-style 3/4)

- **Perspective:** top-down at a 3/4 angle. Walls with floor below them show a **front face**. The back wall is 2 tiles tall (the layout's top two rows). Other walls show their top cap. The rules are in `ShipBuilder.wall_kind()`.
- **Depth:** the ship node has `y_sort_enabled`. The player, consoles, pod, core, sled, and debris are its children and draw in order of their **base** y. Every object's origin is where it touches the floor: the player's feet, a console's front edge. So you walk behind things above you and in front of things below you.
- **Feet collision:** the player collides with an 18×10 box at the feet, so the head can overlap the wall behind, like Stardew. Consoles and the pod have solid footprints.
- **Camera:** smoothly follows the body (`CAMERA_SMOOTHING_SPEED` in `player.gd`) and stops at the map edges. If you see pixel jitter while moving, raise the speed or turn smoothing off there.
- **Shadows:** soft ovals under the player, props, and debris sell the floor plane.
- **Floor:** one continuous surface with no tile grid. `assets/tiles/floor.png` is a 256×256 seamless texture, and each floor cell draws its own slice of it by world position. If you replace it, keep it seamless and a multiple of 32 px.
- **Space window:** the `W` block in the cockpit's back wall is one wide pane. The nebula video plays behind it (`scripts/ship/space_window.gd`). The video is clipped to the glass, loops every 12 s, and shifts slightly as the camera moves (`PARALLAX`). `FOCUS` picks which part of the video is centered at the start of a run. The camera can rise 48 px above the map, so the HUD bar never covers the back wall.

## Suits (skins)

- Four suits: **classic**, **hazard**, **nebula**, **mint**, listed in `Settings.SKINS`.
- **No suit picker.** The player is always Johnny in the **classic** suit (`Settings.PLAYER_SKIN`), because that's what he wears in the opening film. The in-game crewmate (Aaron) takes the first other suit in `SUIT_PREFERENCE` (`crewmate.gd`): hazard, as in the film. If you re-edit the film with a different suit, change `PLAYER_SKIN` to match.
- **Art pipeline:** the original drawings live in `art_source/` (a 4×6 walk sheet and the concept sheet). `python3 tools/import_astronaut_skins.py` (~40 s) snaps them to a true pixel grid and writes:
  - `assets/sprites/astronaut_<suit>.png`: 6 walk frames facing right, each 16×27 art px, saved at 2× (32×54 in-game). Frame 5 is idle; left is a flip. The tool uses the sheet's transparency (its outlines are black, like its background), finds each frame's real pixel grid, and lines every frame up with the front of the helmet at the same x and the feet on the bottom row, so the walk cycle doesn't slide and every suit stands on its shadow.
  - `assets/ui/portrait_<suit>.png`: 16×19 front portrait (from when there was a picker; kept for future UI; re-made only with `--portraits`).
- **Adding a suit:** add a row to both source sheets (or drop in the two PNGs), add an entry to `Settings.SKINS`, then re-run the tool.

## Main menu

- `scenes/menu.tscn` + `scripts/ui/main_menu.gd` is the project's main scene. Everything on it is drawn live by `scripts/ui/menu_backdrop.gd` and fills any window shape (the menu switches the window to "expand" while open):
  - **Sky:** `scripts/ui/menu_sky.gdshader` generates the navy space, two pixel nebula bands and twinkling stars in code, so there are no edges to run out of.
  - **Logo:** true pixel art from `tools/make_logo.py` (hand-drawn letters, plus a 48×24 world map). The Earth is `scripts/ui/menu_earth.gdshader`, a pixel sphere that spins once every 48 s.
  - **Buttons:** pixel art from `tools/make_menu_art.py` (the five buttons and their pressed versions), drawn 3× with nearest filtering. Labels are rendered from the game font (Monocraft) at its native pixel size. Positions go to `data/menu_layout.json`, and the click areas follow them.
  - **Floating sprites** (astronaut, debris, ship, planets): the original menu art's look, cleaned up by `tools/import_menu_sprites.py`. It cuts each piece from `art_source/menu_loop_1080p.ogv`, snaps it onto a true 1-menu-pixel grid, and reduces it to a small palette, which removes the AI smudges and stray pixels.
  - Every piece uses nearest filtering, so each art pixel is a crisp square. The logo and buttons stay centered, the astronaut group sticks to the right edge, the ship and CREDITS to the bottom-left, and the speaker to the bottom-right.
- **Press effect:** hovering lifts and brightens a button. While held, it swaps to its pressed image (the face sunk onto its 3D strip). The action fires on release.
- **Keys:** Enter/E presses START GAME and M presses the speaker, both with the same sink animation. Esc closes a panel. Panel buttons and suit cards sink the same way when clicked.
- **Buttons:**
  - START GAME fades out and loads the game.
  - HOW TO PLAY shows the goal, steps, and controls.
  - SETTINGS has sound, reduced shake & flash, ECHO live replies, fullscreen, and quit. Fullscreen and quit are hidden on web.
  - CREDITS reads `data/credits.json`. **Put your names in it.**
  - The speaker icon toggles sound.
- Every setting is saved in `user://settings.cfg`.
- **Fallback:** if the video is missing, the menu still works and shows labeled buttons.

## Ship map (what Start Game plays)

The escape prototype's ship is data, not code: `tools/make_escape_map.py` holds the rooms, doors, windows, furniture and the named spots the story uses (where the locker sits, where Aaron holds it, where the crew boards...), and writes `data/escape_map.json` plus `docs/escape_map_preview.png`. It also checks that every story step is reachable and that the jammed locker really blocks the cabin. `scripts/prototype/escape_ship.gd` draws it; `escape_mission.gd` reads the spots with `anchor("name")`.

- **Rooms:** gameplay starts where the film ends: in the CORRIDOR on the safe side of the sealed barrier (MAIN POWER OFFLINE screen, emergency panel), facing the locker the impact threw across the hallway. Past the barrier, sealed but visible: the BREACH and the CABIN (the film's seating room, where the crew slept). Past the locker: JUNCTION (launch terminal) with ENGINEERING north, LABORATORY south, SHUTTLE BAY east. To explore: FLIGHT DECK (cockpit window, helm, nav table), GALLEY, STORAGE, OBSERVATION lounge, MEDBAY, HYDROPONICS, SUIT ROOM (airlock).
- **Art:** `tools/make_ship_art.py` draws every floor, wall, piece of furniture and gameplay prop in the film's palette (`assets/ship/`, contact sheet `docs/ship_art.png`).
- **Lighting:** dim emergency light until the shuttle bay has power, rotating red alarm beacons spread along the rooms' back walls (`scripts/prototype/escape_alarm.gd`), a pulsing reactor.
- **Editing:** move or add things in the tables in `make_escape_map.py`, rerun it (`python3 tools/make_escape_map.py`), then run the prototype tests.

## Opening story

The team's 36.8-second cut (with voices) plays as soon as a run starts from the main menu, then cuts to gameplay with the first objective, **RESTORE EMERGENCY POWER**. Restarts (R) skip it. E, Enter, Space, Esc, or a click skips it (after half a second, so the Start key doesn't skip it too).

The crew: **Johnny** (the player, classic suit), **Aaron** (pulls Johnny to safety, hazard), **Kien** (pulled out into space), **Dhan** (gets ahead, locked in the East Section).

| Time (approx.) | Beat |
|---|---|
| 0:00–0:05 | THE YEAR 2126 dissolves into space; the ship cruises past small, far-off planets |
| 0:05–0:11 | Cabin: four crew asleep. MARS SPACE STATION / REPAIRS MISSION: **SUCCESS** / RETURNING HOME. Dashboard: DISTANCE TO EARTH 676,767 MI |
| 0:11–0:19 | Kien: "Real food. Finally." Impact, red alarm. "SYSTEM: Collision detected. Evacuate now." Crew hurry aft |
| 0:19–0:24 | Corridor: Dhan gets through the EAST SECTION door before it locks; "KIEN: \*Sucked out of the ship\*"; Johnny reaches and misses |
| 0:24–0:27 | Outside: the breached ship; Kien tumbles away |
| 0:27–0:37 | Aaron pulls Johnny through the bulkhead; MAIN POWER OFFLINE; Johnny: "That was a close one! We need to fix power first. Then find Dhan." Fade to black |

- **In the game:** the picture is drawn live by `scripts/ui/intro_film.gd`, a line-by-line Godot port of `tools/make_intro.py`'s shots. It draws the same 320×180 pixel art into a viewport, scaled up with nearest filtering, so it stays crisp at any window size (the old 640×360 video was blurry). The sound is `assets/audio/intro.ogg` (the cut's track, voices included), and the picture follows the sound's clock so they stay in sync. `scripts/ui/intro_cutscene.gd` runs both and handles skipping.
  - `assets/intro/` holds the pieces `make_intro.py` draws once (backgrounds, ships, planets, crew frames, masks), and `data/intro_film.json` holds everything it picks at random (stars, air, debris, sparks, camera shake). Both come from `python3 tools/make_intro.py --export-godot`; re-run it after changing the film there.
  - `data/intro_edit_map.json` is the team's final-cut timing: for each frame of the cut, which frame of the original render it shows (longer year card, a frame nudge on the dashboard, 1.4 s trimmed from the outside shot). `python3 tools/align_intro_edit.py` recovers it from `assets/video/intro.ogv`.
  - Checked frame by frame against the original render: no pixel off by more than 8/255 (tint rounding only).
  - If the film's files are missing, the old video `assets/video/intro.ogv` plays instead; if that's missing too, the run starts straight away.
- **Changing the film:** edit `tools/make_intro.py` (timeline, captions, monitor text and the distance figure are constants at the top), port any new drawing code to `intro_film.gd`, then run `--export-godot`. A new voice track goes in `assets/audio/intro.ogg`; if its timing changes, re-cut the video and run `tools/align_intro_edit.py` to refresh the frame map.
- **Base footage:** `python3 tools/make_intro.py` still renders the silent film as video into `art_source/intro_base/` (git-ignored) for editing; it never overwrites the game's copy.

## Video

- `art_source/pixel_nebula_loop_1080p.ogv` is the original (Ogg Theora, 1920×1080, 30 fps, 12 s).
- `assets/video/nebula_loop.ogv` is the game copy, re-encoded to 480×270 so each art pixel is 2×2 in-game, like everything else. It is ~16× cheaper to decode, which matters for laptops and web builds. To redo it:
  ```bash
  ffmpeg -i art_source/pixel_nebula_loop_1080p.ogv -vf "scale=480:270:flags=area" -c:v libtheora -q:v 9 -g 30 -an assets/video/nebula_loop.ogv
  ```
- `art_source/menu_loop_1080p.ogv` is the original menu video. `assets/video/menu_loop.ogv` is a 1280×720 re-encode, drawn with smooth filtering because the menu art isn't on the game's pixel grid:
  ```bash
  ffmpeg -i art_source/menu_loop_1080p.ogv -vf "scale=1280:720:flags=lanczos" -c:v libtheora -q:v 6 -g 30 -an assets/video/menu_loop.ogv
  ```
- Godot only plays Ogg Theora (`.ogv`). Convert any MP4/WebM first.

## Art and sound

**One pixel size everywhere:** art is drawn at 16 px per tile and saved at 2×, so one art pixel = 2×2 screen pixels for tiles, props, and suits alike. Map tiles come from `tools/make_ship_tiles.py`, using the opening film's palette (navy cabin walls with the light stripe and green lights, steel decking, bulkhead doors with amber dashes, light-gray hull plating on top of walls, and the red-striped hull side where the ship meets space). Other placeholders come from `tools/gen_placeholder_assets.py` (PICO-8 palette). To replace one, draw a new file **at the same size** with the same name; collisions never depend on art. See `CREDITS.md`.

Display settings: 640×360 base, `canvas_items` stretch, integer scaling, nearest filtering, 2D pixel snap. Don't rotate sprites (use flip). For a pixel font, add a theme with antialiasing off and log its license in `CREDITS.md`.

---

## Known limitations (be honest in the demo)

- Not yet launched in the Godot editor (see the top of this file).
- Room layout is generated from ASCII at runtime, so the editor's 2D view of `main.tscn` is empty. Run the game to see it.
- The cargo sled ignores the player and the player can't enter its channel. That's deliberate: the sled can't trap anyone.
- Suits only have side-view walk frames; walking up or down keeps the last left/right facing. Front/back frames would be the next art addition.
- Wall faces are drawn on the floor layer, so a wall *below* the player never covers their feet. That's fine for this layout.
- HUD uses Godot's default font until D adds a pixel font.

### Accounts and resumable missions

Start Game opens account access for new players. Sign in or create an account,
or continue as a guest. The saved-game panel offers Resume, New Game, and Delete
Saved Game, with confirmation before replacing or deleting progress. Guest saves
stay on the current device; account saves also sync to the database. An existing
guest checkpoint can be imported into an empty account slot.

Signed-in players can choose Delete Account and confirm with their password.
Deletion permanently removes the account, all sessions, cloud checkpoint and crew
memories, owned runs and their events, and leaderboard results in one transaction.
The current device's account checkpoint is removed after server confirmation;
guest saves are kept. Offline or failed deletion keeps the account and save intact.

The escape mission saves after progress changes, every five seconds while playing,
on pause, and on leaving the mission or losing focus. Checkpoints include the
route, inventory, player/crew positions, flashlights, recent radio conversation, remembered crew facts,
and pending crew tasks. Resume skips the intro and restores cleared-locker
collision and interrupted case deliveries. Completing an escape removes its
resume slot. Crew conversations and remembered facts belong to that checkpoint:
Resume restores them, and New Game, Restart, Delete Save, or completing the mission
clears them with its progress. Accounts and leaderboard results are kept. Current
clients send their saved notes with each chat and never use the older account-wide
memory table, so an old or late reply cannot repopulate a new game's memory.

`SaveGame` keeps a separate atomic local file per account (or guest device).
Offline account changes stay queued and retry every 15 seconds. Cloud revisions
prevent stale uploads from overwriting a newer save or resurrecting a deletion.
If two devices diverge, the menu offers an explicit cloud/local choice. Passwords
are sent only to the existing authentication endpoint and are never checkpointed.

Backend release: apply `server/migrations/001_game_saves.sql` to the existing
database (or `server/schema.sql` for a fresh database), then deploy
`server/save_games.py` together with the updated `game_db.py` and
`companion_server.py`. The web deployment workflow alone does **not** deploy the
backend or apply this migration. Until then, local saves work and cloud saves are
shown as unavailable. The account API remains `/auth/register`, `/auth/login`,
`/auth/logout`, `/auth/me`; saves use authenticated `GET /save`, `POST /save`, and
`POST /save/delete`. Writes include the last known `revision` and return HTTP 409
if another device changed it.

Local integration checks (use separate temporary settings/save paths so test
accounts cannot replace your own):

```sh
python3 -m unittest server/test_game_db.py server/test_escape_dialogue.py
B2E_SAVE_DIR=/tmp/b2e-save-check B2E_SAVE_NETWORK=0 \
  B2E_SETTINGS_PATH=/tmp/b2e-save-settings.cfg \
  godot --headless --path . --script res://tests/save_runner.gd
# Separate terminal: an isolated, in-memory account/save backend.
python3 server/dev_save_server.py
B2E_BACKEND=http://127.0.0.1:8788 B2E_SAVE_DIR=/tmp/b2e-cloud-check \
  B2E_SETTINGS_PATH=/tmp/b2e-cloud-settings.cfg \
  godot --headless --path . --script res://tests/save_cloud_runner.gd
```
