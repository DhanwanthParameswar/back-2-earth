extends CanvasLayer
## HUD, crew chat (typed or spoken), M.A.R.V.I.S. queries, machine close-ups,
## fail cards, the deck map with what you've learned, pause and endings.

const Style = preload("res://scripts/ui/ui_style.gd")
const Radio = preload("res://scripts/prototype/escape_radio.gd")
const Map = preload("res://scripts/prototype/escape_map.gd")
const Closeup = preload("res://scripts/prototype/escape_closeup.gd")
const Rules = preload("res://scripts/prototype/escape_state.gd")
const MARVIS_GREEN := Color("6dff9e")

const ENDINGS := {
	"everyone_home": ["EVERYONE HOME", "Johnny, Aaron and Dhan land together. Aaron loaded every rack into the shuttle's cold store: all of Kien's work came home too.",
		["AARON: \"Kien's work made it.\"", "DHAN: \"So did we. Mostly in one piece.\""]],
	"what_he_left": ["WHAT HE LEFT US", "All three of you are home. The priority rack made it in the insulated case.",
		["AARON: \"Just the priority rack. It's the part he cared about most.\""]],
	"kept_each_other": ["WE KEPT EACH OTHER", "All three of you are home. The samples didn't make it.",
		["AARON (quietly): \"He'd have understood.\""]],
	"barely": ["BARELY", "Dhan goes straight into surgery. He'll keep the leg, but it was closer than anyone says out loud.",
		["DHAN (weak): \"Worth it?\"", "AARON: \"Ask me when you can walk.\""]],
	"two_came_home": ["TWO CAME HOME", "Aaron sits beside the empty seat the whole way down.",
		["AARON: \"...\""]],
}
const CLOSEUP_TITLES := {"cabinet": "DISTRIBUTION CABINET", "fuse": "STORAGE · SPARE FUSES", "aux": "AUX SWITCHES",
	"freezer": "LAB · SAMPLE FREEZER", "socket": "SHUTTLE BAY · EMERGENCY SOCKET", "medkit": "MEDBAY · MEDICAL CABINET", "pilot": "SHUTTLE · PILOT SEAT"}

var mission
var root: Control
var bar: Panel
var objective: Label
var keys: Label
var toast: Label
var hint: Label
var float_prompt: Label
var hold_bar: ColorRect
var modal: PanelContainer
var content: VBoxContainer
var radio
var chat_id := ""
var chat_input: LineEdit
var chat_reply: Label
var chat_status: Label
var chat_aside: Label
var voice_mode := false
var voice_status: Label
var mode := ""
var toast_time := 0.0
var hint_time := 0.0
var _hint_queue: Array = []      # [text, seconds] waiting for the current hint to finish
var pause_was_active := false
var content_width := 490.0
var _quick_replies := false
var closeup
var closeup_panel := ""
var _return_panel := ""          # the close-up a chat was opened from: back to it when the chat closes
var aux_cover_open := false
var freezer_cover_open := false
var _fail_layer: Control
var _fail_time := 0.0
var _fail_done: Callable
var _shake := 0.0
var _alarm: ColorRect           # red siren wash during the launch
var _alarm_t := -1.0
var _black: ColorRect           # fade to black before the ending film; backdrop of the stats card
var _banner: Panel              # timed moments: what to press now, with a time bar
var _banner_text: Label
var _banner_bar: ColorRect

## The HUD is one small tag in the corner (TAB: tablet, what you carry, pilot controls);
## everything else (task, crew, ship, notes, map) is on the crew tablet (show_map).
const BAR_HEIGHT := 18.0

func _ready() -> void:
	layer = 10
	add_to_group("blocks_player_input")
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	bar = Panel.new()
	bar.size = Vector2(624, BAR_HEIGHT)
	bar.add_theme_stylebox_override("panel", Style.box(Color("0b1526", 0.55), Color("34506a", 0.6), 1))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	objective = _label(bar, "", Vector2(7, 2), 9, Style.TEXT)
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys = _label(bar, "", Vector2(7, 2), 9, Style.MUTED)
	keys.visible = false
	toast = _outlined(root, 10, Style.TEXT)
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint = _outlined(root, 9, Style.CYAN_BRIGHT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.visible = false
	_refresh_hints()
	Settings.input_device_changed.connect(_on_device_changed)
	float_prompt = _outlined(root, 10, Style.CYAN_BRIGHT)
	float_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	float_prompt.size = Vector2(200, 14)
	float_prompt.visible = false
	hold_bar = ColorRect.new()
	hold_bar.color = Style.CYAN_BRIGHT
	hold_bar.size = Vector2(0, 3)
	hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hold_bar)
	_alarm = ColorRect.new()
	_alarm.color = Color(1.0, 0.05, 0.12, 0.0)
	_alarm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_alarm)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_black)
	modal = PanelContainer.new()
	modal.position = Vector2(55, 67)
	modal.size = Vector2(530, 270)
	modal.custom_minimum_size = Vector2(530, 0)
	modal.add_theme_stylebox_override("panel", Style.panel())
	root.add_child(modal)
	modal.hide()
	_banner = Panel.new()
	_banner.add_theme_stylebox_override("panel", Style.box(Color("0b1526", 0.88), Style.AMBER, 2))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	root.add_child(_banner)
	_banner_text = _label(_banner, "", Vector2(8, 5), 10, Style.AMBER)
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_bar = ColorRect.new()
	_banner_bar.color = Style.AMBER
	_banner_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_bar)
	_build_fail_layer()
	radio = Radio.new()
	radio.mission = mission
	add_child(radio)
	radio.answered.connect(_answer)
	get_viewport().size_changed.connect(_layout)
	_layout()
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

