extends Node
## Story, branch and scene checks for the escape (docs/Game Design.md).
##   godot --headless --path . res://tests/escape_runner.tscn
##   ... -- --visual     also saves rendered QA frames to /tmp/back2earth-*.png
##   ... -- --fixture    also writes server/fixtures/checkpoint_v2.json (a real save)

const Rules = preload("res://scripts/prototype/escape_state.gd")
const Marvis = preload("res://scripts/prototype/escape_marvis.gd")
const Mission = preload("res://scripts/prototype/escape_mission.gd")
var failures := 0
var checks := 0
var visual := false
var fixture := false
var _voice_guard_checked := false

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _ready() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	fixture = "--fixture" in OS.get_cmdline_user_args()
	SaveGame.enabled = false
	_run.call_deferred()

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_escape_discoveries.cfg"))
	_test_rules()
	_test_parsing()
	_test_condition_math()
	_test_endings()
	_test_marvis_words()
	await _test_darkness()
	await _test_footsteps()
	await _test_opening()
	await _test_engineering()
	await _test_battery(true)
	await _test_battery(false)
	await _test_death_and_medbay()
	await _test_fails_and_launch()
	await _test_guardrail_and_live()
	await _test_save_round_trip()
	await _test_nudges_and_lines()
	await _test_intro_handoff()
	await _test_outro_film()
	await _test_speech_and_voices()
	Sfx.stop_ambient()
	await get_tree().process_frame
	print("ESCAPE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

# --- Pure rules -----------------------------------------------------------------------

func _test_rules() -> void:
	var r = Rules.new()
	check(r.objective() == "Help Dhan.", "Objective is the goal, not a step")
	check(r.apply("cabinet_touch").get("fail") == "F1", "Touching the live cabinet is F1")
	check(r.apply("battery_latch").get("fail") == "F5", "Pulling the battery with the freezer on is F5")
	check(r.apply("launch").get("fail") == "F3", "Launching with clamps on is F3")
	check(r.apply("airlock").get("fail") == "F2", "Airlock without a suit is F2")
	check(r.flags.is_empty(), "Fails never change progress (the world rewinds)")
	r.apply("free_dhan")
	check(r.has_flag("locker_clear") and r.objective() == "Get the shuttle working.", "Freeing Dhan clears the hallway")
	r.apply("isolate")
	check(not r.apply("seat_fuse").ok, "Empty hands: nothing to seat")
	var wrong: String = ["A", "B", "C"].filter(func(b): return b != r.right_fuse())[0]
	r.apply("take_fuse", wrong)
	var seat: Dictionary = r.apply("seat_fuse")
	check(not seat.ok and r.carrying == "fuse_" + wrong, "Wrong fuse won't seat and stays in your hand")
	r.apply("take_fuse", r.right_fuse())
	check(r.apply("seat_fuse").ok and r.carrying == "", "Right fuse seats")
	check(r.apply("test").ok and r.has_flag("fault_found"), "First test finds the short")
	check(not r.apply("restart").ok, "Restart trips while the branch is shorting")
	var bad_toggle := (r.right_toggle() + 1) % 3
	var t: Dictionary = r.apply("toggle", str(bad_toggle))
	check(not t.ok and t.has("hurt"), "Wrong toggle costs Dhan something")
	check(r.apply("toggle", str(r.right_toggle())).ok, "Right toggle cuts the branch")
	check(not r.apply("restart").ok, "Restart alone is rejected: the bay breaker is open")
	check(r.apply("restart", "held").ok and r.powered(), "Engineering powers the bay with the breaker held")
	check(r.route() == "engineering" and r.samples() == "all", "Engineering keeps every sample")
	# Distinct, valid puzzles.
	var seen := {}
	for i in 30:
		var p = Rules.new()
		p.new_puzzle(i)
		seen["%d%s%d%d" % [p.puzzle.code, p.right_fuse(), p.puzzle.aux, p.puzzle.selector]] = true
		var boxes: Array = p.puzzle.fuse_for.values()
		boxes.sort()
		check(boxes == ["A", "B", "C"], "Each code maps to a different box")
	check(seen.size() > 10, "Runs get different puzzle answers")

func _test_parsing() -> void:
	for pair in [["E-6", 6], ["it says e6", 6], ["E six", 6], ["error nine", 9], ["eat three", 3], ["the display says 9", 9],
			["code is E 3", 3], ["I have six apples", 0], ["what do I do", 0], ["it says aux 3", 0], ["the screen says AUX-3", 0]]:
		check(Rules.parse_code(pair[0]) == pair[1], "Code '%s' -> %d" % pair)
	for pair in [["aux two", 2], ["AUX-3", 3], ["ox 1", 1], ["it says aux2", 2], ["auxiliary three", 3], ["two", 0]]:
		check(Rules.parse_aux(pair[0]) == pair[1], "AUX '%s' -> %d" % pair)
	for pair in [["get box B", "B"], ["the fuse from box bee", "B"], ["grab fuse c", "C"], ["box a please", "A"], ["the C box", "C"], ["a fuse", ""], ["get me a fuse", ""]]:
		check(Rules.parse_box(pair[0]) == pair[1], "Box '%s' -> '%s'" % pair)

## Section 5's expected outcomes, from the real tick().
func _test_condition_math() -> void:
	for row in [[150.0, false, false, 62.5], [200.0, false, false, 50.0], [260.0, false, false, 35.0]]:
		var r = Rules.new()
		r.apply("free_dhan")
		_ticks(r, row[0], row[1])
		check(absf(r.vitality - row[3]) < 0.6, "After %ds untreated Dhan is near %d (got %.1f)" % [row[0], row[3], r.vitality])
	var r = Rules.new()
	r.apply("free_dhan")
	_ticks(r, 60.0, false)
	r.carrying = "splint"
	r.apply("apply_splint")
	_ticks(r, 250.0, false)
	check(absf(r.vitality - 65.0) < 0.8, "Splint at 60 s, launch at 310 s: about 65 (got %.1f)" % r.vitality)
	var a = Rules.new()
	a.apply("free_dhan")
	_ticks(a, 100.0, true)
	check(absf(a.vitality - (100.0 - 25.0 * 0.85)) < 0.6, "Aaron beside him slows the drain")
	var d = Rules.new()
	d.apply("free_dhan")
	d.vitality = 3.0
	d.hurt(10.0)
	check(d.dhan_alive() and d.vitality >= 1.0, "A mistake never kills him outright")
	var died := ""
	for i in 100:
		var e: String = d.tick(0.1, false)
		if e != "": died = e
	check(died == "died" and not d.dhan_alive() and d.stage() == 0, "Running out of time kills him")
	var p = Rules.new()
	check(p.tick(500.0, false) == "" and p.vitality == 100.0, "The clock only starts once he's freed")

func _ticks(r, seconds: float, aaron: bool) -> void:
	var t := 0.0
	while t < seconds - 0.001:
		r.tick(0.5, aaron)
		t += 0.5

func _test_endings() -> void:
	var cases := [
		[{}, 80.0, "everyone_home"],
		[{"freezer_off": true, "samples_saved": true}, 80.0, "what_he_left"],
		[{"freezer_off": true}, 80.0, "kept_each_other"],
		[{}, 30.0, "barely"],
		[{"freezer_off": true}, 10.0, "barely"],
		[{"dhan_dead": true}, 0.0, "two_came_home"],
	]
	for c in cases:
		var r = Rules.new()
		r.flags = c[0].duplicate()
		r.vitality = c[1]
		check(r.ending() == c[2], "Ending %s" % c[2])

func _test_marvis_words() -> void:
	for pair in [["status report", "status"], ["what's wrong with the ship?", "status"], ["is dhan okay", "medical"],
			["can you fly the shuttle", "unavailable"], ["what does E-6 mean", "codes"], ["how do I fix the power", "power"],
			["where is aaron", "crew"], ["is kien alive", "kien"], ["open the clamps", "unavailable"], ["shuttle status", "shuttle"],
			["sing me a song", "unknown"], ["hello marvis", "greeting"]]:
		check(Marvis.classify(pair[0]) == pair[1], "M.A.R.V.I.S. hears '%s' as %s (got %s)" % [pair[0], pair[1], Marvis.classify(pair[0])])

# --- Scenes --------------------------------------------------------------------------

func _new_mission():
	var mission = Mission.new()
	Settings.intro_pending = false
	add_child(mission)
	await get_tree().process_frame
	await get_tree().process_frame
	mission.ui.radio.live_enabled = false  # tests use the scripted interpreter, never the network
	if not _voice_guard_checked:
		_voice_guard_checked = true
		# Voice chat echo guard: the mic hearing the crew through speakers is ignored.
		var radio = mission.ui.radio
		radio.note_spoken("Grab the bottom edge while I lift the top of the locker.")
		check(radio.is_echo("grab the bottom edge while I lift the top"), "Mic hearing a crew line from the speakers is thrown away")
		check(not radio.is_echo("yes"), "...but a short 'yes' always counts")
		check(not radio.is_echo("can you help me find the fuse"), "...and your own words go through")
		check(not radio.listening, "The mic is off until you press talk")
	mission.discoveries_path = "user://test_escape_discoveries.cfg"  # never touch a player's real record
	return mission

func _free(mission) -> void:
	mission.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## Let the mission clock run (timers, lines, crew walking) without waiting real time.
func _advance(mission, seconds: float, step := 0.05) -> void:
	var t := 0.0
	while t < seconds:
		mission.elapsed += step
		mission._run_timers()
		mission._deliver_lines()
		for actor in mission.crew.values(): actor._process(step)
		t += step
	await get_tree().process_frame

func _settle(mission) -> void:
	for i in range(900):
		mission.elapsed += 0.05
		mission._run_timers()
		for actor in mission.crew.values(): actor._process(0.05)
		var moving := false
		for actor in mission.crew.values(): moving = moving or not actor.path.is_empty()
		if not moving and i > 2: break
		if i % 20 == 0: await get_tree().process_frame
	await get_tree().physics_frame

func _say(mission, id: String, text: String) -> Dictionary:
	mission.open_chat(id)
	var before: int = mission.ui.radio.histories[id].size()
	mission.ui._send(text)
	var hist: Array = mission.ui.radio.histories[id]
	mission.ui.close()
	return hist[-1] if hist.size() > before else {}

func _open_and_free_dhan(mission) -> void:
	await _advance(mission, 2.0)
	mission.player.position = mission.anchor("dhan_pull")
	_say(mission, "mara", "Lift that thing off him!")
	await _settle(mission)
	await _advance(mission, 0.5)
	mission._free_dhan()
	await _advance(mission, 1.0)

func _test_opening() -> void:
	var mission = await _new_mission()
	check(mission.active and mission.crew.ivo.display_name == "DHAN · ENGINEER", "Dhan is the engineer")
	var film_cast: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/intro_film.json")).cast
	check(mission.crew.mara.suit == film_cast.survivor and mission.crew.ivo.suit == film_cast.ahead, "Suits match the intro")
	check(mission.scripted, "The aftershock plays before control")
	await _advance(mission, 2.0)
	check(not mission.scripted and mission.crew.ivo.pose == "pinned", "The aftershock pins Dhan under the locker")
	check(mission._said.has("aftershock_dhan") or mission._queue.any(func(q): return q.id == "aftershock_dhan"), "Dhan cries out on his own")
	check(mission.find_path(mission.anchor("player_start"), mission.anchor("junction")).is_empty(), "Locker blocks the hallway")
	check(mission.offline_response("mara", "Don't lift it").action == "none", "Negation starts nothing")
	check(mission.offline_response("mara", "What if you lifted it?").action == "none", "A question starts nothing")
	mission.player.position = mission.anchor("barrier_side")
	var reply: Dictionary = _say(mission, "mara", "Can you get that locker off him?")
	check(not reply.is_empty() and mission.crew.mara.path.size() > 0, "Asked from afar, Aaron walks to the locker")
	await _settle(mission)
	check(not mission.lifting(), "He waits for Johnny before lifting")
	mission.player.position = mission.anchor("dhan_pull")
	await _advance(mission, 0.6)
	check(mission.lifting(), "Johnny arrives: Aaron lifts")
	mission.player._update_target()
	var target = mission.player.current_target
	check(target == mission.crew.ivo and mission.actor_prompt("ivo").begins_with("hold"), "E targets Dhan: hold to pull")
	# Hold E for two seconds on Dhan.
	Input.action_press("interact")
	mission.interact_actor("ivo")
	for i in 50:
		mission.player.current_target = mission.crew.ivo
		mission._update_hold(0.05)
	Input.action_release("interact")
	check(mission.state.has_flag("dhan_free"), "Holding E pulls Dhan free")
	await get_tree().create_timer(0.8).timeout
	check(not mission.find_path(mission.player.position, mission.anchor("junction")).is_empty(), "The hallway opens")
	check(mission.crew.ivo.pose == "sit", "Dhan sits where he was freed")
	# The lift runs out if nobody pulls.
	var m2 = await _new_mission()
	await _advance(m2, 2.0)
	m2.player.position = m2.anchor("dhan_pull")
	m2.act_on_dialogue("mara", "lift_locker")
	await _settle(m2)
	await _advance(m2, 0.5)
	check(m2.lifting(), "Aaron lifts")
	m2.elapsed += 7.0
	m2._update_lift()
	check(not m2.lifting() and not m2.state.has_flag("dhan_free"), "He can only hold it a few seconds")
	await _capture("opening")
	await _free(m2)
	await _free(mission)

func _test_engineering() -> void:
	var mission = await _open_and_free(true)
	var s = mission.state
	# The terminal: first report, then the crew lay out both routes on their own.
	mission.use_prop("terminal")
	check(mission.ui.mode == "chat" and mission.ui.chat_id == "marvis", "Terminal opens M.A.R.V.I.S.")
	check(s.learned.has("m_clamps"), "M.A.R.V.I.S. tells you the clamps need power")
	mission.ui.close()
	await _advance(mission, 50.0)
	check(mission._said.has("beat2_problem_dhan") and mission._said.has("beat2_dhan") and mission._said.has("beat2_aaron"), "Dhan and Aaron bring up the two routes unprompted")
	check(s.learned.has("a_battery") and s.learned.has("d_fuse"), "Both routes land in the log")
	# F1: touching the live cabinet.
	mission.player.position = mission.props.cabinet.position + Vector2(0, 30)
	mission.use_prop("cabinet")
	check(mission.ui.mode == "closeup" and s.has_flag("code_read"), "The cabinet close-up shows the fault code")
	await _capture("cabinet")
	var v0: float = s.vitality
	mission.closeup_press("cabinet", "slot")
	check(mission.ui.fail_open() and s.fails.has("F1"), "Reaching into a live cabinet is a fail")
	check(s.vitality < v0 - 4.0, "A fail costs Dhan some condition")
	await _capture("fail")
	mission.ui._end_fail()
	check(not s.has_flag("isolated"), "Nothing changed after the fail")
	s.apply("isolate")
	# Dhan needs the code read out.
	var dh: Dictionary = mission.offline_response("ivo", "Which fuse do I need?")
	check(dh.line.contains("code"), "Without the code Dhan asks for it")
	var said: String = mission.offline_response("ivo", "It says %s" % s.fault_code()).line
	check(said.contains("box " + s.right_fuse()), "Read the code: Dhan names the right box")
	# Relay to Aaron: he needs the letter.
	var no_box: Dictionary = mission.offline_response("mara", "Go get the fuse")
	check(no_box.action == "none" and no_box.line.contains("Which box"), "Aaron asks which box")
	mission.player.position = mission.anchor("junction")
	_say(mission, "mara", "Get the fuse from box %s" % s.right_fuse())
	check(mission._busy.get("mara", "") == "fetch_fuse", "Aaron sets off for Storage")
	await _settle(mission)
	await _settle(mission)
	check(s.fuse_at_cabinet == s.right_fuse(), "Aaron leaves the fuse by the cabinet")
	mission.closeup_press("cabinet", "slot")
	check(s.has_flag("fuse_installed") and s.fuse_at_cabinet == "", "Fuse seated from what Aaron brought")
	mission.closeup_press("cabinet", "test")
	check(s.has_flag("fault_found"), "Test finds the short")
	for n in [1, 2, 3]:
		var said_aux: String = mission.offline_response("ivo", "It says AUX %d" % n).line.to_lower()
		check(said_aux.contains(["left", "middle", "right"][s.toggle_for(n)]) and not said_aux.contains("box"), "AUX %d is a switch, not a fuse code" % n)
	var aux_line: String = mission.offline_response("ivo", "It says %s" % s.short_branch().replace("-", " ")).line
	check(aux_line.to_lower().contains(["left", "middle", "right"][s.right_toggle()]), "Dhan maps the AUX number to the right toggle")
	mission.ui.show_closeup("aux")
	mission.closeup_press("aux", "t%d" % s.right_toggle())
	check(not s.has_flag("aux_off"), "Toggles are behind the guard cover")
	mission.closeup_press("aux", "cover")
	await _capture("aux")
	var before: float = s.vitality
	mission.closeup_press("aux", "t%d" % ((s.right_toggle() + 1) % 3))
	check(not s.has_flag("aux_off") and s.vitality < before, "Wrong toggle: trips and hurts")
	mission.closeup_press("aux", "t%d" % s.right_toggle())
	check(s.has_flag("aux_off"), "Right toggle cuts the branch")
	mission.closeup_press("cabinet", "restart")
	check(not s.powered() and mission._queue.any(func(q): return q.id == "breaker_dhan") or mission._said.has("breaker_dhan"), "RESTART alone is rejected; Dhan says to send Aaron to the bay breaker")
	check(mission.available_actions("mara").has("hold_breaker"), "Aaron can go hold the breaker")
	check(mission.act_on_dialogue("mara", "hold_breaker") == "", "Aaron heads to the shuttle bay breaker")
	await _settle(mission)
	check(mission.breaker_ready() and mission.timing_banner().contains("NOW"), "He's at the breaker; the banner says to radio him \"now\"")
	var quick: Dictionary = mission.quick_action("mara", "okay now!")
	check(str(quick.get("action", "")) == "breaker_now", "\"Now\" is instant, no AI round trip")
	check(mission.quick_action("mara", "not yet, wait").is_empty(), "\"Not yet\" isn't \"now\"")
	mission.act_on_dialogue("mara", "breaker_now")
	check(mission.breaker_held() and mission.timing_left() > 0.9 and mission.timing_banner().contains("RESTART"), "Aaron holds it; the banner says press RESTART, with a timer")
	mission.closeup_press("cabinet", "restart")
	check(s.powered() and s.has_flag("engineering_power"), "Restart powers the bay")
	check(not mission._busy.has("mara"), "Aaron is free again")
	await _board_and_launch(mission)
	check(mission.ending and s.ending() == "everyone_home", "Engineering route: everyone home")
	await _capture("ending-engineering")
	await _free(mission)

func _open_and_free(skip_report := false):
	var mission = await _new_mission()
	await _open_and_free_dhan(mission)
	if not skip_report: mission.use_prop("terminal")
	mission.ui.close()
	return mission

## Beat 4: carry Dhan, take the seat, Aaron releases and boards, launch.
func _board_and_launch(mission) -> void:
	var s = mission.state
	if s.dhan_alive():
		mission.player.position = mission.crew.ivo.position + Vector2(-30, 0)
		var ask: Dictionary = mission.offline_response("mara", "Help me carry Dhan to the shuttle")
		check(ask.action == "carry_dhan", "Asking Aaron to carry Dhan is understood")
		mission.act_on_dialogue("mara", "carry_dhan")
		var start_gap: float = mission.player.position.distance_to(mission.anchor("board_dhan"))
		for i in 6:
			await _settle(mission)
			await _advance(mission, 0.3)
			for k in 40: mission._walk_player(0.05)
			if s.has_flag("dhan_aboard"): break
		check(mission._said.has("carry_start_aaron"), "The carry is a short walk together")
		check(mission.player.position.distance_to(mission.anchor("board_dhan")) < start_gap - 50.0, "Johnny walks with them")
		check(s.has_flag("dhan_aboard") and not mission.crew.ivo.visible and not mission.scripted, "Dhan is aboard")
	check(mission.act_on_dialogue("mara", "release_clamps") != "", "Aaron won't release with nobody at the helm")
	check(mission.ship.hatch == 0.0, "The launch hatch is in the floor, closed, before launch")
	mission.player.position = mission.props.shuttle.position + Vector2(-60, 60)
	mission.player.snap_camera()
	await _capture("bay-closed-hatch")
	mission.player.position = mission.props.shuttle.position + Vector2(0, 20)
	mission.use_prop("shuttle")
	check(mission.seated and mission.ui.closeup_panel == "pilot", "Johnny takes the pilot seat")
	await _capture("pilot")
	check(mission.act_on_dialogue("mara", "release_clamps") == "", "Seated: Aaron goes to the clamp console")
	await _settle(mission)
	check(mission.clamps_ready() and not s.has_flag("clamps"), "He waits at the console for Johnny's word")
	check(mission.timing_banner().contains("HOLD THRUSTERS"), "The banner says: hold thrusters, then radio 'release'")
	var early: Dictionary = mission.quick_action("mara", "release!")
	check(str(early.get("action", "")) == "release_now" and mission.act_on_dialogue("mara", "release_now").contains("Thrusters first"), "Releasing with cold engines is refused")
	mission.closeup_press("pilot", "thrust")
	check(mission.thrusting() and mission.timing_left() > 0.9, "Hold thrusters fire, with a timer")
	check(mission.act_on_dialogue("mara", "release_now") == "" and s.has_flag("clamps"), "On Johnny's mark the clamps open")
	await _settle(mission)
	check(s.has_flag("aaron_aboard"), "Aaron runs aboard")
	mission.closeup_press("pilot", "launch")
	check(mission.ending and mission.launching and not mission.ui.is_open(), "Launch: the sequence starts, controls lock")
	await get_tree().create_timer(1.6).timeout
	check(mission.ship.sealed >= 1.0, "Every door seals")
	await get_tree().create_timer(1.2).timeout
	check(mission.ship.hatch > 0.5, "The hatch opens under the shuttle")
	var hole: Rect2 = mission.ship.hatch_rect()
	var hull: Texture2D = load("res://assets/ship/shuttle.png")
	check(hole.size.x > hull.get_width() and hole.size.y > hull.get_height(), "The hatch is big enough for the wings")
	await _capture("launch-" + s.ending())
	await get_tree().create_timer(2.0).timeout
	check(not mission.props.shuttle.visible and mission.ship.drop >= 1.0, "The shuttle falls through the hatch (not just vanishing)")
	check(mission.ship.thrust > 0.0, "...then its engines push it forward under the hull")
	await _capture("launch-burn-" + s.ending())
	for i in 80:
		if mission.outro != null: break
		await get_tree().create_timer(0.1).timeout
	check(mission.outro != null and mission.outro.is_running(), "The ending film plays")
	if mission.outro != null:
		check(mission.outro.ending_id == s.ending(), "...for this ending")
		mission.outro.skip()
	await get_tree().create_timer(0.9).timeout
	check(mission.ui.mode == "ending", "After the film: the stats card")

func _test_battery(with_case: bool) -> void:
	var mission = await _open_and_free()
	var s = mission.state
	if with_case:
		check(mission.offline_response("mara", "Is there any way to save the samples?").line.contains("case"), "Asking about the samples reveals the case")
		check(mission.offline_response("mara", "What if you got the case?").action == "none", "A question doesn't send him")
		mission.player.position = mission.anchor("case_drop") + Vector2(20, 0)
		_say(mission, "mara", "Please bring the sample case")
		await _settle(mission)
		await _settle(mission)
		check(s.has_flag("case_arrived"), "Aaron brings the case")
		mission.use_prop("freezer")
		check(mission._said.has("freezer_question") or mission.pending_question.has("mara"), "Aaron asks: do we really have to?")
		_say(mission, "mara", "I'm sorry. We have to.")
		check(s.promises.get("freezer_question", "") == "I'm sorry. We have to.", "Your answer is kept for the ending")
		mission.ui.show_closeup("freezer")
		await _capture("freezer")
		mission.closeup_press("freezer", "rack_priority")
		check(s.has_flag("samples_saved"), "Priority rack packed")
	mission.ui.show_closeup("freezer")
	mission.closeup_press("freezer", "switch")
	check(not s.has_flag("freezer_off"), "The switch is under a guard")
	mission.closeup_press("freezer", "cover")
	mission.closeup_press("freezer", "switch")
	check(s.has_flag("freezer_off") and s.route() == "battery", "Freezer off commits the battery route")
	check(not s.apply("pack_rack", "priority").ok, "Too late to pack after")
	s.apply("battery_latch")
	mission.player.position = mission.props.cart.position + Vector2(10, 12)
	_say(mission, "mara", "Help me lift the battery")
	await _settle(mission)
	await _advance(mission, 0.5)
	check(mission._count.has("t"), "Aaron starts the count of three")
	mission._count.t = 0.8
	mission._lift_attempt()
	check(not s.has_flag("battery_loaded"), "Lifting early drops it")
	await _advance(mission, 2.5)
	check(mission._count.has("t"), "He counts again")
	mission._count.t = mission.COUNT_THREE + 0.1
	mission._lift_attempt()
	check(s.has_flag("battery_loaded"), "Lift on three: loaded")
	mission.use_prop("cart")
	check(s.carrying == "battery cart", "Cart collected")
	mission.player.position = mission.props.socket.position + Vector2(0, 30)
	mission.ui.show_closeup("socket")
	await _capture("socket")
	var dl: String = mission.offline_response("ivo", "What setting for the socket?").line
	check(dl.contains("selector to " + s.right_selector()), "Dhan knows the battery's setting")
	while s.selector == int(s.puzzle.selector): mission.closeup_press("socket", "knob")
	mission.closeup_press("socket", "connect")
	check(not s.powered(), "Wrong setting pops the breaker")
	while s.selector != int(s.puzzle.selector): mission.closeup_press("socket", "knob")
	mission.closeup_press("socket", "connect")
	check(s.powered() and s.has_flag("battery_connected"), "Right setting powers the bay")
	await _board_and_launch(mission)
	check(mission.ending and s.ending() == ("what_he_left" if with_case else "kept_each_other"), "Battery ending: " + s.ending())
	await _capture("ending-battery" + ("-case" if with_case else ""))
	await _free(mission)

func _test_death_and_medbay() -> void:
	var mission = await _open_and_free()
	var s = mission.state
	# Medbay.
	mission.ui.show_closeup("medkit")
	mission.closeup_press("medkit", "splint")
	check(s.carrying == "splint", "Splint kit taken")
	mission.player.position = mission.crew.ivo.position + Vector2(30, 0)
	check(mission.actor_prompt("ivo").begins_with("hold: SPLINT"), "Carrying the splint: hold E on Dhan")
	s.vitality = 50.0
	s.apply("apply_splint")
	check(s.has_flag("dhan_treated") and s.vitality == 60.0, "Splint: +10 and slower drain")
	check(Marvis.new().reply("medical", mission).has("dhan_splinted"), "M.A.R.V.I.S. reports the splint")
	# Stages and his question.
	s.vitality = 44.0
	mission._tick_dhan(0.01)
	check(mission._stage_seen == 3, "Stage 3 noticed")
	await _advance(mission, 9.0)
	check(mission.pending_question.has("ivo"), "Dhan asks Johnny not to wait for him")
	_say(mission, "ivo", "I'm not leaving you, Dhan.")
	check(s.promises.get("stage3_dhan_question", "") == "I'm not leaving you, Dhan.", "Johnny's promise is kept")
	check(mission.ui.radio.memory_notes.ivo.size() > 0, "...and Dhan remembers it")
	# Death.
	s.vitality = 0.05
	mission._tick_dhan(1.0)
	check(not s.dhan_alive() and mission.crew.ivo.pose == "dead", "Dhan dies when time runs out")
	check(mission.available_actions("ivo").keys() == ["none"], "No tasks for Dhan")
	mission.open_chat("ivo")
	check(mission.ui.mode != "chat", "Dhan's radio is silent")
	check(Marvis.new().reply("medical", mission) == ["dhan_no_vitals"], "M.A.R.V.I.S. confirms")
	s.flags["engineering_power"] = true
	check(not mission.available_actions("mara").has("carry_dhan"), "No carrying after he's gone")
	await _board_and_launch(mission)
	check(mission.ending and s.ending() == "two_came_home", "Two came home")
	await _capture("ending-two")
	await _free(mission)

func _test_fails_and_launch() -> void:
	var mission = await _open_and_free()
	var s = mission.state
	mission.player.position = mission.props.airlock.position + Vector2(-10, 20)
	mission.use_prop("airlock")
	check(mission.ui.fail_open() and s.fails.has("F2"), "Airlock is a fail")
	mission.ui._end_fail()
	check(mission.player.position.distance_to(mission.props.airlock.position) > 50, "Rewound away from the airlock")
	check(mission.discoveries().fails.has("F2"), "Fails found are remembered between runs")
	s.flags["battery_connected"] = true
	s.flags["dhan_aboard"] = true
	mission.crew.ivo.visible = false
	mission.player.position = mission.props.shuttle.position + Vector2(0, 20)
	mission.use_prop("shuttle")
	mission.closeup_press("pilot", "launch")
	check(s.fails.has("F3"), "Launch with clamps on: F3")
	mission.ui._end_fail()
	s.flags["clamps"] = true
	mission.open_pilot()
	mission.closeup_press("pilot", "launch")
	check(s.fails.has("F4"), "Launch before Aaron boards: F4")
	mission.ui._end_fail()
	check(not mission.ending, "Still here after the fails")
	await _free(mission)

func _test_guardrail_and_live() -> void:
	var mission = await _open_and_free()
	var s = mission.state
	var wrong: String = ["A", "B", "C"].filter(func(b): return b != s.right_fuse())[0]
	var no_code: String = mission.check_reply("ivo", "Grab box %s." % wrong, "which fuse?")
	check(not no_code.contains("box " + wrong) and no_code.to_lower().contains("code"), "Dhan can't name a box he wasn't asked about; he answers by asking for the code (got: %s)" % no_code)
	check(mission.check_reply("ivo", "Box %s, Captain." % s.right_fuse(), "it says " + s.fault_code()) == "Box %s, Captain." % s.right_fuse(), "...but can once the code is read")
	check(not mission.check_reply("ivo", "Position %s." % s.right_selector(), "what setting").contains("Position"), "No selector answer before the battery is out")
	var mixed: String = mission.check_reply("ivo", "Ah, spare fuse box %s. Try toggle four up, Captain." % s.right_fuse(), "the screen says " + s.fault_code())
	check(mixed == "Ah, spare fuse box %s." % s.right_fuse(), "An invented switch tip is cut; the right part stays (got: %s)" % mixed)
	check(mission.check_reply("ivo", "Hang in there. I'm fine.", "how are you") == "Hang in there. I'm fine.", "Ordinary replies pass untouched")
	check(mission.check_reply("ivo", "Kill the freezer switch if you have to.", "what now") == "Kill the freezer switch if you have to.", "Mentioning a switch isn't a guess")
	var extra: String = mission.check_reply("ivo", "Ah, spare fuse box %s. Captain, flip the primary breaker on that panel." % s.right_fuse(), "it says " + s.fault_code())
	check(extra == "Ah, spare fuse box %s." % s.right_fuse(), "A made-up extra step is cut (got: %s)" % extra)
	var wrong_side: String = ["left", "middle", "right"][(s.right_toggle() + 1) % 3]
	var bad_toggle: String = mission.check_reply("ivo", "Flip the %s-hand toggle." % wrong_side, "it says " + s.short_branch())
	check(not bad_toggle.contains(wrong_side), "A wrong toggle is never shown (got: %s)" % bad_toggle)
	# A live reply goes through the same check, and the voice is dropped.
	var radio = mission.ui.radio
	radio.pending_id = "ivo"
	radio.pending_message = "which fuse?"
	radio.pending_version = s.version
	radio._on_reply(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"npc_id": "ivo", "state_version": s.version,
		"line": "Box %s." % wrong, "action": "none", "source": "live", "audio_url": "/npc/audio/x.mp3"}).to_utf8_buffer())
	check(not radio.histories.ivo[-1].text.contains("Box %s" % wrong), "Live guesses are corrected")
	radio.pending_id = "mara"
	radio.pending_version = s.version
	radio._on_reply(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"npc_id": "mara", "state_version": s.version,
		"line": "Launching now.", "action": "launch", "source": "live"}).to_utf8_buffer())
	check(not s.has_flag("departed") and radio.histories.mara[-1].text != "Launching now.", "An invented action falls back to the script")
	check(mission.act_on_dialogue("mara", "fetch_fuse", "go get a fuse").contains("Which box"), "A model can't send Aaron for an unnamed box")
	await _free(mission)

