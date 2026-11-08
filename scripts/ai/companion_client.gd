extends Node
## ECHO, the damaged ship AI. Owner: C (companion/backend).
##
## Two text channels, never mixed:
##   1. Canonical objective + hint: GameState.get_canonical() — the rules.
##   2. ECHO's reaction line: this node. Flavor only. It can't open doors,
##      change timers, invent objectives, or grant items.
##
## Flow: GameState.game_event -> snapshot -> POST /companion (3 s timeout)
##       -> validate -> show live line, or show the authored fallback.
## One request in flight, 15 s cooldown, max 12 per run, repeated events
## coalesced, pending replies dropped on objective change/pause/game over,
## late or mismatched replies discarded. Gameplay never waits on this.

## source is "live" (model), "mock" (server in mock mode), or "offline"
## (authored fallback). The HUD labels each line honestly from this.
signal line_shown(text: String, source: String, event_kind: String)
## "live", "mock", or "offline" — from the most recent request outcome.
signal status_changed(status: String)
signal help_requested

const FALLBACK_PATH := "res://data/dialogue_fallbacks.json"
const REQUEST_TIMEOUT := 3.0
const REQUEST_COOLDOWN := 15.0
const MAX_REQUESTS_PER_RUN := 12
const COALESCE_WINDOW := 10.0
const MAX_LINE_LENGTH := 180

## Events ECHO reacts to. A single debris hit is silent; repeats are not.
const REACT_EVENTS := [
	"run_start", "evacuation_started", "power_restored", "puzzle_solved",
	"core_collected", "clamp_released", "launch", "debris_hit_repeat",
	"boots_frequent", "low_time", "help",
]

## Used only if data/dialogue_fallbacks.json is missing from a build.
const DEFAULT_FALLBACKS := {
	"run_start": ["ECHO online. Mostly. Emergency power first: use the terminal and we can leave this black hole behind."],
	"evacuation_started": ["Emergency power on. The evacuation clock is running. Engineering next."],
	"power_restored": ["Power restored. The cargo sled is awake, unlike my optimism."],
	"puzzle_solved": ["Navigation recovered. I am choosing to interpret that as optimism."],
	"core_collected": ["Core secured. The pod bay is open."],
	"clamp_released": ["Clamp released. Get in the pod."],
	"launch": ["Course set for Earth. Please remember the stars from somewhere safer."],
	"debris_hit_repeat": ["Your suit has filed another complaint. Watch the red arrow and keep clear of the junk."],
	"boots_frequent": ["You and those boots. A lasting relationship."],
	"low_time": ["Under a minute. I would run, if I had legs."],
	"help": ["Follow the objective at the top of your screen. I believe in you. Statistically."],
}

var status := "offline"
var requests_this_run := 0

var _http: HTTPRequest
var _pending := {}          # empty when nothing is in flight
var _event_counter := 0
var _clock := 0.0           # pauses with the game
var _last_request_time := -1000.0
var _last_event_time := {}
var _fallbacks := {}
var _fallback_index := {}


func _ready() -> void:
	add_to_group("companion")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_load_fallbacks()

	GameState.game_event.connect(_on_game_event)
	GameState.objective_changed.connect(_on_objective_changed)
	GameState.paused_changed.connect(_on_paused_changed)
	GameState.run_ended.connect(_on_run_ended)


func _process(delta: float) -> void:
	_clock += delta
	# Belt and braces: never let a request outlive the timeout.
	if not _pending.is_empty() and _clock - float(_pending["sent_at"]) > REQUEST_TIMEOUT + 0.25:
		var kind: String = _pending["kind"]
		invalidate_pending()
		_set_status("offline")
		_show_fallback(kind)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help") and not event.is_echo() and GameState.is_playing():
		help_requested.emit()
		GameState.request_help()  # comes back to us as the "help" game event
		get_viewport().set_input_as_handled()


# --- Events -------------------------------------------------------------------

func _on_game_event(kind: String) -> void:
	if not REACT_EVENTS.has(kind):
		return
	if kind != "help" and _last_event_time.has(kind) \
			and _clock - float(_last_event_time[kind]) < COALESCE_WINDOW:
		return  # coalesce repeats
	_last_event_time[kind] = _clock

	# The launch line belongs to the ending; never wait on the network for it.
	if kind == "launch" or not GameState.is_playing():
		_show_fallback(kind)
		return
	if can_request():
		_send(kind)
	else:
		_show_fallback(kind)


func can_request() -> bool:
	return (
		Settings.companion_enabled
		and Settings.companion_url != ""
		and _pending.is_empty()
		and requests_this_run < MAX_REQUESTS_PER_RUN
		and _clock - _last_request_time >= REQUEST_COOLDOWN
	)


