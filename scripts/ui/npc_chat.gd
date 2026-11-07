extends CanvasLayer
## Chat box for talking to an NPC (press E next to the crewmate). Owner: D.
## Type a question, Enter to send, Esc to close. While it is open the player
## stands still (typing WASD must not walk). The countdown keeps running.

const UiStyle = preload("res://scripts/ui/ui_style.gd")

var _root: PanelContainer
var _name_label: Label
var _status_label: Label
var _you_label: Label
var _text_label: Label
var _line_edit: LineEdit
var _npc = null
var _client = null
var _dots_t := 0.0
var _last_source := ""


func _ready() -> void:
	layer = 11
	add_to_group("npc_chat")
	add_to_group("blocks_player_input")
	_build()
	_root.visible = false
	GameState.run_ended.connect(func(_won): close())


func is_open() -> bool:
	return _root.visible


func open(npc) -> void:
	_npc = npc
	if _client == null:
		_client = get_tree().get_first_node_in_group("npc_client")
		if _client != null:
			_client.reply.connect(_on_reply)
			_client.voice.connect(_on_voice)
			_client.busy_changed.connect(_on_busy_changed)
	_name_label.text = str(npc.display_name).to_upper()
	if _text_label.text == "":
		_text_label.text = npc.last_line
	_root.visible = true
	_line_edit.text = ""
	_line_edit.grab_focus()
	_refresh_status()


func close() -> void:
	if _root == null:
		return
	_root.visible = false
	_line_edit.release_focus()


## Same as pressing Enter in the box (also used by tests).
func submit(text: String) -> void:
	text = text.strip_edges()
	if text == "" or _client == null:
		return
	if _client.ask(text):
		_you_label.text = "YOU: %s" % text
		_line_edit.text = ""


func _input(event: InputEvent) -> void:
	# Runs before the text box, so Esc closes the chat instead of pausing the game.
	if not is_open() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if is_open() and _client != null and _client.busy:
		_dots_t += delta
		_status_label.text = "thinking" + ".".repeat(1 + int(_dots_t * 3.0) % 3)


func _on_reply(text: String, source: String) -> void:
	_text_label.text = text
	_refresh_status(source)
	if _npc != null and is_instance_valid(_npc):
		_npc.say(text)


func _on_voice(stream: AudioStream) -> void:
	if _npc != null and is_instance_valid(_npc):
		_npc.play_voice(stream)


func _on_busy_changed(_is_busy: bool) -> void:
	_dots_t = 0.0
	_refresh_status()


func _refresh_status(source := "") -> void:
	if source != "":
		_last_source = source
	match _last_source:
		"live":
			_status_label.text = "LIVE · Gemini + voice"
			_status_label.modulate = UiStyle.CYAN
		"mock":
			_status_label.text = "MOCK SERVER"
			_status_label.modulate = UiStyle.AMBER
		"offline":
			_status_label.text = "OFFLINE (scripted line)"
			_status_label.modulate = UiStyle.MUTED
		_:
			_status_label.text = ""


func _build() -> void:
	_root = PanelContainer.new()
	_root.position = Vector2(70, 192)
	_root.size = Vector2(500, 124)
	_root.custom_minimum_size = Vector2(500, 124)
	_root.add_theme_stylebox_override("panel", UiStyle.panel())
	add_child(_root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_root.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_name_label = UiStyle.label("CREWMATE", 12, UiStyle.CYAN)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	_status_label = UiStyle.label("", 9, UiStyle.MUTED)
	head.add_child(_status_label)

	_you_label = UiStyle.label("", 10, UiStyle.MUTED)
	_you_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_you_label.custom_minimum_size = Vector2(470, 0)
	col.add_child(_you_label)

	_text_label = UiStyle.label("", 12)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.custom_minimum_size = Vector2(470, 30)
	col.add_child(_text_label)

	_line_edit = LineEdit.new()
	_line_edit.placeholder_text = "Ask her something, e.g. do you have any instructions?"
	_line_edit.max_length = 200
	_line_edit.add_theme_font_size_override("font_size", 12)
	_line_edit.add_theme_color_override("font_color", UiStyle.TEXT)
	_line_edit.add_theme_color_override("font_placeholder_color", UiStyle.MUTED)
	_line_edit.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.NAVY_DEEP, Color(UiStyle.CYAN, 0.5)))
	_line_edit.add_theme_stylebox_override("focus", UiStyle.box(UiStyle.NAVY_DEEP, UiStyle.CYAN))
	_line_edit.text_submitted.connect(submit)
	col.add_child(_line_edit)

	col.add_child(UiStyle.label("[Enter] send      [Esc] close", 9, UiStyle.MUTED))