func _outlined(parent: Node, font_size: int, color: Color) -> Label:
	var label := Style.label("", font_size, color)
	label.add_theme_color_override("font_outline_color", Color("050a19"))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func is_open() -> bool:
	return modal.visible or fail_open()

func fail_open() -> bool:
	return _fail_layer != null and _fail_layer.visible

func _layout() -> void:
	if not is_inside_tree(): return
	var s := get_viewport().get_visible_rect().size
	_fit_tag()
	toast.position = Vector2(14, bar.position.y - 34)
	toast.size = Vector2(s.x - 28, 30)
	toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hint.position = Vector2(14, bar.position.y - 64)
	hint.size = Vector2(s.x - 28, 28)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if _fail_layer != null: _fail_layer.size = s
	_alarm.size = s
	_black.size = s
	_place_modal()

func _place_modal() -> void:
	if not is_inside_tree(): return
	var s := get_viewport().get_visible_rect().size
	if mode == "chat":
		modal.position = Vector2(round((s.x - 500.0) / 2.0), s.y - (206.0 if _quick_replies else 196.0))
	elif mode != "":
		modal.position.x = round((s.x - modal.custom_minimum_size.x) / 2.0)

## A timed moment's instruction at the top of the screen (above any close-up), with a bar
## for the time left (left < 0: no bar). "" hides it.
func set_banner(text: String, left: float) -> void:
	if _banner == null: return
	_banner.visible = text != "" and not fail_open()
	if not _banner.visible: return
	if _banner_text.text != text:
		_banner_text.text = text
	var s := get_viewport().get_visible_rect().size
	var w := minf(s.x - 16, _banner_text.get_minimum_size().x + 24)
	_banner.size = Vector2(w, 26 if left >= 0.0 else 20)
	_banner.position = Vector2(round((s.x - w) / 2.0), 6)
	_banner_text.size = Vector2(w - 16, 14)
	_banner_bar.visible = left >= 0.0
	_banner_bar.position = Vector2(6, 19)
	_banner_bar.size = Vector2((w - 12) * clampf(left, 0.0, 1.0), 3)

func update_hud() -> void:
	if objective == null or mission == null: return
	var parts: Array[String] = []
	var c: String = mission.state.carrying
	if c != "": parts.append("CARRYING " + _carrying(c))
	if mission.seated and not is_open() and not mission.ending: parts.append("%s pilot controls" % Settings.button_label("interact"))
	parts.append("%s tablet" % Settings.button_label("deck_map"))
	var text := "   ·   ".join(parts)
	if objective.text != text:
		objective.text = text
		_fit_tag()

func _carrying(c: String) -> String:
	if c.begins_with("fuse_"): return "FUSE · BOX " + c.substr(5)
	if c.contains("vial_"):
		var names: Array = mission.state.vial_names()
		var i := int(c.right(1))
		var vial: String = str(names[i]) if i < names.size() else "VIAL"
		return ("SPLINT + " if c.begins_with("splint") else "") + vial
	return c.to_upper()

## The corner tag sizes itself to its text, bottom right.
func _fit_tag() -> void:
	if not is_inside_tree() or objective == null: return
	var s := get_viewport().get_visible_rect().size
	var w := objective.get_minimum_size().x + 14
	bar.size = Vector2(w, BAR_HEIGHT)
	bar.position = Vector2(s.x - w - 8, s.y - BAR_HEIGHT - 6)
	objective.size = Vector2(w - 14, 14)

func _refresh_hints() -> void:
	var b := Settings.button_label
	keys.text = "%s move   %s use / talk   %s Aaron   %s Dhan   %s M.A.R.V.I.S.   %s light   %s map   %s pause" % [
		b.call("move"), b.call("interact"), b.call("radio_1"), b.call("radio_2"), b.call("radio_3"), b.call("flashlight"),
		b.call("deck_map"), b.call("pause")]

## First seconds of play: teach the controls, not the solution.
func show_talk_hint() -> void:
	var b := Settings.button_label
	var how := "speak (press %s) or type" % b.call("talk") if Settings.voice_chat and radio.speech_supported() else "type what you want to say"
	show_hint("Talk to the crew in your own words: press %s next to them, or radio Aaron %s · Dhan %s · M.A.R.V.I.S. %s, then %s." % [
		b.call("interact"), b.call("radio_1"), b.call("radio_2"), b.call("radio_3"), how], 14.0)

## Right after the intro: the ship is dark.
func show_light_hint() -> void:
	show_hint("It's dark. Press %s for your flashlight." % Settings.button_label("flashlight"), 5.0)

## Show a hint above the HUD; if one is showing, this one waits its turn.
func show_hint(text: String, seconds: float) -> void:
	if hint_time > 0.5:
		_hint_queue.append([text, seconds])
		return
	hint.text = text
	hint_time = seconds

func _on_device_changed() -> void:
	_refresh_hints()
	if Settings.using_controller and is_open(): _focus_first_button()

