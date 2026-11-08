extends Node
## Full branch and scene-lifecycle checks; -- --visual saves rendered QA frames.

const Rules = preload("res://scripts/prototype/escape_state.gd")
const Mission = preload("res://scripts/prototype/escape_mission.gd")
var failures := 0
var checks := 0
var visual := false

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _ready() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _run() -> void:
	var rules = Rules.new()
	check(not rules.apply("launch").ok, "Launch blocked without clamps")
	check(not rules.apply("connect_battery").ok, "Cannot connect a missing battery")
	check(not rules.apply("push_locker").ok, "Locker requires cooperation")
	check(not rules.apply("choose_battery").ok, "Must assess shuttle before choosing")
	await _test_ask_from_afar()
	for branch in ["engineering", "battery", "saved"]:
		var mission = Mission.new()
		Settings.intro_pending = false
		add_child(mission)
		await get_tree().process_frame
		await get_tree().process_frame
		mission.ui.radio.live_enabled = false  # tests use the offline interpreter, never the network
		check(mission.active, "Scene enters gameplay: " + branch)
		check(not mission.find_path(Vector2(175, 470), Vector2(570, 470)).size(), "Closed cabin blocks navigation")
		mission.player.position = Vector2(300, 470)
		var response: Dictionary = mission.offline_response("mara", "Could you grab the other side and help me?")
		check(response.action == "help_locker", "Natural locker request understood")
		check(mission.offline_response("mara", "Don't help with the locker").action == "none", "Negation cannot start a task")
		mission.act_on_dialogue("mara", response.action)
		await _settle(mission)
		check(mission.state.has_flag("locker_ready"), "Mara arrives and holds locker")
		mission.perform("push_locker")
		check(mission.state.has_flag("locker_clear"), "Cooperation clears cabin")
		check(not mission.find_path(Vector2(175, 470), Vector2(570, 470)).is_empty(), "Open cabin has traversable route")
		mission.player.position = Vector2(520, 460)
		mission.player.snap_camera()
		mission.perform("assess")
		mission.ui.show_routes()
		await _capture("routes")
		mission.ui.close()
		mission.perform("choose_engineering" if branch == "engineering" else "choose_battery")
		if branch == "engineering":
			check(not mission.perform("take_fuse").ok, "Live circuit blocks repair")
			mission.perform("isolate")
			check(not mission.perform("choose_battery").ok, "Committed engineering route cannot switch")
			mission.perform("take_fuse")
			mission.perform("cabinet")
			check(mission.state.has_flag("fuse_installed"), "Replacement is installed")
			mission.perform("cabinet")
			check(not mission.state.powered(), "Fault trips before auxiliary isolation")
			mission.perform("aux")
			mission.perform("cabinet")
			check(mission.state.powered(), "Engineering powers the bay")
		else:
			if branch == "saved":
				var query: Dictionary = mission.offline_response("ivo", "What happens if we fetch the case?")
				check(query.action == "none", "Hypothetical does not assign a task")
				response = mission.offline_response("ivo", "Please bring the insulated sample case")
				check(response.action == "fetch_case", "Sample-case delegation understood")
				mission.act_on_dialogue("ivo", response.action)
				await _settle(mission)
				check(mission.state.has_flag("case_arrived"), "Ivo retrieves and delivers case")
				mission.perform("pack_samples")
				check(mission.state.has_flag("samples_saved"), "Samples packed while cooling is on")
			mission.perform("disconnect_battery")
			check(not mission.perform("choose_engineering").ok, "Battery removal locks route")
			check(not mission.perform("pack_samples").ok, "Cannot recover samples after cooling loss")
			mission.player.position = Vector2(580, 790)
			mission.player.snap_camera()
			mission.open_chat("mara")
			mission.ui._send("Can you help lift the battery onto the cart?")
			await _settle(mission)
			check(mission.state.has_flag("battery_loaded"), "Mara visibly loads battery after conversation")
			await _capture("lab")
			mission.ui.close()
			mission.perform("take_cart")
			check(mission.state.carrying == "battery cart", "Player collects loaded cart")
			mission.perform("connect_battery")
			check(mission.state.powered(), "Emergency battery powers bay")
		mission.perform("release")
		check(not mission.perform("launch").ok, "Cannot leave while crew still boarding")
		await _settle(mission)
		check(mission.crew_ready(), "Both crew reach shuttle through actual map")
		mission.player.position = Vector2(1000, 490)
		mission.player.snap_camera()
		mission.ui.show_map()
		await _capture("map")
		mission.ui.close()
		mission.perform("launch")
		check(mission.ending, "Route reaches ending: " + branch)
		check(mission.state.has_flag("samples_saved") == (branch == "saved"), "Ending reflects cargo decisions: " + branch)
		await _capture("ending-" + branch)
		mission.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	# Preserve the existing intro behavior and verify its handoff into this scene.
	Settings.intro_pending = true
	var intro_mission = Mission.new()
	add_child(intro_mission)
	await get_tree().process_frame
	check(not intro_mission.active, "Existing intro blocks gameplay")
	check(intro_mission._intro != null, "Original cutscene instantiated unchanged")
	intro_mission._intro.skip()
	await get_tree().process_frame
	check(intro_mission.active, "Original cutscene hands off to prototype")
	intro_mission.queue_free()
	await get_tree().process_frame
	Sfx.stop_ambient()
	await get_tree().process_frame
	print("ESCAPE PROTOTYPE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

## The bug players hit: asking Mara for the locker from the starting spot did nothing.
## Now she walks over, waits, and starts when the player arrives; the chat closes itself.
func _test_ask_from_afar() -> void:
	var mission = Mission.new()
	Settings.intro_pending = false
	add_child(mission)
	await get_tree().process_frame
	await get_tree().process_frame
	mission.ui.radio.live_enabled = false
	var start: Vector2 = mission.crew.mara.position
	mission.ui.open_chat("mara")
	mission.ui._send("Could you grab the other side and help me?")
	check(mission.crew.mara.path.size() > 0, "Asked from the start position, Mara sets off for the locker")
	await _settle(mission)
	check(mission.crew.mara.position.distance_to(start) > 10, "Mara actually walks over")
	check(not mission.state.has_flag("locker_ready"), "She waits for the player before holding it")
	await get_tree().create_timer(1.7).timeout
	check(not mission.ui.is_open(), "Chat closes by itself once she starts a task")
	mission.player.position = Vector2(320, 450)
	await get_tree().create_timer(0.6).timeout
	check(mission.state.has_flag("locker_ready"), "Walking up to the locker starts it")
	mission.queue_free()
	await get_tree().process_frame

func _settle(mission) -> void:
	for i in range(700):
		for actor in mission.crew.values(): actor._process(0.05)
		if mission.crew.mara.path.is_empty() and mission.crew.ivo.path.is_empty(): break
		await get_tree().process_frame
	await get_tree().physics_frame

func _capture(label: String) -> void:
	if not visual: return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/back2earth-" + label + ".png")
