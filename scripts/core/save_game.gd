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
		if parsed is Dictionary and parsed.get("snapshot") is Dictionary and _number(parsed.get("revision"), 9007199254740992.0) and parsed.get("dirty") is bool and (parsed.snapshot.is_empty() or compatible(parsed.snapshot) or _outdated(parsed.snapshot)):
			_record = parsed
			if _outdated(parsed.snapshot): _record["snapshot"] = {}  # an earlier story version: start fresh
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

## Escape checkpoints (schema 2). Mirrors server/save_games.py valid(): keep both in step.
func compatible(data) -> bool:
	if not data is Dictionary or data.get("schema") != 2 or data.get("map") != "escape-v2": return false
	if not data.get("state") is Dictionary or not data.get("player") is Dictionary or not data.get("crew") is Dictionary: return false
	var Rules = load("res://scripts/prototype/escape_state.gd")
	var state: Dictionary = data.state
	if not state.get("flags") is Dictionary or state.get("flags", {}).get("departed", false): return false
	for key in state.flags:
		if not key in Rules.FLAGS or not state.flags[key] is bool: return false
	if not state.get("carrying") in Rules.CARRY: return false
	if not _number(state.get("version"), 1000000) or not state.get("journal") is Array or state.journal.size() > 40: return false
	for line in state.journal:
		if not line is String or line.length() > 500: return false
	if not _strings(state.get("learned"), 80, 40) or not _strings(state.get("fails"), 5, 4): return false
	for f in state.fails:
		if not f in Rules.FAILS: return false
	if not _number(state.get("vitality"), 100) or not _number(state.get("selector"), 2): return false
	if not state.get("fuse_at_cabinet") in ["", "A", "B", "C"] or not state.get("fuse_task") in ["", "A", "B", "C"]: return false
	if not _puzzle(state.get("puzzle")): return false
	var promises = state.get("promises")
	if not promises is Dictionary or promises.size() > 4: return false
	for k in promises:
		if not k in ["stage3_dhan_question", "freezer_question"] or not promises[k] is String or promises[k].length() > 100: return false
	if not _strings(data.get("said"), 120, 60): return false
	if not _number(data.get("elapsed"), 31536000) or not data.get("flashlight") is bool or not _point(data.player.get("position")): return false
	var tasks := ["", "lift_locker", "stay_with_dhan", "fetch_fuse", "fetch_case", "lift_battery", "carry_dhan", "release_clamps", "hold_breaker"]
	if data.crew.size() != 2: return false
	for id in ["mara", "ivo"]:
		if not data.crew.get(id) is Dictionary: return false
		var actor: Dictionary = data.crew[id]
		if not _point(actor.get("position")) or not _point(actor.get("facing"), true): return false
		for field in ["following", "light_on", "cargo", "visible"]:
			if not actor.get(field) is bool: return false
		if not actor.get("task") in tasks or not actor.get("pose") in ["stand", "pinned", "straining", "sit", "carried", "dead"]: return false
		if not actor.get("path") is Array or actor.path.size() > 300: return false
		for point in actor.path:
			if not _point(point): return false
	if not data.get("history", {}) is Dictionary: return false
	for id in data.get("history", {}):
		if not id in ["mara", "ivo"]: return false
		var turns = data.history[id]
		if not turns is Array or turns.size() > 6: return false
		for turn in turns:
			if not turn is Dictionary or not turn.get("role") in ["player", "npc"] or not turn.get("text") is String or turn.text.length() > 420: return false
	if not data.get("memory_notes", {}) is Dictionary: return false
	for id in data.get("memory_notes", {}):
		if not id in ["mara", "ivo"]: return false
		var notes = data.memory_notes[id]
		if not notes is Array or notes.size() > 12: return false
		for note in notes:
			if not note is String or note.length() == 0 or note.length() > 120: return false
	return JSON.stringify(data).to_utf8_buffer().size() <= 24000

## A checkpoint from the earlier story (schema 1) can't be resumed; it's treated as no save.
func _outdated(snapshot) -> bool:
	return snapshot is Dictionary and snapshot.get("schema") == 1

func _strings(value, longest: int, most: int) -> bool:
	if not value is Array or value.size() > most: return false
	for item in value:
		if not item is String or item.length() == 0 or item.length() > longest: return false
	return true

## Per-run answers: a code from 3/6/9, each code and branch mapped to a distinct box/toggle.
func _puzzle(p) -> bool:
	if not p is Dictionary or not p.get("fuse_for") is Dictionary or not p.get("toggle_for") is Dictionary: return false
	if p.has("vials"):  # medbay vials (newer saves): three names, one of them the painkiller
		if not p.vials is Array or p.vials.size() != 3 or not p.get("painkiller") in [0, 1, 2, 0.0, 1.0, 2.0]: return false
		for v in p.vials:
			if not v is String or v.length() > 16: return false
	if not p.get("code") in [3, 6, 9, 3.0, 6.0, 9.0] or not p.get("aux") in [1, 2, 3, 1.0, 2.0, 3.0] or not p.get("selector") in [0, 1, 2, 0.0, 1.0, 2.0]: return false
	var boxes: Array = []
	for k in ["3", "6", "9"]:
		if not p.fuse_for.get(k) in ["A", "B", "C"] or boxes.has(p.fuse_for[k]): return false
		boxes.append(p.fuse_for[k])
	var toggles: Array = []
	for k in ["1", "2", "3"]:
		var t = p.toggle_for.get(k)
		if not t in [0, 1, 2, 0.0, 1.0, 2.0] or toggles.has(int(t)): return false
		toggles.append(int(t))
	return p.size() == (7 if p.has("vials") else 5) and p.fuse_for.size() == 3 and p.toggle_for.size() == 3

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

func delete_account(password: String) -> Dictionary:
	if busy or not Settings.is_logged_in(): return {"code": 0, "message": "Sign in and wait for the current request to finish."}
	busy = true
	var generation := _generation
	var local_path := _path()
	var result := await _api("/auth/delete", {"password": password, "confirm": true}, Settings.account_token)
	if generation != _generation: return {"code": 0, "message": "Account changed. Please try again."}
	busy = false
	if result.code == 200 and result.get("ok") == true:
		# Invalidate in-flight uploads before switching back to the guest slot.
		_generation += 1
		for path in [local_path, local_path + ".tmp"]:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		Settings.clear_account()
		status = "Account deleted. You can play as a guest or create a new account."
		changed.emit()
	return result

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
		if _outdated(remote): remote = null
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
	if _outdated(remote): remote = null
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
