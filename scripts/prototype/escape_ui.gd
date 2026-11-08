extends CanvasLayer

const Style = preload("res://scripts/ui/ui_style.gd")
const Radio = preload("res://scripts/prototype/escape_radio.gd")
const Map = preload("res://scripts/prototype/escape_map.gd")
var mission
var root: Control
## The one HUD bar (bottom): "ROOM · objective" on top, radio/map keys on a small row under it.
var bar: Panel
var objective: Label
var keys: Label
## Short line just above the bar: ship messages, or a crewmate who is off-screen.
var toast: Label
## Full key list, shown for the first seconds of the mission (always in the pause menu).
var hint: Label
## "[E] ..." under the name of the object or crewmate you are next to.
var float_prompt: Label
var modal: PanelContainer
var content: VBoxContainer
var radio
var chat_id := ""
var chat_input: LineEdit
var chat_reply: Label
var chat_status: Label
## Voice chat (Settings.voice_chat): no text field; live transcript + spoken replies.
var voice_mode := false
var voice_status: Label
var mode := ""
var toast_time := 0.0
var hint_time := -1.0
var pause_was_active := false
var content_width := 490.0
var _quick_replies := false   # the text chat shows ready-made lines (controller)

const HINT_SECONDS := 15.0
const BAR_HEIGHT := 36.0

func _ready() -> void:
	layer = 10
	add_to_group("blocks_player_input")
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	bar = Panel.new()
	bar.size = Vector2(624, BAR_HEIGHT)
	bar.add_theme_stylebox_override("panel", Style.box(Color("0b1526", 0.92), Color("34506a"), 1))
	root.add_child(bar)
	objective = _label(bar, "", Vector2(10, 3), 11, Style.TEXT)
	objective.clip_text = true
	objective.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	keys = _label(bar, "", Vector2(10, 19), 9, Style.MUTED)
	keys.clip_text = true
	toast = _outlined(root, 10, Style.TEXT)
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = _outlined(root, 9, Style.MUTED)
	hint.visible = false
	_refresh_hints()
	Settings.input_device_changed.connect(_on_device_changed)
	float_prompt = _outlined(root, 10, Style.CYAN_BRIGHT)
	float_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	float_prompt.size = Vector2(160, 14)
	float_prompt.visible = false
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
	radio.speech_partial.connect(_on_speech_partial)
	radio.speech_final.connect(_on_speech_final)
	radio.listening_changed.connect(_on_listening_changed)
	radio.voice_finished.connect(_on_voice_finished)
	radio.status_changed.connect(_on_radio_status)
	radio.transcribed.connect(func(text):
		if mode == "chat" and is_instance_valid(chat_input):
			chat_input.text = text.left(200)
			chat_input.grab_focus())

func _label(parent: Node, text: String, point: Vector2, font_size: int, color: Color) -> Label:
	var label := Style.label(text, font_size, color)
	label.position = point
	parent.add_child(label)
	return label

