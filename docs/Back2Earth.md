# Back2Earth — Godot build pipeline

Prepared for Johnny's four-person UBhacks team · November 7, 2026

**Target:** a top-down 2D escape game built in Godot within 24 hours, combining gravity changes with a state-aware AI ship companion. The game is called Back2Earth. This is an implementation plan; the timings and tuning values are starting estimates, not measured results.

## 1. Lock the playable promise

**Pitch:** “Your spaceship is being pulled toward a black hole. Use its failing gravity to navigate wreckage, work with a damaged AI companion, and launch the last escape pod home.”

For the story, the opening collision damages the ship near the black hole, outside its event horizon. The pod has a fictional emergency jump system that can return you to Earth once you recover its navigation core. Keep this as a short opening and ending, so the entire playable mission happens inside the ship.

**Player experience:** approximately 5–7 minutes for a first attempt; target a six-minute countdown after a brief safe tutorial. The opening teaches movement, the middle turns gravity into a puzzle, and the ending pays off the relationship with the companion.

**Finish line:** a player can start, understand the controls, complete three objectives, launch, see Earth, fail, and restart. The whole route remains playable without an internet connection.

## 2. Define the mission before making assets

| Area | Player action | Purpose | Completion condition |
|---|---|---|---|
| Cockpit | Move, interact with a terminal, brace through a safe surge | Teach controls; introduce the companion | Start evacuation and reveal the power objective |
| Engineering | Reach and activate a marked power console | Teach movement against a changing pull | Restore power; unlock Cargo |
| Cargo | Let a surge slide a guided crate onto a switch; collect the navigation core | Demonstrate the signature gravity puzzle | Door latches open and core enters inventory |
| Pod bay | Release the clamp and board the pod | Deliver the final escape under pressure | Power restored + core collected + clamp released + player boards |

Build one connected ship map, with room scenes placed inside it. Avoid scene transitions between rooms; a single mission state is easier to reason about. Make the route short, readable, and mostly linear.

**Controls:** WASD/arrows move; E interacts; hold Space to engage magnetic boots; H requests companion help; Esc pauses. Show the interaction prompt only near a valid target. Choose the nearest target when two overlap.

**Failure:** one countdown represents remaining safe evacuation time. Debris contact removes 10 seconds and grants a one-second hit cooldown. Reaching zero ends the run. Do not add separate oxygen, health, stamina, hunger, and ship-integrity systems.

**Success:** lock gameplay as soon as boarding is accepted, then play a short pod departure and Earth arrival sequence. Use a starfield, pod sprite, fade, Earth image, and final caption. A second piloting game is outside the core scope.

## 3. Build the two distinguishing features

### Gravity that changes the route

Treat the effect as the ship's unstable gravity system and tumbling frame. Use predictable, authored pulls rather than an orbital simulation.

Start with a repeating 16-second pattern: **3 seconds warning, 6 seconds pull, 7 seconds calm**. Alternate two clearly indicated directions in the ship's coordinate system. Keep the camera upright and label the next direction with an arrow, countdown, and sound cue.

Suggested initial values:

| Setting | Initial value | Reason |
|---|---:|---|
| Normal movement | 150 px/s | Readable movement in compact rooms |
| Active pull drift | 90 px/s | Noticeable pressure while still allowing movement against it |
| Movement with boots | 60 px/s | Bracing trades speed for control |
| Pull with boots | 18 px/s | Strong protection without another resource meter |
| Moving crate | One constrained lane, two stops | Makes the puzzle repeatable and easy to reset |

These values are arcade tuning, not physical measurements. For the first version, calculate velocity from movement input plus the current drift. Apply this during the physics update. Godot's CharacterBody2D requires scripted movement; it will not automatically receive the gravity applied to a physics body. Use floating motion mode for top-down movement [1][2].

**Signature puzzle:** a crate rests in a marked lane. During the correct surge it slides onto a pressure switch, permanently opening the navigation-core compartment. The player uses boots to avoid a nearby debris lane while waiting for that opening. The crate cannot trap the player or block the only exit. Add an accessible reset interaction if it fails to reach its stop.

Start the crate as scripted movement between stops. Free-moving physics crates are a stretch feature; do not let the mission depend on a fragile pile of colliding objects.

**First gate:** before making the full ship, a teammate must be able to understand the warning, brace, and solve the crate room with placeholder art.

### An AI companion that notices the player

Working name: **ECHO**. It is damaged, dryly funny, and increasingly protective. Its personality can glitch; required instructions stay clear.

