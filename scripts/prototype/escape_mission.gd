extends Node2D
## Self-contained, reversible design prototype. The original mission is untouched.

const Rules = preload("res://scripts/prototype/escape_state.gd")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Actor = preload("res://scripts/prototype/escape_actor.gd")
const Prop = preload("res://scripts/prototype/escape_prop.gd")
const Interface = preload("res://scripts/prototype/escape_ui.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const Intro = preload("res://scripts/ui/intro_cutscene.gd")
const TILE := 32
const ROOMS := {
	"CABIN": Rect2i(1, 10, 10, 8),
	"JUNCTION": Rect2i(12, 10, 10, 8),
	"ENGINEERING": Rect2i(12, 1, 10, 8),
	"LABORATORY": Rect2i(12, 19, 10, 8),
	"SHUTTLE BAY": Rect2i(23, 10, 13, 8),
}
const COLORS := {"CABIN": Color("bc9c83"), "JUNCTION": Color("81c5d9"), "ENGINEERING": Color("e0ad65"), "LABORATORY": Color("87d5b3"), "SHUTTLE BAY": Color("9bace8")}

var state = Rules.new()
var player
var crew := {}
var props := {}
var world: Node2D
var ui
var active := false
var ending := false
var elapsed := 0.0
var room := "CABIN"
var floors := {}
var walls := {}
var nav := AStarGrid2D.new()
var locker_body: StaticBody2D
var locker_visual: Sprite2D
var carried_visual: Sprite2D
var floor_tex: Texture2D
var wall_tex: Texture2D
var face_tex: Texture2D
var _intro = null
var _busy_actors := {}

func _ready() -> void:
	GameState.new_run()
	add_to_group("ship")
	floor_tex = load("res://assets/tiles/floor.png")
	wall_tex = load("res://assets/tiles/wall.png")
	face_tex = load("res://assets/tiles/wall_face_single.png")
	_build_floor()
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	_build_props()
	_add_actor("mara", "MARA · RESEARCHER", "mint", Vector2(265, 475), Color("87d5b3"))
	_add_actor("ivo", "IVO · PILOT", "hazard", Vector2(585, 475), Color("e0ad65"))
	player = PlayerScene.instantiate()
	player.position = Vector2(175, 480)
	world.add_child(player)
	player.set_camera_limits(Rect2(0, 0, 1184, 896))
	player.snap_camera()
	carried_visual = Sprite2D.new()
	carried_visual.texture = load("res://assets/sprites/crate.png")
	carried_visual.scale = Vector2(0.65, 0.65)
	world.add_child(carried_visual)
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
	announce("MARA", "You're okay. Good. That locker is caught at the top; I can hold it while you push.")
	refresh()

func _build_floor() -> void:
	for rect in ROOMS.values():
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x): floors[Vector2i(x, y)] = true
	for cell in [Vector2i(11, 13), Vector2i(11, 14), Vector2i(16, 9), Vector2i(17, 9), Vector2i(16, 18), Vector2i(17, 18), Vector2i(22, 13), Vector2i(22, 14)]: floors[cell] = true
	for cell in floors:
		for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not floors.has(cell + offset): walls[cell + offset] = true
	var body := StaticBody2D.new()
	add_child(body)
	for cell in walls:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(32, 32)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = Vector2(cell * 32) + Vector2(16, 16)
		body.add_child(collision)
	nav.region = Rect2i(0, 0, 38, 29)
	nav.cell_size = Vector2(32, 32)
	nav.offset = Vector2(16, 16)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	nav.update()
	for y in range(29):
		for x in range(38): nav.set_point_solid(Vector2i(x, y), not floors.has(Vector2i(x, y)))
	_set_locker_nav(true)

func _set_locker_nav(blocked: bool) -> void:
	nav.set_point_solid(Vector2i(11, 13), blocked)
	nav.set_point_solid(Vector2i(11, 14), blocked)

func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := Vector2i(from / 32)
	var finish := Vector2i(to / 32)
	if not nav.is_in_boundsv(start) or not nav.is_in_boundsv(finish): return PackedVector2Array()
	if nav.is_point_solid(start) or nav.is_point_solid(finish): return PackedVector2Array()
	var result := nav.get_point_path(start, finish)
	if not result.is_empty(): result[result.size() - 1] = to
	return result