func _test_save_round_trip() -> void:
	var mission = await _open_and_free()
	var s = mission.state
	s.apply("isolate")
	s.apply("take_fuse", "B")
	s.vitality = 71.25
	s.fails["F1"] = true
	s.promises["freezer_question"] = "We have to."
	mission.ui.radio.add_memory("ivo", "Johnny promised not to leave him.")
	var snap: Dictionary = mission.progress_snapshot()
	check(SaveGame.compatible(snap), "A real save passes the game's save check")
	check(JSON.parse_string(JSON.stringify(snap)) is Dictionary and SaveGame.compatible(JSON.parse_string(JSON.stringify(snap))), "...also after a JSON round trip")
	var bad := snap.duplicate(true)
	bad.state.flags["teleport"] = true
	check(not SaveGame.compatible(bad), "Unknown flags are rejected")
	bad = snap.duplicate(true)
	bad.state.puzzle.fuse_for["3"] = bad.state.puzzle.fuse_for["6"]
	check(not SaveGame.compatible(bad), "A puzzle with two codes on one box is rejected")
	check(not SaveGame.compatible({"schema": 1, "map": "escape-v1"}), "Old-story saves don't resume")
	if fixture:
		var f := FileAccess.open("res://server/fixtures/checkpoint_v2.json", FileAccess.WRITE)
		f.store_string(JSON.stringify(JSON.parse_string(JSON.stringify(snap)), " "))
		f.close()
	var puzzle: Dictionary = s.puzzle.duplicate(true)
	await _free(mission)
	SaveGame.resume_pending = false
	var m2 = Mission.new()
	Settings.intro_pending = false
	add_child(m2)
	await get_tree().process_frame
	m2._restore_progress(JSON.parse_string(JSON.stringify(snap)))
	check(m2.state.has_flag("isolated") and m2.state.carrying == "fuse_B", "Progress restored")
	check(m2.state.puzzle.fuse_for == puzzle.fuse_for and m2.state.fault_code() == "E-%d" % int(puzzle.code), "Same puzzle answers after loading")
	check(absf(m2.state.vitality - 71.25) < 0.01 and m2.state.promises.freezer_question == "We have to.", "Dhan's condition and promises restored")
	check(m2.crew.ivo.pose == "sit" and m2.ui.radio.memory_notes.ivo.has("Johnny promised not to leave him."), "Poses and memories restored")
	await _free(m2)

