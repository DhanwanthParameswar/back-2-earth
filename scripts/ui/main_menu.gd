extends Control
## Title screen (scenes/menu.tscn, the project's main scene). Owner: D.
##
## The title and the five buttons are painted into a looping video. Invisible
## click areas sit exactly over the painted buttons. While a button is held it
## looks pushed in: the button is covered with background color and its face
## (cut from the video, assets/ui/menu_btn_<id>.png) is drawn lower by the
## depth of its 3D strip, slightly darker. The action fires on release.
## START GAME loads the branching escape prototype (existing opening -> run).
## Keys: Enter/E = Start Game, M = sound, Esc = close a panel.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const PressButton = preload("res://scripts/ui/press_button.gd")
const MENU_VIDEO := "res://assets/video/menu_loop.ogv"
const GAME_SCENE := "res://scenes/escape_prototype.tscn"
const CREDITS_PATH := "res://data/credits.json"

## Painted buttons in 640x360 menu px (1080p source / 3). `rect` covers the
## face plus its 3D strip; `depth` is the strip height; `bg` is the space color
## right behind the button. Re-measure with tools/extract_menu_buttons.py if
## the menu video is redrawn.
const HOTSPOTS := [
	{"id": "start", "rect": Rect2(204, 173, 230, 45), "depth": 6, "bg": Color("0b0b2e"), "label": "START GAME"},
	{"id": "how", "rect": Rect2(202, 228, 233, 43), "depth": 7, "bg": Color("0b0a2d"), "label": "HOW TO PLAY"},
	{"id": "settings", "rect": Rect2(202, 280, 233, 44), "depth": 7, "bg": Color("0c0c30"), "label": "SETTINGS"},
	{"id": "credits", "rect": Rect2(10, 321, 74, 29), "depth": 3, "bg": Color("0a0b2d"), "label": "CREDITS"},
	{"id": "sound", "rect": Rect2(588, 315, 40, 34), "depth": 3, "bg": Color("0b0c2e"), "label": "SOUND"},
]
## How long a keyboard shortcut shows the pushed-in look before acting.
const KEY_PRESS_TIME := 0.12

var open_panel := ""  # "", "how", "settings", or "credits"

var _video: VideoStreamPlayer = null
var _press_overlays := {}    # id -> Control (shown while that button is held)
var _mute_slash: MuteSlash
var _fade: ColorRect
var _panels := {}            # id -> Control
var _settings_buttons := {}  # setting key -> PressButton
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(640, 360)
	get_tree().paused = false
	GameState.new_run()  # nothing ticks while we're on the menu

	var has_video := _build_background()
	_build_hotspots(not has_video)

	_mute_slash = MuteSlash.new()
	_mute_slash.target = HOTSPOTS[4]["rect"]
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

	Sfx.start_ambient()


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
	if _press_overlays.has(id):
		_press_overlays[id].visible = held
	if id == "sound":
		_mute_slash.pressed_offset = int(HOTSPOTS[4]["depth"]) if held else 0
		_mute_slash.queue_redraw()


func is_pressed_look(id: String) -> bool:
	return _press_overlays.has(id) and _press_overlays[id].visible


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

## Returns true if the video is playing (false = plain fallback menu).
func _build_background() -> bool:
	var bg := ColorRect.new()
	bg.color = UiStyle.NAVY_DEEP
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	if not ResourceLoader.exists(MENU_VIDEO):
		push_warning("Menu video missing (%s); showing a plain menu." % MENU_VIDEO)
		var title := UiStyle.label("BACK2EARTH", 34, UiStyle.CYAN)
		title.position = Vector2(0, 70)
		title.size = Vector2(640, 40)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(title)
		return false
	_video = VideoStreamPlayer.new()
	_video.stream = load(MENU_VIDEO)
	_video.expand = true
	_video.size = size
	_video.volume_db = -80.0
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # 720p art on a 640x360 canvas
	_video.finished.connect(_on_video_finished)
	add_child(_video)
	_video.play()
	return true


func _on_video_finished() -> void:
	_video.play()  # seamless 12 s loop


func _build_hotspots(fallback: bool) -> void:
	for spot in HOTSPOTS:
		var id: String = spot["id"]
		var r: Rect2 = spot["rect"]
		if fallback:
			# No video: draw the buttons ourselves (they press the same way).
			var pb := PressButton.new()
			pb.name = "Hotspot_%s" % id
			pb.position = r.position
			pb.size = r.size
			pb.set_label(spot["label"])
			pb.pressed.connect(activate.bind(id))
			pb.add_to_group("menu_hotspot")
			add_child(pb)
			continue

		_press_overlays[id] = _make_press_overlay(spot)
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
		b.pressed.connect(activate.bind(id))  # on release, inside the button
		b.add_to_group("menu_hotspot")
		add_child(b)


## Background patch over the whole button + its face redrawn lower and darker.
func _make_press_overlay(spot: Dictionary) -> Control:
	var r: Rect2 = spot["rect"]
	var depth := float(spot["depth"])
	var overlay := Control.new()
	overlay.name = "Press_%s" % spot["id"]
	overlay.position = r.position
	overlay.size = r.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	add_child(overlay)

	var patch := ColorRect.new()
	patch.color = spot["bg"]
	patch.size = r.size
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(patch)

	var path := "res://assets/ui/menu_btn_%s.png" % spot["id"]
	if ResourceLoader.exists(path):
		var face := TextureRect.new()
		face.texture = load(path)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_SCALE
		face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		face.position = Vector2(0, depth)
		face.size = Vector2(r.size.x, r.size.y - depth)
		face.modulate = Color(0.85, 0.85, 0.85)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(face)
	return overlay


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
	var vbox := _make_panel("how", "HOW TO PLAY", Vector2(440, 318))
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
	var vbox := _make_panel("settings", "SETTINGS", Vector2(330, 262))
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
	var vbox := _make_panel("credits", "CREDITS", Vector2(440, 306))
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
