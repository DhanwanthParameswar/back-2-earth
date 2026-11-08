# Back2Earth: Game Design (v1, locked for build)

This is the game we're building. It replaces the story and steps in `Escape Prototype.md`,
`Back2Earth.md` and `Back2Earth Story Script.md`. The opening film stays as it is.

All numbers here are starting values. Tune them by playtesting.

---

## 1. One-line pitch

You're the pilot of a crippled ship. One crewmate is gone and another is hurt. You can talk
to your crew in your own voice, and they talk back, help, disagree and remember. Together
you decide how to get home, and what you're willing to lose to get there.

**Demo target:** first spoken exchange and visible crew help within 1 minute; a complete
run in about 6–8 minutes (10 at most).

---

## 2. Cast

| | Role | Knows / can do | Can't do | Wants |
|---|---|---|---|---|
| **Johnny** (player) | Pilot, in command | Fly the shuttle; approve launch; do all hands-on work | Engineering know-how, lab science | Get everyone home |
| **Dhan** | Engineer, **injured** (leg pinned by the locker) | Knows every system; reads fault codes; talks you through repairs over radio | Walk on his own; see what you see | Not slow you down; jokes to hide pain |
| **Aaron** | Researcher | Lab, the battery and freezer, the sample case, notices things, steadies Dhan | Engineering, flying | Get Dhan home. Save the samples he and Kien collected |
| **M.A.R.V.I.S.** | Ship maintenance system | Ship facts: power, clamps, crew vitals, room status, medical database | Advise, decide, comfort, fly, move anything | Nothing. It's a menu with a voice |
| **Kien** | Dead (lost in the breach in the film) | — | — | His samples and memories carry weight |

M.A.R.V.I.S. = **M**aintenance, **A**tmosphere and **R**outine **V**essel **I**nformation **S**ystem.
It replaces ECHO everywhere.

Code note: the actor ids are still `mara` (Aaron) and `ivo` (Dhan). Keep the ids; update
labels, personas and roles.

---

## 3. The run, beat by beat

### Beat 0: Aftershock (gameplay start, ~10 s)

The film ends unchanged with the crew by the locker. Control starts, and **an aftershock
hits**: the screen shakes and the locker tips over onto Dhan's leg. This is a short scripted
moment in gameplay, not a change to the film.

> DHAN: "Agh! Okay. Okay. Leg. Locker. Leg's under the locker."
> AARON: "Don't move. Johnny, I'll lift. You pull him out."

### Beat 1: Free Dhan (target 0:10–0:45)

- The player asks Aaron to lift (any wording). Aaron walks to the locker and braces.
- The player interacts with Dhan to pull him free. If Aaron isn't lifting, the locker won't
  budge ("It's too heavy alone").
- Dhan's **condition clock starts** once he's freed (section 5).
- Aaron lets the locker drop to one side, which also clears the hallway to the junction.
- Dhan sits against the corridor wall where he was freed, and that's where he stays for the
  rest of the game, except when he's carried to the shuttle. (The shuttle bay door is right
  next to this spot, so the carry at the end is short.)

> DHAN: "Thanks. Don't think I'm walking anywhere. Somebody ask the ship what's still working."

The last line points at M.A.R.V.I.S. without saying "go to the terminal."

### Beat 2: Learn the situation (target 0:45–1:45)

At the junction terminal (or by speaking to M.A.R.V.I.S. anywhere), the player can ask
about status, power, the shuttle, crew and the medical database. The first time anyone uses
the terminal, M.A.R.V.I.S. gives its summary on its own:

> M.A.R.V.I.S.: "Main power: offline. Shuttle: intact. Docking clamps: engaged, no power.
> Crew: three active. Crew member D. Okafor: injury detected."

Then the crew react without being asked, which surfaces both routes:

> DHAN: "Clamps need juice. The engineering cabinet's probably just a blown fuse. I can't get
> there, but I can talk you through it."
> AARON (hesitant): "…The lab's emergency battery could power the clamps too. But it's
> what's keeping the freezer cold. Kien's and my samples."
> DHAN: "Your call, Captain."

The player decides by doing, not from a menu: they walk into Engineering or the Lab and
start working. **Only one step is irreversible: shutting down the freezer.** That commits
the battery route.

Engineering work can be abandoned at any point. That makes the strongest decision in the game
happen mid-run: you're halfway through the repair, Dhan is fading, and Aaron says (once, at
Dhan stage 3, if you're on engineering and not done):