Use a language model for short reactions based on actual events: repeated debris hits, frequent use of boots, a solved puzzle, low remaining time, or collecting the core. H asks for one contextual response. Free-form chat and voice input are stretch features.

Example authored reference lines, not claims about generated output:

- After repeated collisions: “Your suit has filed another complaint. Try the magnetic boots.”
- After Cargo: “Navigation recovered. I am choosing to interpret that as optimism.”
- At launch: “Course set for Earth. Please remember the stars from somewhere safer.”

**Keep two text channels:** an authoritative objective/hint supplied by game rules, and a short companion reaction supplied by the model. The companion cannot unlock doors, change timers, invent objectives, or grant items. Immediate gravity warnings always come from the game.

Runtime sequence:

1. A meaningful event or H press produces a compact state snapshot.
2. Godot sends it to a small server endpoint, `/companion`.
3. The server adds the ECHO prompt and calls the team's available text model.
4. The server checks the response shape and length; Godot checks its run/state identifiers.
5. The UI shows the valid reaction, or uses the authored fallback for that event.

**State contract:** `run_id`, `state_version`, `event_id`, `room_id`, `objective_id`, `time_band`, `inventory`, `recent_event`, `boots_use_count`, and `canonical_hint`. Send a coarse time band rather than exact seconds that may already be stale when the reply arrives.

**Response contract:** echoed identifiers and `line`, a string limited to 180 characters. Strip markup and reject missing fields, unexpected types, and unsupported response formats. This validation does not prove factual correctness; the separate canonical hint remains the gameplay authority.

Use one in-flight request, a 15-second request cooldown, and a maximum of 12 requests per run. Coalesce repeated events. After three seconds, cancel/ignore the request and use the local fallback. On restart, objective change, pause, or game over, invalidate pending dialogue. Discard late responses whose run or state no longer matches. Do not block movement while waiting.

Godot's HTTPRequest node provides a request-completion signal; a single node should finish its current request before starting another [3]. Keep the provider API key in the backend environment. For a native judge demo the backend can run on the same laptop; a browser build needs a reachable HTTPS endpoint and suitable CORS configuration. If that hosting is not ready, use offline dialogue in the web build.

Expose an honest Online/Offline companion status in settings or the demo explanation. Scripted fallback lines should not be presented as live model output. Set a small provider spending limit before testing.

## 4. Freeze the technical boundaries in hour one

Use **one agreed Godot 4 stable version**, GDScript, the Compatibility renderer, and Git. Record the exact installed version in the README and use matching export templates. Choose the demo laptop's native export as the primary deliverable; try a web export early as a secondary target.

Godot's current web documentation specifies Compatibility rendering; GDScript avoids the documented Godot 4 C# web-export restriction. Single-threaded web export is the simpler default [4].

| Component | Responsibility | Owned files/scenes |
|---|---|---|
| GameState | Run ID, phase, countdown, inventory, objective order, success/failure | `scripts/core/game_state.gd` |
| GravityDirector | Warning/surge/calm cycle and pull vector | `scripts/core/gravity_director.gd` |
| Player | Movement, boots, interaction detection | `scenes/player/player.tscn`, `scripts/player/` |
| Ship and rooms | Geometry, puzzle placement, room IDs, objective triggers | `scenes/ship/`, `scripts/interactables/` |
| CompanionClient | Requests, cooldown, validation, stale-response handling, fallback | `scripts/ai/`, `data/dialogue_fallbacks.json`, `server/` |
| HUD and end screens | Objective, time, gravity arrow, prompts, captions, restart | `scenes/ui/`, `scripts/ui/` |
| Presentation | Sprites, audio, visual effects, asset credits | `assets/`, `CREDITS.md` |

Use GameState as an autoload and reset it explicitly between runs. Keep GravityDirector and CompanionClient under the mission root unless there is a clear reason to persist them. The integration owner places all components into `scenes/main.tscn`.

Agree on these contracts before splitting work:

- `interact(player)` on interactables; GameState validates whether the action is allowed.
- `complete_objective(id)` is idempotent and rejects out-of-order completions.
- `objective_changed(id)`, `inventory_changed()`, `time_changed(seconds)`, and `run_ended(won)` communicate state to the HUD and companion.
- `gravity_warning(direction)` and `gravity_changed(direction, drift_speed)` drive effects and movement.
- A helper returns the current canonical objective and hint without contacting the model.
- Phase is one of briefing, playing, won, or lost. Pause suspends the countdown and gravity cycle.

Validate launch and timer expiry centrally. Once phase leaves playing, ignore further damage and launch events. On retry, reset the timer, objectives, crate, doors, hit cooldown, gravity phase, dialogue state, and run ID.

