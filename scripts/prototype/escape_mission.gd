extends Node2D
## The escape (docs/Game Design.md): free Dhan, learn what's broken, power the
## shuttle bay by repairing Engineering (Dhan talks you through it) or by taking
## the lab battery (losing the samples), get everyone aboard and fly home.
## Rules live in escape_state.gd; this script handles who is where and what shows.

# NPC IDs mara (Aaron) / ivo (Dhan) stay stable for the hosted radio API and saves.
const Rules = preload("res://scripts/prototype/escape_state.gd")
const Marvis = preload("res://scripts/prototype/escape_marvis.gd")
const Actor = preload("res://scripts/prototype/escape_actor.gd")
const Prop = preload("res://scripts/prototype/escape_prop.gd")
const Interface = preload("res://scripts/prototype/escape_ui.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const Intro = preload("res://scripts/ui/intro_cutscene.gd")
const Outro = preload("res://scripts/ui/outro_film.gd")
const Darkness = preload("res://scripts/prototype/escape_darkness.gd")
const Alarm = preload("res://scripts/prototype/escape_alarm.gd")
const Impacts = preload("res://scripts/prototype/escape_impacts.gd")
const ShipMap = preload("res://scripts/prototype/escape_ship.gd")
const Haptics = preload("res://scripts/core/haptics.gd")
const TILE := 32
const MAP_PATH := "res://data/escape_map.json"
const LINES_PATH := "res://data/escape_lines.json"
const VOICE_DIR := "res://assets/voice/escape/"
const DISCOVERIES := "user://escape_discoveries.cfg"
const SCHEMA := 2
const MAP_ID := "escape-v2"
const NEAR := 115.0                 # "standing next to it" for crew tasks
const LIFT_HOLD := 6.0              # how long Aaron can hold the locker up
const SOFT_COOLDOWN := 12.0         # seconds between unprompted lines
const NUDGE_1 := 45.0
const NUDGE_2 := 90.0
const COUNT_THREE := 2.6            # "three!" lands this long after the count starts
const COUNT_WINDOW := 0.4
const CARRY_SPEED := 62.0
const ROOM_LINES := {"ENGINEERING": "enter_eng_dhan", "LABORATORY": "enter_lab_aaron", "MEDBAY": "enter_medbay_aaron", "GALLEY": "galley_aaron"}
const ACTION_HAPTICS := {
	"free_dhan": "shove", "isolate": "click", "take_fuse": "tick", "seat_fuse": "click", "toggle": "click",
	"freezer_off": "power_down", "battery_latch": "click", "load_battery": "heavy", "take_cart": "tick",
	"connect_battery": "power_up", "restart": "power_up", "release": "clamps", "launch": "launch",
	"take_splint": "tick", "apply_splint": "tick", "carry_dhan": "heavy",
}
## Every task a crewmate can be part-way through (saves are checked against this).
## What Aaron is doing, for when Johnny asks again while he's at it.
const BUSY_TELL := {
	"lift_locker": "going to the locker on Dhan. You lift as soon as Johnny is right next to Dhan, ready to pull him out.",
	"lift_battery": "going to the cart in the lab. You lift the battery on three once Johnny is at the cart with you.",
	"carry_dhan": "going to Dhan to carry him. You lift him once Johnny is next to Dhan too.",
	"fetch_fuse": "fetching the spare fuse from Storage. You'll leave it by the engineering cabinet.",
	"fetch_case": "fetching the insulated sample case from the shuttle for the lab freezer.",
	"release_clamps": "releasing the clamps, then getting on the shuttle.",
}
const TASKS := ["", "lift_locker", "stay_with_dhan", "fetch_fuse", "fetch_case", "lift_battery", "carry_dhan", "release_clamps"]

var state = Rules.new()
var marvis = Marvis.new()
var lines: Dictionary = {}
var player
var crew := {}
var props := {}
var world: Node2D
var ui
var active := false
var ending := false
var elapsed := 0.0
var room := "CORRIDOR"
var floors := {}
var walls := {}
var nav := AStarGrid2D.new()
var map_data := {}
var map_size := Vector2i.ZERO
var anchors := {}
var rooms := []
var _room_grid: PackedStringArray
var _room_by_key := {}
var ship
var locker_body: StaticBody2D
var locker_visual: Sprite2D
var carried_visual: Sprite2D
var darkness
var voice: AudioStreamPlayer
var _marvis_chain_active := false
var _intro = null
var _busy := {}                 # crew id -> task
var _task_arg := {}             # crew id -> extra (the fuse box Aaron is fetching)
var alarm                       # escape_alarm.gd: the corridor's rotating beacons
var impacts                     # escape_impacts.gd: debris striking the hull now and then
var _save_ready := false
var _autosave_clock := 0.0
var _resumed := false
var _resume_cover: ColorRect
var seated := false             # Johnny in the pilot seat
var scripted := false           # a short scripted moment: no player control
var _player_path := PackedVector2Array()
var _player_path_done: Callable
var _hold := {}                 # {target, total, t, done, label}
var _lift_until := -1.0         # Aaron holding the locker up until this time
var _count := {}                # Aaron's count of three: {t}
var _said := {}                 # line id -> true (each plays once)
var _queue: Array = []          # [{id, forced}]
var _line_until := 0.0
var _last_soft := -100.0
var _last_progress := 0.0
var _progress_mark := -1
var _nudged := 0
var _rooms_seen := {}
var _stage_seen := 1
var pending_question := {}      # crew id -> question line id the player hasn't answered
var _question_at := {}          # crew id -> when it was asked
const ANSWER_WINDOW := 40.0     # after this the question has passed
var _timers: Array = []         # [{at, call}] mission-clock timers (pause with the game)
var discoveries_path := DISCOVERIES  # tests point this elsewhere
var launching := false          # the launch sequence is playing (sirens, hatch)
var outro = null                # the ending film while it plays

func _ready() -> void:
	GameState.new_run()
	add_to_group("ship")
	add_to_group("blocks_player_input")
	var data = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
	lines = data.get("lines", {}) if data is Dictionary else {}
	_load_map()
	ship = ShipMap.new()
	ship.mission = self
	add_child(ship)
	_build_floor()
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	ship.build_decor(world)
	_build_props()
	_add_actor("mara", "AARON · RESEARCHER", "hazard", anchor("aaron_start"), Color("e0ad65"))
	_add_actor("ivo", "DHAN · ENGINEER", "nebula", anchor("dhan_start"), Color("b18ada"))
	player = PlayerScene.instantiate()
	player.position = anchor("player_start")
	world.add_child(player)
	player.set_camera_limits(Rect2(Vector2.ZERO, Vector2(map_size * TILE)))
	player.snap_camera()
	carried_visual = Sprite2D.new()
	carried_visual.scale = Vector2(0.65, 0.65)
	world.add_child(carried_visual)
	voice = AudioStreamPlayer.new()
	add_child(voice)
	darkness = Darkness.new()
	darkness.mission = self
	add_child(darkness)
	alarm = Alarm.new()  # drawn above the dark: the beacons are light sources
	alarm.mission = self
	add_child(alarm)
	impacts = Impacts.new()
	impacts.mission = self
	add_child(impacts)
	ui = Interface.new()
	ui.mission = self
	add_child(ui)
	var saved := SaveGame.take_resume()
	if not saved.is_empty() and compatible_save(saved):
		_restore_progress(saved)
		Settings.intro_pending = false
	if Settings.intro_pending:
		Settings.intro_pending = false
		Sfx.stop_ambient()
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_intro = Intro.new()
		layer.add_child(_intro)
		_intro.finished.connect(_begin)
		_intro.play()
	else:
		_begin.call_deferred()
	queue_redraw()

func _begin() -> void:
	_intro = null
	_set_wide(true)
	ui._layout.call_deferred()
	active = true
	GameState.begin_play()
	Sfx.start_ambient()
	_last_progress = elapsed
	if _resumed:
		ui.show_caption("M.A.R.V.I.S.", "Welcome back. " + state.objective())
		_resume_tasks()
	elif not state.has_flag("dhan_free"):
		_aftershock()
	refresh()
	_save_ready = true
	save_progress()
	if _resume_cover != null: _reveal_resume()

# --- Map -------------------------------------------------------------------------

func _load_map() -> void:
	map_data = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	map_size = Vector2i(int(map_data.size[0]), int(map_data.size[1]))
	for key in map_data.anchors:
		anchors[key] = Vector2(map_data.anchors[key][0], map_data.anchors[key][1])
	rooms = map_data.rooms
	for r in rooms:
		_room_by_key[r.key] = r
	_room_grid = PackedStringArray(map_data.room_grid)

func anchor(name: String) -> Vector2:
	return anchors.get(name, Vector2.ZERO)

func cell_char(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= map_size.x or c.y >= map_size.y: return " "
	return map_data.grid[c.y][c.x]

func _build_floor() -> void:
	for y in map_size.y:
		for x in map_size.x:
			if cell_char(Vector2i(x, y)) in [".", "D", "L"]: floors[Vector2i(x, y)] = true
	for cell in floors:
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var n: Vector2i = cell + Vector2i(dx, dy)
				if not floors.has(n): walls[n] = true
	var body := StaticBody2D.new()
	add_child(body)
	for cell in walls:
		_add_box(body, Rect2(Vector2(cell * TILE), Vector2(TILE, TILE)))
	var solids: Array[Rect2] = ship.solid_rects()
	for r in solids:
		_add_box(body, r)
	nav.region = Rect2i(Vector2i.ZERO, map_size)
	nav.cell_size = Vector2(TILE, TILE)
	nav.offset = Vector2(TILE / 2.0, TILE / 2.0)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	nav.update()
	for y in map_size.y:
		for x in map_size.x:
			var c := Vector2i(x, y)
			var centre := Vector2(c * TILE) + Vector2(16, 16)
			var blocked := not floors.has(c)
			for r in solids:
				if r.has_point(centre): blocked = true
			nav.set_point_solid(c, blocked)
	_set_locker_nav(true)

func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = rect.get_center()
	body.add_child(collision)

func _locker_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in floors:
		if cell_char(c) == "L": cells.append(c)
	return cells

func _set_locker_nav(blocked: bool) -> void:
	for c in _locker_cells(): nav.set_point_solid(c, blocked)

func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := Vector2i(from / 32)
	var finish := Vector2i(to / 32)
	if not nav.is_in_boundsv(start) or not nav.is_in_boundsv(finish): return PackedVector2Array()
	if nav.is_point_solid(start) or nav.is_point_solid(finish): return PackedVector2Array()
	var result := nav.get_point_path(start, finish)
	if not result.is_empty(): result[result.size() - 1] = to
	return result

func room_at(point: Vector2) -> String:
	var c := Vector2i(floori(point.x / TILE), floori(point.y / TILE))
	if c.x < 0 or c.y < 0 or c.y >= _room_grid.size() or c.x >= _room_grid[c.y].length(): return "PASSAGE"
	var key := _room_grid[c.y][c.x]
	return _room_by_key[key].name if _room_by_key.has(key) else "PASSAGE"

## The floor's style under a point ("deck", "grate", "carpet"...): footsteps sound like it.
func floor_style_at(point: Vector2) -> String:
	var c := Vector2i(floori(point.x / TILE), floori(point.y / TILE))
	if c.x < 0 or c.y < 0 or c.y >= _room_grid.size() or c.x >= _room_grid[c.y].length(): return "deck"
	var key := _room_grid[c.y][c.x]
	return str(_room_by_key[key].get("style", "deck")) if _room_by_key.has(key) else "deck"

# --- Props and crew --------------------------------------------------------------

const PROP_INFO := {
	"locker": ["FALLEN LOCKER", Color("e0ad65")],
	"terminal": ["M.A.R.V.I.S. TERMINAL", Color("6dff9e")],
	"isolate": ["ISOLATOR", Color("e0ad65")],
	"fuse": ["SPARE FUSES", Color("e0ad65")],
	"cabinet": ["DISTRIBUTION CABINET", Color("e0ad65")],
	"aux": ["AUX SWITCHES", Color("e0ad65")],
	"freezer": ["SAMPLE FREEZER", Color("87d5b3")],
	"battery": ["EMERGENCY BATTERY", Color("87d5b3")],
	"cart": ["SERVICE CART", Color("87d5b3")],
	"case": ["SAMPLE CASE", Color("87d5b3")],
	"socket": ["EMERGENCY SOCKET", Color("9bace8")],
	"release": ["CLAMP RELEASE", Color("9bace8")],
	"shuttle": ["SHUTTLE", Color("9bace8")],
	"medkit": ["MEDICAL CABINET", Color("ef8a81")],
	"airlock": ["OUTER AIRLOCK", Color("f4a259")],
}

func _add_prop(id: String, solid := true) -> void:
	var info: Dictionary = map_data.props[id]
	var prop = Prop.new()
	prop.mission = self
	prop.prop_id = id
	prop.title = PROP_INFO[id][0]
	prop.accent = PROP_INFO[id][1]
	var sprite := str(info.sprite)
	prop.texture_path = ("res://assets/ship/" + sprite + ".png") if sprite != "" and id != "locker" else ""
	prop.solid = solid and sprite != ""
	prop.position = Vector2(info.pos[0], info.pos[1])
	world.add_child(prop)
	props[id] = prop

func _build_props() -> void:
	_add_prop("locker", false)
	locker_body = StaticBody2D.new()
	var bounds := Rect2()
	for c in _locker_cells():
		var r := Rect2(Vector2(c * TILE), Vector2(TILE, TILE))
		bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)
	_add_box(locker_body, bounds)
	add_child(locker_body)
	locker_visual = Sprite2D.new()
	locker_visual.texture = load("res://assets/ship/" + str(map_data.props.locker.sprite) + ".png")
	locker_visual.offset = Vector2(0, -locker_visual.texture.get_height() / 2.0)
	locker_visual.position = anchor("locker_visual")
	world.add_child(locker_visual)
	for id in ["terminal", "isolate", "fuse", "cabinet", "aux", "freezer", "battery", "cart", "socket", "release", "shuttle", "medkit", "airlock"]:
		_add_prop(id)
	_add_prop("case", false)

func _add_actor(id: String, title: String, suit: String, point: Vector2, color: Color) -> void:
	var actor = Actor.new()
	actor.mission = self
	actor.actor_id = id
	actor.display_name = title
	actor.suit = suit
	actor.tint = color
	actor.position = point
	world.add_child(actor)
	crew[id] = actor

func crew_name(id: String) -> String:
	return {"mara": "AARON", "ivo": "DHAN", "marvis": "M.A.R.V.I.S."}.get(id, id.to_upper())

func _who_id(who: String) -> String:
	return {"aaron": "mara", "dhan": "ivo", "marvis": "marvis"}.get(who, who)

func aaron_near_dhan() -> bool:
	return crew.mara.visible and crew.ivo.visible and crew.mara.position.distance_to(crew.ivo.position) < 90.0

func near(a: Vector2, b: Vector2, r := NEAR) -> bool:
	return a.distance_to(b) <= r

# --- Frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active or ending: return
	elapsed += delta
	_autosave_clock += delta
	if _autosave_clock >= 5.0:
		_autosave_clock = 0.0
		save_progress()
	_run_timers()
	var now_room := room_at(player.position) if not seated else "SHUTTLE"
	if now_room != room:
		room = now_room
		_entered_room(room)
	_update_carried()
	_walk_player(delta)
	_update_hold(delta)
	_update_lift()
	_update_count()
	_tick_dhan(delta)
	_deliver_lines()
	_check_stuck()
	ui.update_hud()

func _update_carried() -> void:
	var c: String = state.carrying
	carried_visual.visible = c != "" and not seated
	if c == "": return
	var tex := "res://assets/sprites/core.png" if c.begins_with("fuse_") else "res://assets/sprites/crate.png"
	if carried_visual.texture == null or carried_visual.texture.resource_path != tex:
		carried_visual.texture = load(tex)
	carried_visual.scale = Vector2(0.5, 0.5) if c.begins_with("fuse_") or c == "splint" else Vector2(0.75, 0.75)
	carried_visual.position = player.position + Vector2(22, -6)

## Timers on the mission clock, so a pause or a fail card delays them too.
func after(seconds: float, call: Callable) -> void:
	_timers.append({"at": elapsed + seconds, "call": call})

## Run `call` once nobody is talking (no queued line, no line or reply playing).
func when_quiet(call: Callable) -> void:
	if _queue.is_empty() and elapsed >= _line_until and not ui.radio.voice_pending():
		call.call()
	else:
		after(0.3, func(): when_quiet(call))

func _run_timers() -> void:
	var due: Array = []
	for t in _timers:
		if t.at <= elapsed: due.append(t)
	for t in due:
		_timers.erase(t)
		if t.call.is_valid(): t.call.call()

## The player can't move while seated or in a scripted moment (player.gd checks this group).
func is_open() -> bool:
	return seated or scripted

func _input(event: InputEvent) -> void:
	if not active or ending: return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_ASCIITILDE or (event.shift_pressed and (event.keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_QUOTELEFT)):
			get_viewport().set_input_as_handled()
			_secret_trigger_ending()

## Secret developer / demo shortcut (Shift + ~) to jump straight to the launch sequence and ending.
func _secret_trigger_ending() -> void:
	if ending: return
	state.flags["dhan_free"] = true
	state.flags["locker_clear"] = true
	state.flags["isolated"] = true
	state.flags["fuse_installed"] = true
	state.flags["fault_found"] = true
	state.flags["aux_off"] = true
	state.flags["engineering_power"] = true
	state.flags["samples_saved"] = true
	state.flags["dhan_treated"] = true
	state.flags["dhan_aboard"] = true
	state.flags["aaron_aboard"] = true
	state.flags["clamps"] = true
	ui.close()
	_launch()

func _unhandled_input(event: InputEvent) -> void:
	if not active or ending or ui.is_open(): return
	if event.is_echo() or not event.is_pressed(): return
	if event.is_action_pressed("radio_1"): open_chat("mara")
	elif event.is_action_pressed("radio_2"): open_chat("ivo")
	elif event.is_action_pressed("radio_3"): open_chat("marvis")
	elif event.is_action_pressed("deck_map"): ui.show_map()
	elif event.is_action_pressed("pause"): ui.show_pause()
	elif event.is_action_pressed("toggle_mute"): Settings.toggle_mute()
	elif event.is_action_pressed("interact") and seated: open_pilot()
	elif event.is_action_pressed("flashlight") and not seated:
		darkness.toggle_flashlight()
		Haptics.play("tick")
	else: return
	get_viewport().set_input_as_handled()

func open_chat(id: String) -> void:
	if not active or ending or scripted: return
	if id == "ivo" and not state.dhan_alive():
		ui.show_caption("RADIO", "Dhan doesn't answer.")
		return
	ui.open_chat(id)

## A line shown above the HUD (system text, never voiced).
func announce(speaker: String, line: String) -> void:
	if ui != null and line != "": ui.show_caption(speaker, line)

# --- Pre-written lines (section 8) --------------------------------------------------

## Queue a pre-written line. forced: a story beat (ignores the cooldown).
## Each id plays once per run.
func say(id: String, forced := true) -> void:
	if _said.has(id) or not lines.has(id): return
	var who := str(lines[id].who)
	if who == "dhan" and not state.dhan_alive(): return
	for q in _queue:
		if q.id == id: return
	_queue.append({"id": id, "forced": forced})

func _deliver_lines() -> void:
	if _queue.is_empty() or elapsed < _line_until or ui.fail_open(): return
	if ui.radio.voice_pending(): return  # one voice at a time: wait for the crew reply to finish
	var next: Dictionary = _queue[0]
	if not next.forced:
		if elapsed - _last_soft < SOFT_COOLDOWN or ui.mode == "chat" or ui.radio.busy: return
	_queue.pop_front()
	_speak(str(next.id))
	if not next.forced: _last_soft = elapsed

func _speak(id: String) -> void:
	if _said.has(id): return
	_said[id] = true
	var entry: Dictionary = lines[id]
	var who := _who_id(str(entry.who))
	if who == "ivo" and not state.dhan_alive(): return
	var text := shown_text(str(entry.text))
	ui.show_caption(crew_name(who), text, who)
	if crew.has(who): ui.radio.remember_line(who, text)
	var seconds := 1.4 + text.length() * 0.055
	var path := VOICE_DIR + id + ".mp3"
	if ResourceLoader.exists(path) and not Settings.muted:
		voice.stream = load(path)
		voice.play()
		seconds = maxf(seconds * 0.6, voice.stream.get_length() + 0.25)
	_line_until = elapsed + seconds

func line_text(id: String) -> String:
	return shown_text(str(lines.get(id, {}).get("text", "")))

## A line as it's shown: voice directions like "[groans in pain]" are for the recording only.
static func shown_text(text: String) -> String:
	return RegEx.create_from_string("\\s*\\[[^\\]]*\\]\\s*").sub(text, " ", true).strip_edges()

## M.A.R.V.I.S. speaks (unprompted): shown and logged, voiced from per-sentence clips.
func marvis_say(ids: Array) -> void:
	ui.show_caption("M.A.R.V.I.S.", marvis.text(ids), "marvis")
	ui.radio.note_spoken(marvis.text(ids))
	play_marvis(ids)

func play_marvis(ids: Array) -> void:
	if Settings.muted: return
	ui.radio.hush()
	var clips: Array = []
	for id in ids:
		var path := VOICE_DIR + "marvis_" + str(id).replace(" ", "_").to_lower() + ".mp3"
		if ResourceLoader.exists(path): clips.append(path)
	if clips.is_empty():
		Sfx.play("objective", -18)
		return
	var total := 0.2
	for c in clips: total += (load(c) as AudioStream).get_length()
	_line_until = maxf(_line_until, elapsed + total)  # crew lines wait for the ship to finish
	_play_chain(clips)

## Stop any scripted line (and the rest of a M.A.R.V.I.S. clip chain): you're talking.
func stop_voice() -> void:
	if voice == null: return
	voice.stop()
	for c in voice.finished.get_connections(): voice.finished.disconnect(c.callable)

func _play_chain(clips: Array) -> void:
	if clips.is_empty(): return
	voice.stream = load(clips[0])
	voice.play()
	var rest := clips.slice(1)
	if not rest.is_empty():
		voice.finished.connect(func(): _play_chain(rest), CONNECT_ONE_SHOT)

## Typed or spoken to M.A.R.V.I.S. (radio 3 or the junction terminal).
func ask_marvis(message: String) -> String:
	var intent: String = marvis.classify(message)
	var ids: Array = marvis.reply(intent, self)
	play_marvis(ids)
	# However the player first hears the ship's report (terminal or radio), the crew react.
	if intent in ["status", "power", "shuttle"] and not _said.has("marvis_summary") and state.has_flag("dhan_free"):
		_said["marvis_summary"] = true
		_after_first_report()
	_progress()
	refresh()
	return marvis.text(ids)

# --- Opening: the aftershock pins Dhan (Beat 0-1) ----------------------------------

func _aftershock() -> void:
	scripted = true
	crew.ivo.facing = Vector2.LEFT
	after(0.9, func():
		Sfx.play("hit", -2)
		Haptics.play("impact")
		ui.shake(0.5)
		var tw := create_tween()
		tw.tween_property(locker_visual, "rotation", 0.12, 0.12)
		tw.tween_property(locker_visual, "rotation", 0.0, 0.25)
		crew.ivo.position = anchor("dhan_pinned")
		crew.ivo.pose = "pinned"
		crew.ivo.facing = Vector2.RIGHT
		_dust(anchor("dhan_pinned") + Vector2(-15, -4)))
	after(1.6, func():
		scripted = false
		say("aftershock_dhan")
		say("aftershock_aaron")
		ui.show_talk_hint())

## Aaron holds the locker up for a few seconds; pull Dhan out in that window.
func _start_lift() -> void:
	_lift_until = elapsed + LIFT_HOLD
	_busy["mara"] = "lift_locker"
	crew.mara.pose = "straining"
	locker_visual.position = anchor("locker_visual") + Vector2(0, -7)
	say_again("lift_ready")
	Haptics.play("heavy")

func _update_lift() -> void:
	if _lift_until < 0.0 or elapsed < _lift_until: return
	_end_lift()
	if not state.has_flag("dhan_free"):
		say_again("lift_drop")
		Sfx.play("hit", -12)
		Haptics.play("thud")

func _end_lift() -> void:
	_lift_until = -1.0
	if _busy.get("mara", "") == "lift_locker": _busy.erase("mara")
	crew.mara.pose = "stand"
	if not state.has_flag("dhan_free"): locker_visual.position = anchor("locker_visual")

func lifting() -> bool:
	return _lift_until >= 0.0

## Some short lines repeat (Aaron straining, dropping it): allow them again.
func say_again(id: String) -> void:
	_said.erase(id)
	say(id)

func _free_dhan() -> void:
	var result := perform("free_dhan")
	if not result.ok: return
	_end_lift()
	crew.ivo.pose = "sit"
	var tw := create_tween()
	tw.tween_property(crew.ivo, "position", anchor("dhan_rest"), 0.6).set_trans(Tween.TRANS_SINE)
	locker_body.process_mode = Node.PROCESS_MODE_DISABLED
	locker_body.get_child(0).set_deferred("disabled", true)
	_set_locker_nav(false)
	_swing_locker_clear()
	crew.mara.following = true
	say("freed_dhan")
	say("freed_context_aaron")  # where we are and what we're doing: the shuttle is the way home
	after(1.0, func(): when_quiet(func():
		if not _said.has("marvis_summary"):
			_said["marvis_summary"] = true
			marvis_say(["greeting", "main_offline", "shuttle_intact", "clamps_engaged_unpowered"])
			_after_first_report()))

func _swing_locker_clear() -> void:
	var rest := anchor("locker_cleared")
	var tw := create_tween()
	tw.tween_property(locker_visual, "position", locker_visual.position + Vector2(-4, 0), 0.08)
	tw.tween_interval(0.08)
	tw.set_parallel(true)
	tw.tween_property(locker_visual, "rotation", -PI / 2.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(locker_visual, "position", rest, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(false)
	tw.tween_callback(func():
		_dust(rest + Vector2(-50, 0))
		Sfx.play("hit", -10)
		Haptics.play("thud")
		_block_cleared_locker())

func _block_cleared_locker() -> void:
	var t: Texture2D = locker_visual.texture
	var rest := anchor("locker_cleared")
	var rect := Rect2(rest.x - t.get_height(), rest.y - t.get_width() / 2.0 + 6, t.get_height(), t.get_width() / 2.0)
	var body := StaticBody2D.new()
	add_child(body)
	_add_box(body, rect)
	for y in map_size.y:
		for x in map_size.x:
			var centre := Vector2(x * TILE + 16, y * TILE + 16)
			if rect.has_point(centre): nav.set_point_solid(Vector2i(x, y), true)

func _dust(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = 16
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector2(0, 40)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color(0.75, 0.75, 0.82, 0.7)
	p.z_index = 4
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

# --- Hold E (heavy or careful actions) ------------------------------------------------

## `also`: a second thing E can be on for the same hold (the locker and Dhan stand so
## close that E can land on either), so the hold carries on if your target switches.
func begin_hold(target, seconds: float, label: String, done: Callable, also = null) -> void:
	_hold = {"target": target, "total": seconds, "t": 0.0, "done": done, "label": label, "also": also}

func hold_progress() -> float:
	return clampf(_hold.t / _hold.total, 0.0, 1.0) if not _hold.is_empty() else 0.0

func hold_target():
	return _hold.get("target")

func _update_hold(delta: float) -> void:
	if _hold.is_empty(): return
	var aimed = player.current_target
	if aimed != null and aimed == _hold.get("also") and aimed != _hold.target:
		_hold["also"] = _hold.target   # E moved to the other one: the progress bar follows
		_hold["target"] = aimed
	if not Input.is_action_pressed("interact") or aimed != _hold.target or ui.is_open():
		_hold.clear()
		return
	_hold.t += delta
	if _hold.t >= _hold.total:
		var done: Callable = _hold.done
		_hold.clear()
		done.call()

## Prompt under the target ("[E] hold: PULL ISOLATOR"). Empty = its plain name.
func prompt_for(id: String) -> String:
	match id:
		"locker":
			if not state.has_flag("dhan_free") and lifting(): return "hold: PULL DHAN FREE"
		"isolate": return "hold: PULL ISOLATOR" if not state.has_flag("isolated") else "ISOLATOR (pulled)"
		"battery": return "hold: OPEN LATCH" if not state.has_flag("battery_out") else "BATTERY (unlatched)"
		"cart":
			if _count.has("t"): return "LIFT!"
			if state.has_flag("battery_loaded") and not state.has_flag("battery_taken"): return "TAKE CART"
		"shuttle":
			if state.powered(): return "TAKE PILOT SEAT"
		"terminal": return "TALK TO M.A.R.V.I.S."
	return PROP_INFO[id][0] if PROP_INFO.has(id) else id

func actor_prompt(id: String) -> String:
	if id == "ivo":
		if not state.dhan_alive(): return "DHAN"
		if not state.has_flag("dhan_free") and lifting(): return "hold: PULL DHAN FREE"
		if state.carrying == "splint" and not state.has_flag("dhan_treated"): return "hold: SPLINT DHAN'S LEG"
	return "Talk to " + crew_name(id).capitalize()

func actor_interactable(id: String) -> bool:
	if not active or ending or scripted: return false
	if not crew[id].visible: return false
	if id == "mara" and lifting(): return false
	return true

func interact_actor(id: String) -> void:
	if id == "ivo" and state.dhan_alive():
		if not state.has_flag("dhan_free") and lifting():
			begin_hold(crew.ivo, 2.0, "PULL", _free_dhan, props.locker)
			return
		if state.has_flag("dhan_free") and state.carrying == "splint" and not state.has_flag("dhan_treated"):
			begin_hold(crew.ivo, 2.0, "SPLINT", func():
				if perform("apply_splint").ok: say("splint_dhan"))
			return
	if id == "ivo" and not state.dhan_alive(): return
	open_chat(id)

# --- Using things (props) -----------------------------------------------------------

func use_prop(id: String) -> void:
	match id:
		"locker":
			if not state.has_flag("dhan_free"):
				if lifting():
					# Dhan is pinned right under it: holding E on the locker pulls him out too.
					begin_hold(props.locker, 2.0, "PULL", _free_dhan, crew.ivo)
				else:
					announce("JOHNNY", "Too heavy to shift alone. Aaron could lift it.")
		"terminal":
			ui.open_chat("marvis")
			if not _said.has("marvis_summary"):
				_said["marvis_summary"] = true
				var ids: Array = marvis.reply("status", self)
				ui.marvis_reply(marvis.text(ids))
				play_marvis(ids)
				_after_first_report()
		"isolate":
			if state.has_flag("isolated"): announce("ISOLATOR", "Already pulled. The cabinet is dead.")
			else: begin_hold(props.isolate, 1.5, "PULL", func():
				if perform("isolate").ok: marvis_say(["cabinet_isolated"]))
		"cabinet", "fuse", "aux", "freezer", "case", "socket", "medkit":
			if id == "cabinet":
				state.apply("read_code")
				state.learn("code", "CABINET: Fault code %s." % state.fault_code())
			ui.show_closeup("freezer" if id == "case" else id)
			if id in ["freezer", "case"] and not state.has_flag("freezer_off") and not _said.has("freezer_question"):
				say("freezer_question")
				ask_question("mara", "freezer_question")
		"battery":
			if state.has_flag("battery_out"):
				announce("BATTERY", "Unlatched. Too heavy for one. It needs to go on the cart.")
			else: begin_hold(props.battery, 1.0, "LATCH", func(): perform("battery_latch"))
		"cart":
			if _count.has("t"): _lift_attempt()
			elif state.has_flag("battery_loaded"): perform("take_cart")
			elif state.has_flag("battery_out"): announce("JOHNNY", "The battery's too heavy to lift alone.")
			else: announce("SERVICE CART", "Empty. Rated for 400 kg.")
		"release":
			if not state.powered(): announce("CLAMP RELEASE", "No power.")
			elif state.has_flag("clamps"): announce("CLAMP RELEASE", "Released.")
			else: announce("CLAMP RELEASE", "Someone has to be at the helm when the clamps open. Take the pilot seat and have Aaron release them.")
		"shuttle":
			if not state.powered():
				announce("SHUTTLE", "Intact, but the docking clamps hold her in, and they've got no power.")
			else: sit()
		"airlock":
			fail_or(perform("airlock"))

## Johnny takes the pilot seat (Beat 4).
func sit() -> void:
	seated = true
	player.visible = false
	player.position = anchor("seat")
	player.velocity = Vector2.ZERO
	darkness.flashlight = false
	open_pilot()
	save_progress()

func stand() -> void:
	seated = false
	player.visible = true
	player.position = anchor("board_aaron") + Vector2(-30, 0)
	ui.close()
	save_progress()

func open_pilot() -> void:
	ui.show_closeup("pilot")

## A press inside a close-up (escape_ui.gd forwards it here).
func closeup_press(panel: String, part: String) -> void:
	match panel:
		"cabinet":
			match part:
				"display":
					pass
				"slot": fail_or(perform("seat_fuse"))
				"test": fail_or(perform("test"))
				"restart":
					var r := perform("restart")
					fail_or(r)
					if r.ok: _bay_powered()
		"fuse":
			if part in Rules.BOXES: perform("take_fuse", part)
		"aux":
			if part == "cover":
				ui.aux_cover_open = not ui.aux_cover_open
				if ui.aux_cover_open: ui.closeup.prefer = "t0"
			elif part.begins_with("t"):
				if not ui.aux_cover_open: return
				var r := perform("toggle", part.substr(1))
				if r.has("hurt"):
					state.hurt(r.hurt)
					Sfx.play("hit", -10)
					Haptics.play("jolt")
					say_again("wrong_switch_dhan")
		"freezer":
			match part:
				"cover":
					ui.freezer_cover_open = not ui.freezer_cover_open
					if ui.freezer_cover_open: ui.closeup.prefer = "switch"
				"switch":
					if ui.freezer_cover_open and perform("freezer_off").ok:
						pending_question.erase("mara")
						say("freezer_off_aaron")
						marvis_say(["freezer_off"])
				"rack_priority", "rack_cal", "rack_dup":
					if perform("pack_rack", "priority" if part == "rack_priority" else "other").ok:
						announce("CASE", "Packed. The case is sealed.")
		"socket":
			match part:
				"knob": perform("set_selector", str((state.selector + 1) % 3))
				"connect":
					if perform("connect_battery").ok:
						marvis_say(["battery_bay"])
						_bay_powered()
					else: Haptics.play("jolt")
		"medkit":
			if part == "splint" and perform("take_splint").ok:
				announce("MEDICAL CABINET", "Splint kit and painkillers.")
		"pilot":
			match part:
				"launch": fail_or(perform("launch"))
				"leave": stand()
	if ui.mode == "closeup": ui.refresh_closeup()

## Handles a quick failure if the result is one; returns the result.
func fail_or(result: Dictionary) -> Dictionary:
	if result.has("fail"): _fail(str(result.fail))
	return result

func _fail(id: String) -> void:
	ui.close()
	if state.has_flag("dhan_free"): state.hurt(Rules.FAIL_COST)
	Sfx.play("hit", -2)
	Haptics.play("jolt")
	ui.shake(0.4)
	_record_discovery("fails", id)
	ui.show_fail(id, Rules.FAILS[id], func(): _after_fail(id))

func _after_fail(id: String) -> void:
	if id == "F2":  # step back from the airlock
		player.position = props.airlock.position + Vector2(-70, 40)
	if near(crew.mara.position, player.position, 260.0): say("fail_return_aaron")
	else: say("fail_return_dhan")
	save_progress()

func perform(action: String, arg := "") -> Dictionary:
	var result: Dictionary = state.apply(action, arg)
	if result.has("fail"): return result
	if result.line != "": announce(_label_for(action), result.line)
	if not result.ok:
		Haptics.play("deny")
		return result
	if ACTION_HAPTICS.has(action): Haptics.play(ACTION_HAPTICS[action])
	Sfx.play("door" if action in ["free_dhan", "release"] else "objective", -10)
	_after_action(action)
	refresh()
	save_progress()
	return result

func _label_for(action: String) -> String:
	match action:
		"seat_fuse", "test", "restart", "read_code": return "CABINET"
		"toggle": return "AUX SWITCHES"
		"connect_battery", "set_selector": return "SOCKET"
		"take_fuse": return "STORAGE"
		"launch": return "SHUTTLE"
	return "JOHNNY"

func _after_action(action: String) -> void:
	_progress()
	match action:
		"seat_fuse": state.learn("fuse_in", "CABINET: New fuse seated.")
		"test":
			state.learn("aux_" + state.short_branch(), "CABINET: Short circuit on %s." % state.short_branch())
			Sfx.play("hit", -12)
		"aux_off": pass
		"freezer_off": state.learn("freezer_off", "LAB: Freezer off. The samples are warming.")
		"battery_latch": pass
		"carry_dhan": pass
		"launch": _launch()

func _after_first_report() -> void:
	after(1.0, func():
		say("beat2_problem_dhan")
		say("beat2_dhan")
		say("beat2_aaron")
		say("beat2_dhan_call")
		state.learn("d_fuse", "DHAN: The engineering cabinet is probably a blown fuse. He can talk you through it.")
		state.learn("a_battery", "AARON: The lab battery could power the clamps, but it keeps Kien's and his samples cold."))

func _bay_powered() -> void:
	marvis_say(["docking_available"])
	if state.has_flag("engineering_power"): say("eng_power_dhan")
	say("bay_powered_dhan")
	state.learn("bay_power", "M.A.R.V.I.S.: Bay has power. Clamps release from the bay console.")

func _entered_room(name: String) -> void:
	if _rooms_seen.has(name): return
	if not ROOM_LINES.has(name) or not state.has_flag("dhan_free"): return
	var id: String = ROOM_LINES[name]
	# Aaron only comments on rooms he's in with you.
	if lines[id].who == "aaron" and not near(crew.mara.position, player.position, 260.0): return
	if id == "enter_medbay_aaron" and state.has_flag("dhan_treated"): return
	if id == "enter_lab_aaron" and state.has_flag("freezer_off"): return
	if id == "enter_eng_dhan" and state.powered(): return
	_rooms_seen[name] = true
	say(id, id == "enter_eng_dhan")

# --- Dhan's condition (section 5) --------------------------------------------------

func clock_running() -> bool:
	return active and not ending and not scripted and not ui.fail_open() and not ui.radio.busy and ui.mode != "pause"

func _tick_dhan(delta: float) -> void:
	if not clock_running(): return
	if state.tick(delta, aaron_near_dhan()) == "died":
		_dhan_died()
		return
	var s: int = state.stage()
	if s > _stage_seen and s > 0:
		_stage_seen = s
		_stage_changed(s)

func _stage_changed(s: int) -> void:
	match s:
		2:
			if not state.has_flag("dhan_treated"): say("stage2_aaron", false)
		3:
			say("stage3_aaron")
			after(7.0, func():
				if state.dhan_alive() and not state.has_flag("dhan_aboard"):
					say("stage3_dhan_question")
					ask_question("ivo", "stage3_dhan_question"))
			after(16.0, func():
				if state.route() == "engineering" and not state.powered() and state.dhan_alive():
					say("switch_offer_aaron"))
		4: say("stage4_aaron")

func _dhan_died() -> void:
	crew.ivo.pose = "dead"
	pending_question.erase("ivo")
	_busy.erase("ivo")
	if ui.mode == "chat" and ui.chat_id == "ivo": ui.close()
	if _busy.get("mara", "") == "carry_dhan": _busy.erase("mara")
	_queue = _queue.filter(func(q): return str(lines[q.id].who) != "dhan")
	_said.erase("death_aaron")
	say("death_aaron")
	after(2.5, func(): marvis_say(["dhan_no_vitals"]))
	state.learn("dhan_dead", "M.A.R.V.I.S.: Dhan has no vital signs.")
	refresh()
	save_progress()

# --- Crew tasks from conversation ---------------------------------------------------

func available_actions(id: String) -> Dictionary:
	var a := {"none": "Answer using the current situation; no action."}
	if id == "ivo":
		if not state.dhan_alive(): return a
		if not state.powered():
			a["light_on"] = "Turn on your flashlight (you can't walk, but you can point it)."
			a["light_off"] = "Turn your flashlight off."
		return a
	if state.has_flag("aaron_aboard"): return a
	if _busy.has(id):
		# Asked again (he didn't hear, or forgot): say plainly what you're doing and what you need
		# from him. The same request again is fine; it just carries on.
		var task := str(_busy[id]).trim_suffix("_walk")
		var b := {"none": "You are busy: %s Tell Johnny that plainly. Don't start anything else." % str(BUSY_TELL.get(task, "doing a task."))}
		if task in ["lift_locker", "lift_battery", "carry_dhan"]: b[task] = "Johnny asked again: keep at it and remind him what you need from him."
		return b
	a["follow"] = "Follow Johnny."
	a["wait"] = "Stay where you are."
	if not state.powered():
		a["light_on"] = "Turn on your flashlight; it points where you walk."
		a["light_off"] = "Turn your flashlight off."
	if not state.has_flag("dhan_free"):
		a["lift_locker"] = "Lift the fallen locker off Dhan's leg so Johnny can pull him out."
		return a
	if state.dhan_alive() and not state.has_flag("dhan_aboard"):
		a["stay_with_dhan"] = "Go and stay beside Dhan, keeping him calm and still."
	if not state.has_flag("fuse_installed") and not state.has_flag("engineering_power") and state.fuse_at_cabinet == "":
		a["fetch_fuse"] = "Fetch a spare fuse from Storage and leave it by the engineering cabinet. Only if Johnny names the box (A, B or C)."
	if not state.has_flag("freezer_off") and not state.has_flag("case_requested"):
		a["fetch_case"] = "Fetch the insulated sample case from the shuttle and bring it to the lab freezer."
	if state.has_flag("battery_out") and not state.has_flag("battery_loaded"):
		a["lift_battery"] = "Go to the lab cart and lift the battery onto it with Johnny, on a count of three."
	if state.powered() and state.dhan_alive() and not state.has_flag("dhan_aboard"):
		a["carry_dhan"] = "Help Johnny carry Dhan to the shuttle."
	if state.powered() and not state.has_flag("clamps"):
		a["release_clamps"] = "Release the docking clamps from the bay console, then board the shuttle."
	return a

## Carry out what a crewmate agreed to. Returns a corrected line when the
## request can't happen as stated ("" = go ahead with the model's line).
func act_on_dialogue(id: String, action: String, message := "") -> String:
	if action == "none" or action == "": return ""
	if not available_actions(id).has(action): return "Not right now. " + state.objective()
	var actor = crew[id]
	if str(_busy.get(id, "")).trim_suffix("_walk") == action:
		actor.remove_meta("waiting")  # already on it: say again what he's waiting for
		return ""
	match action:
		"light_on": actor.light_on = true
		"light_off": actor.light_on = false
		"follow":
			if find_path(actor.position, player.position).is_empty(): return "I can't get to you from here."
			actor.following = true
		"wait":
			actor.following = false
			actor.path.clear()
		"lift_locker":
			_busy[id] = "lift_locker_walk"
			actor.go_to(anchor("locker_hold"), func(): _when_player_near(id, "lift_locker", anchor("dhan_pull")))
		"stay_with_dhan":
			actor.go_to(anchor("aaron_by_dhan"))
		"fetch_fuse":
			var box: String = Rules.parse_box(message)
			if box == "": return "Which box? I don't know which fuse it needs."
			_fetch_fuse(box)
		"fetch_case":
			perform("fetch_case")
			_fetch_case()
		"lift_battery":
			_busy[id] = "lift_battery"
			actor.go_to(anchor("cart_lift"), func(): _when_player_near(id, "lift_battery", props.cart.position))
		"carry_dhan":
			_busy[id] = "carry_dhan"
			actor.go_to(crew.ivo.position + Vector2(26, 6), func(): _when_player_near(id, "carry_dhan", crew.ivo.position))
		"release_clamps":
			if state.dhan_alive() and not state.has_flag("dhan_aboard"): return line_text("aaron_dhan_first")
			if not seated: return line_text("aaron_needs_pilot")
			_release_clamps()
	save_progress()
	return ""

## A crew task that needs Johnny beside it starts when he arrives.
func _when_player_near(id: String, task: String, spot: Vector2) -> void:
	if ending: return
	if not available_actions(id).has(task) and _busy.get(id, "") != task and _busy.get(id, "") != task + "_walk":
		_busy.erase(id)
		return
	# For the locker Johnny has to be right at Dhan's side, ready to pull.
	var reach := 70.0 if task == "lift_locker" else NEAR
	if near(player.position, spot, reach):
		_busy.erase(id)
		match task:
			"lift_locker": _start_lift()
			"lift_battery": _start_count()
			"carry_dhan": _carry_dhan()
		return
	if not crew[id].has_meta("waiting"):
		crew[id].set_meta("waiting", true)
		announce("AARON", {"lift_locker": "I'm at the locker. Get ready to pull him.", "lift_battery": "I'm at the cart. Come here and we'll lift it.", "carry_dhan": "I'm with Dhan. Take his other arm."}[task])
	after(0.25, func():
		if near(player.position, spot, reach): crew[id].remove_meta("waiting")
		_when_player_near(id, task, spot))

func _fetch_fuse(box: String) -> void:
	_busy["mara"] = "fetch_fuse"
	_task_arg["mara"] = box
	crew.mara.go_to(anchor("fuse_fetch"), func():
		crew.mara.set_cargo(true)
		crew.mara.go_to(anchor("cabinet_drop"), func():
			crew.mara.set_cargo(false)
			_busy.erase("mara")
			_task_arg.erase("mara")
			state.fuse_at_cabinet = box
			state.version += 1
			announce("AARON", "Box %s fuse is by the cabinet." % box)
			refresh()
			save_progress()))

func _fetch_case() -> void:
	_busy["mara"] = "fetch_case"
	var deliver := func():
		crew.mara.set_cargo(true)
		crew.mara.go_to(anchor("case_drop"), func():
			crew.mara.set_cargo(false)
			_busy.erase("mara")
			if ending: return
			if state.has_flag("freezer_off"):
				announce("AARON", "Too late. The freezer's already off.")
				return
			perform("case_arrived")
			say("case_delivered"))
	if crew.mara.cargo.visible: deliver.call()
	else: crew.mara.go_to(anchor("shuttle_side"), deliver)

## Aaron's count of three (M10): press E on "three".
func _start_count() -> void:
	_count = {"t": 0.0}
	_said.erase("count_one")
	_said.erase("count_two")
	_said.erase("count_three")
	ui.show_caption("AARON", line_text("lift_count_ready"), "mara")
	_play_line_audio("lift_count_ready")

func _update_count() -> void:
	if not _count.has("t"): return
	var before: float = _count.t
	_count.t += get_process_delta_time()
	var t: float = _count.t
	for beat in [[0.9, "count_one"], [1.75, "count_two"], [COUNT_THREE, "count_three"]]:
		if before < beat[0] and t >= beat[0]:
			ui.show_caption("AARON", line_text(beat[1]), "mara")
			_play_line_audio(beat[1])
	if t > COUNT_THREE + COUNT_WINDOW + 0.2:
		_count_dropped()
	elif not near(player.position, props.cart.position, 160.0):
		_count.clear()
		announce("AARON", "Where are you going? I'll wait at the cart.")
		_busy["mara"] = "lift_battery"
		_when_player_near("mara", "lift_battery", props.cart.position)

func _lift_attempt() -> void:
	var t: float = _count.t
	if absf(t - COUNT_THREE) <= COUNT_WINDOW:
		_count.clear()
		if perform("load_battery").ok:
			ui.show_caption("AARON", line_text("lift_count_done"), "mara")
			_play_line_audio("lift_count_done")
	else:
		_count_dropped()

func _count_dropped() -> void:
	_count.clear()
	Sfx.play("hit", -8)
	Haptics.play("thud")
	ui.show_caption("AARON", line_text("lift_count_drop"), "mara")
	_play_line_audio("lift_count_drop")
	after(2.2, func():
		if not state.has_flag("battery_loaded") and near(player.position, props.cart.position, 160.0) and not ending:
			_start_count())

## The count of three is timed, so it cuts off anything else being said.
func _play_line_audio(id: String) -> void:
	var path := VOICE_DIR + id + ".mp3"
	if ResourceLoader.exists(path) and not Settings.muted:
		ui.radio.hush()
		stop_voice()
		voice.stream = load(path)
		voice.play()

## You and Aaron walk Dhan to the shuttle at half speed (M16).
func _carry_dhan() -> void:
	scripted = true
	ui.close()
	say("carry_start_aaron")
	after(2.5, func(): say("carry_dhan"))
	var dhan = crew.ivo
	dhan.pose = "carried"
	var goal := anchor("board_dhan")
	_player_path = find_path(_free_spot(player.position), goal + Vector2(-26, 0))
	crew.mara.speed = CARRY_SPEED
	dhan.speed = CARRY_SPEED
	crew.mara.go_to(goal + Vector2(26, 0))
	dhan.go_to(goal, func():
		dhan.visible = false
		dhan.pose = "sit"
		crew.mara.speed = Actor.WALK_SPEED
		dhan.speed = Actor.WALK_SPEED
		_player_path.clear()
		if player.position.distance_to(goal) > 80.0: player.position = goal + Vector2(-26, 0)
		scripted = false
		perform("carry_dhan")
		state.learn("dhan_aboard", "SHUTTLE: Dhan is strapped in."))

## The nearest walkable cell centre (the player can stand half over furniture).
func _free_spot(at: Vector2) -> Vector2:
	var c := Vector2i(at / TILE)
	for r in range(0, 3):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if nav.is_in_boundsv(n) and not nav.is_point_solid(n): return Vector2(n * TILE) + Vector2(16, 16)
	return at

func _walk_player(delta: float) -> void:
	if _player_path.is_empty(): return
	player.position = player.position.move_toward(_player_path[0], delta * CARRY_SPEED)
	if player.position.distance_to(_player_path[0]) < 1.0:
		_player_path.remove_at(0)

## Aaron opens the clamps, then runs aboard (M17). Launching before he's in = F4.
func _release_clamps() -> void:
	_busy["mara"] = "release_clamps"
	crew.mara.following = false
	crew.mara.go_to(anchor("release_stand"), func():
		if ending: return
		say("aaron_releasing")
		if perform("release").ok:
			marvis_say(["clamps_releasing"])
		crew.mara.go_to(anchor("board_aaron"), func():
			_busy.erase("mara")
			if ending: return
			crew.mara.visible = false
			perform("aaron_aboard")
			say("aaron_boarded")))

# --- What the player is stuck on, for nudges and the AI (section 8) -----------------

func next_step() -> String:
	if not state.has_flag("dhan_free"): return "free_dhan"
	if not state.powered():
		if not state.learned.has("m_clamps") and not _said.has("marvis_summary"): return "marvis"
		match state.route():
			"battery":
				if not state.has_flag("battery_out"): return "bat_latch"
				if not state.has_flag("battery_loaded"): return "bat_lift"
				if not state.has_flag("battery_taken"): return "bat_cart"
				return "bat_socket" if room == "SHUTTLE BAY" else "bat_cart"
			"engineering":
				if not state.has_flag("fuse_installed"): return "eng_fuse" if state.has_flag("code_read") else "eng_code"
				if not state.has_flag("fault_found"): return "eng_test"
				if not state.has_flag("aux_off"): return "eng_toggle"
				return "eng_restart"
		if room == "ENGINEERING": return "eng_isolate"
		if room == "LABORATORY": return "bat_freezer"
		return "choose"
	if state.dhan_alive() and not state.has_flag("dhan_aboard"): return "carry"
	if not seated: return "seat"
	if not state.has_flag("clamps"): return "release"
	return "launch"

func _progress() -> void:
	_last_progress = elapsed
	_nudged = 0

func note_player_spoke() -> void:
	_progress()

func _check_stuck() -> void:
	if _progress_mark != state.version:
		_progress_mark = state.version
		_progress()
	if ui.is_open() or scripted: return
	var idle := elapsed - _last_progress
	var level := 2 if idle >= NUDGE_2 else 1 if idle >= NUDGE_1 else 0
	if level <= _nudged: return
	_nudged = level
	var id := "nudge_%s_%d" % [next_step(), level]
	if not lines.has(id): return
	if str(lines[id].who) == "dhan" and not state.dhan_alive(): return
	say(id, false)

## Short notes for the AI on what this crewmate would naturally bring up now.
func talking_points(id: String) -> Array:
	var pts: Array = []
	var step := next_step()
	pts.append("Ship layout: Storage is west, past the Galley, and holds spare fuse boxes A, B, and C. Medbay is west, off the corridor, and has a medical cabinet with a splint kit. The Laboratory is south of the junction and has the sample freezer, emergency battery, and service cart. Engineering is north of the junction with the power cabinet and the big power-cut handle by the door. The Shuttle Bay is east of the junction, with the escape shuttle, battery socket, and clamp console.")
	if id == "mara":
		pts.append("Kien died in the breach; you and he collected the lab samples together. Bring him up rarely: only when Johnny mentions him or the samples, and not again if you already have in this conversation.")
		if not state.has_flag("freezer_off"):
			pts.append("The lab battery could power the clamps, but it keeps the freezer and the samples alive.")
			pts.append("Only if Johnny asks about saving the samples or other options: there's an insulated case aboard the shuttle that fits one rack. You can fetch it.")
		if state.dhan_alive() and state.has_flag("dhan_free") and not state.has_flag("dhan_treated") and state.stage() >= 2:
			pts.append("Dhan's leg needs immobilising and he needs painkillers. The medbay cabinet should have a splint kit.")
		if step == "bat_lift": pts.append("The battery is too heavy for one person; you can lift it together on a count of three.")
		if step == "carry": pts.append("The bay has power. Dhan needs carrying to the shuttle; you can do it together.")
		if step in ["seat", "release"]: pts.append("You'll release the clamps from the bay console, but only once Johnny is in the pilot seat.")
		if state.has_flag("dhan_dead"): pts.append("Dhan has died. You are grieving but you still want to get home.")
	else:
		pts.append("You are pinned or sitting, in pain. You joke to hide it. You can't walk anywhere.")
		pts.append("You know the ship's systems. You can't see what Johnny sees; ask him to describe it or read you codes.")
		if state.has_flag("code_read"):
			pts.append("The cabinet display shows fault code %s. That requires the spare fuse from box %s in Storage." % [state.fault_code(), state.right_fuse()])
		if state.has_flag("fault_found"):
			pts.append("The short is on %s. Flipping the %s toggle down cuts it." % [state.short_branch(), ["left", "middle", "right"][state.right_toggle()].to_upper()])
		if step in ["eng_isolate", "choose"] and room == "ENGINEERING":
			pts.append("Before touching the cabinet, the big isolator handle by the door must be pulled.")
		if step == "eng_test": pts.append("Once the new fuse is in, press TEST on the cabinet.")
		if step == "eng_restart": pts.append("With the shorted branch cut, press RESTART on the cabinet.")
	return pts

## Everything the model may use about the world, for one crewmate (escape_dialogue.py).
func snapshot(id: String, message := "") -> Dictionary:
	var stage: int = state.stage()
	var step := next_step()
	var snap := {"npc_id": id, "state_version": state.version, "objective": state.objective(),
		"route": state.route(), "flags": state.flags.duplicate(), "carrying": state.carrying,
		"room": room, "crew_room": room_at(crew[id].position), "available_actions": available_actions(id),
		"recent_events": state.journal.slice(maxi(0, state.journal.size() - 5)),
		"dhan_condition": ["dead", "stable", "strained", "fading", "critical"][stage],
		"max_words": 40 if id == "mara" else [8, 30, 22, 14, 8][stage],
		"talking_points": talking_points(id),
		"next_step": step,
		"locations": {
			"fuses": "Storage, aft of Galley",
			"splint": "Medical cabinet in Medbay",
			"battery": "Laboratory, starboard side",
			"freezer": "Laboratory, starboard side",
			"cabinet": "Engineering, port side",
			"shuttle": "Shuttle Bay, aft"
		}}
	var q := answering(id, message)
	if q != "": snap["johnny_answering"] = line_text(q)
	if id == "ivo":
		# Dhan knows the code book:
		var told := {}
		var code: int = Rules.parse_code(message)
		if code > 0: told["E-%d" % code] = "spare fuse box " + state.fuse_for(code)
		var aux: int = Rules.parse_aux(message)
		if aux > 0: told["AUX-%d" % aux] = "flip the %s toggle down (of the three under the guard cover)" % ["left", "middle", "right"][state.toggle_for(aux)].to_upper()
		if state.has_flag("code_read"):
			snap["cabinet_fault_code"] = state.fault_code()
			snap["cabinet_fuse_box"] = "box " + state.right_fuse()
			told[state.fault_code()] = "spare fuse box " + state.right_fuse()
		if state.has_flag("fault_found"):
			snap["short_branch"] = state.short_branch()
			snap["short_toggle"] = ["left", "middle", "right"][state.right_toggle()]
			told[state.short_branch()] = "flip the %s toggle down" % ["left", "middle", "right"][state.right_toggle()].to_upper()
		snap["codes_johnny_read_out"] = told
		if state.has_flag("battery_out") or state.carrying == "battery cart":
			snap["lab_battery_selector"] = "position " + state.right_selector()
	else:
		var box: String = Rules.parse_box(message)
		if box != "": snap["box_johnny_named"] = box
		elif state.has_flag("code_read"): snap["box_johnny_named"] = state.right_fuse()
	return snap

## Guardrail on live replies: Dhan may only name a fuse box, toggle or selector
## setting that follows from what Johnny actually read out. A sentence that names
## anything else is dropped; the rest of the reply stays. Returns the line to show.
func check_reply(id: String, line: String, message: String) -> String:
	if id != "ivo": return line
	var code: int = Rules.parse_code(message)
	var aux: int = Rules.parse_aux(message)
	var box_ok: String = state.fuse_for(code).to_lower() if code > 0 else (state.right_fuse().to_lower() if state.has_flag("code_read") else "")
	var toggle_ok: String = ["left", "middle", "right"][state.toggle_for(aux)] if aux > 0 else (["left", "middle", "right"][state.right_toggle()] if state.has_flag("fault_found") else "")
	var knows_selector: bool = state.has_flag("battery_out") or state.carrying == "battery cart"
	var re_box := RegEx.create_from_string("\\b(?:box|fuse|bin|crate)\\s*[-:#]?\\s*([abc])\\b|\\b([abc])\\s+(?:box|fuse)\\b")
	var re_side := RegEx.create_from_string("\\b(left|middle|right)(?:-hand| hand)?\\s+(toggle|switch|one)\\b")
	# An actual switch instruction: "toggle four up", "flip the second switch down".
	var re_switch := RegEx.create_from_string("\\b(toggle|switch|flip)\\b.*\\b(up|down|one|two|three|four|five|first|second|third|[0-9])\\b")
	var re_pos := RegEx.create_from_string("\\b(?:position|setting)\\s+(iii|ii|i|1|2|3|one|two|three)\\b")
	var kept: PackedStringArray = []
	var dropped := false
	var re_sentence := RegEx.create_from_string("[^.!?]+[.!?]*")
	for hit in re_sentence.search_all(line):
		var sentence := hit.get_string().strip_edges()
		if sentence == "": continue
		var l := sentence.to_lower()
		var bad := false
		for b in re_box.search_all(l):
			var found_box: String = b.get_string(1) if b.get_string(1) != "" else b.get_string(2)
			if box_ok == "" or found_box != box_ok: bad = true
		for t in re_side.search_all(l):
			if toggle_ok == "" or t.get_string(1) != toggle_ok: bad = true
		if re_switch.search(l) != null and (toggle_ok == "" or not l.contains(toggle_ok)): bad = true
		if toggle_ok == "" and RegEx.create_from_string("\\bflip\\b").search(l) != null: bad = true
		for q in re_pos.search_all(l):
			var said: String = {"i": "I", "1": "I", "one": "I", "ii": "II", "2": "II", "two": "II", "iii": "III", "3": "III", "three": "III"}.get(q.get_string(1), "")
			if not knows_selector or said != state.right_selector(): bad = true
		if bad: dropped = true
		else: kept.append(sentence)
	if not dropped: return line
	if kept.is_empty():
		# Everything he said was a guess: answer the question from what the game knows instead,
		# so the player still gets a reply to what they asked.
		var known: Dictionary = offline_response(id, message)
		if str(known.get("action", "none")) == "none" and str(known.get("line", "")) != "": return str(known.line)
		return "Read me what the panel says, Captain. I'm not guessing." if code == 0 and aux == 0 and not state.has_flag("code_read") else "Say that again? Read it to me exactly."
	return " ".join(kept)

func ask_question(id: String, question: String) -> void:
	pending_question[id] = question
	_question_at[id] = elapsed

## The crew question this message answers, or "". A message carrying a code, switch
## or box is about the work, not an answer; and a question left too long has passed.
func answering(id: String, message: String) -> String:
	if not pending_question.has(id): return ""
	if elapsed - float(_question_at.get(id, elapsed)) > ANSWER_WINDOW:
		pending_question.erase(id)
		return ""
	if Rules.parse_code(message) > 0 or Rules.parse_aux(message) > 0 or Rules.parse_box(message) != "": return ""
	return str(pending_question[id])

## Before the reply: an answer to a crew question is kept as a promise (endings quote it).
func capture_answer(id: String, message: String) -> void:
	var q := answering(id, message)
	if q == "": return
	pending_question.erase(id)
	state.promises[q] = message.strip_edges().left(100)
	ui.radio.add_memory(id, "Johnny's answer to '%s': %s" % [line_text(q), message.strip_edges().left(60)])

## The scripted interpreter: answers offline or when the live model is unavailable.
## answering: the crew question this message answers ("" if none).
func offline_response(id: String, message: String, answering := "") -> Dictionary:
	var m := message.to_lower()
	var line := ""
	var action := "none"
	var query := m.begins_with("what") or m.begins_with("why") or m.begins_with("where") or m.begins_with("how") or m.begins_with("is ") or m.begins_with("should")
	var negative := m.contains("don't") or m.contains("do not") or m.contains("never")
	var acts := available_actions(id)
	var stage: int = state.stage()
	var step := next_step()
	if _mentions(m, ["flashlight", "torch", "your light", "a light", "light on", "light off"]) and acts.has("light_on") and not query:
		action = "light_off" if _mentions(m, ["off", "kill"]) else "light_on"
		return {"line": "Light's off." if action == "light_off" else "Light's on.", "action": action, "source": "offline"}
	if id == "ivo":
		var code: int = Rules.parse_code(message)
		var aux: int = Rules.parse_aux(message)
		if answering != "":
			line = line_text("dhan_heard")
		elif code > 0:
			line = "E-%d? That's box %s. Spares are in Storage, past the galley." % [code, state.fuse_for(code)]
			if stage >= 3: line = "E-%d... box %s." % [code, state.fuse_for(code)]
		elif aux > 0:
			line = "AUX-%d is the %s toggle. Lift the cover first." % [aux, ["left", "middle", "right"][state.toggle_for(aux)]]
			if stage >= 3: line = "%s one." % ["Left", "Middle", "Right"][state.toggle_for(aux)].capitalize()
		elif _mentions(m, ["where", "find", "locate"]):
			if _mentions(m, ["fuse", "box", "spares"]):
				line = "Spare fuses are in Storage. Go west, through the Galley."
			elif _mentions(m, ["medbay", "medkit", "splint", "medical", "doctor"]):
				line = "Medbay is west, off the corridor. The cabinet has splints."
			elif _mentions(m, ["battery", "lab", "freezer"]):
				line = "The lab is south of the junction."
			elif _mentions(m, ["cabinet", "engineering", "isolator"]):
				line = "Engineering is north of the junction."
			elif _mentions(m, ["shuttle", "bay", "dock"]):
				line = "The shuttle bay is east of the junction."
			else:
				line = "From the junction: Engineering north, the lab south, the shuttle bay east. Galley, Storage and Medbay are west."
		elif _mentions(m, ["what do", "what should", "what now", "what next", "how do", "help me"]):
			match step:
				"free_dhan": line = "Get this locker off my leg! Tell Aaron to lift it, then pull me out."
				"marvis": line = "Check in with M.A.R.V.I.S. on the junction terminal or your radio."
				"choose": line = "We need power for the bay clamps. Fix the cabinet in Engineering, or grab the lab battery."
				"eng_isolate": line = "Pull the big handle by the door first. It cuts the power to the cabinet."
				"eng_code": line = "Look at the cabinet screen and read me the fault code."
				"eng_fuse": line = "We need the fuse from box %s in Storage. Grab it and seat it in the cabinet." % (state.right_fuse() if state.has_flag("code_read") else "the right box")
				"eng_test": line = "Hit TEST on the cabinet to check the circuits."
				"eng_toggle": line = "AUX-%d is shorting. Flip the %s toggle down under the guard cover." % [state.short_branch(), ["left", "middle", "right"][state.right_toggle()]]
				"eng_restart": line = "Hit RESTART on the cabinet to power the shuttle bay."
				"bat_freezer": line = "Shut down the freezer in the Lab before you pull the battery."
				"bat_latch": line = "Open the latch on the emergency battery in the Lab."
				"bat_lift": line = "Battery's heavy. Help Aaron lift it onto the cart."
				"bat_cart": line = "Roll the cart with the battery down to the Shuttle Bay."
				"bat_socket": line = "Plug the battery into the bay socket."
				"carry": line = "The shuttle bay has power! Get me onto that shuttle, Captain."
				"seat": line = "Get in the pilot seat on the shuttle."
				"release": line = "Tell Aaron to release the clamps from the console."
				_: line = "Get us home, Captain."
		elif _mentions(m, ["selector", "setting", "position", "socket", "dial", "knob"]):
			line = "The lab battery on the bay socket? Turn the selector to %s. The wrong setting trips it." % state.right_selector()
		elif _mentions(m, ["code", "display", "screen", "fault", "error", "blinking"]):
			if state.has_flag("code_read"): line = "Cabinet says %s. That's spare box %s in Storage." % [state.fault_code(), state.right_fuse()]
			else: line = "Read me what it says. Every letter."
		elif _mentions(m, ["fuse", "box"]):
			if state.has_flag("code_read"): line = "The fault code is %s. You need the fuse from box %s in Storage." % [state.fault_code(), state.right_fuse()]
			else: line = "Which fuse depends on the fault code. Read it to me off the cabinet display."
		elif _mentions(m, ["switch", "toggle", "aux", "branch", "short", "tripped"]):
			if state.has_flag("fault_found"): line = "AUX-%d is shorting. The %s toggle under the guard cuts it." % [state.short_branch(), ["left", "middle", "right"][state.right_toggle()]]
			else: line = "It tripped? The display shows which AUX switch is shorting. Tell me the number."
		elif _mentions(m, ["spark", "cabinet", "touch", "engineering"]):
			line = "Don't touch that cabinet with the power on. Pull the big handle by the door first." if not state.has_flag("isolated") else "Power's cut? Good. Read me the code on the display."
		elif _mentions(m, ["leg", "pain", "hurt", "okay", "ok", "alright", "feel"]):
			line = ["", "Leg's... not great. I'll live. Probably.", "It's getting worse, Captain. Just keep moving.", "Cold. Keep going.", "...still here."][stage]
		elif _mentions(m, ["kien"]):
			line = "Don't. Not yet. Get us home first." if stage < 3 else "...Kien."
		elif _mentions(m, ["plan", "power", "clamp", "battery", "shuttle"]):
			line = "The shuttle's clamps need power. I can talk you through fixing the cabinet in engineering. Or use Aaron's lab battery, but then the freezer goes off." if not state.powered() else "The shuttle bay has power. Get me on that shuttle."
		else:
			line = ["", "I'm the engineer with a broken leg. Ask me about anything with wires.", "Ask me about the systems. Quickly.", "Wires. Ask.", "..."][stage]
		return {"line": line, "action": "none", "source": "offline"}
	# Aaron
	if answering != "":
		line = line_text("aaron_heard")
	elif negative:
		line = "Okay. I won't."
	elif not query and _mentions(m, ["lift", "hold", "raise", "help", "grab", "locker", "off him", "off his", "get it off", "move it", "push", "pick"]) and acts.has("lift_locker"):
		action = "lift_locker"
		line = "On it. Get ready to pull him."
	elif not query and _mentions(m, ["follow", "come with", "with me", "come on"]) and acts.has("follow"):
		action = "follow"
		line = "Right behind you."
	elif not query and _mentions(m, ["wait here", "stay here", "hold position", "stay put"]) and acts.has("wait"):
		action = "wait"
		line = "I'll wait here."
	elif not query and _mentions(m, ["stay with dhan", "look after dhan", "keep dhan", "watch dhan", "stay with him"]) and acts.has("stay_with_dhan"):
		action = "stay_with_dhan"
		line = "I'll stay with him."
	elif not query and _mentions(m, ["fuse"]) and acts.has("fetch_fuse"):
		var box: String = Rules.parse_box(message)
		if box == "": line = "Which box? I don't know which one it needs."
		else:
			action = "fetch_fuse"
			line = "Box %s. I'll leave it by the cabinet." % box
	elif not query and _mentions(m, ["case", "cooler"]) and acts.has("fetch_case"):
		action = "fetch_case"
		line = "The insulated case. I'll get it from the shuttle."
	elif not query and _mentions(m, ["lift", "battery", "help", "cart", "load"]) and acts.has("lift_battery"):
		action = "lift_battery"
		line = "Meet me at the cart. We lift on three."
	elif not query and _mentions(m, ["carry", "dhan", "help", "shuttle", "aboard"]) and acts.has("carry_dhan"):
		action = "carry_dhan"
		line = "Let's get him aboard."
	elif not query and _mentions(m, ["release", "clamp", "go", "open"]) and acts.has("release_clamps"):
		action = "release_clamps"
		line = "Releasing the clamps."
	elif _mentions(m, ["where", "find", "locate"]):
		if _mentions(m, ["fuse", "box", "spares"]):
			line = "Storage is west, past the Galley. That's where the spare fuse boxes are."
		elif _mentions(m, ["medbay", "medkit", "splint", "medical", "doctor"]):
			line = "Medbay is west, off the corridor. The medical cabinet has a splint kit."
		elif _mentions(m, ["battery", "lab", "freezer"]):
			line = "The lab is south of the junction."
		elif _mentions(m, ["cabinet", "engineering", "isolator"]):
			line = "Engineering is north of the junction."
		elif _mentions(m, ["shuttle", "bay", "dock"]):
			line = "The shuttle bay is east of the junction."
		else:
			line = "From the junction: Engineering north, the lab south, the shuttle bay east. Galley, Storage and Medbay are west."
	elif _mentions(m, ["what do", "what should", "what now", "what next", "how do", "help me"]):
		match step:
			"free_dhan": line = "We have to get the locker off Dhan's leg! I can lift it while you pull him free."
			"marvis": line = "Ask M.A.R.V.I.S. what still works."
			"choose": line = "We need power for the shuttle clamps: either repair Engineering or take the lab battery."
			"eng_isolate", "eng_code", "eng_fuse", "eng_test", "eng_toggle", "eng_restart": line = "Dhan knows the engineering cabinet best. Radio him for instructions."
			"bat_freezer": line = "If we take the battery, the freezer goes off. Or I can grab the shuttle sample case first."
			"bat_latch": line = "Unlatch the battery in the Lab."
			"bat_lift": line = "The battery's too heavy for one person. Meet me at the cart and we'll lift on three."
			"bat_cart": line = "Push the cart to the Shuttle Bay socket."
			"bat_socket": line = "Connect the battery in the Shuttle Bay."
			"carry": line = "We have power! Let's carry Dhan to the shuttle together."
			"seat": line = "Get in the shuttle's pilot seat, Johnny."
			"release": line = "I'm at the clamp console. Tell me when you're in the pilot seat."
			_: line = "Let's get everyone home."
	elif _mentions(m, ["sample", "research", "save", "freezer", "other option", "another way", "alternative"]):
		if state.has_flag("samples_saved"): line = "The priority rack is in the case. Kien would've liked that."
		elif state.has_flag("freezer_off"): line = "They're gone. It's okay. It has to be."
		elif state.has_flag("case_arrived"): line = "The case is by the freezer. Only one rack fits. The priority rack."
		elif state.has_flag("case_requested"): line = "I'm getting the case."
		else: line = "There's an insulated case on the shuttle. It'd only fit the priority rack, but... I could fetch it."
	elif _mentions(m, ["dhan", "leg", "medic", "splint", "pain"]):
		line = "He needs a splint on that leg. The medbay cabinet should have one." if state.dhan_alive() and not state.has_flag("dhan_treated") else ("He's splinted. Let's not waste it." if state.dhan_alive() else "...He's gone, Johnny.")
	elif _mentions(m, ["kien"]):
		line = "We collected every one of those samples together. I keep expecting him to walk in."
	elif _mentions(m, ["power", "plan", "battery", "engineering", "clamp"]):
		line = "The shuttle's clamps need power. Dhan can talk you through fixing the cabinet in engineering. Or we use the lab battery, but then we lose the samples." if not state.powered() else "The shuttle bay has power. Dhan goes on the shuttle first, then we release the clamps."
	elif _mentions(m, ["scared", "afraid", "okay", "ok", "home", "earth"]):
		line = "Scared? Yes. But we've got a way home. Let's take it."
	else:
		line = "I'm with you. " + state.objective()
	if action != "none" and not acts.has(action):
		action = "none"
	return {"line": line, "action": action, "source": "offline"}

func _mentions(message: String, words: Array) -> bool:
	for word in words:
		if message.contains(word): return true
	return false

# --- Launch and endings (section 7) ---------------------------------------------------

## Launch (section 7): sirens, every door seals, a hatch opens under the shuttle and
## it drops out of the ship. Then the ending film (scripts/ui/outro_film.gd), then stats.
func _launch() -> void:
	_save_ready = false
	SaveGame.delete_progress()
	ending = true
	launching = true
	active = false
	_hold.clear()
	ui.close()
	Sfx.stop_ambient()
	var id: String = state.ending()
	_record_discovery("endings", id)
	ui.alarm(true)
	ui.show_caption("SHUTTLE", "Launch sequence. Bulkheads sealing. Stand clear of the hatch.")
	var shuttle = props.shuttle
	shuttle.caption.visible = false
	var tw := create_tween()
	tw.tween_callback(func():
		Sfx.play("door", -2)
		Haptics.play("slam"))
	tw.tween_property(ship, "sealed", 1.0, 0.7).set_trans(Tween.TRANS_QUAD)
	tw.tween_interval(0.6)
	tw.tween_callback(func():
		Sfx.play("door", -6)
		Haptics.play("clamps")
		ui.show_caption("SHUTTLE", "Hatch open. Releasing."))
	tw.tween_property(ship, "hatch", 1.0, 1.3).set_trans(Tween.TRANS_SINE)
	# It falls through the hatch (drawn under the floor from here on, see escape_ship.gd)...
	tw.tween_callback(func():
		shuttle.visible = false
		Sfx.play("hit", -8)
		Haptics.play("thud"))
	tw.tween_property(ship, "drop", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# ...then lights its engines and flies forward under the hull, out of sight.
	tw.tween_callback(func():
		Sfx.play("launch", -2)
		Haptics.play("launch")
		ui.shake(1.6)
		ui.show_caption("SHUTTLE", "Clear of the bay. Main engines."))
	tw.tween_property(ship, "thrust", 1.0, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.4)
	tw.tween_callback(func(): ui.fade_black(0.7, _play_outro.bind(id)))

func _play_outro(id: String) -> void:
	ui.alarm(false)
	_set_wide(false)  # the film is 16:9, like the opening
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	outro = Outro.new()
	outro.setup(id, state.promises.has("stage3_dhan_question") and state.dhan_alive())
	layer.add_child(outro)
	outro.finished.connect(func():
		ui.show_ending(id)
		layer.queue_free()
		outro = null)
	outro.play()

func discoveries() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(discoveries_path)
	return {"endings": cfg.get_value("found", "endings", []), "fails": cfg.get_value("found", "fails", [])}

func _record_discovery(kind: String, id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(discoveries_path)
	var found: Array = cfg.get_value("found", kind, [])
	if not found.has(id):
		found.append(id)
		cfg.set_value("found", kind, found)
		var err := cfg.save(discoveries_path)
		if err != OK:
			push_warning("Failed to save discoveries to %s: %d" % [discoveries_path, err])

# --- Display ----------------------------------------------------------------------

func prop_done(id: String) -> bool:
	var mapping := {"isolate": "isolated", "cabinet": "engineering_power", "aux": "aux_off", "battery": "battery_out",
		"cart": "battery_taken", "socket": "battery_connected", "release": "clamps", "medkit": "splint_taken", "case": "samples_saved"}
	return state.has_flag(mapping.get(id, "_"))

func refresh() -> void:
	for prop in props.values(): prop.refresh()
	props.locker.visible = not state.has_flag("dhan_free")
	props.case.visible = state.has_flag("case_arrived")
	props.cart.visible = not state.has_flag("battery_taken")
	props.battery.visible = not state.has_flag("battery_loaded")
	props.airlock.visible = true
	if state.has_flag("freezer_off"):
		props.freezer.caption.text = "FREEZER OFF"
		props.freezer.caption.modulate = Color("ef8a81")
	if ui != null: ui.update_hud()
	if ship != null: ship.queue_redraw()

func _exit_tree() -> void:
	save_progress()
	Sfx.stop_ambient()
	_set_wide(false)

func _set_wide(on: bool) -> void:
	var win := get_window()
	if win != null:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if on else Window.CONTENT_SCALE_ASPECT_KEEP

func restart_run() -> void:
	_save_ready = false
	SaveGame.delete_progress()
	Settings.intro_pending = false
	get_tree().reload_current_scene()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		save_progress()

# --- Saves (schema 2; checked by SaveGame.compatible and server/save_games.py) --------

func save_progress() -> void:
	if not _save_ready or ending or not SaveGame.enabled or scripted: return
	SaveGame.store(progress_snapshot())

func progress_snapshot() -> Dictionary:
	var actors := {}
	for id in crew:
		var actor = crew[id]
		var points: Array = []
		for point in actor.path: points.append([point.x, point.y])
		var task := str(_busy.get(id, "")).trim_suffix("_walk")
		actors[id] = {"position": [actor.position.x, actor.position.y], "facing": [actor.facing.x, actor.facing.y],
			"following": actor.following, "light_on": actor.light_on, "cargo": actor.cargo.visible,
			"path": points, "task": task if task in TASKS else "", "visible": actor.visible, "pose": actor.pose}
	var player_at: Vector2 = player.position if not seated else anchor("board_aaron") + Vector2(-30, 0)
	return {"schema": SCHEMA, "map": MAP_ID,
		"state": {"flags": state.flags.duplicate(), "carrying": state.carrying, "version": state.version,
			"journal": state.journal.slice(maxi(0, state.journal.size() - 40)), "learned": state.learned.keys(),
			"puzzle": state.puzzle.duplicate(true), "vitality": snappedf(state.vitality, 0.01),
			"fails": state.fails.keys(), "promises": state.promises.duplicate(), "fuse_at_cabinet": state.fuse_at_cabinet,
			"selector": state.selector, "fuse_task": str(_task_arg.get("mara", ""))},
		"said": _said.keys().filter(func(k): return lines.has(k) or k == "marvis_summary"),
		"player": {"position": [player_at.x, player_at.y]}, "crew": actors, "elapsed": elapsed,
		"flashlight": darkness.flashlight, "history": ui.radio.histories.duplicate(true),
		"memory_notes": ui.radio.memory_notes.duplicate(true)}

## Same rules as SaveGame.compatible() for the parts only this scene understands.
func compatible_save(data: Dictionary) -> bool:
	return data.get("schema") == SCHEMA and data.get("map") == MAP_ID

func _safe_point(point: Array, fallback: Vector2) -> Vector2:
	var target := Vector2(float(point[0]), float(point[1]))
	var cell := Vector2i(floori(target.x / TILE), floori(target.y / TILE))
	return target if nav.is_in_boundsv(cell) and not nav.is_point_solid(cell) else fallback

func _restore_progress(data: Dictionary) -> void:
	var s: Dictionary = data.state
	state.flags = s.flags.duplicate()
	state.carrying = str(s.carrying)
	state.version = int(s.version)
	state.journal.assign(s.journal)
	for k in s.get("learned", []): state.learned[str(k)] = true
	var pz: Dictionary = s.get("puzzle", {})
	if pz.has("code") and pz.has("fuse_for") and pz.has("toggle_for"):
		state.puzzle = {
			"code": int(pz.code),
			"fuse_for": {"3": str(pz.fuse_for.get("3", "A")), "6": str(pz.fuse_for.get("6", "B")), "9": str(pz.fuse_for.get("9", "C"))},
			"aux": int(pz.get("aux", 1)),
			"toggle_for": {"1": int(pz.toggle_for.get("1", 0)), "2": int(pz.toggle_for.get("2", 1)), "3": int(pz.toggle_for.get("3", 2))},
			"selector": int(pz.get("selector", 0))
		}
	state.vitality = clampf(float(s.get("vitality", 100.0)), 0.0, 100.0)
	for f in s.get("fails", []): state.fails[str(f)] = true
	state.promises = s.get("promises", {}).duplicate()
	state.fuse_at_cabinet = str(s.get("fuse_at_cabinet", ""))
	state.selector = int(s.get("selector", 0))
	for k in data.get("said", []): _said[str(k)] = true
	_stage_seen = maxi(1, state.stage())
	elapsed = float(data.elapsed)
	if state.has_flag("dhan_free"):
		locker_body.process_mode = Node.PROCESS_MODE_DISABLED
		locker_body.get_child(0).set_deferred("disabled", true)
		_set_locker_nav(false)
		locker_visual.position = anchor("locker_cleared")
		locker_visual.rotation = -PI / 2.0
		_block_cleared_locker()
	player.position = _safe_point(data.player.position, anchor("player_start"))
	player.snap_camera()
	for id in crew:
		var actor = crew[id]
		var saved: Dictionary = data.crew[id]
		actor.position = _safe_point(saved.position, actor.position)
		actor.facing = Vector2(float(saved.facing[0]), float(saved.facing[1]))
		actor.following = bool(saved.following)
		actor.light_on = bool(saved.light_on)
		actor.set_cargo(bool(saved.cargo))
		actor.visible = bool(saved.get("visible", true))
		actor.pose = str(saved.get("pose", "stand"))
		if not saved.path.is_empty():
			var target: Array = saved.path[-1]
			actor.path = find_path(actor.position, Vector2(float(target[0]), float(target[1])))
		if saved.task != "": _busy[id] = str(saved.task)
	if str(s.get("fuse_task", "")) != "": _task_arg["mara"] = str(s.fuse_task)
	# Poses that follow from the story, whatever was saved.
	if state.has_flag("dhan_dead"): crew.ivo.pose = "dead"
	elif not state.has_flag("dhan_free"): crew.ivo.pose = "pinned"
	elif crew.ivo.pose in ["pinned", "carried"]: crew.ivo.pose = "sit"
	if state.has_flag("dhan_aboard"): crew.ivo.visible = false
	if state.has_flag("aaron_aboard"): crew.mara.visible = false
	if crew.mara.pose == "straining": crew.mara.pose = "stand"
	darkness.flashlight = bool(data.flashlight)
	# The saved conversation can be ahead of the saved state ("On it!" before the lift
	# happened), so a resumed crewmate would think it's done. Start the talk fresh and keep
	# only the facts they remember (memory notes: promises, wishes).
	ui.radio.histories = {"mara": [], "ivo": []}
	ui.radio.memory_notes = {"mara": data.get("memory_notes", {}).get("mara", []).duplicate(true), "ivo": data.get("memory_notes", {}).get("ivo", []).duplicate(true)}
	_resumed = true
	var cover_layer := CanvasLayer.new()
	cover_layer.layer = 150
	add_child(cover_layer)
	_resume_cover = ColorRect.new()
	_resume_cover.color = Color.BLACK
	_resume_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_layer.add_child(_resume_cover)
	_resume_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refresh()

## Restart crew tasks that were under way when the game was saved.
func _resume_tasks() -> void:
	var tasks := _busy.duplicate()
	_busy.clear()
	for id in tasks:
		match str(tasks[id]):
			"lift_locker": act_on_dialogue(id, "lift_locker")
			"lift_battery": act_on_dialogue(id, "lift_battery")
			"carry_dhan": act_on_dialogue(id, "carry_dhan")
			"fetch_case": _fetch_case()
			"fetch_fuse":
				if _task_arg.has("mara"): _fetch_fuse(str(_task_arg.mara))
			"release_clamps":
				# Seats aren't saved: Aaron waits for Johnny to sit and ask again.
				if state.has_flag("clamps") and not state.has_flag("aaron_aboard"):
					crew.mara.go_to(anchor("board_aaron"), func():
						crew.mara.visible = false
						perform("aaron_aboard"))
	if state.has_flag("case_requested") and not state.has_flag("case_arrived") and _busy.get("mara", "") != "fetch_case":
		_fetch_case()

func _reveal_resume() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var fade := create_tween()
	fade.tween_property(_resume_cover, "color:a", 0.0, 0.42).set_trans(Tween.TRANS_SINE)
	fade.tween_callback(_resume_cover.get_parent().queue_free)