func _test_nudges_and_lines() -> void:
	var mission = await _new_mission()
	await _advance(mission, 2.0)
	mission._queue.clear()
	mission._said.erase("nudge_free_dhan_1")
	mission._last_progress = mission.elapsed - 50.0
	mission._progress_mark = mission.state.version
	mission._check_stuck()
	check(mission._queue.any(func(q): return q.id == "nudge_free_dhan_1"), "Stuck 45 s: an observation")
	mission._last_progress = mission.elapsed - 95.0
	mission._check_stuck()
	check(mission._queue.any(func(q): return q.id == "nudge_free_dhan_2"), "Stuck 90 s: more direct")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/escape_lines.json"))
	for step in ["free_dhan", "marvis", "choose", "eng_isolate", "eng_code", "eng_fuse", "eng_test", "eng_toggle", "eng_restart",
			"bat_freezer", "bat_latch", "bat_lift", "bat_cart", "bat_socket", "carry", "seat", "release", "launch"]:
		check(data.lines.has("nudge_%s_1" % step) and data.lines.has("nudge_%s_2" % step), "Nudges written for " + step)
	for id in data.lines:
		check(data.lines[id].who in ["aaron", "dhan", "marvis"], "Line %s has a speaker" % id)
	# Lines play once, and respect the cooldown for unprompted ones.
	mission._queue.clear()
	mission._line_until = 0.0
	mission._last_soft = mission.elapsed
	mission.say("galley_aaron", false)
	mission._deliver_lines()
	check(not mission._said.has("galley_aaron"), "Unprompted lines wait for the cooldown")
	mission._last_soft = mission.elapsed - 20.0
	mission._deliver_lines()
	check(mission._said.has("galley_aaron"), "...then play")
	mission.say("galley_aaron", false)
	check(mission._queue.is_empty(), "...once")
	await _free(mission)

