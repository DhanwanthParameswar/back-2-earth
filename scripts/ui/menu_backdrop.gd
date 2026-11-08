extends Control
## Live title-screen art (replaces the old looping menu video). Owner: D.
##
## The space behind everything is drawn in code (menu_sky.gdshader: nebula +
## twinkling stars), so it fills any window shape. The logo is true pixel art
## (tools/make_logo.py): a spinning Earth (menu_earth.gdshader) behind the
## "Back2Earth" title. The buttons are pixel art too (tools/make_menu_art.py,
## drawn 3x). The astronaut, debris, ship and planets keep the original menu
## art's style, snapped onto a clean 1 px grid by tools/import_menu_sprites.py.
## Spots on the 640x360 menu are in data/menu_layout.json. Nearest filtering.
##
## Any window shape works: the logo and buttons stay centered, the astronaut
## group hugs the right edge, the ship and CREDITS the bottom-left corner, and
## the speaker the bottom-right. Call relayout() when the size changes.
## Buttons lift on hover and push in while held (main_menu.gd drives that).

const DIR := "res://assets/menu/"
const LAYOUT_PATH := "res://data/menu_layout.json"
const SKY_SHADER := preload("res://scripts/ui/menu_sky.gdshader")
const EARTH_SHADER := preload("res://scripts/ui/menu_earth.gdshader")
const PIXEL := 3.0                     # menu px per logo art pixel
const EARTH_GRID := 50.0               # art px across the Earth rect
const EARTH_CENTER := Vector2(320, 86) # menu px
const TITLE_TOP := 47.0                # menu px
const BASE := Vector2(640, 360)  # the art grid

## name: [bob px, bob period s, drift px x]. No rotation: pixel art stays on its grid.
const FLOATERS := {
	"planet": [2.0, 9.0, 0.0],
	"satellite": [3.0, 6.5, 2.0],
	"hull": [3.0, 7.5, 2.0],
	"astronaut": [5.0, 5.0, 2.0],
	"antenna": [3.0, 6.0, 2.0],
	"canister": [3.0, 5.5, 2.0],
	"rock_a": [2.0, 4.0, 1.0],
	"rock_b": [2.0, 4.5, 1.0],
	"rock_c": [2.0, 3.5, 1.0],
	"ship": [3.0, 6.0, 3.0],
	"moon": [1.0, 10.0, 0.0],
}
## Button sprite for each menu id (btn_<id>.png plus btn_<id>_pressed.png).
const BUTTONS := {
	"start": "btn_start", "how": "btn_how", "settings": "btn_settings",
	"credits": "btn_credits", "sound": "btn_sound",
}
## Where each piece sticks when the window isn't 16:9 (default: center).
const ANCHORS := {
	"planet": "right", "satellite": "right", "hull": "right", "astronaut": "right",
	"antenna": "right", "canister": "right", "rock_a": "right", "rock_b": "right",
	"rock_c": "right", "ship": "bottom_left", "moon": "bottom_left",
	"btn_credits": "bottom_left", "btn_sound": "bottom_right",
	"credits": "bottom_left", "sound": "bottom_right",
}

var _layout := {}
var _sky: ColorRect
var _sprites := {}    # name -> {node, home}
var _floaters := []   # [{name, cfg, phase}]
var _buttons := {}    # menu id -> {sprite, face, face_home, hover, hover_on, pressed}
var _glow: TextureRect
var _t := 0.0
var _shooting: ShootingStars


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout = _load_layout()

	_sky = ColorRect.new()
	_sky.name = "Sky"
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	_sky.material = mat
	add_child(_sky)

	_shooting = ShootingStars.new()
	add_child(_shooting)

	var i := 0
	for name in FLOATERS:
		if _sprite(name) != null:
			_floaters.append({"name": name, "cfg": FLOATERS[name], "phase": i * 1.7})
			i += 1

	_build_logo()

	for id in BUTTONS:
		var spr := _sprite(BUTTONS[id])
		if spr == null:
			continue
		var face := _make_face(id, spr)
		_buttons[id] = {"sprite": spr, "face": face,
			"face_home": face.position if face else Vector2.ZERO,
			"hover": 0.0, "hover_on": false, "pressed": false}

	relayout(BASE if size == Vector2.ZERO else size)


## True when the art loaded (false = main_menu draws its fallback buttons).
func is_ready() -> bool:
	return _buttons.size() == BUTTONS.size()


## How far a piece with this anchor moves when the screen is `sz` instead of 640x360.
static func anchor_offset(anchor: String, sz: Vector2) -> Vector2:
	var extra := sz - BASE
	match anchor:
		"right": return Vector2(extra.x, extra.y / 2.0)
		"bottom_left": return Vector2(0, extra.y)
		"bottom_right": return extra
		_: return extra / 2.0


static func anchor_for(name: String) -> String:
	return ANCHORS.get(name, "center")


## Where a menu button sits on the 640x360 grid (before any anchor shift).
func button_home_rect(id: String) -> Rect2:
	var l: Dictionary = _layout.get(BUTTONS.get(id, ""), {})
	return Rect2(l.get("x", 0), l.get("y", 0), l.get("w", 0), l.get("h", 0))


## Fit everything to a new screen size (in menu px; at least 640x360 when the
## window uses the "expand" aspect).
func relayout(sz: Vector2) -> void:
	size = sz
	_sky.size = sz
	_sky.material.set_shader_parameter("rect_size", sz)
	_shooting.size = sz
	_apply_positions()


