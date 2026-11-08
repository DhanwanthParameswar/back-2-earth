extends Node2D
## Self-contained, reversible design prototype. The original mission is untouched.

# NPC IDs mara/ivo remain stable for compatibility with the hosted radio API.
const Rules = preload("res://scripts/prototype/escape_state.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Actor = preload("res://scripts/prototype/escape_actor.gd")
const Prop = preload("res://scripts/prototype/escape_prop.gd")
const Interface = preload("res://scripts/prototype/escape_ui.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const Intro = preload("res://scripts/ui/intro_cutscene.gd")
const Darkness = preload("res://scripts/prototype/escape_darkness.gd")
const ShipMap = preload("res://scripts/prototype/escape_ship.gd")
const TILE := 32
## The ship interior: rooms, walls, furniture and the spots the story uses all
## come from data/escape_map.json (tools/make_escape_map.py). escape_ship.gd draws it.
const MAP_PATH := "res://data/escape_map.json"

var state = Rules.new()
var player
var crew := {}
var props := {}
var world: Node2D
var ui
var active := false
var ending := false
var elapsed := 0.0
var room := "CORRIDOR"
var floors := {}           # walkable cells (Vector2i -> true)
var walls := {}            # blocking cells next to floor (for collision)
var nav := AStarGrid2D.new()
var map_data := {}
var map_size := Vector2i.ZERO
var anchors := {}          # name -> Vector2 (px)
var rooms := []            # [{name, color, ...}] from the map file
var _room_grid: PackedStringArray
var _room_by_key := {}
var ship                   # escape_ship.gd: draws floors, walls, decor
var locker_body: StaticBody2D
var locker_visual: Sprite2D
var carried_visual: Sprite2D
var _intro = null
var darkness
var _busy_actors := {}

func _ready() -> void:
	GameState.new_run()
	add_to_group("ship")
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
	_add_actor("ivo", "DHAN · PILOT", "nebula", anchor("dhan_start"), Color("b18ada"))
	player = PlayerScene.instantiate()
	player.position = anchor("player_start")
	world.add_child(player)
	player.set_camera_limits(Rect2(Vector2.ZERO, Vector2(map_size * TILE)))
	player.snap_camera()
	carried_visual = Sprite2D.new()
	carried_visual.texture = load("res://assets/sprites/crate.png")
	carried_visual.scale = Vector2(0.65, 0.65)
	world.add_child(carried_visual)
	darkness = Darkness.new()  # dark until power is back; F = flashlight
	darkness.mission = self
	add_child(darkness)
	ui = Interface.new()
	ui.mission = self
	add_child(ui)
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
	ui._layout.call_deferred()  # re-fit the HUD to the now-wider screen
	active = true
	GameState.begin_play()
	Sfx.start_ambient()
	announce("AARON", "You're okay. Good. That locker is caught at the top; I can hold it while you push.")
	refresh()

func _load_map() -> void:
	map_data = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	map_size = Vector2i(int(map_data.size[0]), int(map_data.size[1]))
	for key in map_data.anchors:
		anchors[key] = Vector2(map_data.anchors[key][0], map_data.anchors[key][1])
	rooms = map_data.rooms
	for r in rooms:
		_room_by_key[r.key] = r
	_room_grid = PackedStringArray(map_data.room_grid)

## A named spot from the map file (px).
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
	# Furniture is solid where it stands (its base), for the player and the crew.
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

func _add_prop(id: String, title: String, texture: String, color: Color, solid := true) -> void:
	var info: Dictionary = map_data.props[id]
	var prop = Prop.new()
	prop.mission = self
	prop.prop_id = id
	prop.title = title
	prop.texture_path = ("res://assets/ship/" + texture + ".png") if texture != "" else ""
	prop.accent = color
	prop.solid = solid
	prop.position = Vector2(info.pos[0], info.pos[1])
	world.add_child(prop)
	props[id] = prop

func _prop_sprite(id: String) -> String:
	return map_data.props[id].sprite

func _build_props() -> void:
	# The jammed locker: a solid block across the hallway until it is pushed clear.
	_add_prop("locker", "JAMMED LOCKER", "", Color("e0ad65"), false)
	locker_body = StaticBody2D.new()
	var bounds := Rect2()
	for c in _locker_cells():
		var r := Rect2(Vector2(c * TILE), Vector2(TILE, TILE))
		bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)
	_add_box(locker_body, bounds)
	add_child(locker_body)
	locker_visual = Sprite2D.new()
	locker_visual.texture = load("res://assets/ship/" + _prop_sprite("locker") + ".png")
	locker_visual.offset = Vector2(0, -locker_visual.texture.get_height() / 2.0)
	locker_visual.position = anchor("locker_visual")
	world.add_child(locker_visual)
	_add_prop("terminal", "LAUNCH STATUS", _prop_sprite("terminal"), Color("81c5d9"))
	_add_prop("isolate", "CIRCUIT CUTOFF", _prop_sprite("isolate"), Color("e0ad65"))
	_add_prop("fuse", "SPARE FUSE", _prop_sprite("fuse"), Color("e0ad65"))
	_add_prop("cabinet", "DISTRIBUTION", _prop_sprite("cabinet"), Color("e0ad65"))
	_add_prop("aux", "AUX BRANCH", _prop_sprite("aux"), Color("e0ad65"))
	_add_prop("freezer", "SAMPLE FREEZER", _prop_sprite("freezer"), Color("87d5b3"))
	_add_prop("battery", "EMERGENCY BATTERY", _prop_sprite("battery"), Color("87d5b3"))
	_add_prop("cart", "SERVICE CART", _prop_sprite("cart"), Color("87d5b3"))
	_add_prop("case", "SAMPLE CASE", _prop_sprite("case"), Color("87d5b3"), false)
	props["case"].visible = false
	_add_prop("socket", "EMERGENCY SOCKET", _prop_sprite("socket"), Color("9bace8"))
	_add_prop("release", "DOCKING CLAMPS", _prop_sprite("release"), Color("9bace8"))
	_add_prop("shuttle", "BOARD SHUTTLE", _prop_sprite("shuttle"), Color("9bace8"))

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

func room_at(point: Vector2) -> String:
	var c := Vector2i(floori(point.x / TILE), floori(point.y / TILE))
	if c.x < 0 or c.y < 0 or c.y >= _room_grid.size() or c.x >= _room_grid[c.y].length(): return "PASSAGE"
	var key := _room_grid[c.y][c.x]
	return _room_by_key[key].name if _room_by_key.has(key) else "PASSAGE"

func _process(delta: float) -> void:
	if not active or ending: return
	elapsed += delta
	room = room_at(player.position)
	carried_visual.visible = state.carrying != ""
	carried_visual.position = player.position + Vector2(25, 4)
	ui.update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if not active or ending or ui.is_open(): return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: open_chat("mara")
			KEY_2: open_chat("ivo")
			KEY_TAB: ui.show_map()
			KEY_ESCAPE: ui.show_pause()
			KEY_M: Settings.toggle_mute()
			KEY_F: darkness.toggle_flashlight()

func open_chat(id: String) -> void:
	if not active or ending: return
	ui.open_chat(id)

func announce(speaker: String, line: String) -> void:
	if ui != null: ui.show_caption(speaker, line)
	# No speech bubbles: lines show as text above the HUD bar (and in the chat box).

func use_prop(id: String) -> void:
	match id:
		"locker": perform("push_locker")
		"terminal":
			if not state.has_flag("assessed"): perform("assess")
			ui.show_routes()
		"isolate": perform("isolate")
		"fuse": perform("take_fuse")
		"cabinet": perform("cabinet")
		"aux":
			if state.has_flag("fault_found") and not state.has_flag("aux_off"):
				ui.confirm_action("Disconnect cabin lighting?", "The damaged cabin-lighting branch is shorted. Isolating it will let the shuttle supply restart. The lab keeps its power.", "aux")
			else: perform("aux")
		"freezer":
			if state.has_flag("case_arrived") and not state.has_flag("samples_saved"):
				perform("pack_samples")
			else:
				announce("AARON", "Living samples. The battery keeps them cold. Dhan has an insulated case aboard the shuttle; it can hold the priority rack." if not state.has_flag("battery_out") else "Cooling is offline. " + ("The priority rack is safe in the case." if state.has_flag("samples_saved") else "The samples are lost. Let's get the crew home."))
		"battery":
			if state.route == "battery" and not state.has_flag("battery_out"):
				var consequence := "Priority samples are packed. The remaining research will be lost." if state.has_flag("samples_saved") else "All living samples will be lost. You can ask Dhan to fetch the insulated case before committing."
				ui.confirm_action("Disconnect freezer power?", consequence + " The crew remains safe. This choice cannot be undone.", "disconnect_battery")
			else: perform("disconnect_battery")
		"cart": perform("take_cart")
		"case": perform("pack_samples")
		"socket": perform("connect_battery")
		"release": perform("release")
		"shuttle":
			if state.has_flag("clamps"):
				if not crew_ready():
					announce("DHAN", "We're walking aboard. Give us a moment before departure.")
					return
				var cargo := "All research preserved aboard the main ship for recovery." if state.route == "engineering" else "Priority samples aboard." if state.has_flag("samples_saved") else "Research left behind."
				ui.confirm_action("Three seats. One destination.", "Johnny, Aaron and Dhan are ready. " + cargo + " Launch for Earth?", "launch")
			else: perform("launch")

func perform(action: String) -> Dictionary:
	if action == "launch" and not crew_ready(): return {"ok": false, "line": "Wait until both crewmates have boarded."}
	if action == "push_locker" and (crew.mara.position.distance_to(anchor("locker_hold")) > 45 or crew.mara.following):
		var refused := {"ok": false, "line": "Aaron needs to hold the top. Ask him to help with the locker first."}
		announce("SHIP", refused.line)
		return refused
	var result: Dictionary = state.apply(action)
	announce("SHIP", result.line)
	if result.ok:
		Sfx.play("door" if action in ["push_locker", "release"] else "objective", -8)
		match action:
			"push_locker":
				locker_body.process_mode = Node.PROCESS_MODE_DISABLED
				locker_body.get_child(0).set_deferred("disabled", true)
				_set_locker_nav(false)
				_swing_locker_clear()
				crew.mara.following = true
			"assess":
				crew.ivo.go_to(anchor("bay_watch"))
			"fetch_case":
				_busy_actors["ivo"] = true
				crew.ivo.go_to(anchor("shuttle_side"), func():
					crew.ivo.set_cargo(true)
					crew.ivo.go_to(anchor("case_drop"), func():
						crew.ivo.set_cargo(false)
						_busy_actors.erase("ivo")
						if not ending: perform("case_arrived")))
			"release":
				crew.mara.go_to(anchor("board_aaron"))
				crew.ivo.go_to(anchor("board_dhan"))
			"launch": _launch()
		refresh()
	return result

## The push: the locker jolts, then swings round on its far end and scrapes to
## rest lying along the north wall, kicking up dust. It stays solid there.
func _swing_locker_clear() -> void:
	var rest := anchor("locker_cleared")
	var tw := create_tween()
	tw.tween_property(locker_visual, "position", locker_visual.position + Vector2(-4, 0), 0.08)
	tw.tween_property(locker_visual, "position", locker_visual.position + Vector2(-1, 0), 0.06)
	tw.tween_interval(0.08)
	tw.set_parallel(true)
	tw.tween_property(locker_visual, "rotation", -PI / 2.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(locker_visual, "position", rest, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(false)
	tw.tween_callback(func():
		_dust(rest + Vector2(-50, 0))
		Sfx.play("hit", -10)
		_block_cleared_locker())
	_dust(locker_visual.position + Vector2(0, -40))

## The fallen locker now lies along the wall: solid for the player and the crew.
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

func crew_ready() -> bool:
	return crew.mara.position.distance_to(anchor("board_aaron")) < 20 and crew.ivo.position.distance_to(anchor("board_dhan")) < 20

func refresh() -> void:
	for prop in props.values(): prop.refresh()
	props["case"].visible = state.has_flag("case_arrived")
	props["locker"].visible = not state.has_flag("locker_clear")  # nothing left to push
	props["cart"].visible = not state.has_flag("battery_taken")
	props["battery"].visible = not state.has_flag("battery_loaded")
	if state.has_flag("battery_out"):
		props["freezer"].caption.text = "COOLING OFFLINE"
		props["freezer"].caption.modulate = Color("ef8a81")
	if state.has_flag("samples_saved"):
		props["case"].caption.text = "SAMPLES SECURED"
	if ui != null: ui.update_hud()
	if ship != null: ship.queue_redraw()

func _exit_tree() -> void:
	Sfx.stop_ambient()
	_set_wide(false)

## Gameplay fills the whole window (a wide browser just shows more of the ship);
## the menu and the opening film stay 16:9 because they are 16:9 videos.
func _set_wide(on: bool) -> void:
	var win := get_window()
	if win != null:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if on else Window.CONTENT_SCALE_ASPECT_KEEP

func prop_done(id: String) -> bool:
	var mapping := {"locker": "locker_clear", "terminal": "assessed", "isolate": "isolated", "fuse": "fuse_taken", "cabinet": "engineering_power", "aux": "aux_off", "freezer": "samples_saved", "battery": "battery_out", "cart": "battery_loaded", "case": "samples_saved", "socket": "battery_connected", "release": "clamps"}
	return state.has_flag(mapping.get(id, ""))

func available_actions(id: String) -> Dictionary:
	var actions := {"none": "Answer a question using the current situation; no action.", "follow": "Follow the engineer.", "wait": "Wait at your current position."}
	if state.has_flag("clamps"): return {"none": "The crew is boarding. Answer briefly; do not leave the shuttle."}
	if _busy_actors.has(id): return {"none": "Currently completing an assigned task. Report progress; do not start another task."}
	if id == "mara":
		if not state.has_flag("locker_clear"): actions["help_locker"] = "Walk to the jammed locker lying across the hallway (players may call it the 'door') and hold it while the player pushes."
		if state.has_flag("battery_out") and not state.has_flag("battery_loaded"): actions["load_battery"] = "Help the player lift the lab battery onto the cart. Player must be beside the cart."
	if id == "ivo" and state.has_flag("assessed") and not state.has_flag("case_requested") and not state.has_flag("battery_out"):
		actions["fetch_case"] = "Fetch the insulated case from the shuttle and deliver it to the lab freezer."
	if not state.powered():  # dark ship: the crew can aim their flashlights
		for dir in ["up", "down", "left", "right"]:
			actions["light_" + dir] = "Turn on your flashlight and point it " + dir + " (on the screen)."
		if crew.has(id) and crew[id].light_dir != Vector2.ZERO:
			actions["light_off"] = "Turn your flashlight off."
	return actions

func act_on_dialogue(id: String, action: String) -> String:
	if action == "none" or action == "": return ""
	if not available_actions(id).has(action): return "That task is no longer available. " + state.objective()
	var actor = crew[id]
	match action:
		"light_up", "light_down", "light_left", "light_right":
			actor.light_dir = {"light_up": Vector2.UP, "light_down": Vector2.DOWN, "light_left": Vector2.LEFT, "light_right": Vector2.RIGHT}[action]
		"light_off":
			actor.light_dir = Vector2.ZERO
		"follow":
			if find_path(actor.position, player.position).is_empty(): return "The hallway is blocked by the locker. Clear it with Aaron first."
			actor.following = true
		"wait":
			actor.following = false
			actor.path.clear()
		"help_locker", "load_battery":
			var target := anchor("locker_hold") if action == "help_locker" else anchor("cart_lift")
			var player_target: Vector2 = anchor("locker_push") if action == "help_locker" else props["cart"].position
			# He always walks over; if the player isn't there yet he waits, and
			# the task starts as soon as the player arrives.
			_busy_actors[id] = true
			actor.go_to(target, func(): _start_when_player_near(id, action, player_target))
		"fetch_case": perform("fetch_case")
	return ""

## Crew task that needs the player beside it: start now if they're close,
## otherwise say so once and keep checking until they walk up.
func _start_when_player_near(id: String, action: String, player_target: Vector2) -> void:
	if ending or not available_actions(id).has(action) and not _busy_actors.has(id):
		_busy_actors.erase(id)
		return
	if player.position.distance_to(player_target) <= 115:
		_busy_actors.erase(id)
		perform(action)
		return
	if not crew[id].has_meta("waiting_for_player"):
		crew[id].set_meta("waiting_for_player", true)
		announce("AARON", "I'm at the locker. Come push when you're ready." if action == "help_locker" else "I'm at the cart. Come here and we'll lift it together.")
	get_tree().create_timer(0.25).timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			if player.position.distance_to(player_target) <= 115:
				crew[id].remove_meta("waiting_for_player")
			_start_when_player_near(id, action, player_target))

func snapshot(id: String) -> Dictionary:
	return {"npc_id": id, "state_version": state.version, "objective": state.objective(), "route": state.route, "flags": state.flags.duplicate(), "carrying": state.carrying, "room": room, "available_actions": available_actions(id), "recent_events": state.journal.slice(maxi(0, state.journal.size() - 5))}

func offline_response(id: String, message: String) -> Dictionary:
	var m := message.to_lower()
	var line := ""
	var action := "none"
	var query := m.begins_with("what") or m.begins_with("why") or m.begins_with("where") or m.begins_with("how")
	var negative := m.contains("don't") or m.contains("do not") or m.contains("stop") or m.contains("never")
	if not state.powered() and _mentions(m, ["light", "flashlight", "torch", "beam", "shine"]):
		var dirs := {"up": "light_up", "north": "light_up", "down": "light_down", "south": "light_down", "left": "light_left", "west": "light_left", "right": "light_right", "east": "light_right"}
		for word in dirs.keys():
			if _mentions(m, [word]) and available_actions(id).has(dirs[word]): action = dirs[word]
		if _mentions(m, ["off", "turn it off", "kill"]) and available_actions(id).has("light_off"): action = "light_off"
		line = "Light off." if action == "light_off" else ("Pointing my light that way." if action != "none" else "Which way should I point my flashlight? Up, down, left or right?")
	elif _mentions(m, ["your name", "who are you"]):
		line = "I'm %s. " % crew[id].display_name.split(" · ")[0].capitalize() + state.objective()
	elif negative:
		line = "Understood. I won't start another task. " + state.objective()
	elif not query and _mentions(m, ["follow", "come with", "stay with me"]):
		action = "follow"
		line = "I'm with you. Lead the way."
	elif not query and _mentions(m, ["wait here", "stay here", "hold position"]):
		action = "wait"
		line = "I'll wait here. Call me on the radio when you need me."
	elif id == "mara" and not state.has_flag("locker_clear"):
		if not query and _mentions(m, ["help", "hold", "lift", "tilt", "grab", "move", "push"]): action = "help_locker"
		line = "I'll hold the top. You push the locker when I'm in position." if action != "none" else "The locker is wedged against the doorway. Ask me to hold it while you push."
	elif id == "mara" and state.has_flag("battery_out") and not state.has_flag("battery_loaded"):
		if not query and _mentions(m, ["help", "lift", "load", "grab", "carry", "battery", "cart"]): action = "load_battery"
		line = "Meet me at the cart. We can lift the battery together."
	elif _mentions(m, ["sample", "research", "case", "cooler", "save", "preserve"]):
		if state.has_flag("samples_saved"): line = "The priority rack is safe in the insulated case. We kept what matters most."
		elif state.has_flag("battery_out"): line = "Cooling has stopped. The samples are lost, but the three of us can still make it home."
		elif state.has_flag("case_arrived"): line = "The case is beside the freezer. Pack the priority rack before disconnecting power."
		elif state.has_flag("case_requested"): line = "I'm delivering the case to the laboratory." if id == "ivo" else "Dhan is bringing the case. Keep the freezer connected until we've packed."
		else:
			line = "There's an insulated case in the shuttle. Ask Dhan to fetch it; we can save the priority rack."
			if id == "ivo" and not query and _mentions(m, ["fetch", "bring", "get", "save", "retrieve", "preserve"]):
				action = "fetch_case"
				line = "I'll fetch the insulated case and bring it to the lab. Keep cooling on until we've packed."
	elif _mentions(m, ["feel", "scared", "okay", "afraid", "home", "earth"]):
		line = "Scared? Yes. But you're here, and we've got a way home. Let's finish this together." if id == "mara" else "I've landed worse ships. Probably. Let's get all three of us home."
	elif _mentions(m, ["engine", "repair", "power", "battery", "plan", "shuttle", "clamp"]):
		line = "Engineering preserves the research. The lab battery powers an emergency release but stops sample cooling. Choose at the junction launch terminal. " if state.route == "" else ""
		line += state.objective()
	else:
		line = ("I can help with the equipment and samples. " if id == "mara" else "I'll handle the shuttle and fetch the sample case if you need it. ") + state.objective()
	if action != "none" and not available_actions(id).has(action):
		action = "none"
		line = "I'm finishing the task we agreed on. " + state.objective()
	return {"line": line, "action": action, "source": "offline"}

func _mentions(message: String, words: Array) -> bool:
	for word in words:
		if message.contains(word): return true
	return false

func _launch() -> void:
	ending = true
	active = false
	Sfx.stop_ambient()
	Sfx.play("launch", -4)
	ui.show_ending()
