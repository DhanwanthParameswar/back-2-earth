extends Control
## Title screen (scenes/menu.tscn, the project's main scene). Owner: D.
##
## The title and the five buttons are painted into a looping video. This script
## lays invisible hit areas exactly over the painted buttons, draws a focus
## marker for keyboard players, and opens the How to Play / Settings / Credits
## panels. START GAME loads scenes/main.tscn (briefing -> suit picker -> run).
## Keys: arrows/WASD move, E/Enter select, M mute, Esc closes a panel.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const MENU_VIDEO := "res://assets/video/menu_loop.ogv"
const GAME_SCENE := "res://scenes/main.tscn"
const CREDITS_PATH := "res://data/credits.json"

## Hit areas in 640x360 base px, measured on the 1920x1080 source and divided
## by 3. If the menu video is redrawn, re-measure these (see README "Menu").
const HOTSPOTS := [
	{"id": "start", "rect": Rect2(205, 175, 228, 38), "label": "START GAME"},
	{"id": "how", "rect": Rect2(203, 227, 232, 38), "label": "HOW TO PLAY"},
	{"id": "settings", "rect": Rect2(203, 280, 232, 38), "label": "SETTINGS"},
	{"id": "credits", "rect": Rect2(11, 320, 73, 27), "label": "CREDITS"},
	{"id": "sound", "rect": Rect2(588, 316, 40, 32), "label": "SOUND"},
]

var focus_index := 0
var open_panel := ""  # "", "how", "settings", or "credits"

var _video: VideoStreamPlayer = null
var _marker: FocusMarker
var _fade: ColorRect
var _panels := {}           # id -> Control
var _panel_items := {}      # id -> Array of focusable Buttons
var _settings_buttons := {} # setting key -> Button
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = Vector2(640, 360)
	get_tree().paused = false
	GameState.new_run()  # nothing ticks while we're on the menu

	var has_video := _build_background()
	_build_hotspots(not has_video)

	_marker = FocusMarker.new()
	_marker.menu = self
	_marker.size = size
	add_child(_marker)

	var hint := UiStyle.label("Arrows / WASD  choose     E / Enter  select     M  mute", 9, Color(UiStyle.MUTED, 0.8))
	hint.position = Vector2(0, 344)
	hint.size = Vector2(640, 14)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)

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

## What each painted button does. Also called by tests.
func activate(id: String) -> void:
	if _leaving:
		return
	var idx := _hotspot_index(id)
	if idx >= 0:
		focus_index = idx
	match id:
		"start":
			_start_game()
		"how", "settings", "credits":
			_open(id)
		"sound":
			Settings.toggle_mute()
			if not Settings.muted:
				Sfx.play("objective", -8.0)
	_marker.queue_redraw()


func _start_game() -> void:
	_leaving = true
	Sfx.play("launch", -6.0)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file(GAME_SCENE))


func _open(id: String) -> void:
	_close_panel(false)
	open_panel = id
	var panel: Control = _panels[id]
	panel.visible = true
	var items: Array = _panel_items[id]
	if not items.is_empty():
		items[0].grab_focus()
	Sfx.play("door", -10.0)


func _close_panel(play_sound := true) -> void:
	if open_panel == "":
		return
	_panels[open_panel].visible = false
	open_panel = ""
	var owner_control := get_viewport().gui_get_focus_owner()
	if owner_control != null:
		owner_control.release_focus()
	if play_sound:
		Sfx.play("boots", -10.0)
	_marker.queue_redraw()


func _move_focus(step: int) -> void:
	focus_index = (focus_index + step + HOTSPOTS.size()) % HOTSPOTS.size()
	Sfx.play("boots", -12.0)
	_marker.queue_redraw()


func get_hotspot_rect(i: int) -> Rect2:
	return HOTSPOTS[i]["rect"]


func is_marker_visible() -> bool:
	return open_panel == "" and not _leaving