func _focus_first_button() -> void:
	if content == null or not is_instance_valid(content): return
	for b in content.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			b.grab_focus()
			return

func _process(delta: float) -> void:
	toast_time -= delta
	toast.visible = toast_time > 0.0 and (not mission.ending or mission.launching) and mode != "chat" and _black.color.a < 0.5
	toast.modulate.a = clampf(toast_time / 0.5, 0.0, 1.0)
	if hint_time > 0.0:
		hint_time = maxf(0.0, hint_time - delta)
	elif not _hint_queue.is_empty():
		var next: Array = _hint_queue.pop_front()
		show_hint(str(next[0]), float(next[1]))
	hint.visible = hint_time > 0.0 and not is_open() and not mission.ending
	hint.modulate.a = clampf(hint_time / 1.0, 0.0, 1.0)
	_update_float_prompt()
	if _fail_layer.visible:
		_fail_time -= delta
		if _fail_time <= 0.0: _end_fail()
	if _alarm_t >= 0.0:
		var before := _alarm_t
		_alarm_t += delta
		_alarm.color.a = 0.08 + 0.2 * (0.5 + 0.5 * sin(_alarm_t * TAU * 1.4))
		if fmod(before, 0.9) > fmod(_alarm_t, 0.9): Sfx.play("warning", -8)
	if _shake > 0.0 and mission.player != null:
		_shake = maxf(0.0, _shake - delta)
		mission.player.camera.offset = Vector2(randf_range(-5, 5), randf_range(-4, 4)) * (_shake / 0.5) if _shake > 0.0 else Vector2.ZERO

## Launch sirens: a pulsing red wash and the warning tone.
func alarm(on: bool) -> void:
	_alarm_t = 0.0 if on else -1.0
	_alarm.color.a = 0.0
	if on: Sfx.play("warning", -8)

func fade_black(seconds: float, then: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 1.0, seconds)
	tw.tween_callback(then)

func shake(seconds: float) -> void:
	if not Settings.reduced_shake: _shake = seconds

func _update_float_prompt() -> void:
	var target = mission.player.current_target if mission != null and mission.player != null else null
	if target == null or not is_instance_valid(target) or not mission.active or mission.ending or is_open():
		float_prompt.visible = false
		hold_bar.visible = false
		return
	float_prompt.text = "[%s] %s" % [Settings.button_label("interact"), str(target.get_prompt())]
	var at: Vector2 = target.get_global_transform_with_canvas().origin
	float_prompt.position = Vector2(round(at.x - float_prompt.size.x / 2.0), round(at.y + 22.0))
	float_prompt.visible = true
	var p: float = mission.hold_progress() if mission.hold_target() == target else 0.0
	hold_bar.visible = p > 0.0
	hold_bar.position = float_prompt.position + Vector2(40, 16)
	hold_bar.size = Vector2(120.0 * p, 3)

## A line above the HUD. With a chat open, the person you're talking to answers in
## the box; anyone else shows on a small line under it.
func show_caption(speaker: String, line: String, who := "") -> void:
	if mode == "chat" and is_instance_valid(chat_reply):
		if who != "" and who == chat_id:
			chat_reply.text = line
		elif is_instance_valid(chat_aside):
			chat_aside.text = speaker + ": " + line
	toast.text = speaker + ": " + line
	toast_time = 4.0 + minf(line.length() * 0.05, 8.0)

