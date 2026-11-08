extends Control
## The close-up of one machine (design doc section 3½): a drawn face with a few
## parts you click (mouse) or select with WASD/arrows and press with E/Enter.
## Parts with "hold" > 0 must be held down that many seconds (mouse or E).
## The mission rebuilds the parts after every press, so the picture always shows
## the true state. Nothing here changes game rules; it only reports presses.

const Style = preload("res://scripts/ui/ui_style.gd")
const FACE := Color("1a2236")
const FACE_EDGE := Color("46557a")
const SCREW := Color("6b7899")
const SCREEN := Color("06120c")
const SCREEN_TEXT := Color("6dff9e")
const LIVE := Color("ff5a4f")

## Each part: {id, rect (Rect2 in this control), kind, label, text, on, color, hold, enabled}
## kind: display | button | slot | cover | toggle | box | knob | rack | led
var parts: Array = []
var on_press: Callable          # func(id: String)
var selected := -1
var sparks := false             # live-circuit sparks drawn across the face
var prefer := ""                # select this part on the next rebuild (a guard just opened)
var _hold_id := ""
var _hold_t := 0.0
var _hold_by_mouse := false
var _t := 0.0

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(470, 190)

func set_parts(new_parts: Array) -> void:
	var keep := str(parts[selected].id) if selected >= 0 and selected < parts.size() else ""
	if prefer != "":
		keep = prefer
		prefer = ""
	parts = new_parts
	selected = -1
	for i in parts.size():
		if str(parts[i].id) == keep and _pressable(parts[i]): selected = i
	if selected < 0: _select_first()
	queue_redraw()

func _select_first() -> void:
	for i in parts.size():
		if _pressable(parts[i]):
			selected = i
			return

func _pressable(p: Dictionary) -> bool:
	return p.get("kind", "") != "display" and p.get("kind", "") != "led" and p.get("enabled", true)

## 0..1 while a part is being held, for the drawn progress bar.
func hold_progress() -> float:
	if _hold_id == "": return 0.0
	var total := _hold_total(_hold_id)
	return clampf(_hold_t / total, 0.0, 1.0) if total > 0.0 else 0.0

func _hold_total(id: String) -> float:
	for p in parts:
		if str(p.id) == id: return float(p.get("hold", 0.0))
	return 0.0

func _process(delta: float) -> void:
	_t += delta
	if _hold_id != "":
		var still := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) if _hold_by_mouse else (Input.is_action_pressed("interact") or Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER) or Input.is_key_pressed(KEY_SPACE))
		if not still:
			_hold_id = ""
		else:
			_hold_t += delta
			if _hold_t >= _hold_total(_hold_id):
				var id := _hold_id
				_hold_id = ""
				_fire(id)
	if sparks or _hold_id != "": queue_redraw()

func _start(index: int, by_mouse: bool) -> void:
	if index < 0 or index >= parts.size() or not _pressable(parts[index]): return
	selected = index
	var p: Dictionary = parts[index]
	if float(p.get("hold", 0.0)) > 0.0:
		_hold_id = str(p.id)
		_hold_t = 0.0
		_hold_by_mouse = by_mouse
	else:
		_fire(str(p.id))
	queue_redraw()

func _fire(id: String) -> void:
	if on_press.is_valid(): on_press.call(id)

## Keyboard / controller: move the selection and press (called by escape_ui.gd).
func handle_key(event: InputEvent) -> bool:
	if event.is_action_pressed("interact") or (event is InputEventKey and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and event.pressed):
		if selected >= 0: _start(selected, false)
		return true
	var dir := Vector2.ZERO
	if event.is_action_pressed("move_left"): dir = Vector2.LEFT
	elif event.is_action_pressed("move_right"): dir = Vector2.RIGHT
	elif event.is_action_pressed("move_up"): dir = Vector2.UP
	elif event.is_action_pressed("move_down"): dir = Vector2.DOWN
	if dir == Vector2.ZERO: return false
	_move(dir)
	return true

func _move(dir: Vector2) -> void:
	if selected < 0:
		_select_first()
		queue_redraw()
		return
	var from: Vector2 = parts[selected].rect.get_center()
	var best := -1
	var best_score := INF
	for i in parts.size():
		if i == selected or not _pressable(parts[i]): continue
		var d: Vector2 = parts[i].rect.get_center() - from
		var along := d.dot(dir)
		if along <= 4.0: continue
		var score := along + absf(d.dot(Vector2(dir.y, -dir.x))) * 2.0
		if score < best_score:
			best_score = score
			best = i
	if best >= 0: selected = best
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	# Later parts draw on top (a closed guard over its switches), so test them first.
	# Screens, lights and switches you can't use yet never block the click on a part under them.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for i in range(parts.size() - 1, -1, -1):
			if parts[i].rect.grow(2.0).has_point(event.position) and _pressable(parts[i]):
				_start(i, true)
				accept_event()
				return
		accept_event()
	elif event is InputEventMouseMotion:
		for i in range(parts.size() - 1, -1, -1):
			if parts[i].rect.has_point(event.position) and _pressable(parts[i]):
				if selected != i:
					selected = i
					queue_redraw()
				return

# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, FACE)
	draw_rect(r, FACE_EDGE, false, 2.0)
	for c in [Vector2(8, 8), Vector2(size.x - 8, 8), Vector2(8, size.y - 8), Vector2(size.x - 8, size.y - 8)]:
		draw_circle(c, 3, SCREW)
		draw_line(c - Vector2(2, 0), c + Vector2(2, 0), FACE, 1.0)
	var font := Style.font()
	for i in parts.size():
		_draw_part(parts[i], i == selected, font)
	if sparks:
		for k in 5:
			var a := Vector2(fmod(_t * 173.0 + k * 97.0, size.x), fmod(_t * 61.0 + k * 53.0, size.y))
			if int(_t * 12.0 + k) % 3 == 0:
				draw_line(a, a + Vector2(6, -4), Color("fff3a0"), 2.0)
				draw_line(a + Vector2(6, -4), a + Vector2(3, 3), Color("ffd84d"), 1.0)

func _draw_part(p: Dictionary, sel: bool, font: Font) -> void:
	var rect: Rect2 = p.rect
	var kind: String = p.get("kind", "button")
	var on: bool = p.get("on", false)
	var col: Color = p.get("color", Style.CYAN)
	var enabled: bool = p.get("enabled", true)
	match kind:
		"display":
			draw_rect(rect, SCREEN)
			draw_rect(rect, Color("21402c"), false, 2.0)
			var lines: PackedStringArray = str(p.get("text", "")).split("\n")
			for li in lines.size():
				var tc: Color = LIVE if lines[li].begins_with("!") else SCREEN_TEXT
				var t := lines[li].trim_prefix("!")
				if lines[li].begins_with("!") and int(_t * 3.0) % 2 == 0: tc = tc.darkened(0.5)
				draw_string(font, rect.position + Vector2(8, 16 + li * 14), t, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 11, tc)
		"led":
			draw_circle(rect.get_center(), rect.size.x / 2.0, col if on else col.darkened(0.75))
		"cover":
			# A hinged guard: closed = striped plate over what's below; open = folded up.
			if on:
				draw_rect(Rect2(rect.position, Vector2(rect.size.x, 6)), Color("c9a227"))
			else:
				draw_rect(rect, Color("c9a227"))
				var x := rect.position.x
				while x < rect.end.x:
					draw_line(Vector2(x, rect.end.y), Vector2(minf(x + rect.size.y, rect.end.x), rect.position.y), Color("201a08"), 3.0)
					x += 10
		"toggle":
			draw_rect(rect, Color("0c1120"))
			var lever := Rect2(rect.position.x + rect.size.x / 2.0 - 4, rect.position.y + (4 if on else rect.size.y / 2.0), 8, rect.size.y / 2.0 - 4)
			draw_rect(lever, Color("d8dde8") if enabled else Color("5d6478"))
		"knob":
			var c := rect.get_center()
			var rad := minf(rect.size.x, rect.size.y) / 2.0 - 4
			draw_circle(c, rad, Color("2c344d"))
			draw_arc(c, rad, 0, TAU, 24, Color("9aa6c8"), 2.0)
			var ang := -PI / 2.0 + (int(p.get("value", 0)) - 1) * 0.9
			draw_line(c, c + Vector2.from_angle(ang) * (rad - 2), Color("ffd84d"), 3.0)
			for k in 3:
				var a := -PI / 2.0 + (k - 1) * 0.9
				draw_circle(c + Vector2.from_angle(a) * (rad + 5), 1.5, SCREW)
		"slot":
			draw_rect(rect, Color("05070d"))
			if on: draw_rect(rect.grow(-4), col)
			draw_rect(rect, Color("8892ad"), false, 1.0)
		"box", "rack":
			draw_rect(rect, col.darkened(0.55) if enabled else Color("262b3a"))
			draw_rect(rect, col if enabled else Color("444b60"), false, 2.0)
			if kind == "rack":
				for k in 6:
					var tube := Rect2(rect.position.x + 8 + k * ((rect.size.x - 16) / 6.0), rect.position.y + 18, 6, rect.size.y - 30)
					draw_rect(tube, Color("9fe8ff") if enabled else Color("39404f"))
		_:  # button
			var face := col if enabled else Color("39404f")
			draw_rect(rect, face.darkened(0.35))
			draw_rect(Rect2(rect.position, rect.size - Vector2(0, 4)), face if not on else face.darkened(0.2))
	var label := str(p.get("label", ""))
	if label != "" and kind != "display":
		var below := kind in ["toggle", "knob", "slot", "led", "cover"]
		var width := maxf(rect.size.x, 110.0) if below else rect.size.x
		var at := Vector2(rect.get_center().x - width / 2.0, rect.end.y + 13) if below else Vector2(rect.position.x, rect.get_center().y + 4)
		var lc: Color = Style.TEXT if enabled else Style.MUTED
		if kind in ["button", "box", "rack"]: lc = Color("0b1233") if kind == "button" and enabled else lc
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, width, 10, lc)
	if sel:
		draw_rect(rect.grow(3), Style.CYAN_BRIGHT, false, 2.0)
		if _hold_id == str(p.id):
			var bar := Rect2(rect.position.x, rect.position.y - 8, rect.size.x * hold_progress(), 4)
			draw_rect(bar, Style.CYAN_BRIGHT)
