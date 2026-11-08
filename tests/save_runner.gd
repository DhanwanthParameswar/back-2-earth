extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("_run")
func mission():
	var node = load("res://scripts/prototype/escape_mission.gd").new()
	root.add_child(node)
	return node
func _run() -> void:
	var saves = root.get_node("SaveGame")
	var settings = root.get_node("Settings")
	saves.network_enabled = false
	saves.enabled = false
	saves.storage_dir = "/private/tmp/back2earth-save-tests-" + str(Time.get_ticks_usec())
	settings.account_name = ""
	settings.account_token = ""
	saves._profile = ""
	saves._profile_changed()
	settings.intro_pending = false
	var first = mission()
	await process_frame
	await process_frame
	first.ui.radio.live_enabled = false
	first.crew.mara.position = first.anchor("locker_hold")
	first.perform("help_locker")
	first.perform("push_locker")
	await create_timer(0.9).timeout
	for action in ["assess", "choose_engineering", "isolate", "take_fuse"]: first.perform(action)
	first.player.position = first.anchor("locker_push")
	first.elapsed = 123.0
	first.crew.mara.light_on = true
	first.crew.mara.facing = Vector2.UP
	first.darkness.flashlight = true
	first.ui.radio.histories.mara = [{"role": "player", "text": "Help me"}, {"role": "npc", "text": "On my way"}]
	first.active = false
	var snapshot: Dictionary = first.progress_snapshot()
	check(saves.compatible(snapshot), "Real mission produces a compatible checkpoint")
	saves.enabled = true
	check(saves.store(snapshot), "Checkpoint writes successfully")
	var saved_file := FileAccess.open("/private/tmp/back2earth-real-checkpoint.json", FileAccess.WRITE)
	saved_file.store_string(JSON.stringify(snapshot))
	saved_file.close()
	saves._profile = ""
	saves._profile_changed()
	check(saves.has_progress(), "Checkpoint survives a fresh load from disk")
	saves.request_resume()
	first._save_ready = false
	first.queue_free()
	await process_frame
	var resumed = mission()
	await process_frame
	await process_frame
	check(resumed._resumed and resumed.active and resumed._intro == null, "Resume enters gameplay and skips the intro")
	check(resumed.state.carrying == "fuse" and resumed.state.route == "engineering", "Route and carried item restored")
	check(resumed.state.has_flag("locker_clear") and resumed.locker_visual.rotation < -1.5, "Cleared locker geometry restored")
	check(resumed.state.has_flag("isolated"), "Progress flags restored")
	check(absf(resumed.elapsed - 123.0) < 1, "Elapsed mission time restored")
	check(resumed.player.position.distance_to(Vector2(snapshot.player.position[0], snapshot.player.position[1])) < 1, "Player position restored")
	check(resumed.crew.mara.light_on and resumed.darkness.flashlight, "Flashlights restored")
	check(resumed.ui.radio.histories.mara.size() == 2, "Recent crew conversation restored")
	resumed.active = false
	resumed._save_ready = false
	resumed.queue_free()
	await process_frame
	settings.account_name = "TestAlice"
	settings.account_token = "test-not-a-real-token"
	saves._profile_changed()
	check(not saves.has_progress(), "Guest progress is isolated from signed-in accounts")
	check(saves.store(snapshot), "Account checkpoint stored locally while offline")
	settings.account_name = "TestBob"
	saves._profile_changed()
	check(not saves.has_progress(), "Other accounts cannot see Alice's checkpoint")
	settings.account_name = "TestAlice"
	saves._profile_changed()
	check(saves.has_progress(), "Switching back restores the correct account slot")
	check(not FileAccess.get_file_as_string(saves._path()).contains("test-not-a-real-token"), "Credentials are never written into checkpoints")
	check(saves.delete_progress() and not saves.has_progress(), "Delete removes the resume slot")
	saves._profile = ""
	saves._profile_changed()
	check(not saves.has_progress() and saves._record.dirty, "Deletion tombstone survives restart for later cloud sync")
	var corrupt := snapshot.duplicate(true)
	corrupt.crew.mara.position = ["bad", 3]
	check(not saves.compatible(corrupt), "Corrupt actor coordinates rejected")
	saves.enabled = false
	settings.account_name = ""
	settings.account_token = ""
	saves._profile_changed()
	await _test_crew_tasks(snapshot)
	print("SAVES: %d checks, %d failures" % [checks, failures])
	quit(failures)
func _test_crew_tasks(base: Dictionary) -> void:
	var saves = root.get_node("SaveGame")
	var task_save := base.duplicate(true)
	task_save.state.flags = {"locker_clear": true, "assessed": true, "case_requested": true}
	task_save.state.carrying = ""
	task_save.crew.ivo.task = "fetch_case"
	task_save.crew.ivo.cargo = true
	saves._record.snapshot = task_save
	saves.resume_pending = true
	var restored = mission()
	await process_frame
	await process_frame
	for i in 1000:
		if restored.state.has_flag("case_arrived"): break
		restored.crew.ivo._process(0.1)
	check(restored.state.has_flag("case_arrived"), "In-flight case delivery resumes and completes after loading")
	check(not restored._busy_actors.has("ivo") and not restored.crew.ivo.cargo.visible, "Crew task unlocks after restored delivery")
	restored._save_ready = false
	restored.queue_free()
	await process_frame