func _hotspot_index(id: String) -> int:
	for i in HOTSPOTS.size():
		if HOTSPOTS[i]["id"] == id:
			return i
	return -1


# --- Input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if open_panel != "":
		_panel_input(event)
		return
	if _any(event, ["move_up", "move_left", "ui_up", "ui_left"]):
		_move_focus(-1)
	elif _any(event, ["move_down", "move_right", "ui_down", "ui_right"]):
		_move_focus(1)
	elif _any(event, ["confirm", "ui_accept"]):
		activate(HOTSPOTS[focus_index]["id"])
	elif event.is_action_pressed("toggle_mute"):
		activate("sound")
	else:
		return
	get_viewport().set_input_as_handled()


## Inside a panel: arrows/Enter go through Godot's focus system; W/S/E and Esc here.
func _panel_input(event: InputEvent) -> void:
	if _any(event, ["pause", "ui_cancel"]):
		_close_panel()
	elif event.is_action_pressed("move_up"):
		_panel_focus_step(-1)
	elif event.is_action_pressed("move_down"):
		_panel_focus_step(1)
	elif event.is_action_pressed("confirm"):
		var f = get_viewport().gui_get_focus_owner()  # untyped: we emit a Button signal
		if f is Button:
			f.pressed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _panel_focus_step(step: int) -> void:
	var items: Array = _panel_items.get(open_panel, [])
	if items.is_empty():
		return
	var current := items.find(get_viewport().gui_get_focus_owner())
	var next := (maxi(current, 0) + step + items.size()) % items.size()
	if current < 0:
		next = 0
	items[next].grab_focus()


static func _any(event: InputEvent, actions: Array) -> bool:
	for a in actions:
		if InputMap.has_action(a) and event.is_action_pressed(a):
			return true
	return false


# --- Background and hit areas -----------------------------------------------------------

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
	_video.finished.connect(func(): _video.play())  # seamless 12 s loop
	add_child(_video)
	_video.play()
	return true


func _build_hotspots(show_labels: bool) -> void:
	for i in HOTSPOTS.size():
		var spot: Dictionary = HOTSPOTS[i]
		var b := Button.new()
		b.name = "Hotspot_%s" % spot["id"]
		var r: Rect2 = spot["rect"]
		b.position = r.position
		b.size = r.size
		b.focus_mode = Control.FOCUS_NONE  # keyboard focus is ours (FocusMarker)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if show_labels:
			b.text = spot["label"]
			UiStyle.style_button(b, 12)
		else:
			for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
				b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.mouse_entered.connect(_on_hotspot_hovered.bind(i))
		b.pressed.connect(activate.bind(spot["id"]))
		b.add_to_group("menu_hotspot")
		add_child(b)


func _on_hotspot_hovered(i: int) -> void:
	if open_panel == "" and focus_index != i:
		focus_index = i
		_marker.queue_redraw()


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
	_panel_items[id] = []
	return vbox


func _add_button(id: String, vbox: VBoxContainer, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 24)
	b.focus_mode = Control.FOCUS_ALL
	UiStyle.style_button(b, 12)
	b.pressed.connect(on_press)
	b.mouse_entered.connect(func(): b.grab_focus())
	vbox.add_child(b)
	_panel_items[id].append(b)
	return b