> AARON: "Johnny… we could still use the battery."

Give up on the repair and lose the samples, or keep going and trust you'll finish in time?

### Beat 3A: Engineering route (Dhan guides you)

| Step | What the player does | What makes them talk |
|---|---|---|
| 1 | Find the distribution cabinet. It's sparking. | Touching it now is a **fail** (F1). Dhan warns if you describe it: "Sparking? Don't touch it. Big handle by the door: that's the isolator." |
| 2 | Pull the isolator. | M.A.R.V.I.S. announces: "Engineering circuit: isolated." |
| 3 | Read the cabinet's **fault code** (random each run: `E-3`, `E-6` or `E-9`). | The code means nothing to the player. Dhan knows: each code names a different spare fuse. Codes are single digits that sound different, so speech recognition gets them right. |
| 4 | Fetch the right fuse from Storage (three boxes: `A`, `B`, `C`). | Wrong fuse = it doesn't fit, so walk back (time cost). Dhan: "E-6? You want box B." |
| 5 | Install the fuse, test it. It trips: an auxiliary branch is shorting. The display shows `SHORT: AUX-1`, `AUX-2` or `AUX-3` (random). | Three unlabelled switches. Dhan knows which one carries which branch, but only if you tell him which one is reported. |
| 6 | Cut the right AUX switch, restart. Power returns to the bay. | Wrong switch = trips again (time cost and a Dhan penalty). |

The random codes mean the conversation can't be skipped by memorizing a walkthrough, and a
judge's run is different from your rehearsal.

**Rule for every puzzle: talking is the fast way, never the only way.** Each one can be
solved by trial and error, just slower. Wrong fuses cost a walk back to Storage. Wrong
switches cost time and a little of Dhan's condition. If Dhan has died, wrong switches cost
time only. Nobody can get stuck.

Dhan's guidance gets worse as his condition drops (section 5). Late in the clock he gives
shorter, vaguer answers ("…the second one. I think."), and at the lowest stage he can
mishear you. That's what makes the slow route risky.

**Aaron on this route: send him or keep him.** You can ask Aaron to:
- **Stay with Dhan.** He keeps him calm and still: Dhan's drain ×0.85 while Aaron is beside him.
- **Fetch the fuse.** He walks to Storage while you pull the isolator, saving you the trip.
  He doesn't know which box, so you have to tell him what Dhan said. That **relays**
  information from one crewmate to another.
- **Come with you.** He lights the way (flashlight) and reads displays aloud.

There's no right answer. It's a small delegation decision that makes the player think about
who should be where.

**Keeps:** all samples. **Costs:** time, and it relies on Dhan.

### Beat 3B: Battery route (Aaron's cost)

| Step | What the player does | Notes |
|---|---|---|
| 1 | In the Lab, look at the freezer and battery. | Pulling the battery while the freezer runs is a **fail** (F5). The label says so. |
| 2 | *(optional)* Save the priority samples. See 3C. | Must happen before step 3. |
| 3 | Shut down the freezer. Aaron hesitates first. | The first time you open the freezer close-up, Aaron asks: "Do we really have to?" Any reply lets you continue. What you said is saved as a memory, and the ending can quote it. Irreversible. Afterwards: "…Okay." |
| 4 | Release the battery latch. | |
| 5 | Ask Aaron to help lift it onto the cart. Too heavy alone. | Coop moment (count of three). |
| 6 | Push the cart to the bay's emergency socket. | |
| 7 | Set the socket's **power selector** and connect. Three unlabelled positions (`I`, `II`, `III`, random each run). | Only Dhan knows which setting fits the lab battery: radio him. Wrong setting: a pop, the breaker trips, try another. Dhan stays useful on this route too. |

**Keeps:** time (fastest route), Dhan is safest. **Costs:** Kien's and Aaron's samples.

### Beat 3C: Sample case (hidden middle path)

Never announced. Found when the player asks Aaron about the samples or about other options:

> AARON: "There's an insulated case on the shuttle. It'd only fit the priority rack, but…"

- Ask Aaron to fetch it. He walks to the shuttle and back (~25 s), and you're alone meanwhile.
- Pack the priority rack (interact at the freezer with the case there).
- Then shut down the freezer as normal.

### Beat 3D: Medbay (hidden, helps Dhan)

