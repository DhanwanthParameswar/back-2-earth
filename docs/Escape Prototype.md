# Branching escape prototype

This is a playable design experiment, not a replacement for the team's final
story or art direction. **Start Game now opens this prototype after the existing
opening film.** The film, soundtrack, skip behavior and intro script are unchanged.
The surviving crew match the film: Johnny (white suit), Aaron (amber suit),
and Dhan (purple suit). Kien is lost in the breach and is not a playable crewmate.
The radio API keeps its original `mara`/`ivo` IDs for compatibility; their displayed
identities are Aaron and Dhan respectively.

## Play locally

Open this project in Godot **4.7.2**, press F5, and select Start Game. To skip the
film while iterating, open `scenes/escape_prototype.tscn` and run the current scene
(F6). Restarting the prototype also skips the film.

- WASD / arrows: move.
- E: use the nearest object or talk to a nearby crewmate.
- 1: Aaron's helmet radio. 2: Dhan's helmet radio.
- Tab: labeled deck map with live crew positions.
- Esc: close a conversation/panel, or pause the mission.
- M: mute while walking.

No countdown. The existing player, suits, floor/wall tiles, consoles, crate,
navigation-core art, pod, Earth backdrop and sound effects are reused.

## Suggested walkthroughs

### Shared opening

1. Walk toward the jammed locker on the right of the cabin.
2. Open Aaron's radio (1), ask him to help hold the locker, and watch him move.
3. Close the radio; push the locker with E while he holds it.
4. Enter the junction and inspect LAUNCH STATUS.
5. Choose a route. You can change your plan until isolating Engineering or
   disconnecting the laboratory battery commits equipment to the chosen route.

### Engineering: normal power, research preserved

Go north. Use CIRCUIT CUTOFF, collect SPARE FUSE, then use DISTRIBUTION to fit it.
Use DISTRIBUTION again to test; the breaker trips safely and identifies the short.
At AUX BRANCH, confirm sacrificing the damaged cabin-lighting branch. Restart
DISTRIBUTION. The cabin darkens and the shuttle bay's floor lights illuminate.

### Battery: emergency power, research lost

Go south. At EMERGENCY BATTERY, read and confirm the cooling-loss consequence.
Stand by SERVICE CART and ask Aaron to help lift/load the battery. He walks to
the cart; it only loads if you remain nearby. Collect the cart with E, bring it
east to the bay and connect it at EMERGENCY SOCKET.

### Battery with priority samples saved

Before disconnecting power, ask Dhan to fetch the insulated sample case. He walks
to the shuttle, visibly carries the case to the lab and reports delivery. Use
SAMPLE CASE or SAMPLE FREEZER to pack the priority rack. Then follow the battery
route. The remaining samples are lost, while the priority rack comes home.

### Shared departure

Use DOCKING CLAMPS once power is restored. Both crewmates walk to the shuttle.
Wait for them to arrive, then use BOARD SHUTTLE and confirm departure. Three
ending variants reflect the power route and sample decision. The prototype does
not submit scores to the existing leaderboard.

## Conversation modes

**Default: OFFLINE scripted intent prototype.** No API keys or server needed.
This is a bounded local phrase interpreter, not a language model. It recognizes
common phrasings of hold/help, lift/load, fetch the case, follow and wait, plus
state-aware questions about the plan, research and crew. It is intentionally
labeled; arbitrary natural language is not promised in offline mode.

**Optional live Gemini + ElevenLabs:** enable Live Gemini + voice inside a crew
conversation. The updated backend adds `POST /escape/talk`; it interprets the
request and returns a short response plus an allowlisted action proposal.
Godot checks the action against the current situation and mission version.
Route choices, power disconnection and launch remain explicit physical actions
with confirmation for irreversible consequences. Failed or stale live requests
cannot grant progress. A failed provider/endpoint falls back to the labeled local
interpreter; stale-state responses are discarded.

For local live testing, use Python 3.10+ with OpenSSL/scrypt support:

```sh
export GEMINI_API_KEY=...
export ELEVENLABS_API_KEY=...
python3 server/companion_server.py
```

Launch Godot with `B2E_BACKEND=http://127.0.0.1:8787` in its environment. With no
override, the existing hosted API address is used. This work does **not** deploy
the backend or modify the hosted game. Updating the server requires both
`server/companion_server.py` and `server/escape_dialogue.py` alongside the existing
server modules. Aaron and Dhan each have their own ElevenLabs voice
(`AARON_VOICE_ID`, `DHAN_VOICE_ID`; `JOHNNY_VOICE_ID` is reserved for the player).

**Speech input:** the radio's Speak button uses browser SpeechRecognition when
available in a web export. It is unavailable in the native Godot build; type or
use OS dictation there. Browser microphone access is requested only after a
click. Transcripts are editable and require Enter/Send before any action occurs.
Support varies by browser and recognition can use the browser vendor's online
speech service. Denial or unsupported browsers retain typed input. The browser
microphone path is implemented but has not been verified in an exported build
because matching web export templates are not installed on this machine.

## Validation

```sh
godot --headless --path . res://tests/escape_runner.tscn
python3 -m unittest server/test_escape_dialogue.py server/test_companion_server.py
```

The Godot runner plays all three endings, exercises actual NPC pathfinding and
local conversation actions, checks irreversible decisions and invalid ordering,
reloads between routes, and verifies the original intro's handoff.
Run it with a graphical renderer and `-- --visual` to save QA screenshots under
`/tmp/back2earth-*.png`.

The old `tests/test_runner.gd` currently fails to parse because it still calls
`get_drift(true)` after the original gravity script changed to a zero-argument
method. This predates this prototype; the old mission and its tests are retained.

## Files and scope

- `scripts/prototype/escape_state.gd`: authoritative branch rules and outcomes.
- `escape_mission.gd`: map, props, crew tasks and scene orchestration.
- `escape_actor.gd`: reused astronaut art and grid-based crew movement.
- `escape_ui.gd`, `escape_radio.gd`, `escape_map.gd`: interface and conversations.
- `escape_prop.gd`: reused interactable protocol and visual feedback.
- `scenes/main.tscn`: original mission, still runnable directly.

Current design shortcuts: the battery cart is represented by a carried crate
sprite, the lab hardware uses existing console art, and endings are illustrated
cards rather than new cinematics. Movement and explicit object interactions are
fully playable; this prototype is intended to evaluate pacing and cooperation.