## 5. Give each teammate a clear lane

| Teammate | Main ownership | First useful delivery | Integration rule |
|---|---|---|---|
| A — gameplay/integration | Player, gravity, GameState, main scene, Git integration | A room where movement, boots, warning, and timer work | Owns `project.godot` and shared contracts |
| B — level/puzzles | Ship layout, interactables, crate puzzle, pod conditions | One solvable room with a clear exit | Builds separate room scenes; does not edit A's core scripts |
| C — companion/backend | Prompt, endpoint, request handling, authored fallback | Mock JSON response and offline lines | Tests in a small scene; never mutates game rules |
| D — presentation/release | HUD, sprites, sound, title/end screens, exports | Readable HUD and initial exported build | Owns UI/assets/export presets; coordinates main-scene edits with A |

Use short branches and integrate at least every two hours. Commit scene dependencies and generated resource UID files; ignore the generated `.godot/` cache, secrets, and exported build directories. Each teammate supplies a tiny test scene or a reproducible manual check for their feature.

AI coding workflow: give the assistant the current contracts and owned files, ask for one small behavior, run it in Godot, verify the acceptance condition, then commit. Have only one teammate change shared files at a time. An assistant should read the existing code before proposing a patch.

## 6. Follow the 24-hour delivery schedule

Hours are relative to the event's actual start. Reserve short breaks; this is a team schedule, not a requirement that each person code continuously.

| Hours | Work in parallel | Required checkpoint |
|---|---|---|
| 0–1 | Agree route, install/pin engine, initialize repo, define contracts, assign files, check event rules | Everyone opens the project; placeholder native build launches |
| 1–4 | A: movement/boots/gravity. B: one room and console. C: fallback/mock endpoint. D: HUD/export/art style | Walk, interact, see a warning, brace, and restart |
| 4–7 | A+B: crate puzzle and first objective. C: first live request in isolation. D: readable effects and sound | One polished-enough room proves the gravity hook |
| 7–10 | A+B: connect four areas and all objectives. C: companion client against mock/fallback. D: ending and failure UI | Entire game works from start to Earth with placeholder assets and offline dialogue |
| 10–14 | Integrate live model, validate failures, replace essential art, run actual exports | Complete exported run; backend outage also completes normally |
| 14–18 | Tune movement and difficulty; playtest with outsiders; polish clarity and feedback | First-time players understand the route; no reproducible softlock |
| 18–21 | Feature freeze; fix blockers; test clean checkout/export and repeated retries | Stable native release candidate plus optional working web build |
| 21–24 | Record backup video, rehearse pitch, finish README/credits/submission, retain final buffer | Submission uploaded before the deadline; demo laptop ready |

**Dependency order:** working movement → readable surge → one complete puzzle → full win/lose route → companion integration → presentation polish → release verification. Art, dialogue, and backend work can proceed independently against placeholders.

**Fallback decisions:**

- If the gravity puzzle is unreliable at hour 7, replace free physics with a deterministic sliding obstacle and switch.
- If there is no complete route at hour 10, stop adding rooms and finish the existing route.
- If live AI is unreliable at hour 14, ship authored dialogue and disclose the limitation; preserve the integration as an optional mode.
- If the web export is still failing at hour 18, commit to the tested native demo and video.
- After hour 18, only change defects that affect understanding, completion, export, or submission.

## 7. Keep the art workload bounded

Use a consistent 32-pixel grid and a dark navy/steel ship, cyan interactions, amber warnings, and red hazards. Communicate danger with shape, arrows, captions, and sound as well as color.

Minimum asset list: one astronaut with idle/walk frames; floor and wall tiles; door; terminal; crate; pressure switch; navigation core; escape pod; black-hole backdrop; Earth ending image; simple ECHO portrait/waveform; six short sound cues and one ambient loop.

Use rectangles and labels until the complete route exists. Replace the visuals without changing the collision shapes. Keep the player, terminals, and exit brighter than the floor. Give the boots an obvious ring/footprint cue, and provide mute and reduced-shake options.

If using generated sprites, request a consistent top-down camera, transparent backgrounds, fixed dimensions, and no baked-in text. Record external asset licenses and any required attribution. Check UBhacks' current rules for pre-existing assets, AI use, and submission requirements in hour one; this plan does not assume those rules.

## 8. Test the actual failure points