func _add_back_button(id: String, vbox: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	_add_button(id, vbox, "BACK", func(): _close_panel())


func _build_how_panel() -> void:
	var vbox := _make_panel("how", "HOW TO PLAY", Vector2(440, 306))
	var body := UiStyle.label(
		"Reach the escape pod before the 6:00 evacuation window closes.\n\n"
		+ "1   Start the evacuation at the cockpit terminal.\n"
		+ "2   Restore power in Engineering.\n"
		+ "3   Wait for a DOWN surge: it slides the cargo sled onto the plate.\n"
		+ "     Then grab the navigation core.\n"
		+ "4   Release the pod clamp and board the pod.\n\n"
		+ "Amber arrow = surge coming.   Red arrow = pulling.\n"
		+ "Hold SPACE for mag-boots: slower, but the pull barely moves you.\n"
		+ "Red lanes carry debris. Each hit costs 10 seconds.\n"
		+ "Press H to ask ECHO, the ship's damaged AI, for help.",
		11)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(body)
	var keys := UiStyle.label("WASD / arrows  move    E  interact    SPACE  boots    H  ECHO    Esc  pause", 10, UiStyle.AMBER)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(keys)
	_add_back_button("how", vbox)


func _build_settings_panel() -> void:
	var vbox := _make_panel("settings", "SETTINGS", Vector2(330, 250))
	_settings_buttons["sound"] = _add_button("settings", vbox, "", func(): Settings.toggle_mute())
	_settings_buttons["shake"] = _add_button("settings", vbox, "", func(): Settings.toggle_reduced_shake())
	_settings_buttons["echo"] = _add_button("settings", vbox, "", func(): Settings.toggle_companion())
	if not OS.has_feature("web"):
		_settings_buttons["fullscreen"] = _add_button("settings", vbox, "", func(): Settings.toggle_fullscreen())
		_add_button("settings", vbox, "QUIT GAME", func(): get_tree().quit())
	_add_back_button("settings", vbox)


func _refresh_settings_labels() -> void:
	if _settings_buttons.is_empty():
		return
	_settings_buttons["sound"].text = "SOUND: %s" % ("OFF" if Settings.muted else "ON")
	_settings_buttons["shake"].text = "REDUCED SHAKE & FLASH: %s" % ("ON" if Settings.reduced_shake else "OFF")
	_settings_buttons["echo"].text = "ECHO LIVE REPLIES: %s" % ("ON" if Settings.companion_enabled else "OFF")
	if _settings_buttons.has("fullscreen"):
		_settings_buttons["fullscreen"].text = "FULLSCREEN: %s" % ("ON" if Settings.fullscreen else "OFF")
	if _marker != null:
		_marker.queue_redraw()  # the speaker icon's mute slash


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
	_add_back_button("credits", vbox)


func _load_credits() -> Dictionary:
	var fallback := {
		"subtitle": "Made at UBhacks 2026",
		"sections": [{"heading": "TEAM", "lines": ["The Back2Earth team"]}],
	}
	if not FileAccess.file_exists(CREDITS_PATH):
		return fallback
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else fallback


# --- Focus marker ----------------------------------------------------------------------

## Pulsing outline (and arrows on the big buttons) around the focused painted
## button, plus a red slash over the speaker icon while muted.
class FocusMarker extends Control:
	var menu = null
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if menu == null:
			return
		var sound_rect: Rect2 = menu.get_hotspot_rect(4)
		if Settings.muted:
			draw_line(sound_rect.position + Vector2(8, sound_rect.size.y - 6),
				sound_rect.position + Vector2(sound_rect.size.x - 8, 6), Color("ff004d"), 3.0)
		if not menu.is_marker_visible():
			return
		var i: int = menu.focus_index
		var r: Rect2 = menu.get_hotspot_rect(i)
		var a := 0.55 + 0.45 * sin(_t * 6.0)
		var c := Color(1, 1, 1, a)
		draw_rect(r.grow(3), c, false, 2.0)
		if i <= 2:  # the three big buttons get pixel arrows
			var mid := r.position.y + r.size.y / 2.0
			var lx := r.position.x - 10.0 - 2.0 * sin(_t * 6.0)
			var rx := r.end.x + 10.0 + 2.0 * sin(_t * 6.0)
			draw_colored_polygon(PackedVector2Array([
				Vector2(lx - 6, mid - 6), Vector2(lx, mid), Vector2(lx - 6, mid + 6)]), Color("3df0ff"))
			draw_colored_polygon(PackedVector2Array([
				Vector2(rx + 6, mid - 6), Vector2(rx, mid), Vector2(rx + 6, mid + 6)]), Color("3df0ff"))