func _panel(title: String, new_mode: String, width := 490.0) -> void:
	_close()
	mode = new_mode
	content_width = width
	modal.add_theme_stylebox_override("panel", Style.panel())
	modal.custom_minimum_size = Vector2(content_width + 28, 0)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	modal.add_child(content)
	var title_label := Style.label(title, 14, Style.CYAN_BRIGHT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = content_width
	content.add_child(title_label)
	modal.size = Vector2(content_width + 28, 0)
	modal.position = Vector2(55, 40)
	modal.show()
	_place_modal()
	if Settings.using_controller: _focus_first_button.call_deferred()

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
	var back_to := _return_panel if mode == "chat" else ""
	_return_panel = ""
	_close(stop_voice)
	if back_to != "" and mission != null and mission.active and not mission.ending and (back_to == "pilot") == mission.seated:
		show_closeup(back_to)

func _close(stop_voice := true) -> void:
	if radio != null: radio.cancel(stop_voice)
	voice_mode = false
	voice_status = null
	if mode == "pause": mission.active = pause_was_active
	chat_id = ""
	chat_input = null
	chat_reply = null
	chat_status = null
	chat_aside = null
	closeup = null
	closeup_panel = ""
	for child in modal.get_children():
		modal.remove_child(child)
		child.queue_free()
	modal.hide()
	mode = ""
	_quick_replies = false
	if mission != null and mission.player != null:
		mission.player.current_target = null
		mission.player.camera.offset = Vector2.ZERO

# --- Chat (crew and M.A.R.V.I.S.) ------------------------------------------------------

func _chat_title(id: String) -> String:
	return "M.A.R.V.I.S. · SHIP SYSTEM" if id == "marvis" else str(mission.crew[id].display_name)

func open_chat(id: String) -> void:
	if Settings.voice_chat and radio.speech_supported():
		_open_voice_chat(id)
		return
	_close()
	mode = "chat"
	chat_id = id
	_chat_frame(id)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Ask the ship: status, power, crew..." if id == "marvis" else "Say anything, in your own words"
	chat_input.max_length = 200
	chat_input.add_theme_font_size_override("font_size", 12)
	chat_input.add_theme_color_override("font_color", Style.TEXT)
	chat_input.add_theme_color_override("font_placeholder_color", Style.MUTED)
	chat_input.add_theme_stylebox_override("normal", Style.box(Style.NAVY_DEEP, Color(Style.CYAN, 0.5)))
	chat_input.add_theme_stylebox_override("focus", Style.box(Style.NAVY_DEEP, Style.CYAN))
	chat_input.text_submitted.connect(_send)
	content.add_child(chat_input)
	_quick_replies = Settings.using_controller
	if _quick_replies:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		content.add_child(row)
		for line in _suggestions(id):
			var b := _button(line, _send.bind(line), row)
			b.add_theme_font_size_override("font_size", 9)
		modal.custom_minimum_size.y = 160
	var keys_hint := ("[A] say it      [B] close" if _quick_replies else "[Enter] send      [Esc] close")
	if Settings.voice_chat: keys_hint += "      (voice needs Chrome or Edge; type here instead)"
	content.add_child(Style.label(keys_hint, 9, Style.MUTED))
	modal.show()
	_place_modal()
	if _quick_replies: _focus_first_button.call_deferred()
	else: chat_input.grab_focus()

func _chat_frame(id: String) -> void:
	content_width = 470.0
	modal.size = Vector2(500, 124)
	modal.custom_minimum_size = Vector2(500, 124)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	modal.add_child(content)
	content.add_child(Style.label(_chat_title(id), 12, MARVIS_GREEN if id == "marvis" else Style.CYAN))
	chat_status = _text("", 10, Style.MUTED)
	var history: Array = radio.histories.get(id, [])
	chat_reply = _text(str(history[-1].text) if not history.is_empty() else _greeting(id), 12, MARVIS_GREEN if id == "marvis" else Style.TEXT)
	chat_reply.custom_minimum_size.y = 30
	chat_aside = _text("", 9, Style.MUTED)

func _open_voice_chat(id: String) -> void:
	_close()
	mode = "chat"
	voice_mode = true
	chat_id = id
	_chat_frame(id)
	voice_status = _text("Press %s to talk" % Settings.button_label("talk"), 10, Style.CYAN_BRIGHT)
	var hint_text := "[%s] talk / send      [%s] close" % [Settings.button_label("talk"), Settings.button_label("back")]
	# Controller: the mic is the way to talk; a row of ready-made lines is there too (A).
	_quick_replies = Settings.using_controller
	if _quick_replies:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		content.add_child(row)
		for line in _suggestions(id):
			var b := _button(line, _send.bind(line), row)
			b.add_theme_font_size_override("font_size", 9)
		hint_text = "[%s] talk / send      [A] say a line      [%s] close" % [Settings.button_label("talk"), Settings.button_label("back")]
	content.add_child(Style.label(hint_text, 9, Style.MUTED))
	modal.show()
	_place_modal()
	if _quick_replies: _focus_first_button.call_deferred()
	# Tap to talk: the mic stays off until you press the talk button.

func _voice_open() -> bool:
	return mode == "chat" and voice_mode and is_instance_valid(voice_status)

func _on_listening_changed(on: bool) -> void:
	if not _voice_open(): return
	if on: voice_status.text = "● LISTENING... press %s to send" % Settings.button_label("talk")
	elif not radio.busy and voice_status.text.begins_with("●"):
		voice_status.text = "Press %s to talk" % Settings.button_label("talk")

func _on_speech_partial(text: String) -> void:
	if _voice_open(): chat_status.text = "YOU: " + text + " ..."

func _on_speech_final(text: String) -> void:
	if not _voice_open(): return
	voice_status.text = "..."
	_send(text)

func _on_radio_status(text: String) -> void:
	if _voice_open() and (text.begins_with("Microphone") or text.begins_with("Didn't") or text.begins_with("Speech") or text.begins_with("Mic off") or text.begins_with("That was")):
		voice_status.text = text

func _on_voice_finished() -> void:
	if _voice_open() and not radio.busy and not radio.listening:
		voice_status.text = "Press %s to talk" % Settings.button_label("talk")

## Ready-made lines for controller players: what fits right now, then everyday ones.
func _suggestions(id: String) -> Array[String]:
	var out: Array[String] = []
	if id == "marvis": return ["Status report.", "Power status.", "Crew medical."]
	var acts: Dictionary = mission.available_actions(id)
	if acts.has("breaker_now"): out.append("Now!")
	if acts.has("release_now"): out.append("Release!")
	if acts.has("hold_breaker"): out.append("Hold the bay breaker.")
	if acts.has("lift_locker"): out.append("Lift the locker off him!")
	if acts.has("lift_battery"): out.append("Help me lift the battery.")
	if acts.has("carry_dhan"): out.append("Help me carry Dhan.")
	if acts.has("release_clamps"): out.append("Release the clamps.")
	if acts.has("fetch_case"): out.append("Can we save the samples?")
	if id == "mara" and mission.room == "MEDBAY" and not mission.state.vial_names().is_empty():
		out.append("The vials say %s." % ", ".join(mission.state.vial_names()))
	if id == "ivo":
		out.append("The code says E-%d." % int(mission.state.puzzle.code) if mission.state.has_flag("code_read") else "What do I do?")
		out.append("How are you holding up?")
	out.append("Follow me." if acts.has("follow") else "What now?")
	out.append("What should we do?")
	return out.slice(0, 3)

func _greeting(id: String) -> String:
	if id == "marvis": return mission.marvis.text(["greeting"])
	if id == "ivo":
		if not mission.state.has_flag("dhan_free"): return "Little help here?"
		return "Still here. Talk to me."
	return "I'm here."

func _send(message: String) -> void:
	if mode != "chat" or radio.busy or message.strip_edges() == "": return
	chat_status.text = "YOU: " + message.strip_edges()
	if is_instance_valid(chat_input): chat_input.text = ""
	if chat_id == "marvis":
		mission.note_player_spoke()
		chat_reply.text = mission.ask_marvis(message.strip_edges().left(200))
		radio.note_spoken(chat_reply.text)
		if _voice_open(): voice_status.text = "Press %s to talk" % Settings.button_label("talk")
		return
	chat_reply.text = "..."
	radio.ask(chat_id, message)

func marvis_reply(text: String) -> void:
	if mode == "chat" and chat_id == "marvis" and is_instance_valid(chat_reply): chat_reply.text = text

func _answer(data: Dictionary) -> void:
	if mode != "chat" or data.npc_id != chat_id: return
	chat_reply.text = data.line
	if voice_mode and is_instance_valid(voice_status):
		# No auto-listen (it heard the crew through speakers and looped): you press talk.
		if str(data.get("audio_url", "")).begins_with("/npc/audio/"):
			voice_status.text = "Speaking...  (%s to interrupt)" % Settings.button_label("talk")
		else:
			voice_status.text = "Press %s to talk" % Settings.button_label("talk")
	if data.get("started", false):
		# They're on their way: close the chat so you can watch them do it.
		show_caption(mission.crew_name(chat_id), data.line)
		var asked := chat_id
		get_tree().create_timer(1.5).timeout.connect(func():
			if mode == "chat" and chat_id == asked: close(false))

# --- Machine close-ups (section 3½) -----------------------------------------------------

func show_closeup(panel: String) -> void:
	_panel(CLOSEUP_TITLES.get(panel, panel.to_upper()), "closeup")
	closeup_panel = panel
	aux_cover_open = false
	freezer_cover_open = false
	closeup = Closeup.new()
	closeup.on_press = func(part: String): mission.closeup_press(closeup_panel, part)
	content.add_child(closeup)
	var foot := "Click a part, or %s + %s.   %s to step back." % [Settings.button_label("move"), Settings.button_label("interact"), Settings.button_label("back")]
	if panel == "pilot": foot += "   Radio: %s Aaron · %s Dhan · %s M.A.R.V.I.S." % [Settings.button_label("radio_1"), Settings.button_label("radio_2"), Settings.button_label("radio_3")]
	_text(foot, 9, Style.MUTED)
	refresh_closeup()
	closeup.grab_focus.call_deferred()

func refresh_closeup() -> void:
	if closeup == null or not is_instance_valid(closeup): return
	var s = mission.state
	var parts: Array = []
	closeup.sparks = false
	match closeup_panel:
		"cabinet":
			var screen: PackedStringArray = []
			if not s.has_flag("isolated"): screen.append("!LIVE CIRCUIT - ISOLATE FIRST")
			if not s.has_flag("fuse_installed"): screen.append("FAULT " + s.fault_code() + "  FUSE BLOWN")
			elif not s.has_flag("fault_found"): screen.append("FUSE OK. RUN TEST.")
			elif not s.has_flag("aux_off"): screen.append("!SHORT: " + s.short_branch())
			elif not s.has_flag("engineering_power"): screen.append("BRANCH CUT. READY.")
			else: screen.append("OUTPUT: SHUTTLE BAY OK")
			if s.fuse_at_cabinet != "" and not s.has_flag("fuse_installed"): screen.append("SPARE BESIDE: BOX " + s.fuse_at_cabinet)
			parts.append({"id": "display", "kind": "display", "rect": Rect2(16, 16, 250, 76), "text": "\n".join(screen)})
			parts.append({"id": "slot", "kind": "slot", "rect": Rect2(290, 20, 56, 64), "label": "FUSE SLOT", "on": s.has_flag("fuse_installed"), "color": Color("e0ad65")})
			parts.append({"id": "test", "kind": "button", "rect": Rect2(366, 22, 88, 28), "label": "TEST", "color": Color("ffd84d")})
			parts.append({"id": "restart", "kind": "button", "rect": Rect2(366, 60, 88, 28), "label": "RESTART", "color": Color("87d5b3")})
			parts.append({"id": "led", "kind": "led", "rect": Rect2(30, 118, 14, 14), "on": s.has_flag("engineering_power"), "color": Color("6dff9e"), "label": "BAY OUTPUT"})
			closeup.sparks = not s.has_flag("isolated")
		"fuse":
			var held: String = s.carrying.substr(5) if s.carrying.begins_with("fuse_") else ""
			for i in 3:
				var box: String = Rules.BOXES[i]
				parts.append({"id": box, "kind": "box", "rect": Rect2(28 + i * 148, 34, 120, 110), "label": "BOX " + box + ("  (IN HAND)" if held == box else ""), "color": Color("e0ad65")})
		"aux":
			parts.append({"id": "title", "kind": "display", "rect": Rect2(60, 8, 350, 22), "text": "AUX BRANCH ISOLATION" if not s.has_flag("aux_off") else "BRANCH ISOLATED"})
			for i in 3:
				var cut: bool = s.has_flag("aux_off") and i == s.right_toggle()
				parts.append({"id": "t%d" % i, "kind": "toggle", "rect": Rect2(110 + i * 105, 50, 40, 74), "on": not cut, "enabled": aux_cover_open and not s.has_flag("aux_off")})
			parts.append({"id": "cover", "kind": "cover", "rect": Rect2(60, 36, 350, 10) if aux_cover_open else Rect2(60, 40, 350, 92), "on": aux_cover_open, "label": "" if aux_cover_open else "GUARD COVER"})
		"freezer":
			var screen := ["!COOLING: OFF" if s.has_flag("freezer_off") else "COOLING: ON   -80 C", "SUPPLY: LAB BATTERY"]
			if s.has_flag("samples_saved") or s.has_flag("samples_wrong"): screen.append("CASE: PACKED")
			parts.append({"id": "display", "kind": "display", "rect": Rect2(16, 16, 230, 62), "text": "\n".join(screen)})
			parts.append({"id": "switch", "kind": "toggle", "rect": Rect2(286, 30, 50, 56), "on": not s.has_flag("freezer_off"), "hold": 1.0, "enabled": freezer_cover_open and not s.has_flag("freezer_off"), "label": "POWER"})
			if not s.has_flag("freezer_off"):
				parts.append({"id": "cover", "kind": "cover", "rect": Rect2(270, 18, 82, 8) if freezer_cover_open else Rect2(270, 24, 82, 70), "on": freezer_cover_open, "label": ""})
			if s.has_flag("case_arrived") and not s.has_flag("freezer_off") and not (s.has_flag("samples_saved") or s.has_flag("samples_wrong")):
				var racks := [["rack_cal", "CALIBRATION"], ["rack_priority", "K + A  PRIORITY"], ["rack_dup", "DUPLICATES"]]
				for i in 3:
					parts.append({"id": racks[i][0], "kind": "rack", "rect": Rect2(16 + i * 150, 104, 138, 70), "label": racks[i][1], "color": Color("87d5b3")})
		"socket":
			var screen := ["EMERGENCY SOCKET", "INPUT: " + ("LAB BATTERY" if s.carrying == "battery cart" else ("CONNECTED" if s.has_flag("battery_connected") else "NONE")), "PROFILE: " + Rules.SELECTOR[s.selector]]
			parts.append({"id": "display", "kind": "display", "rect": Rect2(16, 16, 230, 62), "text": "\n".join(screen)})
			parts.append({"id": "knob", "kind": "knob", "rect": Rect2(270, 22, 80, 80), "value": s.selector, "label": "I    II    III", "enabled": not s.has_flag("battery_connected")})
			parts.append({"id": "connect", "kind": "button", "rect": Rect2(370, 46, 88, 30), "label": "CONNECT", "color": Color("9bace8"), "enabled": s.carrying == "battery cart"})
		"medkit":
			parts.append({"id": "splint", "kind": "box", "rect": Rect2(28, 34, 120, 110), "label": "SPLINT KIT" if not s.has_flag("splint_taken") else "(TAKEN)", "color": Color("ef8a81"), "enabled": not s.has_flag("splint_taken")})
			# Three vials, names only. Aaron knows which one is the painkiller (read him the labels).
			var names: Array = s.vial_names()
			var used: bool = s.has_flag("vial_given") or s.has_flag("vial_wrong") or s.carrying.contains("vial_")
			for i in names.size():
				parts.append({"id": "vial%d" % i, "kind": "box", "rect": Rect2(176 + i * 96, 50, 84, 78), "label": str(names[i]), "color": Color("c9a6ff"), "enabled": not used})
			if not names.is_empty():
				parts.append({"id": "vials_note", "kind": "display", "rect": Rect2(176, 8, 276, 34), "text": "PAIN RELIEF: ONE OF THREE.\nNO DOSAGE CARD." if not used else "VIAL TAKEN."})
				mission.state.learn("vials", "MEDBAY: Three vials: %s. Only one is a painkiller. Aaron knows medicine." % ", ".join(names))
		"pilot":
			var dhan := "NO VITAL SIGNS" if not s.dhan_alive() else ("ABOARD" if s.has_flag("dhan_aboard") else "NOT ABOARD")
			var screen := ["CLAMPS: " + ("RELEASED" if s.has_flag("clamps") else "!ENGAGED"), "DHAN: " + dhan, "AARON: " + ("ABOARD" if s.has_flag("aaron_aboard") else "OUTSIDE"), "COURSE: EARTH"]
			for i in screen.size():
				if screen[i].contains("!"): screen[i] = "!" + screen[i].replace("!", "")
			parts.append({"id": "display", "kind": "display", "rect": Rect2(16, 16, 300, 74), "text": "\n".join(screen)})
			if not s.has_flag("clamps"):
				parts.append({"id": "thrust", "kind": "button", "rect": Rect2(16, 112, 150, 30), "label": "HOLDING..." if mission.thrusting() else "HOLD THRUSTERS", "color": Color("ffd84d"), "enabled": not mission.thrusting()})
			parts.append({"id": "launch", "kind": "button", "rect": Rect2(340, 22, 112, 40), "label": "LAUNCH", "color": Color("ff8a5c")})
			parts.append({"id": "leave", "kind": "button", "rect": Rect2(340, 84, 112, 28), "label": "LEAVE SEAT", "color": Color("9aa0c0")})
	closeup.set_parts(parts)

# --- Quick failures (section 6) ------------------------------------------------------

func _build_fail_layer() -> void:
	_fail_layer = ColorRect.new()
	_fail_layer.color = Color(0.03, 0.0, 0.02, 0.9)
	_fail_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_fail_layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_fail_layer.add_child(box)
	var big := Style.label("FAIL", 40, Color("ff5a4f"))
	big.name = "Big"
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big)
	var card := Style.label("", 14, Style.TEXT)
	card.name = "Card"
	card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(card)
	var sub := Style.label("", 9, Style.MUTED)
	sub.name = "Sub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_fail_layer.hide()

