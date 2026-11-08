extends Control
## Title screen (scenes/menu.tscn, the project's main scene). Owner: D.
##
## The art is drawn live by menu_backdrop.gd: a sky generated in code, the
## pixel-art logo with a spinning Earth, drifting pixel-art astronaut and
## debris, and pixel-art buttons. Invisible click areas sit over the buttons.
## Hovering lifts a button; while held it shows its pressed image (face sunk
## onto its 3D strip). Fires on release. Fills any window shape.
## START GAME loads the branching escape prototype (existing opening -> run).
## Keys: Enter/E = Start Game, M = sound, Esc = close a panel.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const PressButton = preload("res://scripts/ui/press_button.gd")
const MenuBackdrop = preload("res://scripts/ui/menu_backdrop.gd")
const GAME_SCENE := "res://scenes/escape_prototype.tscn"
const CREDITS_PATH := "res://data/credits.json"

## Menu buttons on the 640x360 grid. The real spots come from
## data/menu_layout.json (tools/make_menu_art.py); these rects are only used
## if the art is missing. `depth` is the 3D strip height (2 art px).
const HOTSPOTS := [
	{"id": "start", "rect": Rect2(203, 166, 234, 51), "depth": 6, "label": "START GAME"},
	{"id": "how", "rect": Rect2(203, 223, 234, 51), "depth": 6, "label": "HOW TO PLAY"},
	{"id": "settings", "rect": Rect2(203, 280, 234, 51), "depth": 6, "label": "SETTINGS"},
	{"id": "credits", "rect": Rect2(10, 305, 153, 45), "depth": 6, "label": "CREDITS"},
	{"id": "sound", "rect": Rect2(585, 311, 45, 39), "depth": 6, "label": "SOUND"},
]
## How long a keyboard shortcut shows the pushed-in look before acting.
const KEY_PRESS_TIME := 0.12

var open_panel := ""  # "", "how", "settings", or "credits"

var _backdrop: MenuBackdrop = null
var _mute_slash: MuteSlash
var _fade: ColorRect
var _panels := {}            # id -> Control
var _settings_buttons := {}  # setting key -> PressButton
var _hotspots := {}          # id -> Control (click area over a painted button)
var _panel_boxes := {}       # id -> PanelContainer (re-centered on resize)
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The menu fills any window shape (the sky is drawn in code); gameplay and
	# the opening film set their own aspect when they start.
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	get_tree().paused = false
	GameState.new_run()  # nothing ticks while we're on the menu

	var has_art := _build_background()
	_build_hotspots(not has_art)

	_mute_slash = MuteSlash.new()
	_mute_slash.target = _spot_rect(HOTSPOTS[4])
	_mute_slash.size = size
	add_child(_mute_slash)

	_build_how_panel()
	_build_settings_panel()
	_build_credits_panel()
	Settings.changed.connect(_refresh_settings_labels)
	_refresh_settings_labels()

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.size = size
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.4)

	get_viewport().size_changed.connect(_relayout)
	_relayout()
	Sfx.start_ambient()


func _exit_tree() -> void:
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


## Fit the menu to the current window: art, click areas, panels, fade.
func _relayout() -> void:
	var sz := get_viewport_rect().size
	if _backdrop != null:
		_backdrop.relayout(sz)
	for spot in HOTSPOTS:
		var id: String = spot["id"]
		var shift := MenuBackdrop.anchor_offset(MenuBackdrop.anchor_for(id), sz)
		var r := _spot_rect(spot)
		_hotspots[id].position = r.position + shift
		if id == "sound":
			_mute_slash.target = Rect2(r.position + shift, r.size)
	_mute_slash.size = sz
	_mute_slash.queue_redraw()
	_fade.size = sz
	for id in _panels:
		_panels[id].size = sz
		_panels[id].get_child(0).size = sz  # the dim layer
		var box: PanelContainer = _panel_boxes[id]
		box.position = ((sz - box.size) / 2.0).round()


# --- Actions ----------------------------------------------------------------------

## What each painted button does (fires on release). Also called by tests.
func activate(id: String) -> void:
	if _leaving:
		return
	match id:
		"start":
			_start_game()
		"how", "settings", "credits":
			_open(id)
		"sound":
			Settings.toggle_mute()
			if not Settings.muted:
				Sfx.play("objective", -8.0)


func _start_game() -> void:
	_leaving = true
	Settings.intro_pending = true  # opening story -> gameplay
	Sfx.play("launch", -6.0)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file(GAME_SCENE))


