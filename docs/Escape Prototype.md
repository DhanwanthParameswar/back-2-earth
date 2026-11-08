# The escape: build notes

What Start Game plays after the opening film. The design (story, routes, numbers,
lines) is in [Game Design.md](Game%20Design.md); this page is for running, testing
and changing it. **Spoilers below**: it's written for the team, not players.

The radio API keeps the original crew ids: `mara` is Aaron, `ivo` is Dhan.

## Play locally

Open the project in Godot **4.7.2**, press F5, Start Game. To skip the film while
iterating, run `scenes/escape_prototype.tscn` directly (F6).

| Key | Does |
|---|---|
| WASD | Move |
| E | Use / talk. **Hold** for heavy jobs (pulling Dhan, the isolator, the battery latch, the splint) |
| 1 / 2 / 3 | Radio Aaron / Dhan / M.A.R.V.I.S. (controller: LB / RB / L3) |
| Space | Talk again in voice chat (web, Chrome/Edge) |
| F | Flashlight (the ship is dark until the bay has power) |
| Tab | Deck map and the log of what you've learned |
| Esc | Close a panel, step back from a machine, pause |

Inside a machine close-up: click parts, or WASD to move the highlight and E to press.

**Settings · CREW LIVE AI** turns live replies off: the crew then use the scripted
interpreter (`offline_response` in `escape_mission.gd`), which handles every story step.

## Walkthroughs (spoilers)

Puzzle answers change every run (`Rules.new_puzzle`). Read them off the screen and
ask Dhan, the way a player would.

**Opening.** The aftershock pins Dhan. Ask Aaron to lift the locker (any wording:
"get it off him"). Stand by Dhan; when Aaron lifts, hold E on Dhan for 2 s. Aaron
can only hold it ~6 s. Then use the junction terminal (or radio 3, "status"): the
crew react on their own and lay out both routes.

**Engineering.** In Engineering, hold E on the ISOLATOR. Open the cabinet and read the
fault code (E-3/E-6/E-9) to Dhan: he names the fuse box. Get it from Storage yourself,
or tell Aaron "get the fuse from box B" and he leaves it by the cabinet. Seat it, TEST:
the display shows `SHORT: AUX-n`. Tell Dhan the AUX number, he says which toggle. Open
the AUX guard, flip it, RESTART.

**Battery.** Optional first: ask Aaron about saving the samples, he offers the case;
ask him to fetch it, then pack the "K + A PRIORITY" rack in the freezer close-up.
Lift the freezer guard and hold POWER off (this commits). Hold E on the battery latch.
Ask Aaron to lift it with you; press E on his "three!". Take the cart to the bay
socket, ask Dhan which setting, set the knob, CONNECT.

**Medbay** (any time). Take the splint kit from the medical cabinet, hold E on Dhan.

**Launch.** Ask Aaron to help carry Dhan. Take the pilot seat (E on the shuttle).
Tell Aaron to release the clamps; launch once he's aboard.

**Fails.** Touch the live cabinet (slot/TEST/RESTART) before isolating · press the
outer airlock in the suit room · pull the battery latch while the freezer runs ·
LAUNCH with clamps on · LAUNCH before Aaron boards.

**Launch and ending film.** LAUNCH runs `_launch()` in `escape_mission.gd` (sirens,
doors seal, hatch, drop; ~5 s), then `scripts/ui/outro_film.gd` (~70 s with credits; E
skips), then the stats card. The film's lines per ending are `DIALOGUE` in that file;
the credits come from `data/credits.json` (**fill in your names there**).

**Endings.** Engineering, Dhan fine → Everyone home · battery + priority rack → What
he left us · battery only → We kept each other · Dhan at stage 3-4 → Barely · Dhan's
condition ran out → Two came home. Tune times in `escape_state.gd` (`DRAIN` etc.).

## Live AI and voice

```sh
export GEMINI_API_KEY=...
export ELEVENLABS_API_KEY=...
python3 server/companion_server.py
```

Launch Godot with `B2E_BACKEND=http://127.0.0.1:8787` to use it; otherwise the hosted
API is used. **The hosted backend needs `server/escape_dialogue.py` and
`server/save_games.py` from this version** (new actions, instructions and save format).
Until it's updated, crew replies fall back to the scripted interpreter and cloud saves
of the new format are refused (local saves still work).

How the AI is kept honest (section 9 of the design doc): the game sends each crewmate
only the facts it should know; Dhan gets a fault code's meaning only when the player's
message contains that code; the game re-checks every action, and `check_reply()` replaces
any line where Dhan names a box, switch or setting he wasn't told about. M.A.R.V.I.S.
never uses the AI at all: `escape_marvis.gd` matches the question to a fixed list and
answers with template sentences.

**Pre-recorded lines.** Every scripted line and M.A.R.V.I.S. sentence lives in
`data/escape_lines.json`. Without audio files the game shows the text only. To voice them,
on the server (where the ElevenLabs key is):

```sh
set -a; . /etc/back2earth/companion.env; set +a
python3 tools/record_escape_lines.py
```

Commit the new `assets/voice/escape/*.mp3` and open the project once so Godot imports
them. Set `MARVIS_VOICE_ID` for a separate ship voice. Aaron's count of three uses
separate clips (`count_one/two/three`), timed by the game, so the window stays fair.

**Speech input** uses browser SpeechRecognition in the web build (Chrome/Edge). Native
builds and other browsers type instead.

## Tests

```sh
godot --headless --path . res://tests/escape_runner.tscn
python3 -m unittest server/test_escape_dialogue.py server/test_companion_server.py server/test_game_db.py
```

The Godot runner checks the rules, code/letter parsing, Dhan's condition numbers against
the design table, every ending, M.A.R.V.I.S.'s query matching, and plays the opening, the
engineering route, both battery routes, Dhan's death, every fail, the AI guardrails and a
save round trip, then the film handoff. `-- --visual` (with a renderer) saves screenshots
to `/tmp/back2earth-*.png`; `-- --fixture` rewrites `server/fixtures/checkpoint_v2.json`,
the real save the Python save check is tested against. Change the save format in three
places together: `escape_state.gd` (lists), `SaveGame.compatible()` and
`server/save_games.py`.

## Files

- `scripts/prototype/escape_state.gd`: rules, puzzle answers, Dhan's clock, fails, endings, parsing.
- `escape_mission.gd`: scene: props, crew tasks, holds, scripted lines, nudges, AI context, saves.
- `escape_marvis.gd`: the ship computer.
- `escape_closeup.gd`: the machine close-up control. `escape_ui.gd`: HUD, chat, close-ups, fail card, map, endings.
- `escape_radio.gd`: live replies, voice, memory. `escape_actor.gd`: crew movement and poses.
- `data/escape_lines.json`: every pre-written line. `tools/make_escape_map.py`: the map and story spots.
- `scenes/main.tscn`: the original gravity mission, still runnable directly.
