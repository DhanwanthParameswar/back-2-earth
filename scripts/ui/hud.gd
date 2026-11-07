extends CanvasLayer
## HUD, briefing, pause, and end screens. Owner: D.
## Built in code against GameState / GravityDirector / CompanionClient signals,
## so it works with placeholder art and can be restyled freely.
## Base resolution is 640x360 (see project.godot); positions are in those pixels.

const Art = preload("res://scripts/ship/art.gd")
const PressButton = preload("res://scripts/ui/press_button.gd")

const CAPTION_TIME := 6.0

var _timer_label: Label
var _objective_label: Label
var _hint_label: Label
var _gravity_label: Label
var _gravity_icon: Control
var _prompt_label: Label
var _boots_label: Label
var _caption_panel: Control
var _caption_tag: Label
var _caption_text: Label
var _status_label: Label
var _hit_flash: ColorRect
var _edge_flash: Control

var _picker: Control
var _picker_cards: Array = []
var _pick_index := 0
var _pause: Control
var _pause_options: Label
var _lost: Control
var _won: Control
var _won_caption: Label
var _won_stats: Label
var _won_prompt: Label
var _earth: TextureRect
var _pod: Control

var _caption_left := 0.0
var _launch_line := ""
var _end_input_ready := false
var _blink_t := 0.0

var _companion = null
var _director = null
var _player = null


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_build_picker()
	_build_pause()
	_build_lost()
	_build_won()

	GameState.phase_changed.connect(_on_phase_changed)
	GameState.objective_changed.connect(_on_objective_changed)
	GameState.time_changed.connect(_on_time_changed)
	GameState.damaged.connect(_on_damaged)
	GameState.run_ended.connect(_on_run_ended)
	GameState.paused_changed.connect(_on_paused_changed)
	Settings.changed.connect(_refresh_pause_options)

	_companion = get_tree().get_first_node_in_group("companion")
	if _companion != null:
		_companion.line_shown.connect(_on_companion_line)
		_companion.status_changed.connect(_on_companion_status)
		_companion.help_requested.connect(_on_help_requested)

	_on_phase_changed(GameState.phase)
	_on_objective_changed("")
	_on_time_changed(int(ceil(GameState.time_left)))
	_on_companion_status("offline")


# --- Per-frame ------------------------------------------------------------------

func _process(delta: float) -> void:
	_blink_t += delta
	if _director == null or not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("gravity_director")
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")

	_update_gravity_label()
	_update_prompt()

	if _caption_left > 0.0 and not GameState.is_paused():
		_caption_left -= delta
		_caption_panel.modulate.a = clampf(_caption_left / 0.6, 0.0, 1.0)
		_caption_panel.visible = _caption_left > 0.0

	if _picker.visible:
		for i in _picker_cards.size():
			_picker_cards[i].set_selected(i == _pick_index, _blink_t)


func _update_gravity_label() -> void:
	if _director == null:
		_gravity_label.text = ""
		return
	var secs := int(ceil(_director.seconds_left()))
	var dir_name: String = _director.direction_name(_director.next_direction())
	match _director.state:
		0:  # CALM
			_gravity_label.text = "CALM %d\nnext %s" % [secs, dir_name]
			_gravity_label.modulate = Color(0.75, 0.76, 0.78)
		1:  # WARNING
			_gravity_label.text = "SURGE %s\nin %d" % [dir_name, secs]
			_gravity_label.modulate = Art.AMBER
		2:  # PULL
			_gravity_label.text = "PULL %s\n%ds  [SPACE]" % [dir_name, secs]
			_gravity_label.modulate = Art.RED


func _update_prompt() -> void:
	var braced := false
	var prompt := ""
	if _player != null and GameState.is_playing():
		braced = _player.braced
		if _player.current_target != null:
			prompt = "[E] %s" % _player.current_target.get_prompt()
	_prompt_label.text = prompt
	_prompt_label.visible = prompt != ""
	_boots_label.modulate = Art.CYAN if braced else Color(0.6, 0.6, 0.65)
	_boots_label.text = "MAG-BOOTS ON" if braced else "[SPACE] mag-boots"