func show_fail(id: String, text: String, done: Callable) -> void:
	var box: Control = _fail_layer.get_child(0)
	box.get_node("Card").text = "\"" + text + "\""
	var found: int = mission.discoveries().fails.size()
	box.get_node("Sub").text = "Fail %s  ·  fails found %d/%d  ·  rewinding..." % [id.substr(1), found, Rules.FAILS.size()]
	box.reset_size()
	box.position = (get_viewport().get_visible_rect().size - box.size) / 2.0
	_fail_layer.size = get_viewport().get_visible_rect().size
	_fail_time = 2.8
	_fail_done = done
	_fail_layer.show()

func _end_fail() -> void:
	_fail_layer.hide()
	if _fail_done.is_valid():
		var cb := _fail_done
		_fail_done = Callable()
		cb.call()

# --- Map, pause, ending --------------------------------------------------------------

func _facts(count: int) -> String:
	var j: Array = mission.state.journal
	if j.is_empty(): return "Nothing yet. Ask the crew, or the ship."
	return "\n".join(j.slice(maxi(0, j.size() - count)))

## The crew tablet (TAB): a see-through slate with the deck plan, your task, the crew,
## the ship's systems and your notes. The game keeps running behind it.
func show_map() -> void:
	var secs := int(mission.elapsed)
	_panel("CREW TABLET  ·  WAYFARER  ·  %d:%02d" % [secs / 60, secs % 60], "map", 588.0)
	var glass := Style.box(Color(Style.NAVY, 0.9), Color(Style.CYAN, 0.8), 2)
	glass.set_content_margin_all(10)
	modal.add_theme_stylebox_override("panel", glass)
	content.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)
	var map := Map.new()
	map.mission = mission
	map.custom_minimum_size = Vector2(300, 196)
	left.add_child(map)
	_slate(left, "White: you    Amber: Aaron    Purple: Dhan", 8, Style.MUTED, 300)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 3)
	row.add_child(side)
	var s = mission.state
	var w := 276.0
	_slate(side, "TASK", 9, Style.CYAN, w)
	_slate(side, s.objective(), 11, Style.TEXT, w)
	_slate(side, "You're in: " + mission.room.capitalize(), 9, Style.MUTED, w)
	if s.carrying != "": _slate(side, "Carrying: " + _carrying(s.carrying), 9, Style.MUTED, w)
	_slate(side, "CREW", 9, Style.CYAN, w)
	_slate(side, "Aaron: " + _aaron_status(), 9, Style.TEXT, w)
	_slate(side, "Dhan: " + _dhan_status(), 9, Style.TEXT if s.stage() < 3 else Style.AMBER, w)
	_slate(side, "SHIP", 9, Style.CYAN, w)
	for line in _ship_status(): _slate(side, line, 9, Style.TEXT, w)
	_text("NOTES", 9, Style.CYAN)
	_text(_facts(4), 9, Style.TEXT)
	var b := Settings.button_label
	_text("%s move   %s use / talk   %s Aaron   %s Dhan   %s M.A.R.V.I.S.   %s light   %s pause" % [
		b.call("move"), b.call("interact"), b.call("radio_1"), b.call("radio_2"), b.call("radio_3"), b.call("flashlight"), b.call("pause")], 8, Style.MUTED)
	_button("Close [%s / %s]" % [b.call("deck_map"), b.call("back")], close)
	modal.position.y = 6

