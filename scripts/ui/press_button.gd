extends Button
## A menu-panel button that looks pushed in while held: navy face, cyan edge,
## violet 3D strip underneath. Pressing drops the face onto the strip.
## No hover or focus highlight, on purpose. Owner: D.
## Use set_label() instead of `text` (the label moves with the face).

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const DEPTH := 4.0
const SHADOW := Color("5b3fa8")
const FONT_SIZE := 12

var label_text := ""
## Highlighted by controller / arrow-key navigation (main_menu.gd).
var selected := false


func set_selected(on: bool) -> void:
	selected = on
	queue_redraw()


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if custom_minimum_size.y < 26.0:
		custom_minimum_size.y = 26.0


func set_label(value: String) -> void:
	label_text = value
	queue_redraw()


func is_held() -> bool:
	var mode := get_draw_mode()
	return mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED


func _draw() -> void:
	var held := is_held()
	var face := Rect2(Vector2.ZERO, Vector2(size.x, size.y - DEPTH))
	if held:
		face.position.y = DEPTH
	else:
		draw_rect(Rect2(0, size.y - DEPTH - 2.0, size.x, DEPTH + 2.0), SHADOW)
	draw_rect(face, UiStyle.NAVY.darkened(0.15) if held else UiStyle.NAVY)
	draw_rect(face.grow(-1.0), Color(UiStyle.CYAN, 0.8 if held else 1.0), false, 2.0)
	if selected:  # controller cursor: a bright frame and a marker
		draw_rect(face.grow(1.0), UiStyle.TEXT, false, 2.0)
		var mid := face.position.y + face.size.y / 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(6, mid - 4), Vector2(11, mid), Vector2(6, mid + 4)]), UiStyle.CYAN_BRIGHT)

	var font := get_theme_default_font()
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var baseline := face.position.y + (face.size.y + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0
	var pos := Vector2((size.x - text_size.x) / 2.0, baseline)
	draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		UiStyle.TEXT.darkened(0.15) if held else UiStyle.TEXT)