## Text drawn straight over the ship, with a dark outline so it stays readable.
func _outlined(parent: Node, font_size: int, color: Color) -> Label:
	var label := Style.label("", font_size, color)
	label.add_theme_color_override("font_outline_color", Color("050a19"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func is_open() -> bool:
	return modal.visible

## Fit the HUD to the visible screen, which is wider than 640 on wide windows
## (gameplay uses the "expand" aspect): the bar spans the bottom, popups stay centered.
func _layout() -> void:
	if not is_inside_tree():
		return  # the mission is closing
	var s := get_viewport().get_visible_rect().size
	bar.position = Vector2(8, s.y - BAR_HEIGHT - 6)
	bar.size.x = s.x - 16
	objective.size = Vector2(bar.size.x - 20, 16)
	keys.size = Vector2(bar.size.x - 20, 14)
	toast.position = Vector2(14, bar.position.y - 34)
	toast.size = Vector2(s.x - 28, 30)
	toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.position = Vector2(14, bar.position.y - 50)
	hint.size = Vector2(s.x - 28, 14)
	_place_modal()

func _place_modal() -> void:
	if not is_inside_tree():
		return
	var s := get_viewport().get_visible_rect().size
	if mode == "chat":
		modal.position = Vector2(round((s.x - 500.0) / 2.0), s.y - (206.0 if _quick_replies else 180.0))
	elif mode != "":
		modal.position.x = round((s.x - modal.custom_minimum_size.x) / 2.0)

func update_hud() -> void:
	if objective == null: return
	var text: String = mission.room + "   ·   " + mission.state.objective()
	if mission.state.route != "": text += "   ·   PLAN: " + mission.state.route.to_upper()
	if mission.state.carrying != "": text += "   [" + mission.state.carrying.to_upper() + "]"
	objective.text = text

## Key hints for whatever the player is using: keyboard or a controller.
func _refresh_hints() -> void:
	var b := Settings.button_label
	keys.text = "%s move   %s use / talk   %s Aaron   %s Dhan   %s light   %s map   %s pause" % [
		b.call("move"), b.call("interact"), b.call("radio_1"), b.call("radio_2"), b.call("flashlight"),
		b.call("deck_map"), b.call("pause")]
	hint.text = "It's dark: press %s for your flashlight.   Aaron and Dhan are on the radio (%s / %s)." % [
		b.call("flashlight"), b.call("radio_1"), b.call("radio_2")]

func _on_device_changed() -> void:
	_refresh_hints()
	if Settings.using_controller and is_open():
		_focus_first_button()

## Give the first button in an open panel keyboard/controller focus.
func _focus_first_button() -> void:
	if content == null or not is_instance_valid(content): return
	for b in content.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			b.grab_focus()
			return

func _process(delta: float) -> void:
	toast_time -= delta
	toast.visible = toast_time > 0.0 and not mission.ending and mode != "chat"  # the chat box shows it
	toast.modulate.a = clampf(toast_time / 0.5, 0.0, 1.0)
	if hint_time < 0.0 and mission.active:
		hint_time = HINT_SECONDS  # the mission just started
	if hint_time > 0.0:
		hint_time = maxf(0.0, hint_time - delta)
		hint.visible = hint_time > 0.0 and not is_open()
		hint.modulate.a = clampf(hint_time / 1.0, 0.0, 1.0)
	_update_float_prompt()

## "[E] Talk" / "[E] JAMMED LOCKER" just under the target's own name label.
func _update_float_prompt() -> void:
	var target = mission.player.current_target if mission != null and mission.player != null else null
	if target == null or not is_instance_valid(target) or not mission.active or mission.ending or is_open():
		float_prompt.visible = false
		return
	var key := "[%s] " % Settings.button_label("interact")
	float_prompt.text = key + "Talk" if "actor_id" in target else key + str(target.get_prompt())
	var at: Vector2 = target.get_global_transform_with_canvas().origin
	float_prompt.position = Vector2(round(at.x - float_prompt.size.x / 2.0), round(at.y + 22.0))
	float_prompt.visible = true

## Crew and ship lines, as text just above the bar (there are no speech bubbles).
func show_caption(speaker: String, line: String) -> void:
	toast.text = speaker + ": " + line
	toast_time = 4.0 + minf(line.length() * 0.05, 8.0)

func _on_screen(node: Node2D) -> bool:
	var at: Vector2 = node.get_global_transform_with_canvas().origin
	return get_viewport().get_visible_rect().grow(-20.0).has_point(at)

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
	if Settings.using_controller:
		_focus_first_button.call_deferred()

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

func close(stop_voice := true) -> void:
	if radio != null: radio.cancel(stop_voice)
	voice_mode = false
	voice_status = null
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
	_quick_replies = false
	mission.player.current_target = null
	mission.player.camera.offset = Vector2.ZERO

## The crew chat box: same look as the main game's crewmate chat (scripts/ui/npc_chat.gd):
## a wide box at the bottom with the name, your line, the reply, and a text field.
func open_chat(id: String) -> void:
	if Settings.voice_chat and radio.speech_supported():
		_open_voice_chat(id)
		return
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
	# No keyboard in hand: offer ready-made lines that fit what the crew can do now.
	_quick_replies = Settings.using_controller
	if _quick_replies:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		content.add_child(row)
		for line in _suggestions(id):
			var b := _button(line, _send.bind(line), row)
			b.add_theme_font_size_override("font_size", 9)
		modal.custom_minimum_size.y = 150
	var keys_hint := ("[A] say it      [B] close" if _quick_replies else "[Enter] send      [Esc] close")
	if Settings.voice_chat:
		keys_hint += "      (voice chat needs Chrome or Edge, so type here instead)"
	content.add_child(Style.label(keys_hint, 9, Style.MUTED))
	if mission.crew.has(id):
		mission.crew[id].bubble_left = 0.0  # hide any bubble; the box shows the conversation
	modal.show()
	_place_modal()
	if _quick_replies:
		_focus_first_button.call_deferred()
	else:
		chat_input.grab_focus()

## Voice version of the chat box: same look, no text field. Your words show
## live as you speak; when you stop, it sends; the reply appears and is spoken;
## then it listens again. Space = talk again, Esc = close.
func _open_voice_chat(id: String) -> void:
	close()
	mode = "chat"
	voice_mode = true
	chat_id = id
	content_width = 470.0
	modal.size = Vector2(500, 124)
	modal.custom_minimum_size = Vector2(500, 124)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	modal.add_child(content)
	content.add_child(Style.label(mission.crew[id].display_name.to_upper(), 12, Style.CYAN))
	chat_status = _text("", 10, Style.MUTED)  # "YOU: ..." live transcript
	var history: Array = radio.histories[id]
	chat_reply = _text(str(history[-1].text) if not history.is_empty() else _greeting(id), 12)
	chat_reply.custom_minimum_size.y = 30
	voice_status = _text("", 10, Style.CYAN_BRIGHT)
	content.add_child(Style.label("[%s] talk      [%s] close" % [Settings.button_label("talk"), Settings.button_label("back")], 9, Style.MUTED))
	modal.show()
	_place_modal()
	radio.listen()

func _voice_open() -> bool:
	return mode == "chat" and voice_mode and is_instance_valid(voice_status)

func _on_listening_changed(on: bool) -> void:
	if not _voice_open(): return
	if on:
		voice_status.text = "● LISTENING... speak now"
	elif not radio.busy and voice_status.text.begins_with("●"):
		voice_status.text = "Press %s to talk" % Settings.button_label("talk")

func _on_speech_partial(text: String) -> void:
	if _voice_open():
		chat_status.text = "YOU: " + text + " ..."

func _on_speech_final(text: String) -> void:
	if not _voice_open(): return
	voice_status.text = "Thinking..."
	_send(text)

func _on_radio_status(text: String) -> void:
	# Only mic problems are worth showing; progress text stays hidden.
	if _voice_open() and (text.begins_with("Microphone") or text.begins_with("Didn't") or text.begins_with("Speech")):
		voice_status.text = text

## The crew finished speaking: listen for your next line.
func _on_voice_finished() -> void:
	if _voice_open() and not radio.busy and not radio.listening:
		voice_status.text = ""
		radio.listen()

## Ready-made lines for the chat (for controller players): the task this crewmate
## can do right now first, then the everyday ones.
func _suggestions(id: String) -> Array[String]:
	var acts: Dictionary = mission.available_actions(id)
	var out: Array[String] = []
	if acts.has("help_locker"): out.append("Hold the locker while I push?")
	if acts.has("load_battery"): out.append("Help me lift the battery.")
	if acts.has("fetch_case"): out.append("Fetch the sample case?")
	if acts.has("light_up"): out.append("Point your light ahead.")
	out.append("Follow me." if acts.has("follow") else "What now?")
	out.append("What should we do?")
	return out.slice(0, 3)

func _greeting(id: String) -> String:
	if not mission.state.has_flag("locker_clear"):
		return "I can hold that locker while you push. We need both of us." if id == "mara" else "I'm checking the forward section. Can you and Aaron clear that locker?"
	if mission.state.has_flag("clamps"): return "We're boarding. All three of us are going home."
	return ("I'm with you. " if id == "mara" else "Shuttle's intact. We just need the clamps released. ") + mission.state.objective()

func _send(message: String) -> void:
	if mode != "chat" or radio.busy or message.strip_edges() == "": return
	chat_status.text = "YOU: " + message.strip_edges()
	chat_reply.text = "..."
	if is_instance_valid(chat_input): chat_input.text = ""
	radio.ask(chat_id, message)

func _answer(data: Dictionary) -> void:
	if mode != "chat" or data.npc_id != chat_id: return
	chat_reply.text = data.line  # the reply lives in the chat box only (no speech bubble)
	if voice_mode and is_instance_valid(voice_status):
		if str(data.get("audio_url", "")).begins_with("/npc/audio/"):
			voice_status.text = "Speaking..."
			# If the voice never arrives, don't leave the player waiting.
			var asked_at := chat_id
			get_tree().create_timer(8.0).timeout.connect(func():
				if _voice_open() and chat_id == asked_at and not radio.voice.playing and not radio.listening and not radio.busy:
					radio.listen())
		elif not data.get("started", false):
			voice_status.text = ""
			get_tree().create_timer(1.2).timeout.connect(func():
				if _voice_open() and not radio.listening and not radio.busy: radio.listen())
	if data.get("started", false):
		# They're on their way: close the chat shortly so you can see them move.
		show_caption("AARON" if chat_id == "mara" else "DHAN", data.line)
		var asked := chat_id
		get_tree().create_timer(1.5).timeout.connect(func():
			if mode == "chat" and chat_id == asked: close(false))  # let them finish speaking

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
	_text("You can ask Dhan about an insulated case before disconnecting the freezer.", 10, Style.MUTED)
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
	_text("White: you    Amber: Aaron    Purple: Dhan    Engineering north / Lab south / Shuttle east", 9, Style.MUTED)
	_button("Close [Tab / Esc]", close)
	modal.position.y = 15

func show_pause() -> void:
	mission.save_progress()
	_panel("MISSION PAUSED", "pause")
	pause_was_active = mission.active
	mission.active = false
	var b := Settings.button_label
	_text("%s move · %s interact · %s / %s crew radio · %s flashlight · %s deck plan. No countdown; take time to discuss your plan." % [
		b.call("move"), b.call("interact"), b.call("radio_1"), b.call("radio_2"), b.call("flashlight"), b.call("deck_map")])
	var history: Array[String] = mission.state.journal
	_text("RECENT EVENTS\n" + "\n".join(history.slice(maxi(0, history.size() - 3))), 10, Style.MUTED)
	_button("Resume", close)
	_text(SaveGame.status, 9, Style.MUTED)
	_button("Restart game", _confirm_restart)
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
	var detail := "The lab remains powered aboard Wayfarer, ready for a recovery mission. All three crew made it home." if mission.state.route == "engineering" else "The priority samples survived in the insulated case. All three crew made it home." if mission.state.has_flag("samples_saved") else "The research was lost. Johnny, Aaron and Dhan all made it home."
	_text(detail)
	_text('AARON: "Next expedition, we pack a bigger case."' if mission.state.has_flag("samples_saved") else 'DHAN: "Three seats occupied. That was the important part."', 10, Style.MUTED)
	var row := HBoxContainer.new()
	content.add_child(row)
	_button("Try another route", mission.restart_run, row)
	_button("Main menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"), row)

func _input(event: InputEvent) -> void:
	if not modal.visible: return
	if not event.is_pressed() or event.is_echo(): return
	# Keyboard and controller share actions (scripts/core/input_setup.gd).
	if event.is_action_pressed("talk") and _voice_open():
		if not radio.listening and not radio.busy: radio.listen()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("back") or (event.is_action_pressed("pause") and not event is InputEventKey) \
			or (event.is_action_pressed("deck_map") and mode == "map"):
		if mode != "ending": close()
		get_viewport().set_input_as_handled()


func _confirm_restart() -> void:
	_panel("START OVER?", "pause")
	pause_was_active = mission.active
	mission.active = false
	_text("Your current saved progress will be replaced with a new game.")
	_button("Cancel", show_pause)
	_button("Start new game", mission.restart_run)