func _test_intro_handoff() -> void:
	Settings.intro_pending = true
	var intro_mission = Mission.new()
	add_child(intro_mission)
	await get_tree().process_frame
	check(not intro_mission.active and intro_mission._intro != null, "The intro film plays first, unchanged")
	var cutscene = intro_mission._intro
	cutscene.skip()
	await cutscene.finished
	check(intro_mission.active and intro_mission.scripted, "The film hands off into the aftershock")
	await cutscene.tree_exited
	await _free(intro_mission)

## The ending film on its own: lines per ending, shot timing, and a frame of every shot.
func _test_speech_and_voices() -> void:
	const Radio = preload("res://scripts/prototype/escape_radio.gd")
	const S = preload("res://scripts/prototype/escape_state.gd")
	check(Radio.fix_names("hey dawn can you hear me") == "hey Dhan can you hear me", "Misheard 'dawn' becomes Dhan")
	check(Radio.fix_names("erin lift the locker") == "Aaron lift the locker", "Misheard 'Erin' becomes Aaron")
	check(Radio.fix_names("I don't know") == "I don't know", "'don't' is left alone")
	check(Radio.fix_names("ask jarvis") == "ask MARVIS", "'Jarvis' becomes MARVIS")
	var best: Dictionary = Radio.pick_heard([{"t": "it says easy sex", "c": 0.9}, {"t": "it says E6", "c": 0.6}])
	check(str(best.t) == "it says E6", "The guess with the code in it wins")
	check(S.parse_box("get the fuse from box bravo") == "B" and S.parse_box("charlie box") == "C", "NATO letters name boxes")
	check(S.parse_code("echo nine") == 9 and S.parse_aux("it says ax two") == 2, "More spoken forms of codes and switches")
	var mission = await _new_mission()
	await _advance(mission, 20.0)  # let the opening lines play out
	mission.ui.radio._audio_loading = true
	var id: String = mission.lines.keys().filter(func(k): return not mission._said.has(k) and str(mission.lines[k].who) == "aaron")[0]
	mission.say(id)
	await _advance(mission, 3.0)
	check(not mission._said.has(id), "Scripted lines wait while a crew reply's voice is on its way")
	mission.ui.radio.hush()
	await _advance(mission, 1.0)
	check(mission._said.has(id), "...and play once it's done")
	await _free(mission)
	check(Mission.shown_text("[groans in pain] Agh! My leg.") == "Agh! My leg.", "Voice directions aren't shown in subtitles")
	# Clicks: a screen drawn over a button doesn't swallow the click.
	const Closeup = preload("res://scripts/prototype/escape_closeup.gd")
	var cu = Closeup.new()
	add_child(cu)
	var fired := [""]
	cu.on_press = func(part: String): fired[0] = part
	cu.set_parts([{"id": "go", "kind": "button", "rect": Rect2(10, 10, 60, 30), "label": "GO"},
		{"id": "screen", "kind": "display", "rect": Rect2(0, 0, 200, 100), "text": ""}])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(30, 20)
	cu._gui_input(click)
	check(fired[0] == "go", "A click reaches a button under a screen")
	cu.queue_free()
	# Shift+~ demo shortcut: everyone walks to the shuttle and climbs in, then it launches.
	var md = await _new_mission()
	await _advance(md, 3.0)
	md._secret_trigger_ending()
	check(not md.ending and md.crew.mara.visible and not md.crew.mara.path.is_empty(), "Shortcut: the crew start walking to the shuttle")
	for i in 600:
		md.elapsed += 0.05
		md._run_timers()
		for actor in md.crew.values(): actor._process(0.05)
		md._walk_player(0.05)
		if md.ending: break
	check(md.ending and not md.crew.mara.visible and not md.crew.ivo.visible and not md.player.visible, "...everyone boards, then the launch starts")
	check(md.player.position.distance_to(md.anchor("board_aaron")) < 120.0, "...Johnny walked there himself")
	await get_tree().create_timer(0.2).timeout
	await _free(md)
	# Medbay vials: only Aaron knows which is the painkiller, and only once he's read the labels.
	var mv = await _new_mission()
	var sv = mv.state
	var names: Array = sv.vial_names()
	check(names.size() == 3 and Rules.vial_kind(names[sv.puzzle.painkiller]) == "painkiller", "Three vials, one painkiller")
	check(mv.offline_response("mara", "which vial is the painkiller?").line.contains("labels"), "Aaron asks for the labels first")
	var reply: String = mv.offline_response("mara", "the vials say " + ", ".join(names)).line
	check(reply.to_upper().contains(str(names[sv.puzzle.painkiller])), "...then names the painkiller (got: %s)" % reply)
	check(mv.snapshot("mara", "it says " + str(names[0])).vials_johnny_read_out.has(str(names[0])), "The AI only knows vials Johnny read out")
	var wrong_i: int = (int(sv.puzzle.painkiller) + 1) % 3
	sv.flags["dhan_free"] = true
	check(sv.apply("take_vial", str(wrong_i)).ok and sv.carrying == "vial_%d" % wrong_i, "Take a vial")
	var hp: float = sv.vitality
	check(not sv.apply("give_vial").ok and sv.vitality < hp and sv.has_flag("vial_wrong"), "The wrong vial hurts Dhan")
	await _free(mv)
	# Asking again while Aaron is on his way to the locker carries on, it doesn't block.
	var m3 = await _new_mission()
	await _advance(m3, 2.0)
	check(m3.act_on_dialogue("mara", "lift_locker") == "", "Aaron heads to the locker")
	check(m3.available_actions("mara").has("lift_locker") and m3.act_on_dialogue("mara", "lift_locker") == "", "Asking him again is fine")
	check(str(m3.available_actions("mara").none).contains("next to Dhan"), "...and he can say what he's waiting for")
	await _free(m3)