# --- Input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var phase: int = GameState.phase
	if phase == GameState.Phase.BRIEFING:
		# The suit picker is the only pre-run screen (the menu covers the rest).
		if event.is_action_pressed("move_left") or event.is_action_pressed("move_up"):
			_move_pick(-1)
			_handled()
		elif event.is_action_pressed("move_right") or event.is_action_pressed("move_down"):
			_move_pick(1)
			_handled()
		elif event.is_action_pressed("confirm"):
			_launch()
			_handled()
		elif event.is_action_pressed("pause") or event.is_action_pressed("to_menu"):
			_go_to_menu()
			_handled()
	elif phase == GameState.Phase.PLAYING:
		if event.is_action_pressed("pause"):
			GameState.set_paused(not GameState.is_paused())
			_handled()
		elif GameState.is_paused():
			if event.is_action_pressed("restart"):
				_restart()
			elif event.is_action_pressed("to_menu"):
				_go_to_menu()
			elif event.is_action_pressed("toggle_mute"):
				Settings.toggle_mute()
			elif event.is_action_pressed("toggle_shake"):
				Settings.toggle_reduced_shake()
			_handled()
	elif _end_input_ready and (event.is_action_pressed("restart") or event.is_action_pressed("confirm")):
		_restart()
		_handled()
	elif _end_input_ready and event.is_action_pressed("to_menu"):
		_go_to_menu()
		_handled()


func _handled() -> void:
	get_viewport().set_input_as_handled()


func _restart() -> void:
	GameState.set_paused(false)
	get_tree().paused = false
	get_tree().reload_current_scene()


const MENU_SCENE := "res://scenes/menu.tscn"


func _go_to_menu() -> void:
	GameState.set_paused(false)
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


# --- Signal handlers ----------------------------------------------------------------

func _on_phase_changed(phase: int) -> void:
	if phase == GameState.Phase.BRIEFING:
		_show_picker()
	else:
		_picker.visible = false
	_pause.visible = false
	_on_objective_changed("")


func _on_objective_changed(_id: String) -> void:
	var c: Dictionary = GameState.get_canonical()
	var total: int = GameState.OBJECTIVES.size()
	var step := mini(GameState.objective_index + 1, total)
	if GameState.phase == GameState.Phase.PLAYING:
		_objective_label.text = "%d/%d  %s" % [step, total, c["text"]]
	else:
		_objective_label.text = str(c["text"])
	_hint_label.text = str(c["hint"])
	_on_time_changed(int(ceil(GameState.time_left)))  # recolor when the timer starts


func _on_time_changed(seconds: int) -> void:
	_timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	if seconds <= 30:
		_timer_label.modulate = Art.RED
	elif seconds <= 60:
		_timer_label.modulate = Art.AMBER
	else:
		_timer_label.modulate = Color.WHITE
	if not GameState.is_timer_running() and GameState.phase == GameState.Phase.PLAYING:
		_timer_label.modulate = Color(0.6, 0.6, 0.65)  # not started yet


func _on_damaged(seconds_lost: float) -> void:
	_hit_flash.color.a = 0.0 if Settings.reduced_shake else 0.35
	var tw := create_tween()
	tw.tween_property(_hit_flash, "color:a", 0.0, 0.35)
	_show_caption("-%d s" % int(seconds_lost), "IMPACT", Art.RED, 1.2)


func _on_companion_line(text: String, source: String, kind: String) -> void:
	if kind == "launch":
		_launch_line = text
	var tag := "ECHO · OFFLINE (scripted line)"
	var color := Art.AMBER
	if source == "live":
		tag = "ECHO · LIVE"
		color = Art.CYAN
	elif source == "mock":
		tag = "ECHO · MOCK SERVER"
		color = Art.STEEL_LIGHT
	_show_caption(text, tag, color, CAPTION_TIME)


func _on_companion_status(status: String) -> void:
	_status_label.text = "ECHO: %s" % status.to_upper()
	_status_label.modulate = Art.CYAN if status == "live" else Color(0.6, 0.6, 0.65)


func _on_help_requested() -> void:
	var tw := create_tween()
	_hint_label.modulate = Art.CYAN
	tw.tween_property(_hint_label, "modulate", Color(0.76, 0.76, 0.78), 1.5)


