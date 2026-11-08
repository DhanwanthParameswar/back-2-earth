extends CanvasLayer

const Style = preload("res://scripts/ui/ui_style.gd")
const Radio = preload("res://scripts/prototype/escape_radio.gd")
const Map = preload("res://scripts/prototype/escape_map.gd")
var mission
var root: Control
var top: Panel
var lower: Panel
var heading: Label
var objective: Label
var prompt: Label
var caption: Label
var footer: Label
var modal: PanelContainer
var content: VBoxContainer
var radio
var chat_id := ""
var chat_input: LineEdit
var chat_reply: Label
var chat_status: Label
var mode := ""
var caption_time := 0.0
var pause_was_active := false
var content_width := 490.0

func _ready() -> void:
	layer = 10
	add_to_group("blocks_player_input")
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	top = Panel.new()
	top.position = Vector2(8, 7)
	top.size = Vector2(624, 54)
	top.add_theme_stylebox_override("panel", Style.box(Color("0b1526"), Color("34506a"), 1))
	root.add_child(top)
	heading = _label(top, "", Vector2(10, 4), 10, Style.MUTED)
	objective = _label(top, "", Vector2(10, 23), 12, Style.TEXT)
	objective.size = Vector2(602, 26)
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lower = Panel.new()
	lower.position = Vector2(8, 273)
	lower.size = Vector2(624, 80)
	lower.add_theme_stylebox_override("panel", Style.box(Color("0b1526"), Color("34506a"), 1))
	root.add_child(lower)
	prompt = _label(lower, "", Vector2(10, 4), 11, Style.CYAN_BRIGHT)
	caption = _label(lower, "", Vector2(10, 23), 11, Style.TEXT)
	caption.size = Vector2(600, 35)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer = _label(lower, "WASD move   E use / talk   1 Mara   2 Ivo   Tab map   Esc pause", Vector2(10, 61), 9, Style.MUTED)
	modal = PanelContainer.new()
	modal.position = Vector2(55, 67)
	modal.size = Vector2(530, 270)
	modal.custom_minimum_size = Vector2(530, 0)
	modal.add_theme_stylebox_override("panel", Style.panel())
	root.add_child(modal)
	modal.hide()
	radio = Radio.new()
	radio.mission = mission
	add_child(radio)
	radio.answered.connect(_answer)
	get_viewport().size_changed.connect(_layout)
	_layout()
	# Status messages ("Contacting Gemini...", source labels) are no longer shown.
	radio.transcribed.connect(func(text):
		if mode == "chat" and is_instance_valid(chat_input):
			chat_input.text = text.left(200)
			chat_input.grab_focus())

func _label(parent: Node, text: String, point: Vector2, font_size: int, color: Color) -> Label:
	var label := Style.label(text, font_size, color)
	label.position = point
	parent.add_child(label)
	return label

func is_open() -> bool:
	return modal.visible

## Fit the HUD to the visible screen, which is wider than 640 on wide windows
## (gameplay uses the "expand" aspect): bars span the width, the bottom bar
## sits at the bottom, popups stay centered.
func _layout() -> void:
	if not is_inside_tree():
		return  # the mission is closing
	var s := get_viewport().get_visible_rect().size
	top.size.x = s.x - 16
	objective.size.x = s.x - 38
	lower.position = Vector2(8, s.y - 87)
	lower.size.x = s.x - 16
	caption.size.x = s.x - 40
	_place_modal()

func _place_modal() -> void:
	if not is_inside_tree():
		return
	var s := get_viewport().get_visible_rect().size
	if mode == "chat":
		modal.position = Vector2(round((s.x - 500.0) / 2.0), s.y - 168.0)
	elif mode != "":
		modal.position.x = round((s.x - modal.custom_minimum_size.x) / 2.0)