func _add_prop(id: String, title: String, point: Vector2, texture: String, color: Color) -> void:
	var prop = Prop.new()
	prop.mission = self
	prop.prop_id = id
	prop.title = title
	prop.texture_path = "res://assets/sprites/" + texture + ".png"
	prop.accent = color
	prop.position = point
	world.add_child(prop)
	props[id] = prop

func _build_props() -> void:
	_add_prop("locker", "JAMMED LOCKER", Vector2(333, 449), "crate", Color("e0ad65"))
	locker_body = StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(32, 64)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(368, 448)
	locker_body.add_child(collider)
	add_child(locker_body)
	locker_visual = Sprite2D.new()
	locker_visual.texture = load("res://assets/sprites/crate.png")
	locker_visual.position = Vector2(368, 444)
	locker_visual.scale = Vector2(1.2, 1.5)
	world.add_child(locker_visual)
	_add_prop("terminal", "LAUNCH STATUS", Vector2(535, 390), "terminal", Color("81c5d9"))
	_add_prop("isolate", "CIRCUIT CUTOFF", Vector2(430, 155), "clamp_console", Color("e0ad65"))
	_add_prop("fuse", "SPARE FUSE", Vector2(650, 155), "core", Color("e0ad65"))
	_add_prop("cabinet", "DISTRIBUTION", Vector2(535, 155), "power_console", Color("e0ad65"))
	_add_prop("aux", "AUX BRANCH", Vector2(610, 250), "terminal", Color("e0ad65"))
	_add_prop("freezer", "SAMPLE FREEZER", Vector2(460, 715), "power_console", Color("87d5b3"))
	_add_prop("battery", "EMERGENCY BATTERY", Vector2(635, 715), "crate", Color("87d5b3"))
	_add_prop("cart", "SERVICE CART", Vector2(570, 815), "crate", Color("87d5b3"))
	_add_prop("case", "SAMPLE CASE", Vector2(435, 815), "core", Color("87d5b3"))
	props["case"].visible = false
	_add_prop("socket", "EMERGENCY SOCKET", Vector2(795, 395), "power_console", Color("9bace8"))
	_add_prop("release", "DOCKING CLAMPS", Vector2(900, 395), "clamp_console", Color("9bace8"))
	_add_prop("shuttle", "BOARD SHUTTLE", Vector2(1050, 485), "pod", Color("9bace8"))
	props["shuttle"]._visual.scale = Vector2(1.5, 1.5)

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
	for key in ROOMS:
		var rect: Rect2i = ROOMS[key]
		if Rect2(Vector2(rect.position * 32), Vector2(rect.size * 32)).has_point(point): return key
	return "PASSAGE"

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

func open_chat(id: String) -> void:
	if not active or ending: return
	ui.open_chat(id)

func announce(speaker: String, line: String) -> void:
	if ui != null: ui.show_caption(speaker, line)
	var id := "mara" if speaker == "MARA" else "ivo" if speaker == "IVO" else ""
	if crew.has(id): crew[id].say(line)

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
				announce("MARA", "Living samples. The battery keeps them cold. Ivo has an insulated case aboard the shuttle; it can hold the priority rack." if not state.has_flag("battery_out") else "Cooling is offline. " + ("The priority rack is safe in the case." if state.has_flag("samples_saved") else "The samples are lost. Let's get the crew home."))
		"battery":
			if state.route == "battery" and not state.has_flag("battery_out"):
				var consequence := "Priority samples are packed. The remaining research will be lost." if state.has_flag("samples_saved") else "All living samples will be lost. You can ask Ivo to fetch the insulated case before committing."
				ui.confirm_action("Disconnect freezer power?", consequence + " The crew remains safe. This choice cannot be undone.", "disconnect_battery")
			else: perform("disconnect_battery")
		"cart": perform("take_cart")
		"case": perform("pack_samples")
		"socket": perform("connect_battery")
		"release": perform("release")
		"shuttle":
			if state.has_flag("clamps"):
				if not crew_ready():
					announce("IVO", "We're walking aboard. Give us a moment before departure.")
					return
				var cargo := "All research preserved aboard the main ship for recovery." if state.route == "engineering" else "Priority samples aboard." if state.has_flag("samples_saved") else "Research left behind."
				ui.confirm_action("Three seats. One destination.", "Johnny, Mara and Ivo are ready. " + cargo + " Launch for Earth?", "launch")
			else: perform("launch")