func _test_outro_film() -> void:
	const Outro = preload("res://scripts/ui/outro_film.gd")
	for id in ["everyone_home", "what_he_left", "kept_each_other", "barely", "two_came_home"]:
		var film = Outro.new()
		film.setup(id, id == "everyone_home")
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		layer.add_child(film)
		film.play()
		check(film.lines.size() >= 3, "Ending film has lines: " + id)
		for i in film.lines.size():
			var words := RegEx.create_from_string("[A-Z]").search(str(film.lines[i][1])) != null
			check(not words or film._voices[i] != null, "Ending line is voiced: %s %d" % [id, i])
		check(film.hum_level(film._starts[0] + 1.0) > 0.5 and film.hum_level(film.t_logo + 1.0) == 0.0, "Shuttle hum under the crew, gone by the logo: " + id)
		check(film.t_later > film.T_EXT_END and film.t_earth > film.t_later and film.t_logo > film.t_earth and film.t_end > film.t_credits + 15.0, "Shots in order, credits roll: " + id)
		if id == "everyone_home":
			check(film.lines.any(func(l): return str(l[1]).contains("HEARD WHAT YOU SAID")), "Dhan remembers Johnny's promise")
			for shot in [["1-drop", 1.0], ["2-hits", 3.2], ["3-split", 5.7], ["4-debris", 7.0], ["5-dialogue", film._starts[1] + 1.6],
					["6-later", film.t_later + 1.6], ["7-earth-a", film.t_earth + 1.5], ["8-earth-b", film.t_earth + 6.5],
					["9-logo", film.t_logo + 2.8], ["10-credits", film.t_credits + 8.0], ["11-credits-end", film.t_end - 4.0]]:
				film.set_time(shot[1])
				await _capture("outro-" + shot[0])
		else:
			film.set_time(film._starts[0] + 2.5)
			await _capture("outro-dialogue-" + id)
		for ch in "".join(film.lines.map(func(l): return str(l[0]) + ": " + str(l[1]))):
			check(ch == " " or film._glyph.has(ch), "Film font has '%s' (%s)" % [ch, id])
		var finished := [false]
		film.finished.connect(func(): finished[0] = true)
		film.set_time(film.t_end + 0.1)
		film._process(0.01)
		await get_tree().create_timer(0.7).timeout
		check(finished[0], "The film ends by itself: " + id)
		layer.queue_free()
		await get_tree().process_frame