func _on_paused_changed(is_paused: bool) -> void:
	_pause.visible = is_paused
	_refresh_pause_options()


func _on_run_ended(won: bool) -> void:
	_caption_left = 0.0
	_caption_panel.visible = false
	_end_input_ready = false
	# Tweens (not awaits) so nothing resumes on a freed HUD after a restart.
	var tw := create_tween()
	if won:
		tw.tween_interval(0.6)
		tw.tween_callback(_play_win_sequence)
	else:
		tw.tween_interval(0.4)
		tw.tween_callback(func(): _lost.visible = true)
		tw.tween_interval(0.8)  # avoid an instant restart from a held key
		tw.tween_callback(func(): _end_input_ready = true)


func _show_caption(text: String, tag: String, tag_color: Color, seconds: float) -> void:
	_caption_tag.text = tag
	_caption_tag.modulate = tag_color
	_caption_text.text = text
	_caption_panel.visible = true
	_caption_panel.modulate.a = 1.0
	_caption_left = seconds


func _refresh_pause_options() -> void:
	if _pause_options == null:
		return
	_pause_options.text = "[Esc] Resume\n[R] Restart run\n[M] Sound: %s\n[V] Reduced shake/flash: %s\n[Q] Main menu" % [
		"OFF" if Settings.muted else "ON",
		"ON" if Settings.reduced_shake else "OFF",
	]


# --- Win sequence: pod departure -> stars -> Earth --------------------------------

func _play_win_sequence() -> void:
	_won.visible = true
	_won.modulate.a = 0.0
	_earth.modulate.a = 0.0
	_won_caption.text = ""
	_won_stats.text = ""
	_won_prompt.visible = false
	_pod.position = Vector2(-80, 150)

	var tw := create_tween()
	tw.tween_property(_won, "modulate:a", 1.0, 0.6)
	tw.tween_property(_pod, "position", Vector2(700, 140), 3.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_earth, "modulate:a", 1.0, 2.5).set_delay(1.5)
	tw.tween_callback(_show_win_text)


func _show_win_text() -> void:
	var secs := int(ceil(GameState.time_left))
	if _launch_line != "":
		_won_caption.text = _launch_line
	else:
		_won_caption.text = "Course set for Earth. Please remember the stars from somewhere safer."
	_won_stats.text = "Time left %02d:%02d   ·   Debris hits %d   ·   Boots used %d" % [
		secs / 60, secs % 60, GameState.hit_count, GameState.boots_use_count]
	_won_prompt.visible = true
	_end_input_ready = true


# --- Construction --------------------------------------------------------------------

