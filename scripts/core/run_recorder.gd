extends Node
## Records each run on the server (Tiger Cloud database) and handles the optional
## leaderboard account. Owner: C. Lives in the main scene (group "run_recorder").
##
## Run:   PLAYING starts -> POST /runs/start -> events are logged locally ->
##        run_ended -> POST /runs/end (with the event log) -> `run_saved`.
##        The server times the run itself, so the result can't be faked.
## Account: everyone starts as a guest. register()/login() store a session token
##        in Settings and, after a guest win, claim that run for the leaderboard.
## If the server is unreachable, the game carries on; the panel just says offline.

signal run_saved(result: Dictionary)          # {} if the run couldn't be saved
signal leaderboard_loaded(entries: Array, me)  # me: {"username", "best"} or null
signal leaderboard_offline
signal auth_done(ok: bool, message: String)

const REQUEST_TIMEOUT := 10.0
const MAX_EVENTS := 300

var run_token := ""
## The server's answer to /runs/end ({} until then, or if it failed).
var last_result := {}
## Why /runs/end failed: the server's error code ("implausible", ...), "offline", or "".
var last_error := ""
## This device's own clock for the run, shown if the server's time is missing.
var local_seconds := 0.0
var events: Array = []

var _start_ms := 0
var _starting := false
var _ended := false
var _won := false
var _end_sent := false


func _ready() -> void:
	add_to_group("run_recorder")
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.game_event.connect(_on_game_event)
	GameState.room_changed.connect(_on_room_changed)
	GameState.run_ended.connect(_on_run_ended)


# --- Run lifecycle ---------------------------------------------------------------------

func _on_phase_changed(phase: int) -> void:
	if phase != GameState.Phase.PLAYING or _starting or run_token != "":
		return
	_starting = true
	_start_ms = Time.get_ticks_msec()
	var body := {"suit": Settings.skin, "client": "web" if OS.has_feature("web") else "desktop",
		"guest_id": Settings.guest_id}
	_call(HTTPClient.METHOD_POST, "/runs/start", body, _on_started)


func _on_started(code: int, data: Dictionary) -> void:
	_starting = false
	if code == 200 and typeof(data.get("run_token")) == TYPE_STRING:
		run_token = data["run_token"]
	if _ended and not _end_sent:
		_send_end()  # the run finished before the server answered


func _on_game_event(event_id: String) -> void:
	log_event(event_id)


func _on_room_changed(_room_id: String) -> void:
	log_event("enter_room")


## Time-stamped (seconds since the run started) for the events table.
func log_event(event_id: String) -> void:
	if event_id == "" or _ended or events.size() >= MAX_EVENTS:
		return
	events.append({
		"t": snappedf(maxf(0.0, (Time.get_ticks_msec() - _start_ms) / 1000.0), 0.01),
		"event": event_id,
		"room": GameState.current_room,
		"objective": GameState.current_objective_id(),
	})


func _on_run_ended(won: bool) -> void:
	_ended = true
	_won = won
	local_seconds = (Time.get_ticks_msec() - _start_ms) / 1000.0
	if run_token != "":
		_send_end()
	elif not _starting:
		last_error = "offline"  # never got a run from the server
		run_saved.emit({})
		refresh_leaderboard()


func build_end_body() -> Dictionary:
	var npc = get_tree().get_first_node_in_group("npc_client")
	return {
		"run_token": run_token,
		"outcome": "won" if _won else "lost",
		"time_left_s": snappedf(clampf(GameState.time_left, 0.0, 3600.0), 0.1),
		"debris_hits": GameState.hit_count,
		"boots_uses": GameState.boots_use_count,
		"npc_messages": npc.messages_sent if npc != null else 0,
		"objectives_done": GameState.objective_index,
		"events": events,
	}


func _send_end() -> void:
	if run_token == "":
		run_saved.emit({})
		return
	_end_sent = true
	_call(HTTPClient.METHOD_POST, "/runs/end", build_end_body(), func(code: int, data: Dictionary):
		last_result = data if code == 200 else {}
		last_error = "" if code == 200 else (str(data.get("error", "")) if code != 0 else "offline")
		run_saved.emit(last_result)
		refresh_leaderboard())


func refresh_leaderboard() -> void:
	_call(HTTPClient.METHOD_GET, "/leaderboard?limit=10", null, func(code: int, data: Dictionary):
		var entries = data.get("entries", [])
		if code != 200 or typeof(entries) != TYPE_ARRAY:
			leaderboard_offline.emit()
			return
		leaderboard_loaded.emit(entries, data.get("me")))


# --- Account ---------------------------------------------------------------------------

func register(username: String, password: String) -> void:
	_auth("/auth/register", username, password)


func login(username: String, password: String) -> void:
	_auth("/auth/login", username, password)


func _auth(path: String, username: String, password: String) -> void:
	var body := {"username": username.strip_edges(), "password": password}
	_call(HTTPClient.METHOD_POST, path, body, func(code: int, data: Dictionary):
		if code != 200 or typeof(data.get("token")) != TYPE_STRING:
			auth_done.emit(false, str(data.get("message", "Can't reach the leaderboard right now")))
			return
		Settings.set_account(str(data["username"]), str(data["token"]))
		if _can_claim():
			_claim()
		else:
			auth_done.emit(true, "")
			refresh_leaderboard())


## A guest win this session that the new account can take onto the leaderboard.
func _can_claim() -> bool:
	return _won and run_token != "" and not last_result.is_empty() \
		and not bool(last_result.get("saved_to_account", true))


func _claim() -> void:
	_call(HTTPClient.METHOD_POST, "/runs/claim", {"run_token": run_token}, func(code: int, data: Dictionary):
		if code == 200:
			last_result["saved_to_account"] = true
			last_result["best"] = data.get("best")
			auth_done.emit(true, "")
		else:
			auth_done.emit(true, str(data.get("message", "Logged in, but this run couldn't be saved")))
		refresh_leaderboard())


func logout() -> void:
	if Settings.is_logged_in():
		_call(HTTPClient.METHOD_POST, "/auth/logout", {}, func(_c: int, _d: Dictionary): pass)
	Settings.clear_account()
	auth_done.emit(true, "")
	refresh_leaderboard()


# --- HTTP ------------------------------------------------------------------------------

## One HTTPRequest per call (a node can only run one request at a time).
## `done` gets (http_code or 0 if unreachable, parsed JSON object or {}).
func _call(method: int, path: String, body, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray):
		http.queue_free()
		var data = null
		if result == HTTPRequest.RESULT_SUCCESS:
			data = JSON.parse_string(raw.get_string_from_utf8())
		done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data if typeof(data) == TYPE_DICTIONARY else {}))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if Settings.account_token != "":
		headers.append("Authorization: Bearer " + Settings.account_token)
	var err := http.request(Settings.backend_url() + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		http.queue_free()
		done.call(0, {})


static func format_time(seconds: float) -> String:
	var s := maxf(0.0, seconds)
	return "%d:%04.1f" % [int(s) / 60, fmod(s, 60.0)]