## The dark ship (team's lighting): your light, the flashlight beam, crew lights,
## labels only within reach, and power bringing the lights back.
func _test_darkness() -> void:
	var mission = await _new_mission()
	await _advance(mission, 2.0)
	var dark = mission.darkness
	var fuse_pos: Vector2 = mission.props["fuse"].position
	var storage: Rect2
	for room in mission.map_data.rooms:
		if room.name == "STORAGE":
			storage = Rect2(Vector2(room.rect[0], room.rect[1]) * 32.0, Vector2(room.rect[2], room.rect[3]) * 32.0)
	check(storage.has_point(fuse_pos), "Spare fuses are in the storage room")
	check(dark.is_dark(), "No power: the ship is dark")
	check(absf(dark.BASE_RADIUS * 2.0 - 4.0 * 32.0) < 1.0, "Without a flashlight your bright circle is about 4 x 4 tiles")
	for i in 3: await get_tree().process_frame
	var src: Vector2i = dark._cell(mission.player.position + Vector2(0, -8))
	var walls_lit := 0
	var leaks := 0
	for cell in dark.lit.keys():
		if dark.is_opaque(cell): walls_lit += 1
		elif not dark.line_of_sight(src, cell): leaks += 1
	check(walls_lit > 0, "Walls within your light are visible")
	check(leaks == 0, "No lit floor has a wall between it and you (can't see through walls)")
	check(dark.is_opaque(Vector2i(-5, -5)) and "D" in dark.OPAQUE, "Doorways and outside the ship stop light")
	check(dark.DARK_COLOR.v < 0.03, "Unlit areas are black (nothing shows beyond your light)")
	dark.facing = Vector2.RIGHT
	dark.toggle_flashlight()
	for i in 40: await get_tree().process_frame
	check(dark.is_beam_on("player"), "F turns your flashlight on")
	dark.facing = Vector2.UP
	await get_tree().process_frame
	check(dark.beam_direction("player").dot(Vector2.UP) < 0.95, "Turning from right to up swings the beam (no instant snap)")
	for i in 40: await get_tree().process_frame
	check(dark.beam_direction("player").dot(Vector2.UP) > 0.99, "...and it settles pointing up")
	var diagonal := Vector2(1, 1).normalized()
	dark.facing = diagonal
	for i in 40: await get_tree().process_frame
	check(dark.beam_direction("player").dot(diagonal) > 0.99, "The beam points diagonally too (the way you walk)")
	check(dark.beam_shape(1.0) > 0.99 and dark.beam_shape(cos(deg_to_rad(25.0))) < 0.5 \
		and dark.beam_shape(cos(deg_to_rad(40.0))) == 0.0, "Flashlight beam: bright hotspot, dimmer spill, then dark")
	check(dark.falloff(32.0, dark.BEAM_NEAR, dark.BEAM_REACH) > dark.falloff(160.0, dark.BEAM_NEAR, dark.BEAM_REACH) \
		and dark.falloff(dark.BEAM_REACH, dark.BEAM_NEAR, dark.BEAM_REACH) == 0.0, "...that fades with distance, to black")
	dark.toggle_flashlight()
	await get_tree().process_frame
	check(not dark.is_beam_on("player"), "F again turns it off")
	# Crew lights: Dhan (pinned) can still turn his on; Aaron's points where he walks.
	check(mission.available_actions("ivo").has("light_on"), "Dhan offers his flashlight while it's dark")
	check(mission.offline_response("ivo", "turn your flashlight on").action == "light_on", "Asking Dhan for his light is understood")
	check(mission.offline_response("mara", "turn your flashlight on").action == "light_on", "...and Aaron")
	mission.act_on_dialogue("mara", "light_on")
	var aaron = mission.crew.mara
	aaron.path = PackedVector2Array([aaron.position + Vector2(64, 0)])  # walk right
	for i in 50:
		aaron._process(0.02)
		await get_tree().process_frame
	check(dark.is_beam_on("mara") and dark.beam_direction("mara").dot(Vector2.RIGHT) > 0.95, "Aaron's beam points the way he walks")
	check(not dark.is_beam_on("ivo"), "Asking Aaron doesn't turn on Dhan's light")
	mission.act_on_dialogue("mara", "light_off")
	await get_tree().process_frame
	check(not dark.is_beam_on("mara"), "...and it turns off when asked")
	mission.player.position = aaron.position + Vector2(300, 0)
	await get_tree().process_frame
	check(not aaron.name_label.visible, "Aaron's name is hidden when you're far away")
	mission.player.position = aaron.position + Vector2(30, 0)
	await get_tree().process_frame
	check(aaron.name_label.visible, "...and shows once you're close enough to press E")
	check(not mission.props["fuse"].caption.visible, "Far objects' labels are hidden too")
	check(mission.alarm != null, "The corridor's alarm beacons are in the scene")
	mission.state.flags["engineering_power"] = true
	await get_tree().create_timer(1.8).timeout
	check(not dark.is_dark(), "Power restored: the lights come back")
	check(not mission.available_actions("ivo").has("light_on"), "No flashlight actions once the lights are on")
	await _free(mission)

## Footsteps: the floor underfoot picks the sound (metal, grate, soft).
func _test_footsteps() -> void:
	var mission = await _new_mission()
	var steps = mission.player._footsteps
	check(steps != null and mission.crew.mara.footsteps != null, "Johnny and the crew have footsteps")
	var all_there := true
	for surface in ["metal", "grate", "soft"]:
		for k in range(1, 7):
			all_there = all_there and ResourceLoader.exists("res://assets/audio/steps/%s_%d.wav" % [surface, k])
	check(all_there, "Every footstep sound exists (6 per floor)")
	for room in mission.map_data.rooms:
		var r: Array = room.rect
		var centre := (Vector2(r[0], r[1]) + Vector2(r[2], r[3]) / 2.0) * 32.0
		if mission.room_at(centre) != room.name:
			continue
		var want: String = {"grate": "grate", "carpet": "soft", "hydro": "soft"}.get(room.style, "metal")
		check(steps.surface_at(centre) == want, "Footsteps in %s sound like %s" % [room.name, want])
	check(mission.floor_style_at(Vector2(-100, -100)) == "deck", "Off the map, steps sound like deck plating")
	await _free(mission)

func _capture(label: String) -> void:
	if not visual: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/back2earth-" + label + ".png")