func build_snapshot(kind: String, event_id: String) -> Dictionary:
	var canonical: Dictionary = GameState.get_canonical()
	return {
		"run_id": GameState.run_id,
		"state_version": GameState.state_version,
		"event_id": event_id,
		"room_id": GameState.current_room,
		"objective_id": canonical["id"],
		"time_band": GameState.time_band(),
		"inventory": GameState.inventory.duplicate(),
		"recent_event": kind,
		"boots_use_count": GameState.boots_use_count,
		"canonical_hint": canonical["hint"],
	}


func _send(kind: String) -> void:
	_event_counter += 1
	var event_id := "%s#%d" % [kind, _event_counter]
	var snapshot := build_snapshot(kind, event_id)
	var err := _http.request(
		Settings.companion_url,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(snapshot)
	)
	if err != OK:
		_set_status("offline")
		_show_fallback(kind)
		return
	requests_this_run += 1
	_last_request_time = _clock
	_pending = {
		"kind": kind,
		"event_id": event_id,
		"run_id": GameState.run_id,
		"state_version": GameState.state_version,
		"sent_at": _clock,
	}


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _pending.is_empty():
		return  # invalidated while in flight: drop it
	var pending := _pending
	_pending = {}
	var kind: String = pending["kind"]

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_set_status("offline")
		_show_fallback(kind)
		return

	var data = JSON.parse_string(body.get_string_from_utf8())
	var line := validate_response(data, int(pending["run_id"]), int(pending["state_version"]), str(pending["event_id"]))
	if line == "":
		_set_status("offline")
		_show_fallback(kind)
		return

	# Stale check against the game as it is NOW.
	if int(pending["run_id"]) != GameState.run_id \
			or int(pending["state_version"]) != GameState.state_version \
			or not GameState.is_playing():
		return
	# The server says whether the line came from the model or its mock mode.
	var source := "mock" if str(data.get("source", "")) == "mock" else "live"
	_set_status(source)
	line_shown.emit(line, source, kind)


## Drop any request in flight (restart, objective change, pause, game over).
func invalidate_pending() -> void:
	if _pending.is_empty():
		return
	_pending = {}
	_http.cancel_request()


func _on_objective_changed(_id: String) -> void:
	invalidate_pending()


func _on_paused_changed(is_paused: bool) -> void:
	if is_paused:
		invalidate_pending()


func _on_run_ended(_won: bool) -> void:
	invalidate_pending()


# --- Validation (pure; covered by tests/test_runner.gd) ---------------------------

## Returns the cleaned line, or "" if the response must be rejected.
static func validate_response(data, run_id: int, state_version: int, event_id: String) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	for key in ["run_id", "state_version", "event_id", "line"]:
		if not data.has(key):
			return ""
	if not _is_whole_number(data["run_id"]) or int(data["run_id"]) != run_id:
		return ""
	if not _is_whole_number(data["state_version"]) or int(data["state_version"]) != state_version:
		return ""
	if typeof(data["event_id"]) != TYPE_STRING or data["event_id"] != event_id:
		return ""
	if typeof(data["line"]) != TYPE_STRING:
		return ""
	var line := sanitize(data["line"])
	if line.is_empty() or line.length() > MAX_LINE_LENGTH:
		return ""
	return line


## Strip markup (BBCode, HTML, markdown symbols) and collapse whitespace.
static func sanitize(text: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]|<[^>]*>|[*`#]")
	var out := re.sub(text, "", true)
	var ws := RegEx.new()
	ws.compile("\\s+")
	return ws.sub(out, " ", true).strip_edges()


static func _is_whole_number(v) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		return v == floor(v)
	return false


# --- Fallbacks ------------------------------------------------------------------

func _load_fallbacks() -> void:
	_fallbacks = DEFAULT_FALLBACKS.duplicate(true)
	if not FileAccess.file_exists(FALLBACK_PATH):
		push_warning("Companion fallbacks missing (%s); using built-in lines." % FALLBACK_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FALLBACK_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Companion fallbacks are not valid JSON; using built-in lines.")
		return
	for key in parsed.keys():
		if typeof(parsed[key]) == TYPE_ARRAY and not parsed[key].is_empty():
			_fallbacks[key] = parsed[key]


func fallback_line(kind: String) -> String:
	var key := kind
	if kind == "help" and _fallbacks.has("help_" + GameState.current_objective_id()):
		key = "help_" + GameState.current_objective_id()
	var lines: Array = _fallbacks.get(key, _fallbacks.get("help", []))
	if lines.is_empty():
		return ""
	var i: int = _fallback_index.get(key, 0)
	_fallback_index[key] = i + 1
	return str(lines[i % lines.size()])


func _show_fallback(kind: String) -> void:
	var line := fallback_line(kind)
	if line != "":
		line_shown.emit(line, "offline", kind)


func _set_status(value: String) -> void:
	if status == value:
		return
	status = value
	status_changed.emit(status)
