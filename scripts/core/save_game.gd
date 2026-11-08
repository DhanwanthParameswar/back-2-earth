extends Node
## Per-profile, crash-safe local checkpoint plus authenticated cloud sync.
signal changed
var enabled := true
var network_enabled := true
var storage_dir := "user://"
var status := ""
var resume_pending := false
var conflict := false
var busy := false
var _profile := ""
var _record: Dictionary = {}
var _generation := 0
var _syncing := false
var _sequence := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("B2E_SAVE_DIR") != "": storage_dir = OS.get_environment("B2E_SAVE_DIR")
	network_enabled = OS.get_environment("B2E_SAVE_NETWORK") != "0"
	Settings.changed.connect(_profile_changed)
	_profile_changed()
	var retry := Timer.new()
	retry.wait_time = 15.0
	retry.timeout.connect(_sync)
	add_child(retry)
	retry.start()

func _identity() -> String:
	return "account_" + Settings.account_name.to_lower().sha256_text() if Settings.is_logged_in() else "guest_" + Settings.guest_id

func _path() -> String:
	return storage_dir.path_join(_profile + ".json")

func _profile_changed() -> void:
	if _profile == _identity(): return
	_generation += 1
	_profile = _identity()
	_record = {"revision": 0, "snapshot": {}, "dirty": false, "saved_at": 0}
	resume_pending = false
	conflict = false
	status = ""
	busy = false
	_syncing = false
	if FileAccess.file_exists(_path()):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(_path()))
		if parsed is Dictionary and parsed.get("snapshot") is Dictionary and _number(parsed.get("revision"), 9007199254740992.0) and parsed.get("dirty") is bool and (parsed.snapshot.is_empty() or compatible(parsed.snapshot)):
			_record = parsed
		else:
			status = "This device's save could not be read. Your cloud save may still be available."
	changed.emit()

func _number(value, high: float) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0 and value <= high

func _point(value, direction := false) -> bool:
	if not value is Array or value.size() != 2: return false
	for item in value:
		if not typeof(item) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)): return false
		if item < (-1 if direction else 0) or item > (1 if direction else 10000): return false
	return true

func compatible(data) -> bool:
	if not data is Dictionary or data.get("schema") != 1 or data.get("map") != "escape-v1": return false
	if not data.get("state") is Dictionary or not data.get("player") is Dictionary or not data.get("crew") is Dictionary: return false
	var state: Dictionary = data.state
	if not state.get("flags") is Dictionary or state.get("flags", {}).get("departed", false): return false
	var allowed := "locker_ready locker_clear assessed isolated fuse_taken fuse_installed fault_found aux_off engineering_power case_requested case_arrived samples_saved battery_out battery_loaded battery_taken battery_connected clamps departed".split(" ")
	for key in state.flags:
		if not key in allowed or not state.flags[key] is bool: return false
	if not state.get("route") in ["", "engineering", "battery"] or not state.get("carrying") in ["", "fuse", "battery cart"]: return false
	if not _number(state.get("version"), 1000000) or not state.get("journal") is Array or state.journal.size() > 40: return false
	for line in state.journal:
		if not line is String or line.length() > 500: return false
	if not _number(data.get("elapsed"), 31536000) or not data.get("flashlight") is bool or not _point(data.player.get("position")): return false
	for id in ["mara", "ivo"]:
		if not data.crew.get(id) is Dictionary: return false
		var actor: Dictionary = data.crew[id]
		if not _point(actor.get("position")) or not _point(actor.get("facing"), true): return false
		for field in ["following", "light_on", "cargo"]:
			if not actor.get(field) is bool: return false
		if not actor.get("task") in ["", "help_locker", "load_battery", "fetch_case"]: return false
		if not actor.get("path") is Array or actor.path.size() > 300: return false
		for point in actor.path:
			if not _point(point): return false
	if not data.get("history", {}) is Dictionary: return false
	for turns in data.get("history", {}).values():
		if not turns is Array or turns.size() > 6: return false
		for turn in turns:
			if not turn is Dictionary or not turn.get("role") in ["player", "npc"] or not turn.get("text") is String or turn.text.length() > 420: return false
	return JSON.stringify(data).to_utf8_buffer().size() <= 24000