| Check | Pass condition |
|---|---|
| Basic movement | Diagonal movement is controlled; walls stop the player; boots work during a surge |
| Puzzle | Crate reliably reaches its switch; door stays open; reset cannot trap the player |
| Objective order | Pod cannot launch without all requirements; repeated interaction does not duplicate progress |
| Fairness | Warnings precede pulls; objectives remain reachable in every gravity phase |
| Timer | Damage penalty has a cooldown; pause stops time; success/failure cannot both trigger |
| Retry | Three consecutive restarts restore the same initial state without stale dialogue |
| AI outage | Missing key, timeout, HTTP error, or invalid JSON produces readable fallback without stopping gameplay |
| Late AI response | A reply from a prior room/objective/run does not appear in the current context |
| Presentation | Controls, objective, countdown, gravity direction, and interaction prompt remain readable |
| Release | Actual export opens on the demo machine with sound and assets; it also works offline |

Have three people outside the team play without coaching. Ask where they got lost, whether boots made sense, and whether the crate puzzle felt intentional. Watch their behavior; fix unclear cues before adding mechanics.

## 9. Use these scoped AI coding assignments

Paste this shared context before each assignment:

> We are building Back2Earth, a Godot 4 top-down 2D escape game in GDScript. Four people have 24 hours. The core is a six-minute ship evacuation with three objectives, predictable gravity surges, magnetic boots, and an optional state-aware AI companion. Read the current project and contracts before editing. Implement only the assigned component and its minimal dependencies. State exact node paths, input actions, files changed, and a short manual verification procedure. Use placeholder art. Do not invent a new architecture, modify other teammates' files without flagging the dependency, or add extra features. Use APIs for the exact Godot version in our README. If you cannot run the project, say so.

**A — first assignment:** Build the Player scene and GravityDirector sandbox. Use CharacterBody2D floating mode; input movement plus authored drift; Space reduces both speed and drift. Implement the warning/pull/calm cycle and visible direction signal. Acceptance: a tester can move against the pull, brace, collide with walls, and repeat the cycle without jitter.

**B — first assignment:** Build a standalone Cargo room using the agreed interaction and objective contracts. Use a constrained moving crate, two stops, a pressure switch, a door that latches open, a core pickup, and an accessible reset. Acceptance: solve from a clean reset repeatedly; no configuration can block the only exit.

**C — first assignment:** Build authored fallbacks and a mock companion response first. Then implement one `/companion` backend adapter using the team's selected provider, plus a Godot client with single-flight requests, cooldown, timeout, response validation, and run/state invalidation. Acceptance: mock success, timeout, malformed response, and stale reply all behave correctly; the game never waits for a reply to continue.

**D — first assignment:** Build the HUD and end screens against mock GameState signals. Include timer, canonical objective, gravity warning arrow, interaction prompt, companion caption, pause, restart, mute, and reduced shake. Produce the first native export. Acceptance: text is legible at the demo resolution and the exported build contains its assets.

Only start the next assignment after the current one runs and the teammate can explain it.

## 10. Prepare a 90-second demonstration

| Time | Demonstration |
|---|---|
| 0–15 seconds | State the premise and start inside the damaged ship |
| 15–35 seconds | Show the warning, activate boots, and visibly resist the pull |
| 35–55 seconds | Let the surge solve the cargo puzzle; show a companion reaction |
| 55–75 seconds | Use an explicitly labeled demo checkpoint to show pod launch and Earth |
| 75–90 seconds | Explain event-driven AI, offline resilience, and what the team built |

A checkpoint is fine if disclosed; do not present a shortened demo as a full playthrough. Show whether the companion is currently live or offline. Keep a prerecorded backup that accurately represents the build.

**Submission package:** tested executable and run instructions; repository; engine version; controls; backend setup without keys; AI-use explanation; credits; known limitations; screenshots; short video; one-sentence pitch. Deliver only features you can demonstrate.

**Keep for a later version:** multiplayer, combat, procedural ships, free-form voice conversations, full orbital simulation, additional rescue NPCs, inventory crafting, and a separately playable trip to Earth.

## Official implementation references

1. [Godot — 2D movement overview](https://docs.godotengine.org/en/stable/tutorials/2d/2d_movement.html): CharacterBody2D, input vectors, and the basic movement loop.
2. [Godot — CharacterBody2D](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html): floating mode, scripted motion, velocity, and collision movement.
3. [Godot — Making HTTP requests](https://docs.godotengine.org/en/stable/tutorials/networking/http_request_class.html): HTTPRequest, completion signals, JSON, and per-node request handling.
4. [Godot — Exporting for the Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html): Compatibility renderer, GDScript/C# considerations, and single-threaded export.

References checked November 7, 2026. The stable documentation can advance; use the documentation matching the version your team pins.
