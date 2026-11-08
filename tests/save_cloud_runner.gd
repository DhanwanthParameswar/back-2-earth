extends SceneTree
## Run against the in-memory API test server, with B2E_BACKEND set to localhost.
var failures := 0
var checks := 0
var saves
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("_run")
func _synced() -> void:
	var until := Time.get_ticks_msec() + 6000
	while saves._syncing or saves._record.get("dirty", false):
		if saves.conflict or Time.get_ticks_msec() > until: break
		await create_timer(0.02).timeout
func _run() -> void:
	saves = root.get_node("SaveGame")
	var settings = root.get_node("Settings")
	settings.clear_account()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/private/tmp/back2earth-real-checkpoint.json"))
	var name := "Save" + Crypto.new().generate_random_bytes(4).hex_encode()
	var auth: Dictionary = await saves.authenticate("register", name, "test-password-123")
	check(auth.code == 200 and settings.is_logged_in(), "Sign up creates a session through the client")
	check(saves.store(data), "Authenticated checkpoint is written locally")
	await _synced()
	check(not saves._record.dirty and saves._record.revision == 1, "Autosave syncs to the account")
	var duplicate: Dictionary = await saves._api("/save", {"snapshot": data, "revision": int(saves._record.revision)}, settings.account_token)
	check(duplicate.code == 200, "Simulate an acknowledged-lost duplicate write")
	saves.store(data)
	await _synced()
	check(not saves.conflict and not saves._record.dirty, "Identical cloud progress recovers a lost acknowledgement without a conflict prompt")
	await saves.sign_out()
	auth = await saves.authenticate("login", name, "wrong-password")
	check(auth.code == 401 and not settings.is_logged_in(), "Incorrect password cannot open an account")
	auth = await saves.authenticate("login", name, "test-password-123")
	check(auth.code == 200 and saves.has_progress(), "Sign in loads the saved mission")
	check(saves.checkpoint().memory_notes.mara == data.memory_notes.mara, "Crew memories travel with the account's cloud checkpoint")
	var competing: Dictionary = data.duplicate(true)
	competing.elapsed = 444
	competing.memory_notes.mara = ["A different device's saved memory"]
	var remote: Dictionary = await saves._api("/save", {"snapshot": competing, "revision": int(saves._record.revision)}, settings.account_token)
	check(remote.code == 200, "Another device updates the cloud checkpoint")
	saves.store(data)
	await _synced()
	check(saves.conflict and saves.checkpoint().elapsed != 444, "Stale autosave preserves local progress instead of overwriting cloud")
	await saves.resolve_conflict(true)
	check(not saves.conflict and saves.checkpoint().elapsed == 444, "Choosing cloud loads the other device's progress")
	check(saves.checkpoint().memory_notes.mara == competing.memory_notes.mara, "Conflict resolution selects progress and crew memory as one save")
	# Delete while a deliberately slow upload is in flight: final cloud state must be deleted.
	saves.store(data)
	saves._sync()
	saves.delete_progress()
	await _synced()
	remote = await saves._api("/save", null, settings.account_token)
	check(remote.code == 200 and remote.snapshot == null and not saves.has_progress(), "Deleting during an upload cannot resurrect a save")
	saves.store(data)
	await _synced()
	saves.network_enabled = false
	saves.delete_progress()
	check(saves._record.dirty and not saves.has_progress(), "Offline deletion is remembered locally")
	saves.network_enabled = true
	await saves.refresh_cloud()
	await _synced()
	remote = await saves._api("/save", null, settings.account_token)
	check(remote.snapshot == null, "Offline deletion syncs on reconnection")
	await saves.sign_out()
	auth = await saves.authenticate("register", name + "B", "test-password-123")
	check(auth.code == 200 and not saves.has_progress(), "A second account starts with a separate empty slot")
	await saves.sign_out()
	print("CLOUD CLIENT: %d checks, %d failures" % [checks, failures])
	quit(failures)