func has_progress() -> bool:
	return compatible(_record.get("snapshot", {}))

func checkpoint() -> Dictionary:
	return _record.get("snapshot", {}).duplicate(true)

func request_resume() -> void:
	resume_pending = has_progress()

func take_resume() -> Dictionary:
	var result := checkpoint() if resume_pending else {}
	resume_pending = false
	return result

func _write_local() -> bool:
	DirAccess.make_dir_recursive_absolute(storage_dir)
	var file := FileAccess.open(_path() + ".tmp", FileAccess.WRITE)
	if file == null:
		status = "Could not save on this device. Check available storage."
		changed.emit()
		return false
	file.store_string(JSON.stringify(_record))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(_path() + ".tmp", _path()) != OK:
		status = "Could not finish saving on this device."
		changed.emit()
		return false
	return true

func store(snapshot: Dictionary) -> bool:
	if not enabled or not compatible(snapshot): return false
	_record["snapshot"] = snapshot.duplicate(true)
	_record["saved_at"] = int(Time.get_unix_time_from_system())
	_record["dirty"] = Settings.is_logged_in()
	_sequence += 1
	var written := _write_local()
	if written:
		status = "Cloud save changed. Choose which save to keep on the start menu." if conflict else ("Saved on this device. Syncing…" if Settings.is_logged_in() else "Saved on this device.")
		changed.emit()
		_sync.call_deferred()
	return written

func delete_progress() -> bool:
	if not enabled: return false
	var previous := _record.duplicate(true)
	_record["snapshot"] = {}
	_record["dirty"] = Settings.is_logged_in()
	_record["saved_at"] = 0
	resume_pending = false
	_sequence += 1
	var written := _write_local()
	if not written:
		_record = previous
		changed.emit()
	if written:
		status = "Save deleted on this device. Syncing…" if Settings.is_logged_in() else "Save deleted."
		changed.emit()
		_sync.call_deferred()
	return written

func _api(path: String, data = null, token := "") -> Dictionary:
	if not network_enabled: return {"code": 0, "message": "Offline. Progress is saved on this device."}
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "": headers.append("Authorization: Bearer " + token)
	var method := HTTPClient.METHOD_GET if data == null else HTTPClient.METHOD_POST
	var error := request.request(Settings.backend_url() + path, headers, method, "" if data == null else JSON.stringify(data))
	if error != OK:
		request.queue_free()
		return {"code": 0, "message": "Could not connect. Progress is saved on this device."}
	var response: Array = await request.request_completed
	request.queue_free()
	var body = JSON.parse_string(response[3].get_string_from_utf8())
	var result: Dictionary = body if body is Dictionary else {}
	result["code"] = int(response[1]) if response[0] == HTTPRequest.RESULT_SUCCESS else 0
	return result

func authenticate(mode: String, username: String, password: String) -> Dictionary:
	if busy: return {"code": 0, "message": "Please wait for the current request."}
	busy = true
	var result := await _api("/auth/" + mode, {"username": username.strip_edges(), "password": password})
	busy = false
	if result.code == 200:
		if not result.get("token") is String or not result.get("username") is String or result.token == "":
			return {"code": 502, "message": "Account service returned an invalid response."}
		Settings.set_account(result.username, result.token)
		await refresh_cloud()
	return result

func sign_out() -> void:
	var token := Settings.account_token
	Settings.clear_account()  # separate local slots prevent one account seeing another's save
	status = "Signed out. Guest progress stays on this device."
	changed.emit()
	await _api("/auth/logout", {}, token)