func _label(text: String, pos: Vector2, size: Vector2, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _full_screen() -> Control:
	var c := Control.new()
	c.position = Vector2.ZERO
	c.size = Vector2(640, 360)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _build_hud() -> void:
	var root := _full_screen()
	root.name = "Hud"

	_edge_flash = EdgeFlash.new()
	_edge_flash.size = Vector2(640, 360)
	root.add_child(_edge_flash)

	_hit_flash = _rect(Vector2.ZERO, Vector2(640, 360), Color(1, 0, 0.3, 0))
	root.add_child(_hit_flash)

	root.add_child(_rect(Vector2.ZERO, Vector2(640, 46), Color(0, 0, 0, 0.6)))
	_timer_label = _label("06:00", Vector2(8, 4), Vector2(100, 36), 26)
	root.add_child(_timer_label)

	_objective_label = _label("", Vector2(112, 3), Vector2(400, 18), 14)
	root.add_child(_objective_label)
	_hint_label = _label("", Vector2(112, 20), Vector2(400, 26), 10)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.modulate = Color(0.76, 0.76, 0.78)
	root.add_child(_hint_label)

	_gravity_icon = GravityIcon.new()
	_gravity_icon.position = Vector2(516, 4)
	_gravity_icon.size = Vector2(36, 38)
	root.add_child(_gravity_icon)
	_gravity_label = _label("", Vector2(554, 6), Vector2(84, 36), 11)
	root.add_child(_gravity_label)

	_prompt_label = _label("", Vector2(120, 262), Vector2(400, 20), 15, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt_label.modulate = Art.CYAN
	root.add_child(_prompt_label)

	_boots_label = _label("", Vector2(8, 286), Vector2(160, 16), 10)
	root.add_child(_boots_label)
	_status_label = _label("", Vector2(472, 286), Vector2(160, 16), 10, HORIZONTAL_ALIGNMENT_RIGHT)
	root.add_child(_status_label)

	_caption_panel = Control.new()
	_caption_panel.position = Vector2(16, 304)
	_caption_panel.size = Vector2(608, 50)
	_caption_panel.visible = false
	root.add_child(_caption_panel)
	_caption_panel.add_child(_rect(Vector2.ZERO, Vector2(608, 50), Color(0.03, 0.05, 0.12, 0.88)))
	var portrait_tex := Art.tex("res://assets/sprites/echo.png")
	if portrait_tex != null:
		var portrait := TextureRect.new()
		portrait.texture = portrait_tex
		portrait.position = Vector2(8, 9)
		portrait.size = Vector2(32, 32)
		_caption_panel.add_child(portrait)
	_caption_tag = _label("ECHO", Vector2(48, 2), Vector2(552, 14), 10)
	_caption_panel.add_child(_caption_tag)
	_caption_text = _label("", Vector2(48, 15), Vector2(552, 34), 12)
	_caption_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_panel.add_child(_caption_text)


func _build_picker() -> void:
	_picker = _full_screen()
	_picker.name = "SuitPicker"
	_picker.visible = false
	_picker.add_child(_rect(Vector2.ZERO, Vector2(640, 360), Color("080d26")))
	var title := _label("CHOOSE YOUR SUIT", Vector2(0, 14), Vector2(640, 30), 22, HORIZONTAL_ALIGNMENT_CENTER)
	title.modulate = Art.WHITE
	_picker.add_child(title)
	_picker.add_child(_rect(Vector2(248, 44), Vector2(144, 2), Art.CYAN))

	var card_size := Vector2(136, 206)
	var gap := 14.0
	var left := (640.0 - (card_size.x * 4.0 + gap * 3.0)) / 2.0
	_picker_cards.clear()
	for i in Settings.SKINS.size():
		var skin: Dictionary = Settings.SKINS[i]
		var card := SkinCard.new()
		card.position = Vector2(left + i * (card_size.x + gap), 60)
		card.size = card_size
		_picker.add_child(card)
		card.setup(
			Art.tex(Settings.skin_portrait_path(skin["id"])),
			str(skin["name"]),
			str(skin["blurb"]),
			"%d" % (i + 1)
		)
		card.clicked.connect(_on_card_clicked.bind(i))
		_picker_cards.append(card)

	var launch := PressButton.new()
	launch.name = "Launch"
	launch.position = Vector2(250, 274)
	launch.size = Vector2(140, 28)
	launch.set_label("LAUNCH")
	launch.pressed.connect(_launch)
	_picker.add_child(launch)

	var help := _label("Click a suit or use A / D      E  launch      Esc  main menu",
		Vector2(0, 308), Vector2(640, 18), 11, HORIZONTAL_ALIGNMENT_CENTER)
	help.modulate = Art.AMBER
	_picker.add_child(help)
	var note := _label("Your suit is remembered for the next run.", Vector2(0, 328), Vector2(640, 16), 10,
		HORIZONTAL_ALIGNMENT_CENTER)
	note.modulate = Color(0.6, 0.6, 0.65)
	_picker.add_child(note)


func _show_picker() -> void:
	_picker.visible = true
	_pick_index = maxi(0, Settings.skin_index(Settings.skin))


## Start the run with the highlighted suit.
func _launch() -> void:
	if GameState.phase != GameState.Phase.BRIEFING:
		return
	Settings.set_skin(Settings.SKINS[_pick_index]["id"])
	Sfx.play("objective", -8.0)
	GameState.begin_play()


func _on_card_clicked(i: int) -> void:
	if i == _pick_index:
		_launch()  # clicking the chosen suit again launches
	else:
		_pick_index = i
		Settings.set_skin(Settings.SKINS[i]["id"])
		Sfx.play("boots", -10.0)


func _move_pick(delta: int) -> void:
	var n: int = Settings.SKINS.size()
	_pick_index = (_pick_index + delta + n) % n
	Settings.set_skin(Settings.SKINS[_pick_index]["id"])
	Sfx.play("boots", -10.0)


func _build_pause() -> void:
	_pause = _full_screen()
	_pause.name = "Pause"
	_pause.visible = false
	_pause.add_child(_rect(Vector2.ZERO, Vector2(640, 360), Color(0, 0, 0, 0.7)))
	_pause.add_child(_label("PAUSED", Vector2(0, 90), Vector2(640, 36), 28, HORIZONTAL_ALIGNMENT_CENTER))
	_pause_options = _label("", Vector2(0, 140), Vector2(640, 100), 14, HORIZONTAL_ALIGNMENT_CENTER)
	_pause.add_child(_pause_options)
	_refresh_pause_options()


func _build_lost() -> void:
	_lost = _full_screen()
	_lost.name = "Lost"
	_lost.visible = false
	_lost.add_child(_rect(Vector2.ZERO, Vector2(640, 360), Color(0.05, 0, 0.02, 0.85)))
	var t := _label("EVACUATION FAILED", Vector2(0, 110), Vector2(640, 36), 28, HORIZONTAL_ALIGNMENT_CENTER)
	t.modulate = Art.RED
	_lost.add_child(t)
	_lost.add_child(_label("The safe window closed before the pod launched.",
		Vector2(0, 156), Vector2(640, 20), 13, HORIZONTAL_ALIGNMENT_CENTER))
	var r := _label("[R] Try again      [Q] Main menu", Vector2(0, 210), Vector2(640, 24), 16, HORIZONTAL_ALIGNMENT_CENTER)
	r.modulate = Art.AMBER
	_lost.add_child(r)


func _build_won() -> void:
	_won = _full_screen()
	_won.name = "Won"
	_won.visible = false
	_won.add_child(_rect(Vector2.ZERO, Vector2(640, 360), Color.BLACK))
	var stars := Starfield.new()
	stars.size = Vector2(640, 360)
	_won.add_child(stars)

	_earth = TextureRect.new()
	var earth_tex := Art.tex("res://assets/backdrops/earth.png")
	if earth_tex != null:
		_earth.texture = earth_tex
	_earth.position = Vector2(256, 70)
	_earth.size = Vector2(128, 128)
	_earth.stretch_mode = TextureRect.STRETCH_SCALE
	_won.add_child(_earth)

	var pod_tex := Art.tex("res://assets/sprites/pod.png")
	if pod_tex != null:
		var pod := TextureRect.new()
		pod.texture = pod_tex
		pod.size = Vector2(64, 64)
		_pod = pod
	else:
		_pod = _rect(Vector2.ZERO, Vector2(48, 24), Art.STEEL_LIGHT)
	_won.add_child(_pod)

	var title := _label("BACK TO EARTH", Vector2(0, 206), Vector2(640, 30), 24, HORIZONTAL_ALIGNMENT_CENTER)
	title.modulate = Art.CYAN
	_won.add_child(title)
	_won_caption = _label("", Vector2(40, 240), Vector2(560, 36), 12, HORIZONTAL_ALIGNMENT_CENTER)
	_won_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_won.add_child(_won_caption)
	_won_stats = _label("", Vector2(0, 280), Vector2(640, 18), 11, HORIZONTAL_ALIGNMENT_CENTER)
	_won_stats.modulate = Color(0.76, 0.76, 0.78)
	_won.add_child(_won_stats)
	_won_prompt = _label("[R] Play again      [Q] Main menu", Vector2(0, 312), Vector2(640, 22), 15, HORIZONTAL_ALIGNMENT_CENTER)
	_won_prompt.modulate = Art.AMBER
	_won.add_child(_won_prompt)


# --- Small drawn widgets ---------------------------------------------------------

## Arrow showing the upcoming/current pull. Grey = calm, blinking amber =
## warning, red = pulling.
class GravityIcon extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
		var d = get_tree().get_first_node_in_group("gravity_director")
		if d == null:
			return
		var dir: Vector2 = d.next_direction()
		var color := Color(0.6, 0.6, 0.65)
		if d.state == 1:
			color = Color("ffa300") if int(_t * 6.0) % 2 == 0 else Color("ffa300", 0.3)
		elif d.state == 2:
			dir = d.current_direction
			color = Color("ff004d")
		var angle := dir.angle() - PI / 2.0  # points authored facing DOWN
		var pts := PackedVector2Array([
			Vector2(-4, -12), Vector2(4, -12), Vector2(4, 1), Vector2(11, 1),
			Vector2(0, 13), Vector2(-11, 1), Vector2(-4, 1),
		])
		var center := size / 2.0
		for i in pts.size():
			pts[i] = center + pts[i].rotated(angle)
		draw_colored_polygon(pts, color)


## Amber frame around the screen during a surge warning.
class EdgeFlash extends Control:
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var d = get_tree().get_first_node_in_group("gravity_director")
		if d == null or d.state != 1 or int(_t * 6.0) % 2 != 0:
			return
		var c := Color("ffa300", 0.8)
		draw_rect(Rect2(Vector2.ZERO, size), c, false, 3.0)


## Scrolling stars for the ending.
class Starfield extends Control:
	var _stars: Array[Vector3] = []  # x, y, speed

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 2026
		for i in 90:
			_stars.append(Vector3(rng.randf() * 640.0, rng.randf() * 360.0, rng.randf_range(10.0, 60.0)))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		for i in _stars.size():
			var s := _stars[i]
			s.x -= s.z * delta
			if s.x < 0.0:
				s.x += 640.0
			_stars[i] = s
		queue_redraw()

	func _draw() -> void:
		for s in _stars:
			var b := 0.4 + s.z / 100.0
			draw_rect(Rect2(Vector2(floor(s.x), floor(s.y)), Vector2.ONE * (2.0 if s.z > 45.0 else 1.0)), Color(b, b, b + 0.1))


## One suit in the picker: grid panel (like the concept sheet), portrait at 6x,
## name and blurb. Cyan frame + bobbing portrait when selected.
class SkinCard extends Control:
	signal clicked

	var _portrait: TextureRect
	var _name: Label
	var _blurb: Label
	var _key: Label
	var _selected := false

	var _held := false
	var _base_y := 0.0

	func setup(portrait: Texture2D, title: String, blurb: String, key: String) -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_base_y = position.y
		_portrait = TextureRect.new()
		_portrait.texture = portrait
		_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_portrait.size = Vector2(96, 114)  # 16x19 art at 6x
		_portrait.position = Vector2((size.x - 96.0) / 2.0, 16)
		add_child(_portrait)
		_name = _make_label(title, 140, 15)
		_blurb = _make_label(blurb, 160, 10)
		_blurb.modulate = Color(0.7, 0.72, 0.8)
		_key = _make_label(key, 182, 10)
		_key.modulate = Color(0.45, 0.5, 0.65)

	## Press feel: the card sinks 3 px while held; a release on it is a click.
	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_held = true
			position.y = _base_y + 3.0
		elif _held:
			_held = false
			position.y = _base_y
			if Rect2(Vector2.ZERO, size).has_point(mb.position):
				clicked.emit()
		accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and _held:
			_held = false
			position.y = _base_y

	func _make_label(text: String, y: float, font_size: int) -> Label:
		var l := Label.new()
		l.text = text
		l.position = Vector2(0, y)
		l.size = Vector2(size.x, 18)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", font_size)
		add_child(l)
		return l

	func set_selected(value: bool, t: float) -> void:
		_selected = value
		if _portrait != null:
			var bob := 0.0
			if value:
				bob = -2.0 if int(t * 3.0) % 2 == 0 else 0.0
			_portrait.position.y = 16 + bob
			_portrait.modulate = Color.WHITE if value else Color(0.55, 0.55, 0.65)
			_name.modulate = Color("29adff") if value else Color(0.8, 0.8, 0.85)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0b1233"))
		var grid := Color("16204a")
		var step := 12.0
		var x := step
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, 132), grid, 1.0)
			x += step
		var y := step
		while y < 132.0:
			draw_line(Vector2(0, y), Vector2(size.x, y), grid, 1.0)
			y += step
		if _selected:
			draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color("29adff"), false, 2.0)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color("28325a"), false, 1.0)