func set_hover(id: String, on: bool) -> void:
	if _buttons.has(id):
		_buttons[id]["hover_on"] = on


func set_pressed(id: String, held: bool) -> void:
	if not _buttons.has(id):
		return
	var b: Dictionary = _buttons[id]
	b["pressed"] = held
	if b["face"] != null:
		b["sprite"].visible = not held
		b["face"].visible = held


func is_pressed(id: String) -> bool:
	return _buttons.has(id) and _buttons[id]["pressed"]


func _process(delta: float) -> void:
	_t += delta
	if _glow:
		_glow.modulate.a = 0.08 + 0.3 * (0.5 + 0.5 * sin(_t * 2.2))
	for id in _buttons:
		var b: Dictionary = _buttons[id]
		var target := 1.0 if b["hover_on"] and not b["pressed"] else 0.0
		b["hover"] = move_toward(b["hover"], target, delta * 8.0)
		var shine: float = 1.0 + b["hover"] * 0.18
		b["sprite"].modulate = Color(shine, shine, shine)
	_apply_positions()


## Home spot + anchor shift + animation (bob/sway for floaters, lift for buttons).
func _apply_positions() -> void:
	for name in _sprites:
		var s: Dictionary = _sprites[name]
		s["node"].position = s["home"] + anchor_offset(anchor_for(name), size)
	for f in _floaters:
		var cfg: Array = f["cfg"]
		var ph: float = f["phase"]
		var n: TextureRect = _sprites[f["name"]]["node"]
		var bob: float = sin(_t * TAU / cfg[1] + ph) * cfg[0]
		var drift: float = sin(_t * TAU / (cfg[1] * 1.9) + ph * 0.5) * cfg[2]
		n.position = (n.position + Vector2(drift, bob)).round()
	for id in _buttons:
		var b: Dictionary = _buttons[id]
		b["sprite"].position.y -= round(b["hover"] * 2.0)
		if b["face"] != null:
			b["face"].position = b["face_home"] + anchor_offset(anchor_for(id), size)


# --- Building ---------------------------------------------------------------------

func _load_layout() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		push_warning("Menu layout missing (%s)." % LAYOUT_PATH)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _sprite(name: String) -> TextureRect:
	var path := DIR + name + ".png"
	if not ResourceLoader.exists(path) or not _layout.has(name):
		return null
	var l: Dictionary = _layout[name]
	var r := _rect(load(path))
	r.name = name
	r.position = Vector2(l["x"], l["y"])
	r.size = Vector2(l["w"], l["h"])
	add_child(r)
	_sprites[name] = {"node": r, "home": r.position}
	return r


## Pixel-art logo: spinning Earth behind the title, plus the pulsing "2".
func _build_logo() -> void:
	var earth := ColorRect.new()
	earth.name = "Earth"
	earth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = EARTH_SHADER
	mat.set_shader_parameter("world_map", load(DIR + "earth_map.png"))
	mat.set_shader_parameter("grid", EARTH_GRID)
	earth.material = mat
	earth.size = Vector2.ONE * EARTH_GRID * PIXEL
	add_child(earth)
	_sprites["earth"] = {"node": earth, "home": EARTH_CENTER - earth.size / 2.0}

	for name: String in ["title", "title_two"]:
		var path: String = DIR + name + ".png"
		if not ResourceLoader.exists(path):
			continue
		var t: Texture2D = load(path)
		var r := _rect(t)
		r.name = name
		r.size = t.get_size() * PIXEL
		add_child(r)
		_sprites[name] = {"node": r, "home": Vector2(round(EARTH_CENTER.x - r.size.x / 2.0), TITLE_TOP)}
		if name == "title_two":
			var add := CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			r.material = add
			_glow = r


func _rect(t: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp art pixels
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The pushed-in look: the same button with its face dropped onto the strip.
func _make_face(id: String, spr: TextureRect) -> TextureRect:
	var path: String = DIR + BUTTONS[id] + "_pressed.png"
	if not ResourceLoader.exists(path):
		return null
	var face := _rect(load(path))
	face.position = spr.position
	face.size = spr.size
	face.visible = false
	add_child(face)
	return face


## A pixel streak crossing the sky every few seconds.
class ShootingStars extends Control:
	var _wait := 2.5
	var _t := -1.0
	var _from := Vector2.ZERO
	var _dir := Vector2.ZERO
	const LIFE := 0.9
	const LENGTH := 46.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if _t < 0.0:
			_wait -= delta
			if _wait <= 0.0:
				_t = 0.0
				_from = Vector2(randf_range(80, size.x - 40), randf_range(-10, size.y * 0.33))
				_dir = Vector2(-1.0, 0.45).normalized().rotated(randf_range(-0.2, 0.2))
		else:
			_t += delta
			if _t > LIFE:
				_t = -1.0
				_wait = randf_range(4.0, 9.0)
		queue_redraw()

	func _draw() -> void:
		if _t < 0.0:
			return
		var k := _t / LIFE
		var head := _from + _dir * (k * 260.0)
		var fade := 1.0 - k
		for i in 12:
			var p := head - _dir * (i * LENGTH / 12.0)
			var a := fade * (1.0 - i / 12.0)
			var s := 2.0 if i < 2 else 1.0
			draw_rect(Rect2(p.round(), Vector2(s, s)), Color(0.85, 0.95, 1.0, a))
