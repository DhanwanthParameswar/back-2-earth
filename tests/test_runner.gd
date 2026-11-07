extends Node
## Headless checks for the shared contracts and one scripted full run.
## Owner: A. Run from the project folder:
##     godot --headless --path . res://tests/test_runner.tscn
## Exit code = number of failures (0 = all good). Takes about 5 seconds.

const GravityDirector = preload("res://scripts/core/gravity_director.gd")
const CompanionClient = preload("res://scripts/ai/companion_client.gd")
const MainScene = preload("res://scenes/main.tscn")

var _failures := 0
var _passes := 0


func _ready() -> void:
	print("\n=== Back2Earth tests ===")
	_test_objective_order()
	_test_launch_requires_everything()
	_test_damage_and_timer()
	_test_end_states_are_exclusive()
	_test_gravity_cycle()
	_test_companion_validation()
	_test_skin_assets()
	await _test_full_run()
	await _test_restart_resets()
	print("=== %d passed, %d failed ===\n" % [_passes, _failures])
	get_tree().quit(_failures)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  ", label)
	else:
		_failures += 1
		printerr("  FAIL  ", label)


func _fresh_playing_run() -> void:
	GameState.new_run()
	GameState.begin_play()


func _test_objective_order() -> void:
	print("Objective order")
	_fresh_playing_run()
	_check(GameState.current_objective_id() == "start_evacuation", "first objective is start_evacuation")
	_check(not GameState.complete_objective("restore_power"), "out-of-order completion is rejected")
	_check(GameState.objective_index == 0, "rejected completion changes nothing")
	_check(GameState.complete_objective("start_evacuation"), "current objective completes")
	var version: int = GameState.state_version
	_check(GameState.complete_objective("start_evacuation"), "repeat completion reports done (idempotent)")
	_check(GameState.objective_index == 1 and GameState.state_version == version, "repeat completion adds no progress")
	_check(GameState.is_timer_running(), "timer starts after evacuation begins")


func _test_launch_requires_everything() -> void:
	print("Launch requirements")
	_fresh_playing_run()
	for id in ["start_evacuation", "restore_power", "open_compartment", "collect_core"]:
		GameState.complete_objective(id)
	_check(GameState.has_item("navigation_core"), "collecting the core adds it to inventory")
	_check(not GameState.complete_objective("board_pod"), "cannot board before the clamp is released")
	_check(GameState.phase == GameState.Phase.PLAYING, "run continues after a refused launch")
	GameState.complete_objective("release_clamp")
	_check(GameState.complete_objective("board_pod"), "boarding works once everything is done")
	_check(GameState.phase == GameState.Phase.WON, "boarding wins the run")


func _test_damage_and_timer() -> void:
	print("Damage and timer")
	_fresh_playing_run()
	GameState.complete_objective("start_evacuation")
	var before: float = GameState.time_left
	_check(GameState.apply_debris_hit(), "first debris hit applies")
	_check(is_equal_approx(GameState.time_left, before - GameState.DEBRIS_PENALTY), "hit removes 10 seconds")
	_check(not GameState.apply_debris_hit(), "second hit inside the 1 s cooldown is ignored")
	GameState._process(GameState.HIT_COOLDOWN + 0.01)
	_check(GameState.apply_debris_hit(), "hit applies again after the cooldown")
	GameState._set_time(0.5)
	GameState._process(1.0)
	_check(GameState.phase == GameState.Phase.LOST, "reaching zero loses the run")


func _test_end_states_are_exclusive() -> void:
	print("End states")
	_fresh_playing_run()
	for id in ["start_evacuation", "restore_power", "open_compartment", "collect_core", "release_clamp", "board_pod"]:
		GameState.complete_objective(id)
	_check(GameState.phase == GameState.Phase.WON, "won")
	var t: float = GameState.time_left
	_check(not GameState.apply_debris_hit() and GameState.time_left == t, "no damage after the run ends")
	GameState._set_time(0.0)
	_check(GameState.phase == GameState.Phase.WON, "timer expiry after winning can't flip to lost")
	GameState.complete_objective("board_pod")
	_check(GameState.phase == GameState.Phase.WON, "launch after the end changes nothing")


func _test_gravity_cycle() -> void:
	print("Gravity cycle")
	var d = GravityDirector.new()
	add_child(d)
	_check(d.state == GravityDirector.State.CALM, "starts calm")
	d.advance(GravityDirector.FIRST_CALM_TIME + 0.01)
	_check(d.state == GravityDirector.State.WARNING and d.next_direction() == Vector2.DOWN, "warning comes first, DOWN")
	_check(d.get_drift(false) == Vector2.ZERO, "no drift during warning")
	d.advance(GravityDirector.WARNING_TIME)
	_check(d.state == GravityDirector.State.PULL, "pull after 3 s warning")
	_check(d.get_drift(false) == Vector2.DOWN * 90.0, "unbraced drift 90 px/s")
	_check(d.get_drift(true) == Vector2.DOWN * 18.0, "braced drift 18 px/s")
	d.advance(GravityDirector.PULL_TIME)
	_check(d.state == GravityDirector.State.CALM and d.next_direction() == Vector2.UP, "calm after 6 s pull, next is UP")
	d.advance(GravityDirector.CALM_TIME + GravityDirector.WARNING_TIME)
	_check(d.is_pulling() and d.current_direction == Vector2.UP, "second pull is UP (16 s cycle)")
	d.queue_free()