func refresh_cloud() -> void:
	if not enabled or not Settings.is_logged_in() or _syncing or busy: return
	busy = true
	status = "Checking cloud save…"
	changed.emit()
	var generation := _generation
	var result := await _api("/save", null, Settings.account_token)
	if generation != _generation: return
	busy = false
	if result.code == 401:
		status = "Your session expired. Sign in again; your local save is safe."
	elif result.code == 200 and _number(result.get("revision"), 9007199254740992.0):
		var remote = result.get("snapshot")
		if remote == null or compatible(remote):
			if _record.get("dirty", false):
				if (remote if remote is Dictionary else {}) == checkpoint():
					_record["revision"] = int(result.revision)
					_record["dirty"] = false
					conflict = false
					_write_local()
					status = "Cloud save up to date."
				else:
					conflict = int(result.revision) != int(_record.get("revision", 0))
					status = "Cloud progress changed on another device. Choose which save to keep." if conflict else "Syncing local progress…"
			else:
				_record = {"revision": int(result.revision), "snapshot": remote if remote is Dictionary else {}, "dirty": false, "saved_at": int(result.get("updated_at", 0)) if result.get("updated_at") != null else 0}
				conflict = false
				_write_local()
				status = "Cloud save up to date."
		else: status = "Cloud save is incompatible with this version. Local progress is safe."
	else:
		status = "Cloud save unavailable. Local progress is safe; sync will retry."
	changed.emit()
	if not conflict: _sync.call_deferred()

func resolve_conflict(use_cloud: bool) -> void:
	if busy or _syncing: return
	busy = true
	changed.emit()
	var generation := _generation
	var result := await _api("/save", null, Settings.account_token)
	if generation != _generation: return
	busy = false
	if result.code != 200 or not _number(result.get("revision"), 9007199254740992.0):
		status = "Could not load the cloud save. Local progress is safe."
		changed.emit()
		return
	var remote = result.get("snapshot")
	if remote != null and not compatible(remote):
		status = "Cloud save is incompatible. Local progress is safe."
		changed.emit()
		return
	_record["revision"] = int(result.revision)
	if use_cloud:
		_record["snapshot"] = remote if remote is Dictionary else {}
		_record["dirty"] = false
		_record["saved_at"] = int(result.get("updated_at", 0)) if result.get("updated_at") != null else 0
	conflict = false
	_sequence += 1
	_write_local()
	status = "Cloud save selected." if use_cloud else "Local save selected. Syncing…"
	changed.emit()
	_sync.call_deferred()

func _sync() -> void:
	if not enabled or not network_enabled or _syncing or busy or conflict or not Settings.is_logged_in() or not _record.get("dirty", false): return
	_syncing = true
	var generation := _generation
	var sequence := _sequence
	var data := checkpoint()
	var path := "/save/delete" if data.is_empty() else "/save"
	var result := await _api(path, {"snapshot": data, "revision": int(_record.get("revision", 0))}, Settings.account_token)
	if generation != _generation: return
	_syncing = false
	var succeeded: bool = result.code == 200 and _number(result.get("revision"), 9007199254740992.0)
	if succeeded:
		_record["revision"] = int(result.revision)
		if sequence == _sequence: _record["dirty"] = false
		_write_local()
		status = "Progress saved to your account." if has_progress() else "Save deleted."
	elif result.code == 409:
		# A successful write with a lost response can also cause a conflict.
		# Fetching recognizes identical progress without making the player choose.
		await refresh_cloud()
		return
	elif result.code == 401:
		status = "Session expired. Sign in again to sync. Local progress is safe."
	else: status = "Saved on this device. Cloud sync pending."
	changed.emit()
	if succeeded and _record.get("dirty", false): _sync.call_deferred()

func guest_checkpoint() -> Dictionary:
	var path := storage_dir.path_join("guest_" + Settings.guest_id + ".json")
	if not FileAccess.file_exists(path): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed.snapshot.duplicate(true) if parsed is Dictionary and compatible(parsed.get("snapshot")) else {}

func import_guest() -> void:
	if Settings.is_logged_in() and not has_progress():
		var guest := guest_checkpoint()
		if not guest.is_empty(): store(guest)