func perform(action: String) -> Dictionary:
	if action == "launch" and not crew_ready(): return {"ok": false, "line": "Wait until both crewmates have boarded."}
	if action == "push_locker" and (crew.mara.position.distance_to(Vector2(305, 440)) > 45 or crew.mara.following):
		var refused := {"ok": false, "line": "Mara needs to hold the top. Ask her to help with the locker first."}
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
				create_tween().tween_property(locker_visual, "position", Vector2(328, 520), 0.6)
				crew.mara.following = true
			"assess":
				crew.ivo.go_to(Vector2(970, 475))
			"fetch_case":
				_busy_actors["ivo"] = true
				crew.ivo.go_to(Vector2(1000, 470), func():
					crew.ivo.set_cargo(true)
					crew.ivo.go_to(Vector2(475, 795), func():
						crew.ivo.set_cargo(false)
						_busy_actors.erase("ivo")
						if not ending: perform("case_arrived")))
			"release":
				crew.mara.go_to(Vector2(1005, 505))
				crew.ivo.go_to(Vector2(1045, 525))
			"launch": _launch()
		refresh()
	return result

func crew_ready() -> bool:
	return crew.mara.position.distance_to(Vector2(1005, 505)) < 20 and crew.ivo.position.distance_to(Vector2(1045, 525)) < 20

func refresh() -> void:
	for prop in props.values(): prop.refresh()
	props["case"].visible = state.has_flag("case_arrived")
	props["cart"].visible = not state.has_flag("battery_taken")
	props["battery"].visible = not state.has_flag("battery_loaded")
	if state.has_flag("battery_out"):
		props["freezer"].caption.text = "COOLING OFFLINE"
		props["freezer"].caption.modulate = Color("ef8a81")
	if state.has_flag("samples_saved"):
		props["case"].caption.text = "SAMPLES SECURED"
	if ui != null: ui.update_hud()
	queue_redraw()

func _exit_tree() -> void:
	Sfx.stop_ambient()
	_set_wide(false)

## Gameplay fills the whole window (a wide browser just shows more of the ship);
## the menu and the opening film stay 16:9 because they are 16:9 videos.
func _set_wide(on: bool) -> void:
	var win := get_window()
	if win != null:
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if on else Window.CONTENT_SCALE_ASPECT_KEEP