func _open(id: String) -> void:
	_close_panel(false)
	open_panel = id
	_panels[id].visible = true
	Sfx.play("door", -10.0)


func _close_panel(play_sound := true) -> void:
	if open_panel == "":
		return
	_panels[open_panel].visible = false
	open_panel = ""
	if play_sound:
		Sfx.play("boots", -10.0)


## Pushed-in look on/off for one painted button.
func set_pressed_look(id: String, held: bool) -> void:
	if _backdrop != null:
		_backdrop.set_pressed(id, held)
	if id == "sound":
		_mute_slash.pressed_offset = int(HOTSPOTS[4]["depth"]) if held else 0
		_mute_slash.queue_redraw()


func is_pressed_look(id: String) -> bool:
	return _backdrop != null and _backdrop.is_pressed(id)


func _on_hotspot_down(id: String) -> void:
	if not _leaving and open_panel == "":
		set_pressed_look(id, true)
		Sfx.play("boots", -12.0)


func _on_hotspot_up(id: String) -> void:
	set_pressed_look(id, false)


## Keyboard shortcut: show the press briefly, then act.
func _press_by_key(id: String) -> void:
	set_pressed_look(id, true)
	Sfx.play("boots", -12.0)
	var tw := create_tween()
	tw.tween_interval(KEY_PRESS_TIME)
	tw.tween_callback(_release_key_press.bind(id))


func _release_key_press(id: String) -> void:
	set_pressed_look(id, false)
	activate(id)


# --- Input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if open_panel != "":
		if _any(event, ["pause", "ui_cancel"]):
			_close_panel()
			get_viewport().set_input_as_handled()
		return
	if _any(event, ["confirm", "ui_accept"]):
		_press_by_key("start")
	elif event.is_action_pressed("toggle_mute"):
		_press_by_key("sound")
	else:
		return
	get_viewport().set_input_as_handled()


static func _any(event: InputEvent, actions: Array) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			return true
	return false


# --- Background and painted buttons --------------------------------------------------------