func update_hud() -> void:
	if heading == null: return
	heading.text = "WAYFARER / " + mission.room + "     ·     " + ("PLAN: " + mission.state.route.to_upper() if mission.state.route != "" else "CREW 3/3") + "     ·     DESIGN PROTOTYPE"
	objective.text = mission.state.objective()
	if mission.state.carrying != "": objective.text += "  [" + mission.state.carrying.to_upper() + "]"
	var target = mission.player.current_target
	prompt.text = "[E] " + target.get_prompt() if target != null and is_instance_valid(target) else "[1 / 2] Crew radio     [Tab] Ship map"

func _process(delta: float) -> void:
	caption_time -= delta
	if caption_time <= 0 and not mission.ending:
		caption.text = "Mara and Ivo are on your helmet radio. Ask about the situation, or ask them to help."

func show_caption(speaker: String, line: String) -> void:
	caption.text = speaker + ": " + line
	caption_time = 10.0

func _panel(title: String, new_mode: String) -> void:
	close()
	mode = new_mode
	content_width = 255.0 if new_mode == "chat" else 490.0
	modal.custom_minimum_size.x = content_width + 28
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	modal.add_child(content)
	var title_label := Style.label(title, 12 if new_mode == "chat" else 16, Style.CYAN_BRIGHT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = content_width
	content.add_child(title_label)
	modal.size = Vector2(content_width + 28, 0)
	modal.position = Vector2(345, 65) if new_mode == "chat" else Vector2(55, 67)
	modal.show()
	_place_modal()

func _text(text: String, size := 11, color := Style.TEXT) -> Label:
	var label := Style.label(text, size, color)
	label.custom_minimum_size = Vector2(content_width, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func _button(text: String, callback: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	Style.style_button(button, 11)
	button.pressed.connect(callback)
	(parent if parent != null else content).add_child(button)
	return button

func close() -> void:
	if radio != null: radio.cancel()
	if mode == "pause": mission.active = pause_was_active
	chat_id = ""
	chat_input = null
	chat_reply = null
	chat_status = null
	for child in modal.get_children():
		modal.remove_child(child)
		child.queue_free()
	modal.hide()
	mode = ""
	mission.player.current_target = null
	mission.player.camera.offset = Vector2.ZERO

## The crew chat box: same look as the main game's crewmate chat (scripts/ui/npc_chat.gd):
## a wide box at the bottom with the name, your line, the reply, and a text field.
func open_chat(id: String) -> void:
	close()
	mode = "chat"
	chat_id = id
	content_width = 470.0
	modal.position = Vector2(70, 192)
	modal.size = Vector2(500, 124)
	modal.custom_minimum_size = Vector2(500, 124)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	modal.add_child(content)
	content.add_child(Style.label(mission.crew[id].display_name.to_upper(), 12, Style.CYAN))
	chat_status = _text("", 10, Style.MUTED)  # "YOU: ..." once you send something
	var history: Array = radio.histories[id]
	chat_reply = _text(str(history[-1].text) if not history.is_empty() else _greeting(id), 12)
	chat_reply.custom_minimum_size.y = 30
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Ask something, e.g. can you help me with the locker?"
	chat_input.max_length = 200
	chat_input.add_theme_font_size_override("font_size", 12)
	chat_input.add_theme_color_override("font_color", Style.TEXT)
	chat_input.add_theme_color_override("font_placeholder_color", Style.MUTED)
	chat_input.add_theme_stylebox_override("normal", Style.box(Style.NAVY_DEEP, Color(Style.CYAN, 0.5)))
	chat_input.add_theme_stylebox_override("focus", Style.box(Style.NAVY_DEEP, Style.CYAN))
	chat_input.text_submitted.connect(_send)
	content.add_child(chat_input)
	content.add_child(Style.label("[Enter] send      [Esc] close", 9, Style.MUTED))
	modal.show()
	_place_modal()
	chat_input.grab_focus()

func _greeting(id: String) -> String:
	if not mission.state.has_flag("locker_clear"):
		return "I can hold that locker while you push. We need both of us." if id == "mara" else "I'm checking the forward section. Can you and Mara clear the cabin doorway?"
	if mission.state.has_flag("clamps"): return "We're boarding. All three of us are going home."
	return ("I'm with you. " if id == "mara" else "Shuttle's intact. We just need the clamps released. ") + mission.state.objective()

func _send(message: String) -> void:
	if mode != "chat" or radio.busy or message.strip_edges() == "": return
	chat_status.text = "YOU: " + message.strip_edges()
	chat_reply.text = "..."
	chat_input.text = ""
	radio.ask(chat_id, message)

func _answer(data: Dictionary) -> void:
	if mode != "chat" or data.npc_id != chat_id: return
	chat_reply.text = data.line
	mission.announce("MARA" if chat_id == "mara" else "IVO", data.line)

func show_routes() -> void:
	_panel("SHUTTLE / LAUNCH DIAGNOSTICS", "routes")
	_text("PROPULSION: INTACT   ·   CREW CAPACITY: 3   ·   DOCKING CLAMPS: NO POWER", 10, Style.AMBER)
	_text("Engineering is north. The laboratory is south. Both can restore launch power; the crew can discuss the tradeoffs over radio.")
	_button("A · Repair Engineering — preserve the lab supply", func():
		mission.perform("choose_engineering")
		close())
	_text("Isolate the circuit, replace its fuse, diagnose the short and restart the supply.", 10, Style.MUTED)
	_button("B · Divert the lab battery — faster, costs sample cooling", func():
		mission.perform("choose_battery")
		close())
	_text("You can ask Ivo about an insulated case before disconnecting the freezer.", 10, Style.MUTED)
	_button("Keep looking / talk to the crew", close)

func confirm_action(title: String, description: String, action: String) -> void:
	_panel(title, "confirm")
	_text(description)
	_button("Confirm", func():
		close()
		mission.perform(action))
	_button("Go back", close)

func show_map() -> void:
	_panel("WAYFARER / DECK PLAN", "map")
	var map := Map.new()
	map.mission = mission
	map.custom_minimum_size = Vector2(490, 218)
	content.add_child(map)
	_text("White: you    Mint: Mara    Amber: Ivo    Engineering north / Lab south / Shuttle east", 9, Style.MUTED)
	_button("Close [Tab / Esc]", close)
	modal.position.y = 15

func show_pause() -> void:
	_panel("MISSION PAUSED", "pause")
	pause_was_active = mission.active
	mission.active = false
	_text("WASD / arrows move · E interact · 1 / 2 crew radio · Tab deck plan. No countdown; take time to discuss your plan.")
	var history: Array[String] = mission.state.journal
	_text("RECENT EVENTS\n" + "\n".join(history.slice(maxi(0, history.size() - 3))), 10, Style.MUTED)
	_button("Resume", close)
	_button("Restart prototype (skip intro)", func(): get_tree().reload_current_scene())
	_button("Main menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))

func show_ending() -> void:
	_panel("BACK 2 EARTH", "ending")
	modal.position.y = 18
	var earth := TextureRect.new()
	earth.texture = load("res://assets/backdrops/earth.png")
	earth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	earth.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	earth.custom_minimum_size = Vector2(490, 100)
	content.add_child(earth)
	_text(mission.state.ending(), 14, Style.CYAN_BRIGHT)
	var detail := "The lab remains powered aboard Wayfarer, ready for a recovery mission. All three crew made it home." if mission.state.route == "engineering" else "The priority samples survived in the insulated case. All three crew made it home." if mission.state.has_flag("samples_saved") else "The research was lost. Johnny, Mara and Ivo all made it home."
	_text(detail)
	_text('MARA: "Next expedition, we pack a bigger case."' if mission.state.has_flag("samples_saved") else 'IVO: "Three seats occupied. That was the important part."', 10, Style.MUTED)
	var row := HBoxContainer.new()
	content.add_child(row)
	_button("Try another route", func(): get_tree().reload_current_scene(), row)
	_button("Main menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"), row)

func _input(event: InputEvent) -> void:
	if not modal.visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE or (event.physical_keycode == KEY_TAB and mode == "map"):
			if mode != "ending": close()
			get_viewport().set_input_as_handled()
