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
	await _test_dark_and_fuse()
	for branch in ["engineering", "battery", "saved"]:
		var mission = Mission.new()
		Settings.intro_pending = false
		add_child(mission)
		await get_tree().process_frame
		await get_tree().process_frame
		mission.ui.radio.live_enabled = false  # tests use the offline interpreter, never the network
		check(mission.active, "Scene enters gameplay: " + branch)
		if branch == "engineering":
			var film_cast: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/intro_film.json")).cast
			check(mission.crew.mara.display_name == "AARON · RESEARCHER", "Cabin companion is Aaron from the intro")
			check(mission.crew.ivo.display_name == "DHAN · PILOT", "Forward companion is Dhan from the intro")
			check(mission.crew.mara.suit == film_cast.survivor, "Aaron wears his surviving crewmate suit from the intro")
			check(mission.crew.ivo.suit == film_cast.ahead, "Dhan wears his forward crewmate suit from the intro")
			check(mission.offline_response("mara", "What's your name?").line.begins_with("I'm Aaron."), "Offline Aaron knows his name")
			check(mission.offline_response("ivo", "Who are you?").line.begins_with("I'm Dhan."), "Offline Dhan knows his name")
			var radio = mission.ui.radio
			radio.pending_id = "mara"
			radio.pending_version = mission.state.version
			radio._on_reply(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"npc_id": "mara", "state_version": mission.state.version, "line": "The survivor is with Mara and Ivo.", "action": "none", "source": "live"}).to_utf8_buffer())
			check(radio.histories.mara[-1].text == "The survivor is with Aaron and Dhan.", "Older hosted dialogue uses current crew names without changing other words")
		check(not mission.find_path(mission.anchor("player_start"), mission.anchor("junction")).size(), "Closed cabin blocks navigation")
		mission.player.position = mission.anchor("locker_push")
		var response: Dictionary = mission.offline_response("mara", "Could you grab the other side and help me?")
		check(response.action == "help_locker", "Natural locker request understood")
		check(mission.offline_response("mara", "Don't help with the locker").action == "none", "Negation cannot start a task")
		mission.act_on_dialogue("mara", response.action)
		await _settle(mission)
		check(mission.state.has_flag("locker_ready"), "Aaron arrives and holds locker")
		mission.perform("push_locker")
		check(mission.state.has_flag("locker_clear"), "Cooperation clears cabin")
		check(not mission.find_path(mission.anchor("player_start"), mission.anchor("junction")).is_empty(), "Open cabin has traversable route")
		mission.player.position = mission.anchor("junction")
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
				check(mission.state.has_flag("case_arrived"), "Dhan retrieves and delivers case")
				mission.perform("pack_samples")
				check(mission.state.has_flag("samples_saved"), "Samples packed while cooling is on")
			mission.perform("disconnect_battery")
			check(not mission.perform("choose_engineering").ok, "Battery removal locks route")
			check(not mission.perform("pack_samples").ok, "Cannot recover samples after cooling loss")
			mission.player.position = mission.props.cart.position + Vector2(10, 10)
			mission.player.snap_camera()
			mission.open_chat("mara")
			mission.ui._send("Can you help lift the battery onto the cart?")
			await _settle(mission)
			check(mission.state.has_flag("battery_loaded"), "Aaron visibly loads battery after conversation")
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
		mission.player.position = mission.anchor("board_aaron") + Vector2(-30, 0)
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

## The bug players hit: asking Aaron for the locker from the starting spot did nothing.
## Now he walks over and waits; when you arrive he holds it and E pushes it.
func _test_ask_from_afar() -> void:
	var mission = Mission.new()
	Settings.intro_pending = false
	add_child(mission)
	await get_tree().process_frame
	await get_tree().process_frame
	mission.ui.radio.live_enabled = false
	mission.player.position = mission.anchor("barrier_side")  # step away first: he must wait for you
	var start: Vector2 = mission.crew.mara.position
	var was_voice: bool = Settings.voice_chat
	Settings.voice_chat = true
	mission.ui.open_chat("mara")
	check(is_instance_valid(mission.ui.chat_input) and not mission.ui.voice_mode, "Voice chat falls back to the text box where speech isn't available")
	Settings.voice_chat = was_voice
	mission.ui._send("Could you grab the other side and help me?")
	check(mission.crew.mara.path.size() > 0, "Asked from the start position, Aaron sets off for the locker")
	await _settle(mission)
	check(mission.crew.mara.position.distance_to(start) > 10, "Aaron actually walks over")
	check(not mission.state.has_flag("locker_ready"), "She waits for the player before holding it")
	await get_tree().create_timer(1.7).timeout
	check(not mission.ui.is_open(), "Chat closes by itself once he starts a task")
	mission.player.position = mission.anchor("locker_push") + Vector2(-12, 0)  # coming from the cabin side
	await get_tree().create_timer(0.6).timeout
	check(mission.state.has_flag("locker_ready"), "Walking up to the locker: Aaron takes hold")
	check(not mission.state.has_flag("locker_clear"), "Aaron does not move the locker by herself")
	mission.player._update_target()
	var target = mission.player.current_target
	check(target != null and "prop_id" in target and target.prop_id == "locker", "With Aaron holding, E targets the locker (not Aaron's chat)")
	if target != null: target.interact(mission.player)  # the player presses E
	check(mission.state.has_flag("locker_clear"), "Pressing E pushes the locker clear")
	await get_tree().create_timer(0.8).timeout  # the slide animation
	check(mission.locker_visual.position.distance_to(mission.anchor("locker_visual")) > 20, "The locker visibly slides out of the doorway")
	check(not mission.find_path(mission.player.position, mission.anchor("junction")).is_empty(), "You can walk right into the junction")
	check(not mission.find_path(mission.player.position, mission.props["fuse"].position + Vector2(0, 32)).is_empty(), "You can walk to the spare fuse in storage")
	mission.queue_free()
	await get_tree().process_frame