## Returns true if the live menu art loaded (false = plain fallback menu).
func _build_background() -> bool:
	_backdrop = MenuBackdrop.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	if _backdrop.is_ready():
		return true
	push_warning("Menu art missing (assets/menu/); showing a plain menu.")
	_backdrop.queue_free()
	_backdrop = null
	var bg := ColorRect.new()
	bg.color = UiStyle.NAVY_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := UiStyle.label("BACK2EARTH", 34, UiStyle.CYAN)
	title.position = Vector2(0, 70)
	title.size = Vector2(640, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	return false


## A button's spot on the 640x360 grid: from the art layout when it loaded.
func _spot_rect(spot: Dictionary) -> Rect2:
	if _backdrop != null:
		var r := _backdrop.button_home_rect(spot["id"])
		if r.size != Vector2.ZERO:
			return r
	return spot["rect"]


func _build_hotspots(fallback: bool) -> void:
	for spot in HOTSPOTS:
		var id: String = spot["id"]
		var r: Rect2 = _spot_rect(spot)
		if fallback:
			# No art: draw the buttons ourselves (they press the same way).
			var pb := PressButton.new()
			pb.name = "Hotspot_%s" % id
			pb.position = r.position
			pb.size = r.size
			pb.set_label(spot["label"])
			pb.pressed.connect(activate.bind(id))
			pb.add_to_group("menu_hotspot")
			add_child(pb)
			_hotspots[id] = pb
			continue

		var b := Button.new()
		b.name = "Hotspot_%s" % id
		b.position = r.position
		b.size = r.size
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.button_down.connect(_on_hotspot_down.bind(id))
		b.button_up.connect(_on_hotspot_up.bind(id))
		b.mouse_entered.connect(_backdrop.set_hover.bind(id, true))
		b.mouse_exited.connect(_backdrop.set_hover.bind(id, false))
		b.pressed.connect(activate.bind(id))  # on release, inside the button
		b.add_to_group("menu_hotspot")
		add_child(b)
		_hotspots[id] = b


# --- Panels --------------------------------------------------------------------------

## A dimmed overlay with a centered panel; returns the VBox to fill.
func _make_panel(id: String, title_text: String, panel_size: Vector2) -> VBoxContainer:
	var root := Control.new()
	root.name = "Panel_%s" % id
	root.size = size
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to the menu behind
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel())
	panel.position = (size - panel_size) / 2.0
	panel.size = panel_size
	panel.custom_minimum_size = panel_size
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var title := UiStyle.label(title_text, 18, UiStyle.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_panels[id] = root
	_panel_boxes[id] = panel
	return vbox


func _add_button(vbox: VBoxContainer, label_text: String, on_press: Callable) -> PressButton:
	var b := PressButton.new()
	b.set_label(label_text)
	b.custom_minimum_size = Vector2(0, 26)
	b.pressed.connect(on_press)
	b.button_down.connect(_on_panel_button_down)
	vbox.add_child(b)
	return b


func _on_panel_button_down() -> void:
	Sfx.play("boots", -12.0)


func _add_back_button(vbox: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	_add_button(vbox, "BACK", _close_panel.bind(true))


func _build_how_panel() -> void:
	var vbox := _make_panel("how", "HOW TO PLAY", Vector2(530, 326))
	var body := UiStyle.label(
		"BRANCHING ESCAPE · DESIGN PROTOTYPE\n\n"
		+ "Work with Mara and Ivo to get the shuttle home.\n"
		+ "The original opening film plays before this new mission.\n\n"
		+ "1   Ask Mara to hold the jammed cabin locker, then push it.\n"
		+ "2   Inspect launch status in the junction.\n"
		+ "3   Repair Engineering, or divert the lab battery.\n"
		+ "4   Consider saving the samples before cutting cooling.\n"
		+ "5   Release the clamps and board with your crew.\n\n"
		+ "Crew radio uses a labeled offline interpreter by default.\n"
		+ "Live Gemini + voice can be enabled inside a conversation.\n"
		+ "No countdown. Explore, talk, and choose your approach.",
		11)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	var keys := UiStyle.label("WASD move   E use   1 / 2 radio   Tab map   Esc pause", 10, UiStyle.AMBER)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(keys)
	_add_back_button(vbox)


func _build_settings_panel() -> void:
	var vbox := _make_panel("settings", "SETTINGS", Vector2(380, 262))
	_settings_buttons["sound"] = _add_button(vbox, "", Settings.toggle_mute)
	_settings_buttons["shake"] = _add_button(vbox, "", Settings.toggle_reduced_shake)
	_settings_buttons["echo"] = _add_button(vbox, "", Settings.toggle_companion)
	if not OS.has_feature("web"):
		_settings_buttons["fullscreen"] = _add_button(vbox, "", Settings.toggle_fullscreen)
		_add_button(vbox, "QUIT GAME", _quit)
	_add_back_button(vbox)


func _quit() -> void:
	get_tree().quit()


func _refresh_settings_labels() -> void:
	if _settings_buttons.is_empty():
		return
	_settings_buttons["sound"].set_label("SOUND: %s" % ("OFF" if Settings.muted else "ON"))
	_settings_buttons["shake"].set_label("REDUCED SHAKE & FLASH: %s" % ("ON" if Settings.reduced_shake else "OFF"))
	_settings_buttons["echo"].set_label("ECHO LIVE REPLIES: %s" % ("ON" if Settings.companion_enabled else "OFF"))
	if _settings_buttons.has("fullscreen"):
		_settings_buttons["fullscreen"].set_label("FULLSCREEN: %s" % ("ON" if Settings.fullscreen else "OFF"))
	if _mute_slash != null:
		_mute_slash.queue_redraw()


func _build_credits_panel() -> void:
	var vbox := _make_panel("credits", "CREDITS", Vector2(530, 326))
	var data := _load_credits()
	var sub := UiStyle.label(str(data.get("subtitle", "")), 11, UiStyle.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	for section in data.get("sections", []):
		if typeof(section) != TYPE_DICTIONARY:
			continue
		var heading := UiStyle.label(str(section.get("heading", "")), 12, UiStyle.AMBER)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(heading)
		var lines := []
		for line in section.get("lines", []):
			lines.append(str(line))
		var body := UiStyle.label("\n".join(PackedStringArray(lines)), 10)
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(body)
	_add_back_button(vbox)


func _load_credits() -> Dictionary:
	var fallback := {
		"subtitle": "Made at UBhacks 2026",
		"sections": [{"heading": "TEAM", "lines": ["The Back2Earth team"]}],
	}
	if not FileAccess.file_exists(CREDITS_PATH):
		return fallback
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else fallback


# --- Mute indicator ----------------------------------------------------------------------

## Red slash over the painted speaker while sound is off (moves with the press).
class MuteSlash extends Control:
	var target := Rect2()
	var pressed_offset := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if not Settings.muted:
			return
		var r := target
		r.position.y += pressed_offset
		draw_line(r.position + Vector2(8, r.size.y - 8), r.position + Vector2(r.size.x - 8, 6),
			Color("ff004d"), 3.0)