func _slate(parent: Node, text: String, size: int, color: Color, width: float) -> Label:
	var label := Style.label(text, size, color)
	label.custom_minimum_size = Vector2(width, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _aaron_status() -> String:
	var aaron = mission.crew.mara
	if mission.state.has_flag("aaron_aboard"): return "on the shuttle"
	var task := str(mission._busy.get("mara", "")).trim_suffix("_walk")
	var doing: String = {"lift_locker": "at the locker", "lift_battery": "at the cart", "carry_dhan": "helping Dhan",
		"fetch_fuse": "fetching a fuse", "fetch_case": "fetching the sample case", "release_clamps": "releasing the clamps",
		"stay_with_dhan": "staying with Dhan"}.get(task, "")
	var where: String = "with you" if aaron.following else mission.room_at(aaron.position).capitalize()
	return where + (" · " + doing if doing != "" else "")

func _dhan_status() -> String:
	var s = mission.state
	if not s.dhan_alive(): return "no vital signs"
	var how: String = ["", "stable", "in pain, getting worse", "fading, needs help soon", "critical"][s.stage()]
	if not s.has_flag("dhan_free"): return "pinned under the locker"
	var where: String = "on the shuttle" if s.has_flag("dhan_aboard") else str(mission.room_at(mission.crew.ivo.position)).capitalize()
	return "%s · %s%s" % [where, how, " · leg splinted" if s.has_flag("dhan_treated") else ""]

func _ship_status() -> Array[String]:
	var s = mission.state
	var out: Array[String] = []
	var power := "offline"
	if s.has_flag("engineering_power"): power = "restored from engineering"
	elif s.has_flag("battery_connected"): power = "lab battery in the shuttle bay"
	out.append("Main power: " + power)
	out.append("Shuttle: intact")
	out.append("Docking clamps: " + ("released" if s.has_flag("clamps") else ("powered, ready to release" if s.powered() else "locked, no power")))
	out.append("Lab freezer: " + ("off" if s.has_flag("freezer_off") else "on, samples cold"))
	return out

func show_pause() -> void:
	mission.save_progress()
	_panel("PAUSED", "pause")
	pause_was_active = mission.active
	mission.active = false
	var b := Settings.button_label
	_text("%s move · %s use (hold for heavy things) · radio %s Aaron / %s Dhan / %s M.A.R.V.I.S. · %s flashlight · %s map" % [
		b.call("move"), b.call("interact"), b.call("radio_1"), b.call("radio_2"), b.call("radio_3"), b.call("flashlight"), b.call("deck_map")], 10)
	_text("WHAT YOU KNOW", 10, Style.CYAN)
	_text(_facts(5), 10, Style.MUTED)
	_button("Resume", close)
	_text(SaveGame.status, 9, Style.MUTED)
	_button("Restart game", _confirm_restart)
	_button("Main menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))

func show_ending(id: String) -> void:
	_black.color.a = 1.0
	_alarm_t = -1.0
	_alarm.color.a = 0.0
	_panel("BACK 2 EARTH", "ending")
	modal.position.y = 10
	var info: Array = ENDINGS.get(id, ENDINGS.kept_each_other)
	var earth := TextureRect.new()
	earth.texture = load("res://assets/backdrops/earth.png")
	earth.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	earth.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	earth.custom_minimum_size = Vector2(490, 80)
	content.add_child(earth)
	var s = mission.state
	_text(info[0], 16, Style.CYAN_BRIGHT)
	var detail: String = info[1]
	if id in ["barely", "two_came_home"]:
		detail += " " + {"all": "Every one of Kien's samples made it.", "priority": "The priority rack made it.", "none": "The samples were lost."}[s.samples()]
	_text(detail, 11)
	for line in info[2]: _text(line, 10, Style.TEXT)
	if s.promises.has("stage3_dhan_question"):
		_text("You told Dhan: \"%s\"" % s.promises.stage3_dhan_question, 9, Style.MUTED)
	if s.promises.has("freezer_question"):
		_text("You told Aaron: \"%s\"" % s.promises.freezer_question, 9, Style.MUTED)
	var found: Dictionary = mission.discoveries()
	var secs := int(mission.elapsed)
	_text("Endings found %d/%d   ·   Fails found %d/%d   ·   %d:%02d" % [found.endings.size(), ENDINGS.size(), found.fails.size(), Rules.FAILS.size(), secs / 60, secs % 60], 10, Style.AMBER)
	var other := "Some crews kept every sample and got Dhan home in one piece." if id != "everyone_home" else "Some crews never touched a fuse."
	_text(other, 9, Style.MUTED)
	var row := HBoxContainer.new()
	content.add_child(row)
	_button("Play again", mission.restart_run, row)
	_button("Main menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"), row)

func _input(event: InputEvent) -> void:
	if fail_open():
		if event.is_pressed() and not event.is_echo() and _fail_time < 2.0 and (event.is_action_pressed("interact") or event.is_action_pressed("back") or event is InputEventMouseButton):
			_end_fail()
		get_viewport().set_input_as_handled()
		return
	if not modal.visible: return
	if not event.is_pressed() or event.is_echo() or not Settings.fresh_press(event): return
	if event.is_action_pressed("talk") and _voice_open():
		if radio.listening: radio.finish_listening()   # tap again: send
		elif not radio.busy: radio.listen()
		get_viewport().set_input_as_handled()
		return
	if mode == "closeup":
		# Clicks go to the close-up's own parts (_gui_input runs after this): don't eat them here.
		if event is InputEventMouseButton or event is InputEventScreenTouch: return
		if event.is_action_pressed("back") or (event.is_action_pressed("pause") and not event is InputEventKey):
			close()
		elif event.is_action_pressed("radio_1") or event.is_action_pressed("radio_2") or event.is_action_pressed("radio_3"):
			# Radio from any panel ("now!" from the cabinet); the chat brings you back here.
			var id := "mara" if event.is_action_pressed("radio_1") else "ivo" if event.is_action_pressed("radio_2") else "marvis"
			var back_to := closeup_panel
			mission.open_chat(id)
			_return_panel = back_to
		elif closeup != null and is_instance_valid(closeup):
			closeup.handle_key(event)
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
	_text("Your saved progress and the crew's memories will be reset for a new game.")
	_button("Cancel", show_pause)
	_button("Start new game", mission.restart_run)