## Spare fuse lives in STORAGE (not next to the cabinet); the ship is dark until
## power is back, F gives a ~6x6-tile flashlight, and power brings the lights back.
func _test_dark_and_fuse() -> void:
	var mission = Mission.new()
	Settings.intro_pending = false
	add_child(mission)
	await get_tree().process_frame
	await get_tree().process_frame
	mission.ui.radio.live_enabled = false
	var fuse_pos: Vector2 = mission.props["fuse"].position
	var storage: Rect2
	for room in mission.map_data.rooms:
		if room.name == "STORAGE":
			storage = Rect2(Vector2(room.rect[0], room.rect[1]) * 32.0, Vector2(room.rect[2], room.rect[3]) * 32.0)
	check(storage.has_point(fuse_pos), "Spare fuse is in the storage room")
	check(mission.darkness.is_dark(), "No power: the ship is dark")
	check(absf(mission.darkness.BASE_RADIUS * 2.0 - 6.0 * 32.0) < 1.0, "Without a flashlight you see about 6 x 6 tiles")
	await get_tree().process_frame
	var far_actor = mission.crew.ivo
	var near_dist: float = mission.player.position.distance_to(far_actor.position)
	check(near_dist < 3.0 * 32.0 or far_actor.modulate.a < 0.5, "Crew outside your light are hidden in the dark")
	mission.darkness.facing = Vector2.RIGHT
	mission.darkness.toggle_flashlight()
	for i in 40: await get_tree().process_frame
	mission.darkness.facing = Vector2.UP  # D then W
	await get_tree().process_frame
	var mid: Array = mission.darkness._beams()
	check(Vector2(mid[0].z, mid[0].w).dot(Vector2.UP) < 0.95, "Turning from right to up swings the beam (no instant snap)")
	for i in 40: await get_tree().process_frame
	mid = mission.darkness._beams()
	check(Vector2(mid[0].z, mid[0].w).dot(Vector2.UP) > 0.99, "...and it settles pointing up")
	mission.darkness.facing = Vector2.LEFT
	for i in 60: await get_tree().process_frame
	var beams: Array = mission.darkness._beams()
	check(mission.darkness.flashlight and beams.size() == 1 and Vector2(beams[0].z, beams[0].w).dot(Vector2.LEFT) > 0.99, "F = a beam in the direction you face")
	var origin := Vector2(beams[0].x, beams[0].y)
	check(mission.darkness.light_at(origin + Vector2(-6.0 * 32.0, 0), beams) > 0.5, "The beam lights 6 tiles ahead")
	check(mission.darkness.light_at(origin + Vector2(6.0 * 32.0, 0), beams) < 0.1, "...but not behind you")
	mission.darkness.toggle_flashlight()
	check(not mission.darkness.flashlight, "F again turns it off")
	check(mission.available_actions("ivo").has("light_left"), "Crew offer flashlight actions while it's dark")
	check(mission.offline_response("ivo", "point your light left").action == "light_left", "Asking Dhan to point his light left is understood")
	mission.act_on_dialogue("ivo", "light_left")
	check(mission.crew.ivo.light_dir == Vector2.LEFT and mission.darkness._beams().size() == 1, "Dhan's flashlight beam points left")
	mission.player.position = mission.crew.ivo.position + Vector2(300, 0)
	await get_tree().process_frame
	check(not mission.crew.ivo.name_label.visible, "Dhan's name is hidden when you're far away")
	mission.player.position = mission.crew.ivo.position + Vector2(30, 0)
	await get_tree().process_frame
	check(mission.crew.ivo.name_label.visible, "...and shows once you're close enough to press E")
	check(not mission.props["fuse"].caption.visible, "Far objects' labels (SPARE FUSE) are hidden too")
	mission.act_on_dialogue("ivo", "light_off")
	check(mission.crew.ivo.light_dir == Vector2.ZERO, "...and turns off when asked")
	mission.state.flags["engineering_power"] = true
	await get_tree().create_timer(1.8).timeout
	check(not mission.darkness.is_dark(), "Power restored: the lights come back")
	check(mission.crew.ivo.modulate.a > 0.95, "With power, everyone is visible again")
	check(not mission.available_actions("ivo").has("light_left"), "No flashlight actions once the lights are on")
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
