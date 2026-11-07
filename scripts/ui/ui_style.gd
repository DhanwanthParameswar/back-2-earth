extends RefCounted
## Shared look for menu panels and buttons: navy boxes with a cyan pixel border,
## matching the buttons painted in the menu video. Owner: D.

const NAVY := Color("0b1233")
const NAVY_DEEP := Color("080d26")
const CYAN := Color("29adff")
const CYAN_BRIGHT := Color("3df0ff")
const TEXT := Color("fff1e8")
const MUTED := Color("9aa0c0")
const AMBER := Color("ffa300")


static func box(bg: Color, border: Color, border_width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(0)  # square corners read as pixel art
	sb.set_content_margin_all(6)
	return sb


static func panel() -> StyleBoxFlat:
	var sb := box(Color(NAVY, 0.97), CYAN, 2)
	sb.set_content_margin_all(14)
	return sb


## Navy button with a cyan border; fills cyan (dark text) on hover/focus.
static func style_button(b: Button, font_size := 14) -> void:
	b.add_theme_stylebox_override("normal", box(NAVY, Color(CYAN, 0.55)))
	b.add_theme_stylebox_override("hover", box(CYAN, CYAN_BRIGHT))
	b.add_theme_stylebox_override("pressed", box(CYAN_BRIGHT, TEXT))
	b.add_theme_stylebox_override("focus", box(CYAN, CYAN_BRIGHT))
	b.add_theme_stylebox_override("disabled", box(NAVY_DEEP, Color(MUTED, 0.4)))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", NAVY)
	b.add_theme_color_override("font_focus_color", NAVY)
	b.add_theme_color_override("font_pressed_color", NAVY)
	b.add_theme_color_override("font_hover_pressed_color", NAVY)
	b.add_theme_font_size_override("font_size", font_size)


static func label(text: String, font_size: int, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