Never put on the objective card. Ways the player can discover it:
- Asking M.A.R.V.I.S. about medical or crew status: "Crew member D. Okafor: suspected
  fracture, left leg. Recommended: immobilize. Analgesic: medbay cabinet."
- Aaron at stage 2: "He needs something for the pain. And that leg shouldn't move."
- Walking into the Medbay and inspecting the cabinet.

The player takes the **splint kit** from the cabinet, brings it to Dhan and uses it on him.
It doesn't need to be on a particular route. Effect is in section 5: it **slows** the clock
a lot and gives a small boost, but doesn't stop it.

> DHAN (after): "Oh, that's… much better. Thank you. Still not dancing."

### Beat 4: Board and launch (target last ~60–90 s)

1. Once the bay has power, M.A.R.V.I.S.: "Docking control: available. Manual release required
   at bay console."
2. **Get Dhan aboard:** ask Aaron to help. Both of you support Dhan to the shuttle (a short
   coop walk, and Dhan's lines suit his condition).
3. **Two-person launch:** the clamps release from the bay console (outside the shuttle); the
   pilot seat is inside. The player takes the pilot seat and tells Aaron to release the
   clamps. Aaron releases, then boards. Only then is it safe to launch.
   - Launching before the clamps are released = **fail** F3.
   - Launching before Aaron is aboard = **fail** F4.
4. **Fly out:** a short piloting sequence. The player steers the shuttle out through the bay
   doors (simple thrust and steering). This is the player's moment as pilot.
5. Ending (section 7).

---

## 3½. Mechanics and minigames

### Controls (mostly existing)

| Key | Does |
|---|---|
| WASD | Move |
| E (tap) | Interact / pick up / put down (carry one item at a time) |
| E (hold) | Heavy or careful actions: a ring fills around the prompt (1–2 s). Let go early and nothing happens |
| Space | Push-to-talk to whoever you're facing or on radio (exists) |
| 1 / 2 / 3 | Radio Aaron / Dhan / M.A.R.V.I.S. (3 is new) |
| F | Flashlight (exists; the ship is dark until the bay has power) |
| Tab | Deck map + learned-facts log |

### One reusable piece: the close-up panel

Most puzzles use one shared UI: interacting with a machine opens a **pixel-art close-up**
of it over the game (switches, displays, slots). Click or use WASD+E on the parts. Esc closes
it. The world keeps running behind it (Dhan's clock too), and you can still talk while it's
open. Build it once; each machine is a different picture plus a few clickable parts.

### Every mechanic in the game

| # | Where | Mechanic | How it plays | Talking it needs | Fail / mistake |
|---|---|---|---|---|---|
| M1 | Corridor | **Lift and pull** (coop) | Ask Aaron to lift; he strains and the locker rises. Hold E on Dhan for 2 s to drag him out. Aaron can only hold it ~6 s, then drops it and you ask again | Asking Aaron to lift | None; just retry |
| M2 | Junction / anywhere | **M.A.R.V.I.S. query** | Speak or type to the terminal or on radio 3. Reply appears on the terminal screen in green text and is spoken | All of it | "Query not recognized" |
| M3 | Engineering | **Isolator lever** | Hold E on the big handle by the door (heavy, 1.5 s). Lights in the room drop; sparks stop | Dhan points you at it if you describe the sparks | Touching the cabinet first = **F1** |
| M4 | Engineering | **Read the fault code** (close-up) | Cabinet display shows `E-3` / `E-6` / `E-9`. Nothing on it says what it means | Read it to Dhan; he names the fuse | — |
| M5 | Storage | **Pick the fuse** (close-up) | Shelf with three boxes, `A`, `B`, `C`. Take one; you carry it (visible in hand) | From M4 | Wrong one: it won't seat in the slot; walk back |
| M5b | Junction → Storage | **Send Aaron for the fuse** (delegation + relay) | Ask Aaron to get the fuse; he asks "Which box?" Tell him what Dhan said. He walks there and back (~30 s) | Relaying Dhan's answer | Wrong box: he brings the wrong one |
| M6 | Engineering | **Seat and test** (close-up) | Drag the fuse into the empty slot, press TEST. It trips; display now says `SHORT: AUX-n` | — | — |
| M7 | Engineering | **AUX switches** (close-up) | Three unlabelled toggles under a guard cover. Lift the cover, flip one, press RESTART | Tell Dhan which AUX is shorting; he says which toggle is which | Wrong toggle: trips again, Dhan −3 |
| M8 | Lab | **Freezer shutdown** (close-up) | Two-step: flip a guard cover, then hold the switch for 1 s. The freezer hum stops and its lights die. This replaces the yes/no confirmation popup | Aaron asks "Do we really have to?" first; your answer is remembered | Pulling the battery first = **F5** |
| M9 | Lab | **Battery latch** | Hold E for 1 s on the battery latch | — | — |
| M10 | Lab | **Count-of-three lift** (coop) | Ask Aaron to lift. He takes his side and counts aloud, "One… two… *three*." Press E on "three" (±0.4 s). Early or late: you both drop it with a thud, and Aaron grumbles and counts again. The count is a **pre-recorded clip**, and the timing window is measured from that audio (live voice would lag unpredictably) | Asking Aaron; listening to the count | None; just retry |
| M11 | Lab → bay | **Push the cart** | Walk with the cart at 60% speed; the cart can't take the tight Medbay or Galley doors, so you go the long way | — | — |
| M12 | Bay | **Power selector + connect** (close-up) | Turn the unlabelled selector to `I` / `II` / `III`, plug the cable in, twist it locked | Radio Dhan: he knows which setting fits | Wrong setting: pop, breaker trips, try again |
| M13 | Shuttle / lab | **Fetch the sample case** (delegation) | Ask Aaron to fetch it; he walks there and back on his own (~25 s) while you keep working | Asking Aaron | — |
| M14 | Lab | **Pack the priority rack** (close-up) | A rack of ~8 sample tubes. One rack is marked in handwriting, "K + A — PRIORITY"; drag it into the case | Aaron can tell you which one if asked | Packing the wrong rack is allowed, and the ending says so |
| M15 | Medbay → Dhan | **Splint** | Take the splint kit from the medbay cabinet. At Dhan: hold E for 2 s (he groans, then relaxes) | Finding out it exists (Beat 3D) | — |
| M16 | Junction → shuttle | **Carry Dhan** (coop) | Ask Aaron to help. You and Aaron walk together at 50% speed with Dhan between you | Asking Aaron | — |
| M17 | Shuttle / bay | **Two-person release** | You sit in the pilot seat (E). Tell Aaron over radio to release; he pulls the bay lever, M.A.R.V.I.S. confirms "Clamps released," Aaron boards. Then press E on LAUNCH | Telling Aaron when | Launch early = **F3**; launch before Aaron boards = **F4** |
| M18 | Space | **Fly out** | Short top-down scene: W thrust, A/D rotate, steer through the opening bay doors (~20 s). Bumping walls shakes the screen; no penalty. Until this is built, use a cutscene | Crew react ("Easy…") | — |
| M19 | Suit room | **Airlock** (fail-only) | The outer airlock button works. Pressing it without a suit = **F2** | — | F2 |

### Which mechanics each route uses

| Route | Mechanics | Count of coop moments |
|---|---|---|
| Everyone | M1, M2, M16, M17, M18 | 3 |
| Engineering | M3–M7 | Dhan talks you through 3 of 5 |
| Battery | M8–M12 | 3 (M8 Aaron's question, M10 lift, M12 Dhan's selector) |
| Battery + case | M8–M14 | 4 (adds M13 delegation) |
| Medbay (any route) | M15 | — |

Build priority: the close-up panel and the hold-E ring first, since most of the list uses
them. M18 (fly out) can be a cutscene for the first version.

---

## 4. Route matrix (why a player would choose each)

The player is never shown this table. They should be weighing it in their head:
*"Dhan's getting worse. Fast and certain, and lose Kien's work? Or the slow repair, trusting
Dhan while he can still think straight?"*

| | Engineering | Battery | Battery + case |
|---|---|---|---|
| Time from freeing Dhan to launch (normal play) | ~4–5 min | ~2.5 min | ~3.5 min |
| Risk to Dhan | High without medbay | Low | Low–medium |
| Samples | All saved | All lost | Priority rack saved |
| Who it features | Dhan (guided repair, most talking) | Aaron (emotional cost, coop lift) + Dhan (socket) | Aaron (discovery, delegation) + Dhan (socket) |
| Moments you must talk | Dhan ×3 | Aaron ×2, Dhan ×1 | Aaron ×3, Dhan ×1 |
| Can you switch away? | Yes, any time | No, once the freezer is off | No, once the freezer is off |
| Ways to go wrong | Wrong fuse, wrong switch, touching live cabinet | Pulling battery with freezer on | Running out of time while waiting |
| Pairs well with Medbay? | Yes, nearly required for a calm run | Rarely needed | Sometimes |

---

## 5. Dhan's condition (the one soft clock)

A hidden number, **V**, starts at 100 when Dhan is freed. It's deterministic, not a dice
roll, so the outcome always follows from what the player did. Slower play and mistakes
make death more likely; the medbay makes it less likely but never impossible.

| Rule | Value |
|---|---|
| Drain, untreated | 0.25 per second |
| Drain, after splint kit | 0.12 per second |
| Aaron staying beside Dhan | drain ×0.85 (stacks with the splint) |
| Splint kit, one-off boost | +10 (cap 100) |
| Each fail retry | −5 (the world rewinds; Dhan's condition doesn't) |
| Paused during | AI reply waits, fail cards, pause menu, scripted scenes |
| Death | V reaches 0 before the shuttle launches |

**Stages** change how Dhan sounds and how much Aaron worries:

| V | Stage | Dhan | Aaron (unprompted, once per stage) |
|---|---|---|---|
| 100–70 | 1 Joking | Full sentences, jokes | — |
| 69–45 | 2 Strained | Shorter, winces | "He needs something for the pain." |
| 44–20 | 3 Fading | Short, vague answers | "Johnny. He's going pale. We need to move." |
| 19–1 | 4 Critical | A few words, may mishear | "Stay with us, Dhan. Stay awake." |
| 0 | Dies | — | Scripted scene; the run continues without him |

If Dhan dies, the run doesn't end. Aaron and the player finish the escape alone. It's quieter,
and the launch needs Aaron at the release as before.

**Expected outcomes with these numbers:**

| Run | Time from freeing to launch | V at launch | Result |
|---|---|---|---|
| Battery only | ~150 s | ~62 | Fine |
| Battery + case | ~200 s | ~50 | Fine |
| Engineering, quick | ~210 s | ~47 | Fine (just) |
| Engineering, normal | ~260 s | ~35 | Barely makes it |
| Engineering, slow or many mistakes | 400 s+ | 0 | Dies |
| Engineering + medbay at ~60 s, normal (310 s total) | 310 s | ~65 | Fine |
| Engineering + medbay, very slow | ~850 s | 0 | Dies |

---

## 6. Fails (Henry Stickmin style)

Each fail is a 2–3 second scene, a title card, then an instant retry from just before the
mistake. The crew can react on return ("Let's not do that again.").

| # | Trigger | Card |
|---|---|---|
| F1 | Touch the sparking cabinet before isolating it | "Dhan did mention the handle." |
| F2 | Open the outer airlock without a suit | "Fresh air. Briefly." |
| F3 | Launch with clamps engaged | "Parking brake." |
| F4 | Launch before Aaron is aboard | "Forgetting someone?" |
| F5 | Pull the battery with the freezer running | "Read the label." |

The ending screen shows "Fails found: N/5".

Not failures, ever: AI misunderstanding, slow replies, exploring, chatting, asking for
something impossible (that gets a dry in-character refusal).

---

## 7. Endings

Decided at launch from three facts: the route, the samples saved, and whether Dhan is alive
and what stage he's at. Each ending is one short scene (the shuttle leaving, then Earth) plus
2–3 authored lines. One line can call back to a remembered promise (section 9).

| Ending | Condition | Closing exchange (draft) |
|---|---|---|
| **Everyone home** | Engineering, Dhan stage 1–2 | AARON: "Kien's work made it." DHAN: "So did we. Mostly in one piece." |
| **What he left us** | Battery + case, Dhan alive | AARON: "Just the priority rack. It's the part he cared about most." |
| **We kept each other** | Battery only, Dhan alive | AARON (quietly): "He'd have understood." |
| **Barely** | Engineering, Dhan stage 3–4 at launch | DHAN (weak): "Worth it?" AARON: "Ask me when you can walk." |
| **Two came home** | Dhan died | AARON: "…" A beat on the empty seat. Any samples saved are mentioned in one line. |

---

## 8. Who speaks first (proactive lines)

The crew and M.A.R.V.I.S. start conversations; the player shouldn't have to do it all.

**Rules:**
- Proactive lines are **observations and feelings, never instructions**.
- Never interrupt while the player is speaking or a reply is playing.
- Cooldown: at most one proactive line every 12 s (scripted story beats skip the cooldown).
- Each line plays once per run.

| Trigger | Speaker | Line (draft) |
|---|---|---|
| Aftershock | Dhan, Aaron | Beat 0 |
| Dhan freed | Dhan | Beat 1 |
| First terminal use | M.A.R.V.I.S., then Dhan, Aaron | Beat 2 |
| Enter Engineering first time | Dhan (radio) | "Tell me what you're looking at." |
| Enter Lab first time | Aaron | "The freezer's still holding. For now." |
| Fuse/switch wrong | Dhan | "Not that one— okay, okay, try again." |
| Freezer shut down | Aaron | "…Okay." |
| Enter Galley | Aaron | "Kien was so excited about real food." |
| Enter Medbay | Aaron | "There should be splints in that cabinet." |
| Dhan stage changes | Aaron | Section 5 table |
| Bay powered | M.A.R.V.I.S. | Beat 4 |
| Stuck 45 s (no progress, not talking) | Nearest crewmate | An **observation** about the room they're in, e.g. "That display's been blinking a code." |
| Stuck 90 s | Nearest crewmate | More direct, e.g. "Dhan knows those codes. Ask him." |

---

## 9. Dialogue: what's written vs. what the AI makes up

**Hybrid.** Everything the story depends on is written and recorded ahead of time. The AI
only handles replies to what the player says, inside tight limits. This keeps the key beats
reliable and well acted, and keeps the live conversation flexible.

| Content | Source | Why |
|---|---|---|
| Story beats, proactive lines, Dhan stage lines, fail reactions, endings | **Written + pre-recorded** (ElevenLabs, same voices) | Must work every time, including offline; timing matters |
| M.A.R.V.I.S. replies | **Templates** with live numbers; AI may only pick which intent the player meant | It should sound like a phone menu, never invent facts |
| Replies to anything the player says to Aaron or Dhan | **AI-generated** (Gemini → ElevenLabs) | The unique feature. Varied, reactive, in character |
| Offline fallback replies | **Written** keyword lines (exists: `offline_response`) | Works with no server |

### What the AI gets each turn (per crewmate)

1. **Persona** (fixed): who they are, voice, relationships, what they know and don't know,
   their current wants. Includes: Kien is dead; Dhan is injured; the player is the pilot
   and in command.
2. **Current facts** from the game (the only truth): room, route, steps done, Dhan's stage,
   what each person has heard (below), the fault code and AUX number **only for Dhan**.
3. **Talking points for this beat**: what this character would naturally bring up now, so
   their replies steer without giving orders. Example for Aaron at Beat 2: "You can mention
   the lab battery and its cost to the freezer. You can mention the sample case only if asked
   about the samples or alternatives."
4. **Memory notes** from this save (exists): short facts about Johnny. New: tagged
   **promises** (e.g. "promised Aaron we'd save the samples"), which endings can call back.
5. **Allowed actions** right now (exists: allowlist, revalidated in Godot).

### Guardrails

- **Characters only know what they plausibly heard.** Each fact records who knows it. Dhan
  is told the fault code because the player reads it to him; the game marks "Dhan knows the
  code" only once the player's message to Dhan contains it. Until then Dhan says "Read me the
  code." This is what makes talking necessary.
- **Codes heard by speech recognition are normalized.** "E6", "e six", "E-6", "eat six" and
  "the six one" all count as E-6; the same goes for "box B" / "bee", "aux two" / "AUX-2",
  "position two" / "II". If no code can be read from the message, Dhan asks you to say it
  again. He never guesses.
- **Dhan's stage limits his replies**: the stage goes into the prompt with a word limit (stage
  1: 30 words, stage 4: 8 words), and the game can blank a stage-4 answer to "…what?"
- **Questions never trigger actions** (exists). Big choices happen through physical controls.
- **Off-topic or rude input:** short answer, back to the situation (exists).
- **M.A.R.V.I.S. never uses free AI text.**

---

## 10. M.A.R.V.I.S. command list

The player talks to M.A.R.V.I.S. at the junction terminal, or anywhere with a new radio key (3; 1 and 2 stay Aaron and Dhan). A flat,
robotic voice. If nothing matches:

> "Query not recognized. Available: STATUS. POWER. SHUTTLE. CREW. MEDICAL. DOORS."

| Intent | Example player wording | Reply template |
|---|---|---|
| STATUS | "status", "what's wrong", "report" | "Main power: {main}. Shuttle: intact. Clamps: {clamps}. Hull: breach sealed, aft section." |
| POWER | "power", "how do we get power" | "Main bus: offline. Fault: engineering distribution. Emergency battery: laboratory, supplying freezer." |
| SHUTTLE | "shuttle", "can we launch" | "Shuttle systems: nominal. Docking clamps: {clamps}. Manual release: bay console." |
| CREW | "where's everyone", "crew" | "Crew active: {n}. A. Reyes: {room}. D. Okafor: {room}, injured." |
| MEDICAL | "is Dhan okay", "medical" | "D. Okafor: suspected fracture, left leg. Condition: {stage_word}. Recommended: immobilize. Analgesic: medbay cabinet." |
| DOORS | "open the door" | "Door control requires main power." / "Opening." |
| Can't do | "fly the shuttle", "fix it", "help Dhan" | "Function unavailable. I am a maintenance system." |
| Kien | "where's Kien", "is Kien alive" | "Crew member K. Tan: no signal since 04:12." |

`{stage_word}`: stable, deteriorating, serious, critical. (Surnames are placeholders.)

---

## 11. Objective card and log

- **Objective card shows only the goal**, never the steps:
  - Beat 0–1: "Help Dhan."
  - Beat 2–3: "Get the shuttle working."
  - Beat 4: "Get everyone aboard. Launch."
- **Log** (a panel on the Tab deck map) lists facts the player has learned, in the words of whoever said them:
  - "M.A.R.V.I.S.: Clamps need power."
  - "Dhan: Engineering cabinet is probably a fuse."
  - "Aaron: The lab battery keeps the samples cold."
  - "M.A.R.V.I.S.: Splints in medbay cabinet."
- The current step-by-step lines in `escape_state.gd` ("Ask Aaron to help load the battery")
  become terse results ("Battery released.") or are removed.

---

## 12. Final review: additions and removals

### Relationships (one line each in personas and scripted lines)

- **Johnny & Dhan:** have flown together for years. Dhan calls him "Captain," half as a joke.
  He hides pain behind jokes because he doesn't want to be the reason anyone gets hurt.
- **Aaron & Kien:** collected the samples together and were close friends. Aaron is the one
  who mentions Kien, never in a long speech.
- **Aaron & Dhan:** bicker like siblings. When Dhan gets quiet, Aaron gets scared, and the
  player hears it.

### Two moments where the crew asks *you* something

The player's answer is saved as a memory and can be quoted in the ending.

1. **Aaron at the freezer** (battery route): "Do we really have to?"
2. **Dhan at stage 3** (any route, once): "Hey, Captain. If this goes bad… don't wait for me."
   Whatever the player promises, the ending remembers. ("You said you wouldn't leave me." /
   "You told me you'd go without me. Glad you're a liar.")

These are the only scripted questions. They give the relationships one beat each, inside the
gameplay, with no cutscene.

### Teach the controls, not the solutions

- The first time Aaron speaks in Beat 0, show **"Hold Space to talk · or type"** once. That's
  teaching a control, not giving the answer, so it's allowed.
- The typing box must be easy to find. Hackathon floors are loud and microphones fail. Typed
  messages go through exactly the same AI.

### Replay hooks on the ending screen

- "Endings found: N/5" and "Fails found: N/5", saved per account.
- One line hinting at a path not taken, without spoiling it, e.g. "Some people found a way to
  save Kien's work *and* get Dhan home."
- Judges who replay see a different game, and the random codes make the puzzles new too.

### Remove or change

| What | Why |
|---|---|
| ECHO, the H "ask ECHO" key, `dialogue_fallbacks.json` lines | Replaced by M.A.R.V.I.S. on key 3 |
| Step-by-step objective text and result lines in `escape_state.gd` | Spoon-feeding (section 11) |
| "Inspect the launch terminal first" gate before choosing a route | Routes are chosen by doing; the terminal is optional knowledge |
| Yes/no confirmation popups for big choices | Replaced by physical controls (M8 guard cover) |
| Dhan's `fetch_case` action | Dhan can't walk; Aaron fetches the case |
| "Johnny the engineer" and "Dhan the pilot" in the AI prompts | Johnny is now the pilot, Dhan the engineer (keep "Kien was lost") |
| Time-based leaderboard as the main score | Rewards rushing, which fights the story. Keep it, but show endings and fails found first |
| The old gravity-mission docs in README | Point README at this doc |

### Demo plan

- **Rehearsed path for the pitch: engineering with the medbay.** It shows the most: Dhan's
  guided repair, relaying to Aaron, discovering the medbay, Dhan's decline and recovery,
  and the two-person launch. About 6 minutes.
- Then **hand the controls to a judge.** The random codes mean their run won't match yours,
  which proves the conversation is live.
- Have the battery route in your pocket as the "shorter path" if time is tight.

### If time runs short, cut in this order

1. M18 fly-out (use a cutscene)
2. F2 airlock fail, M19
3. "Endings found" counter and hint line
4. M14 rack choice (the case saves the right rack automatically)
5. M11 cart-door detour
6. Aaron's ×0.85 stay-with-Dhan bonus

Never cut: freeing Dhan, M.A.R.V.I.S., Dhan's clock and medbay, the fault-code conversation,
the battery lift, the two-person launch, and the endings. Those are the game.

---

## 13. Build order

1. **Must-have**
   - Role swap (player = pilot, Dhan = injured engineer); aftershock and free-Dhan opening.
   - M.A.R.V.I.S. rename, command list, templates and voice.
   - Goal-only objectives and the learned-facts log; strip the spoon-feeding lines.
   - Dhan's condition clock, stages and death; medbay splint kit.
   - The close-up panel and hold-E ring (most mechanics use them).
   - Engineering route with random fault code / fuse / AUX, the "who knows what" rule,
     code normalization, sending Aaron for the fuse, and switching away mid-route.
   - Battery route with Aaron's question, the count-of-three lift, Dhan's power selector,
     and the sample case (Aaron fetches it now, not Dhan).
   - Two-person launch; fails F1, F3, F4, F5; the five endings.
   - Proactive lines, stuck nudges, Dhan's stage-3 question; pre-recorded key lines.
   - "Hold Space to talk · or type" first-time prompt.
2. **Next**
   - Fly-out piloting sequence (until then, a short cutscene).
   - F2 airlock fail; galley Kien memory; "Fails found" counter.
   - Promise callbacks in endings.
3. **Only if there's time**
   - Dhan mishearing at stage 4.
   - More AI talking points per room.

## 13½. What's built (Nov 8)

Everything in the must-have list is in the game, plus F2, the galley line, the "Fails
found" counter and promise quotes in the endings. Build notes and tests:
[Escape Prototype.md](Escape%20Prototype.md). Differences from the plan above:

- **M.A.R.V.I.S. uses no AI at all.** Questions are matched against a fixed word list in
  `escape_marvis.gd`; answers are template sentences filled from the game state. More
  predictable, instant, free, and it sounds like a phone menu, which is the point.
- **Fly-out (M18)** isn't a piloting scene. Instead, LAUNCH plays the launch sequence:
  sirens, every door seals, a hatch opens under the shuttle and it drops out of the ship.
  Then the **ending film** (`scripts/ui/outro_film.gd`, drawn live in the opening's pixel
  style): the Wayfarer is hit by asteroids and breaks apart as the shuttle pulls away; a
  short exchange aboard that depends on the ending (Dhan adds "I heard what you said back
  there" if you answered his question and he lived); "11 DAYS LATER"; Earth fills the
  window; the logo; credits roll from `data/credits.json`; then the stats card. Skippable.
- Because the Wayfarer is destroyed, on the engineering route Aaron loads every sample
  rack into the shuttle's cold store (the freezer never warmed), so "Everyone home" keeps
  all of Kien's work.
- **Dhan mishearing at stage 4** isn't built; his replies just get shorter.
- **Aaron's freezer question doesn't block the switch.** Answering is optional; what the
  player says is quoted at the end. A question expires after 40 s, and a message containing
  a code, switch number or box letter is never taken as the answer.
- **Endings and fails found** are remembered per device, not per account.
- **No voice files yet.** Every scripted line works as text; `tools/record_escape_lines.py`
  records them all on the server.
- **The hosted backend needs updating** (`escape_dialogue.py`, `save_games.py`) before live
  replies and cloud saves work with this version.

## 14. Open questions

- The film's last voice line is "Then find Dhan," but Dhan is right there. Can someone
  re-record it as "Then get Dhan out of here"? Otherwise leave it; the aftershock covers it.
- Surnames for M.A.R.V.I.S. readouts (placeholders above).
- M.A.R.V.I.S. voice: pick a flat ElevenLabs voice, or run a normal voice through a radio filter.