func _test_companion_validation() -> void:
	print("Companion response validation")
	var ok := {"run_id": 7, "state_version": 2, "event_id": "help#1", "line": "Brace, please."}
	_check(CompanionClient.validate_response(ok, 7, 2, "help#1") == "Brace, please.", "valid reply accepted")
	var floats := {"run_id": 7.0, "state_version": 2.0, "event_id": "help#1", "line": "Fine."}
	_check(CompanionClient.validate_response(floats, 7, 2, "help#1") == "Fine.", "JSON float ids accepted")
	_check(CompanionClient.validate_response(ok, 8, 2, "help#1") == "", "other run rejected (stale)")
	_check(CompanionClient.validate_response(ok, 7, 3, "help#1") == "", "other state_version rejected (stale)")
	_check(CompanionClient.validate_response(ok, 7, 2, "help#2") == "", "other event rejected")
	_check(CompanionClient.validate_response({"run_id": 7}, 7, 2, "help#1") == "", "missing fields rejected")
	_check(CompanionClient.validate_response("nope", 7, 2, "help#1") == "", "non-object rejected")
	var long_line := {"run_id": 7, "state_version": 2, "event_id": "help#1", "line": "x".repeat(181)}
	_check(CompanionClient.validate_response(long_line, 7, 2, "help#1") == "", "lines over 180 chars rejected")
	var wrong_type := {"run_id": 7, "state_version": 2, "event_id": "help#1", "line": 42}
	_check(CompanionClient.validate_response(wrong_type, 7, 2, "help#1") == "", "non-string line rejected")
	_check(CompanionClient.sanitize("[b]**Hi**[/b] <i>there</i>") == "Hi there", "markup stripped")


func _test_skin_assets() -> void:
	print("Suit art")
	for skin in Settings.SKINS:
		var sheet_path: String = Settings.skin_sheet_path(skin["id"])
		var portrait_path: String = Settings.skin_portrait_path(skin["id"])
		var ok := ResourceLoader.exists(sheet_path) and ResourceLoader.exists(portrait_path)
		_check(ok, "%s has a walk sheet and a portrait" % skin["id"])
		if ok:
			var sheet: Texture2D = load(sheet_path)
			_check(sheet.get_width() % 6 == 0, "%s walk sheet splits into 6 frames" % skin["id"])


func _test_full_run() -> void:
	print("Scripted full run (main scene)")
	var main = MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	GameState.begin_play()
	var player = get_tree().get_first_node_in_group("player")
	var ship = get_tree().get_first_node_in_group("ship")
	var director = get_tree().get_first_node_in_group("gravity_director")
	_check(player != null and ship != null and director != null, "main scene builds player, ship, gravity")
	if player == null or ship == null or director == null:
		main.queue_free()
		return
	_check(ship.y_sort_enabled and player.get_parent() == ship, "player is y-sorted inside the ship (3/4 view)")
	var views := get_tree().get_nodes_in_group("space_window")
	_check(ship.space_windows.size() >= 1 and views.size() == ship.space_windows.size(), "each W window gets a video view")
	var original_skin: String = Settings.skin
	Settings.set_skin("nebula")
	_check(player.get_node("Sprite2D").texture.resource_path.ends_with("astronaut_nebula.png"), "choosing a suit re-skins the player")
	Settings.set_skin(original_skin)

	_check(not ship.get_node("Door_1").is_open, "cockpit door starts closed")
	ship.get_node("Console_start_evacuation").interact(player)
	await get_tree().process_frame
	_check(ship.get_node("Door_1").is_open, "terminal opens the cockpit door")
	ship.get_node("Console_restore_power").interact(player)

	# Force a long DOWN pull so the sled slides onto the plate.
	director.state = GravityDirector.State.PULL
	director.current_direction = Vector2.DOWN
	director.time_in_state_left = 100.0
	var sled = ship.get_node("CargoSled")
	for i in 60:  # ~3 s of physics at most
		await get_tree().physics_frame
		await get_tree().create_timer(0.05).timeout
		if sled.latched:
			break
	_check(sled.latched, "DOWN pull slides the powered sled onto the plate")
	_check(GameState.is_objective_complete("open_compartment"), "plate opens the core compartment")
	_check(ship.get_node("Door_K").is_open, "compartment door is open")

	ship.get_node("NavigationCore").interact(player)
	ship.get_node("Console_release_clamp").interact(player)
	_check(ship.get_node("Door_3").is_open, "pod bay door opens after taking the core")
	var pod = ship.get_node("EscapePod")
	_check(pod.can_interact(player), "pod offers boarding once clamp is released")
	pod.interact(player)
	_check(GameState.phase == GameState.Phase.WON, "boarding the pod wins")
	main.queue_free()
	await get_tree().process_frame


func _test_restart_resets() -> void:
	print("Restart resets")
	var seen_ids := []
	for i in 3:
		var main = MainScene.instantiate()
		add_child(main)
		await get_tree().process_frame
		var ship = get_tree().get_first_node_in_group("ship")
		var ok: bool = GameState.phase == GameState.Phase.BRIEFING \
			and GameState.objective_index == 0 \
			and is_equal_approx(GameState.time_left, GameState.START_TIME) \
			and GameState.inventory.is_empty() \
			and not ship.get_node("Door_1").is_open \
			and not ship.get_node("CargoSled").latched
		_check(ok, "restart %d returns to the same initial state" % (i + 1))
		seen_ids.append(GameState.run_id)
		main.queue_free()
		await get_tree().process_frame
	_check(seen_ids[0] != seen_ids[1] and seen_ids[1] != seen_ids[2], "each restart gets a new run_id")