## A floor sign centered on x (world px).
func _sign(font: Font, text: String, center_x: float, y: float, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(round(center_x - w / 2.0), y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

func prop_done(id: String) -> bool:
	var mapping := {"locker": "locker_clear", "terminal": "assessed", "isolate": "isolated", "fuse": "fuse_taken", "cabinet": "engineering_power", "aux": "aux_off", "freezer": "samples_saved", "battery": "battery_out", "cart": "battery_loaded", "case": "samples_saved", "socket": "battery_connected", "release": "clamps"}
	return state.has_flag(mapping.get(id, ""))

func available_actions(id: String) -> Dictionary:
	var actions := {"none": "Answer a question using the current situation; no action.", "follow": "Follow the engineer.", "wait": "Wait at your current position."}
	if state.has_flag("clamps"): return {"none": "The crew is boarding. Answer briefly; do not leave the shuttle."}
	if _busy_actors.has(id): return {"none": "Currently completing an assigned task. Report progress; do not start another task."}
	if id == "mara":
		if not state.has_flag("locker_clear"): actions["help_locker"] = "Walk to the locker and hold it while the player pushes."
		if state.has_flag("battery_out") and not state.has_flag("battery_loaded"): actions["load_battery"] = "Help the player lift the lab battery onto the cart. Player must be beside the cart."
	if id == "ivo" and state.has_flag("assessed") and not state.has_flag("case_requested") and not state.has_flag("battery_out"):
		actions["fetch_case"] = "Fetch the insulated case from the shuttle and deliver it to the lab freezer."
	return actions

func act_on_dialogue(id: String, action: String) -> String:
	if action == "none" or action == "": return ""
	if not available_actions(id).has(action): return "That task is no longer available. " + state.objective()
	var actor = crew[id]
	match action:
		"follow":
			if find_path(actor.position, player.position).is_empty(): return "The cabin doorway is blocked. Clear it with Mara first."
			actor.following = true
		"wait":
			actor.following = false
			actor.path.clear()
		"help_locker", "load_battery":
			var target := Vector2(305, 440) if action == "help_locker" else Vector2(535, 800)
			var player_target := Vector2(320, 450) if action == "help_locker" else Vector2(570, 815)
			if player.position.distance_to(player_target) > 115: return "Meet me beside the " + ("cabin locker." if action == "help_locker" else "lab cart, then ask me to help lift it.")
			_busy_actors[id] = true
			actor.go_to(target, func():
				_busy_actors.erase(id)
				if action == "load_battery" and player.position.distance_to(player_target) > 115:
					announce("MARA", "I'm at the cart. Come back here and ask me to lift it with you.")
				else:
					perform(action))
		"fetch_case": perform("fetch_case")
	return ""

func snapshot(id: String) -> Dictionary:
	return {"npc_id": id, "state_version": state.version, "objective": state.objective(), "route": state.route, "flags": state.flags.duplicate(), "carrying": state.carrying, "room": room, "available_actions": available_actions(id), "recent_events": state.journal.slice(maxi(0, state.journal.size() - 5))}

func offline_response(id: String, message: String) -> Dictionary:
	var m := message.to_lower()
	var line := ""
	var action := "none"
	var query := m.begins_with("what") or m.begins_with("why") or m.begins_with("where") or m.begins_with("how")
	var negative := m.contains("don't") or m.contains("do not") or m.contains("stop") or m.contains("never")
	if negative:
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
		elif state.has_flag("case_requested"): line = "I'm delivering the case to the laboratory." if id == "ivo" else "Ivo is bringing the case. Keep the freezer connected until we've packed."
		else:
			line = "There's an insulated case in the shuttle. Ask Ivo to fetch it; we can save the priority rack."
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

func _draw() -> void:
	draw_rect(Rect2(-500, -500, 2200, 1900), Color("050a19"))
	for i in range(130):
		var p := Vector2(posmod(i * 197 + 31, 1600) - 200, posmod(i * 313 + 13, 1300) - 200)
		draw_rect(Rect2(p, Vector2(1, 1)), Color(0.45, 0.6, 0.85, 0.4))
	for cell in floors:
		var rect := Rect2(Vector2(cell * 32), Vector2(32, 32))
		var src := Rect2(Vector2(posmod(cell.x * 32, floor_tex.get_width()), posmod(cell.y * 32, floor_tex.get_height())), Vector2(32, 32))
		draw_texture_rect_region(floor_tex, rect, src)
	for key in ROOMS:
		var grid: Rect2i = ROOMS[key]
		var rect := Rect2(Vector2(grid.position * 32), Vector2(grid.size * 32))
		var color: Color = COLORS[key]
		draw_rect(rect, Color(color, 0.07))
		draw_rect(rect.grow(-3), Color(color, 0.4), false, 2)
		draw_string(UiStyle.font(), rect.position + Vector2(18, 25), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		if key == "CABIN" and state.has_flag("aux_off"): draw_rect(rect, Color(0, 0, 0, 0.45))
	for cell in walls:
		var rect := Rect2(Vector2(cell * 32), Vector2(32, 32))
		draw_texture_rect(face_tex if floors.has(cell + Vector2i.DOWN) else wall_tex, rect, false)
	# Floor direction markers are environmental signage rather than quest arrows.
	var font := UiStyle.font()
	# Centered on each doorway so they stay clear of the room names.
	_sign(font, "ENGINEERING ^", 544, 342, COLORS.ENGINEERING)
	_sign(font, "LABORATORY v", 544, 563, COLORS.LABORATORY)
	_sign(font, "BAY >", 662, 465, COLORS["SHUTTLE BAY"])
	if state.powered():
		for x in range(765, 1120, 32): draw_rect(Rect2(x, 545, 12, 3), Color("87d5b3"))
