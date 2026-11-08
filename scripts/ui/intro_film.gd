extends Control
## The opening film, drawn live in Godot (no video). Owner: D.
##
## A line-by-line port of the shot code in tools/make_intro.py: it draws the
## same 320x180 pixel-art frames into a SubViewport, shown scaled up with
## nearest filtering, so it stays crisp at any window size. The pieces that
## script draws once (backgrounds, ship, planets, crew frames) come from
## assets/intro/, and everything it picks at random (stars, air, debris, sparks,
## camera shake) from data/intro_film.json, both written by
## `make_intro.py --export-godot`. data/intro_edit_map.json holds the team's
## final-cut timing (tools/align_intro_edit.py): which original frame each
## frame of the final cut shows, so the picture lines up with the voice track.
##
## Call set_time(seconds since the film started); it redraws when the frame changes.

const ART := "res://assets/intro/"
const DATA_PATH := "res://data/intro_film.json"
const EDIT_PATH := "res://data/intro_edit_map.json"
const W := 320
const H := 180
const FPS := 30
const LB := 16
const LB_BOTTOM := 20
const FEET := 131

# Timeline (seconds, original render clock). Same names as make_intro.py.
const T_YEAR_IN := 0.3
const T_EXT_IN := 2.0
const T_EXT_FULL := 3.2
const T_CABIN_A := 5.2
const T_NAV := 9.0
const T_CABIN_B := 11.4
const T_WAKE := 11.7
const T_IMPACT := 14.7
const T_STAND := 17.3
const T_WALK := 17.7
const T_CORR := 19.3
const T_HIT2 := 21.4
const T_OUT := 24.2
const T_SEAL := 27.2
const LENGTH := 41.2
const T_FADE_OUT := LENGTH - 0.4
const SEAL_OFF := T_SEAL - 19.0
const JOHNNY_TURNS := 33.6
const CPS := 30.0
const MONITOR_LINES := [[5.6, "MARS SPACE STATION"], [6.45, "REPAIRS MISSION:"], [7.9, "RETURNING HOME"]]
const SUCCESS_AT := 7.2
const MONITOR_CPS := 26.0
const DISTANCE_MI := 676767
const FLICKER := [[24.0, 24.08], [24.16, 24.22], [24.35, 24.7], [24.76, 24.8], [24.9, 26.4], [26.47, 26.52], [26.6, 30.0]]

# Palette (PICO-8 based).
const SPACE := Color8(5, 6, 20)
const STEEL_D := Color8(40, 44, 64)
const STEEL := Color8(58, 56, 72)
const STEEL_L := Color8(95, 92, 112)
const STEEL_LL := Color8(126, 126, 140)
const WHITE := Color8(255, 241, 232)
const GRAY := Color8(194, 195, 199)
const CYAN := Color8(61, 240, 255)
const BLUE := Color8(41, 173, 255)
const AMBER := Color8(255, 163, 0)
const YELLOW := Color8(255, 236, 39)
const RED := Color8(255, 0, 77)
const GREEN := Color8(0, 228, 54)
const INK := Color8(10, 10, 14)
const STAR_COLORS := [Color8(64, 72, 112), Color8(150, 160, 200), Color8(255, 241, 232)]
const BAYER4 := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# Cabin.
const CABIN_W := 420
const ROLES := ["ahead", "survivor", "player", "lost"]
const SEAT_X := {"ahead": 104, "survivor": 168, "player": 232, "lost": 296}
const MONITOR := [112, 35, 322, 77]
const NAVSCR := [341, 49, 409, 101]
const CAB_DOOR := [15, 69, 49, 132]
const NAV_SHIP_U := 0.9
const CABIN_RUN := 55.0
const CAB_DOOR_OPEN := [T_WALK + 0.85, T_WALK + 1.15]
const Z_PHASE := {"ahead": 1.2, "survivor": 0.0, "player": 0.5, "lost": 0.9}
# Dashboard.
const NAV_SCREEN := [34, 22, 286, 134]
const NAV_P0 := Vector2(70, 92)
const NAV_P1 := Vector2(150, 30)
const NAV_P2 := Vector2(250, 74)
# Corridor.
const CORR_DOOR := [144, 164]
const CORR_PANEL := [128, 113, 140, 125]
const CORR_TERM := [50, 50, 118, 82]
const T_LOCKER_LOOK := 37.9   # the crew turns to the locker blocking the hallway aft
const AHEAD_WAIT_X := 58.0    # Dhan stops here: the locker blocks the way
# role: [x from, x to, delay, walk time] as they step up to the locker
# Johnny walks up to the locker past the others; Dhan steps back toward the barrier.
const LOCKER_LOOK := {"ahead": [58.0, 110.0, 0.0, 1.1], "survivor": [90.0, 96.0, 0.35, 0.4],
	"player": [124.0, 54.0, 0.15, 1.5]}
const CORR_RUN := {"survivor": [330.0, 170.0], "player": [362.0, 206.5], "lost": [400.0, 246.5]}
const AHEAD_X0 := 150.0
const AHEAD_V := 82.0
const OUT_SCALE := 4

var _data := {}
var _edit: Array = []
var _tex := {}             # name -> Texture2D
var _glyph := {}           # char -> Texture2D (5x7, white)
var _crew := {}            # role -> {skin, w, h, bx0, bx1, color, dark}
var _frames := {}          # cache key -> ImageTexture (crew frames, flipped/rotated)
var _sheets := {}          # skin -> Image
var _breach_mask: Image
var _viewport: SubViewport
var _canvas: Canvas
var _frame := -1           # final-cut frame shown
var _base := 0             # matching frame of the original render

var _cam := Vector2.ZERO   # current shot's camera transform (for drawing helpers)
var _src_w := W            # current shot's source width (cabin is wider)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_data = _load_json(DATA_PATH)
	_edit = _load_json(EDIT_PATH).get("frames", [])
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(W, H)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_canvas = Canvas.new()
	_canvas.film = self
	_viewport.add_child(_canvas)
	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A newly allocated viewport texture may still contain an old frame.
	# Keep the cutscene's black backing visible until the first draw finishes.
	view.hide()
	add_child(view)
	_build()
	set_time(0.0)
	RenderingServer.frame_post_draw.connect(view.show, CONNECT_ONE_SHOT)


## True when the art and data loaded.
func is_ready() -> bool:
	return not _data.is_empty() and not _edit.is_empty() and _tex.has("cabin_bg")


## Length of the final cut in seconds.
func length() -> float:
	return float(_edit.size()) / FPS


func set_time(seconds: float) -> void:
	if _edit.is_empty():
		return
	var f := clampi(int(seconds * FPS), 0, _edit.size() - 1)
	if f == _frame:
		return
	_frame = f
	_base = int(_edit[f])
	_canvas.queue_redraw()


# --- Loading ----------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Intro data missing: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _build() -> void:
	for name in ["cabin_bg", "cabin_glass", "corridor_bg", "nav_bg", "ship2", "ship4", "breach_mask",
			"breach_edge", "vignette", "glow_near", "glow_far", "hole_atlas", "hole_inner_atlas",
			"hole_edge_atlas", "far_planet_0", "far_planet_1", "far_planet_2"]:
		var path: String = ART + name + ".png"
		if ResourceLoader.exists(path):
			_tex[name] = load(path)
	if _tex.has("breach_mask"):
		_breach_mask = _tex["breach_mask"].get_image()
	for ch in _data.get("font", {}):
		var rows: PackedStringArray = str(_data["font"][ch]).split(" ")
		var img := Image.create(5, 7, false, Image.FORMAT_RGBA8)
		for y in 7:
			for x in 5:
				if rows[y][x] == "1":
					img.set_pixel(x, y, Color.WHITE)
		_glyph[ch] = ImageTexture.create_from_image(img)
	var cast: Dictionary = _data.get("cast", {})
	for role in cast:
		var skin: String = cast[role]
		var info: Dictionary = _data["crew"][skin].duplicate()
		info["skin"] = skin
		_crew[role] = info
		if not _sheets.has(skin) and ResourceLoader.exists(ART + "astro_%s.png" % skin):
			_sheets[skin] = load(ART + "astro_%s.png" % skin).get_image()
		for k in 3:
			var p := ART + "tiny_%s_%d.png" % [skin, k]
			if ResourceLoader.exists(p):
				_tex["tiny_%s_%d" % [skin, k]] = load(p)


## A crew frame as a texture: walk frame i, mirrored, rotated a quarter turn
## counterclockwise `rot` times (np.rot90).
func _crew_tex(skin: String, i: int, left: bool, rot: int) -> Texture2D:
	var key := "%s/%d/%s/%d" % [skin, i, left, rot]
	if _frames.has(key):
		return _frames[key]
	var info: Dictionary = _data["crew"][skin]
	var fw: int = info["w"]
	var img: Image = _sheets[skin].get_region(Rect2i(i * fw, 0, fw, int(info["h"])))
	if left:
		img.flip_x()
	for _r in rot:
		img.rotate_90(COUNTERCLOCKWISE)
	var tex := ImageTexture.create_from_image(img)
	_frames[key] = tex
	return tex


# --- Python-exact math ---------------------------------------------------------------

## Python's round(): halves go to the even neighbour.
static func pyround(x: float) -> int:
	var f := floorf(x)
	var d := x - f
	if d > 0.5:
		return int(f) + 1
	if d < 0.5:
		return int(f)
	return int(f) + (1 if posmod(int(f), 2) == 1 else 0)


static func ease_out(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u)


static func ease_io(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func text_w(s: String) -> int:
	return 6 * s.length() - 1 if s != "" else 0


## tint_color(): each channel times m, cut to whole numbers like numpy does.
static func tint(c: Color, m) -> Color:
	if m == null:
		return c
	return Color8(mini(255, int(c.r8 * m[0])), mini(255, int(c.g8 * m[1])), mini(255, int(c.b8 * m[2])), c.a8)


static func mod_color(m) -> Color:
	return Color.WHITE if m == null else Color(m[0], m[1], m[2])


static func nav_point(u: float, p0: Vector2, p1: Vector2, p2: Vector2) -> Vector2:
	return Vector2((1 - u) ** 2 * p0.x + 2 * (1 - u) * u * p1.x + u * u * p2.x,
		(1 - u) ** 2 * p0.y + 2 * (1 - u) * u * p1.y + u * u * p2.y)


static func with_commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


# --- Drawing primitives (on the canvas, in source-image pixels) -------------------------

func _rect(x0: float, y0: float, x1: float, y1: float, color: Color) -> void:
	var a := maxi(0, int(x0))
	var b := mini(_src_w, int(x1))
	var c := maxi(0, int(y0))
	var d := mini(H, int(y1))
	if a < b and c < d:
		_canvas.draw_rect(Rect2(a, c, b - a, d - c), color)


func _px(x: int, y: int, color: Color) -> void:
	if x >= 0 and x < _src_w and y >= 0 and y < H:
		_canvas.draw_rect(Rect2(x, y, 1, 1), color)


func _blend(x: int, y: int, color: Color, a: float) -> void:
	if x >= 0 and x < _src_w and y >= 0 and y < H:
		_canvas.draw_rect(Rect2(x, y, 1, 1), Color(color, a))


## blit(): sprite at round(x), round(y), optionally clipped to a box.
func _blit(tex: Texture2D, x: float, y: float, modulate := Color.WHITE, clip := [], src := Rect2()) -> void:
	if tex == null:
		return
	if src.size == Vector2.ZERO:
		src = Rect2(Vector2.ZERO, tex.get_size())
	var cx0 := 0
	var cy0 := 0
	var cx1 := _src_w
	var cy1 := H
	if not clip.is_empty():
		cx0 = clip[0]; cy0 = clip[1]; cx1 = clip[2]; cy1 = clip[3]
	var ix := pyround(x)
	var iy := pyround(y)
	var dx0 := maxi(cx0, ix)
	var dy0 := maxi(cy0, iy)
	var dx1 := mini(cx1, ix + int(src.size.x))
	var dy1 := mini(cy1, iy + int(src.size.y))
	if dx0 >= dx1 or dy0 >= dy1:
		return
	var part := Rect2(src.position.x + dx0 - ix, src.position.y + dy0 - iy, dx1 - dx0, dy1 - dy0)
	_canvas.draw_texture_rect_region(tex, Rect2(dx0, dy0, dx1 - dx0, dy1 - dy0), part, modulate)


func _text(x: int, y: int, s: String, color: Color, k := 1) -> void:
	s = s.to_upper()
	for i in s.length():
		var g: Texture2D = _glyph.get(s[i])
		if g != null and s[i] != " ":
			_canvas.draw_texture_rect(g, Rect2(x + 6 * k * i, y, 5 * k, 7 * k), false, color)


func _glyph_on(ch: String, gx: int, gy: int) -> bool:
	var rows: PackedStringArray = str(_data["font"].get(ch, "00000 00000 00000 00000 00000 00000 00000")).split(" ")
	return rows[gy][gx] == "1"


func _stars(list: Array, t: float, offx := 0.0, offy := 0.0, wrap_w := 0, mask: Image = null) -> void:
	var ww := wrap_w if wrap_w > 0 else _src_w
	for s in list:
		var x := int(fposmod(float(s[0]) + offx, ww))
		var y := int(float(s[1]) + offy)
		if not (x >= 0 and x < _src_w and y >= 0 and y < H):
			continue
		if mask != null and mask.get_pixel(x, y).a < 0.5:
			continue
		var b := int(s[2])
		var ph := float(s[3])
		if b == 2 and sin(t * 3 + ph) < -0.6:
			b = 1
		_canvas.draw_rect(Rect2(x, y, 1, 1), STAR_COLORS[b])
		if b == 2 and ph > 5.6:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and nx < _src_w and ny >= 0 and ny < H:
					if mask == null or mask.get_pixel(nx, ny).a >= 0.5:
						_canvas.draw_rect(Rect2(nx, ny, 1, 1), STAR_COLORS[1])


## Astro.draw(): cx = visual centre, feet = bottom row. Returns the top row.
func _astro(role: String, cx: float, feet: float, t_anim := 0.0, walking := false, left := false,
		rows := -1, rot := 0, lift := 0, clip := [], tint_m = null) -> float:
	var info: Dictionary = _crew[role]
	var i := posmod(int(t_anim * 10), 6) if walking else 5
	var tex := _crew_tex(info["skin"], i, left, rot)
	var h := int(info["h"])
	var w := int(info["w"])
	var fh := h
	var mid := (float(info["bx0"]) + float(info["bx1"])) / 2.0
	if left:
		mid = w - 1 - mid
	if rows >= 0:
		fh = rows
	if rot:
		var sz := tex.get_size()
		mid = sz.x / 2.0
		fh = int(sz.y)
	var top := feet - fh + 1 - lift
	var src := Rect2(0, 0, tex.get_width(), fh)
	_blit(tex, cx - mid, top, mod_color(tint_m), clip, src)
	return top


## Astro.arm(): arm reaching forward from the shoulder.
func _arm(role: String, cx: float, top: float, length: int, left := false, tint_m = null) -> void:
	var info: Dictionary = _crew[role]
	var c: Array = info["color"]
	var y := top + 14
	var suit := tint(Color8(int(c[0]), int(c[1]), int(c[2])), tint_m)
	var glove := tint(GRAY, tint_m)
	if left:
		var x1 := pyround(cx) - 4
		var x0 := x1 - length
		_rect(x0, y, x1, y + 2, suit)
		_rect(x0, y, x0 + 2, y + 2, glove)
	else:
		var x0 := pyround(cx) + 4
		_rect(x0, y, x0 + length, y + 2, suit)
		_rect(x0 + length - 2, y, x0 + length, y + 2, glove)


func _engine(sx: float, sy: float, s: int, t: float) -> void:
	var n := 10 + 4 * (s - 1)
	for k in n:
		_blend(int(sx + 2 * s - k * 3), int(sy + 12 * s), AMBER, 0.5 * (1.0 - float(k) / n))
		if s > 1:
			_blend(int(sx + 2 * s - k * 3), int(sy + 12 * s + 1), AMBER, 0.35 * (1.0 - float(k) / n))
	var fl := (4 + (int(t * FPS) % 3)) * s
	for k in fl:
		_rect(int(sx + 3 * s - k), int(sy + 11 * s), int(sx + 4 * s - k), int(sy + 14 * s), AMBER if k > s else YELLOW)


func _flow(name: String, t: float, debris: bool, x_min = null) -> void:
	var f: Dictionary = _data["flows"][name]
	var ts: Array = f["ts"]
	for i in ts.size():
		var dt := t - float(ts[i])
		if dt < 0 or dt > 2.4:
			continue
		var x := float(f["x"][i]) + float(f["v"][i]) * dt + 70 * dt * dt
		if x > W or (x_min != null and x < x_min):
			continue
		var xi := int(x)
		var yi := int(float(f["y"][i]) + (sin(float(ts[i]) * 9) * 4 * dt))
		if debris:
			var sz := int(f["sz"][i])
			_rect(xi, yi, xi + sz, yi + sz, STEEL_LL if sz > 1 else GRAY)
		else:
			var ln := int(f["ln"][i])
			for k in ln:
				_blend(xi - k, yi, Color8(175, 195, 225), 0.55 * (1.0 - float(k) / ln))


func _shake(key: String) -> Vector2i:
	var table: Dictionary = _data["shakes"].get(key, {})
	var v = table.get(str(_base))
	return Vector2i(int(v[0]), int(v[1])) if v != null else Vector2i.ZERO


## view(): the frame is a W-wide window starting at x0, moved by a shake.
func _set_view(x0: float, shake := Vector2i.ZERO) -> void:
	_cam = Vector2(-(pyround(x0) + shake.x), shake.y)
	_canvas.draw_set_transform(_cam)


func _screen() -> void:
	_cam = Vector2.ZERO
	_src_w = W
	_canvas.draw_set_transform(Vector2.ZERO)


## Darken everything drawn so far: img * k (as a black wash).
func _darken(k: float) -> void:
	_canvas.draw_rect(Rect2(0, 0, _src_w, H), Color(0, 0, 0, clampf(1.0 - k, 0.0, 1.0)))


# --- Frame -------------------------------------------------------------------------------

func draw_frame() -> void:
	var t := float(_base) / FPS
	_screen()
	_canvas.draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	if t < T_CABIN_A:
		_shot_exterior(t)
	elif t < T_NAV:
		_shot_cabin(t)
	elif t < T_CABIN_B:
		_shot_nav(t)
	elif t < T_CORR:
		_shot_cabin(t)
	elif t < T_OUT:
		_shot_breach(t)
	elif t < T_SEAL:
		_shot_outside(t)
	else:
		_shot_seal(t)
	_screen()
	if t < T_EXT_FULL:
		_year_card(t)
	_canvas.draw_rect(Rect2(0, 0, W, LB), Color.BLACK)
	_canvas.draw_rect(Rect2(0, H - LB_BOTTOM, W, LB_BOTTOM), Color.BLACK)
	_captions(t)
	if t >= T_FADE_OUT:
		_darken(maxf(0.0, 1.0 - (t - T_FADE_OUT) / (LENGTH - T_FADE_OUT - 0.05)))


func _year_card(t: float) -> void:
	var k: float
	if t < T_EXT_IN:
		k = 0.3 * ease_io((t - 0.6) / (T_EXT_IN - 0.6))
	else:
		k = lerpf(0.3, 1.0, ease_io((t - T_EXT_IN) / (T_EXT_FULL - T_EXT_IN)))
	_darken(k)
	var text := "THE YEAR 2126"
	var kk := 3
	var tw := (6 * text.length() - 1) * kk
	var x0 := (W - tw) / 2
	var appear := (t - T_YEAR_IN) / 0.8
	var leave := (t - T_EXT_IN) / 1.0
	for i in text.length():
		if text[i] == " ":
			continue
		for gy in 7:
			for gx in 5:
				if not _glyph_on(text[i], gx, gy):
					continue
				for sy in kk:
					for sx in kk:
						var x := x0 + 6 * kk * i + gx * kk + sx
						var y := 80 + gy * kk + sy
						var th: float = BAYER4[(y / 2) % 4][(x / 2) % 4] / 16.0
						if th < appear and th >= leave:
							_canvas.draw_rect(Rect2(x, y, 1, 1), WHITE)


func _captions(t: float) -> void:
	for cap in _data.get("captions", []):
		var t0: float = cap["t0"]
		var t1: float = T_FADE_OUT if cap["t1"] == null else float(cap["t1"])
		if not (t0 <= t and t < t1):
			continue
		var n := int((t - t0) * CPS)
		var rows: Array = cap["rows"]
		var top := H - LB_BOTTOM + (LB_BOTTOM - (9 * rows.size() - 2)) / 2
		for k in rows.size():
			var spk: String = rows[k][0]
			var text: String = rows[k][1]
			var full := ("%s %s" % [spk, text]) if spk != "" else text
			var x := W / 2 - text_w(full) / 2
			var y := top + 9 * k
			if spk != "":
				_text(x, y, spk, CYAN if cap["style"] != "system" else RED)
				x += 6 * (spk.length() + 1)
			_text(x, y, text.substr(0, maxi(0, n)), WHITE if cap["style"] != "action" else GRAY)
			n -= text.length() + 1


# --- Shots -------------------------------------------------------------------------------

func _shot_exterior(t: float) -> void:
	_src_w = W
	_canvas.draw_rect(Rect2(0, 0, W, H), SPACE)
	_stars(_data["stars"]["ext_far"], t, -3 * t, 0.0, W)
	_stars(_data["stars"]["ext_near"], t, -8 * t, 0.0, W)
	for k in 3:
		var tex: Texture2D = _tex.get("far_planet_%d" % k)
		var p: Array = _data["far_planets"][k]
		_blit(tex, int(p[0]) - tex.get_width() / 2, int(p[1]) - tex.get_height() / 2)
	var sx := lerpf(-130, 150, (t - T_EXT_IN) / (T_CABIN_A - T_EXT_IN))
	var sy := 66 + pyround(sin(t * 2.2))
	_engine(sx, sy, 2, t)
	_blit(_tex["ship2"], sx, sy)


func _monitor_text(t: float) -> void:
	var mx0: int = MONITOR[0]
	var my0: int = MONITOR[1]
	if t >= T_IMPACT:
		return
	for i in MONITOR_LINES.size():
		var t0: float = MONITOR_LINES[i][0]
		var line: String = MONITOR_LINES[i][1]
		var n := int(maxf(0.0, t - t0) * MONITOR_CPS)
		if n > 0:
			_text(mx0 + 8, my0 + 6 + 11 * i, line.substr(0, n), CYAN)
	if t >= SUCCESS_AT:
		var x: int = mx0 + 8 + text_w(MONITOR_LINES[1][1] + " ") + 1
		var pop := maxf(0.0, 1.0 - (t - SUCCESS_AT) / 0.5)
		var glow := 0.45 + 0.2 * sin(2 * PI * 1.1 * (t - SUCCESS_AT)) + 0.4 * pop
		_blit(_tex["glow_far"], x - 3, my0 + 17 - 3, Color(GREEN, minf(1.0, glow * 0.45)))
		_blit(_tex["glow_near"], x - 3, my0 + 17 - 3, Color(GREEN, minf(1.0, glow)))
		_text(x, my0 + 17, "SUCCESS", Color8(150, 255, 170))
	var last: Array = MONITOR_LINES[-1]
	var done: float = float(last[0]) + str(last[1]).length() / MONITOR_CPS
	if t > done and int(t * 2) % 2 == 0:
		var cx: int = mx0 + 8 + text_w(last[1]) + 3
		_rect(cx, my0 + 28, cx + 5, my0 + 35, CYAN)


func _monitor_alert(t: float) -> void:
	var mx0: int = MONITOR[0]
	var my0: int = MONITOR[1]
	var mx1: int = MONITOR[2]
	var my1: int = MONITOR[3]
	_rect(mx0 + 3, my0 + 3, mx1 - 3, my1 - 3, Color8(40, 4, 12))
	if int(t * 2.5) % 2 == 0:
		var s := "! COLLISION DETECTED !"
		_text((mx0 + mx1) / 2 - text_w(s) / 2, my0 + 17, s, RED)


func _nav_mini(t: float, m) -> void:
	var x0: int = NAVSCR[0]
	var y0: int = NAVSCR[1]
	var x1: int = NAVSCR[2]
	var y1: int = NAVSCR[3]
	_rect(x0, y0, x1, y1, tint(Color8(4, 12, 18), m))
	var gx := x0 + 8
	while gx < x1:
		_rect(gx, y0, gx + 1, y1, tint(Color8(10, 26, 34), m))
		gx += 12
	var p0 := Vector2(x0 + 7, y0 + 34)
	var p1 := Vector2(x0 + 30, y0 + 4)
	var p2 := Vector2(x1 - 8, y0 + 18)
	for k in 40:
		var u := k / 39.0
		if u > NAV_SHIP_U and k % 2:
			continue
		var p := nav_point(u, p0, p1, p2)
		_px(int(p.x), int(p.y), tint(CYAN if u <= NAV_SHIP_U else Color8(40, 110, 130), m))
	_rect(int(p0.x) - 1, int(p0.y) - 1, int(p0.x) + 2, int(p0.y) + 2, tint(Color8(200, 80, 44), m))
	_rect(int(p2.x) - 2, int(p2.y) - 2, int(p2.x) + 2, int(p2.y) + 2, tint(BLUE, m))
	if int(t * 3) % 2 == 0:
		var s := nav_point(NAV_SHIP_U, p0, p1, p2)
		_rect(int(s.x) - 1, int(s.y) - 1, int(s.x) + 2, int(s.y) + 2, tint(WHITE, m))
	var label := "%s MI" % with_commas(DISTANCE_MI)
	_text((x0 + x1) / 2 - text_w(label) / 2, y1 - 10, label, tint(CYAN, m))


func _cabin_door(u: float, m) -> void:
	var x0: int = CAB_DOOR[0]
	var y0: int = CAB_DOOR[1]
	var x1: int = CAB_DOOR[2]
	var y1: int = CAB_DOOR[3]
	var half := (x1 - x0) / 2
	_rect(x0, y0, x1, y1, tint(Color8(8, 10, 16), m))
	var gap := pyround(half * u)
	if gap < half:
		_rect(x0, y0, x0 + half - gap, y1, tint(STEEL, m))
		_rect(x0 + half + gap, y0, x1, y1, tint(STEEL, m))
		_rect(x0 + half - gap - 1, y0, x0 + half - gap, y1, tint(STEEL_D, m))
		_rect(x0 + half + gap, y0, x0 + half + gap + 1, y1, tint(STEEL_D, m))
		if gap == 0:
			_rect(x0 + 4, 80, x0 + 12, 92, tint(STEEL_D, m))
			_rect(x1 - 12, 80, x1 - 4, 92, tint(STEEL_D, m))


func _console(sx: int, t: float, m) -> void:
	_rect(sx + 7, 117, sx + 18, 132, tint(STEEL, m))
	_rect(sx + 7, 117, sx + 18, 118, tint(STEEL_L, m))
	if t < T_IMPACT:
		_rect(sx + 8, 120, sx + 10, 121, GREEN if int(t * 2 + sx) % 3 else STEEL_D)
		_rect(sx + 12, 120, sx + 14, 121, AMBER)
	_rect(sx + 8, 124, sx + 17, 125, tint(STEEL_D, m))


func _cabin_camera(t: float) -> float:
	if t < T_NAV:
		return lerpf(0, 50, ease_io((t - T_CABIN_A) / (T_NAV - T_CABIN_A)))
	if t < T_IMPACT + 2.1:
		return 100.0
	return lerpf(100, 0, ease_io((t - (T_IMPACT + 2.1)) / 1.9))


## (room multiplier, crew multiplier) after the impact; [null, null] before.
func _cabin_light(t: float) -> Array:
	var t0 := T_IMPACT
	if t < t0 + 0.15:
		return [null, null]
	if t < t0 + 0.8:
		var k := 0.55 if (t0 + 0.35 <= t and t < t0 + 0.42) else 0.1
		var c := maxf(k, 0.2)
		return [[k, k, k], [c, c, c]]
	var k2 := minf(1.0, (t - t0 - 0.8) / 0.2)
	var pulse := 0.86 + 0.1 * sin(2 * PI * 1.6 * (t - t0 - 0.8))
	var room := [1.0 * pulse * k2 + 0.1 * (1 - k2), 0.4 * pulse * k2 + 0.1 * (1 - k2), 0.44 * pulse * k2 + 0.1 * (1 - k2)]
	var crew := [1.0 * pulse * k2 + 0.2 * (1 - k2), 0.68 * pulse * k2 + 0.2 * (1 - k2), 0.7 * pulse * k2 + 0.2 * (1 - k2)]
	return [room, crew]


func _sparks(t: float, ox: float, oy: float) -> void:
	var sp: Dictionary = _data["sparks"]
	for i in sp["at"].size():
		var dt := t - float(sp["at"][i])
		if not (0 <= dt and dt <= 0.7):
			continue
		for p in sp["bursts"][i]:
			var x := int(ox + float(p[0]) * dt)
			var y := int(oy + float(p[1]) * dt + 180 * dt * dt)
			_rect(x, y, x + 1, y + 1, YELLOW if p[2] else AMBER)


func _shot_cabin(t: float) -> void:
	_src_w = CABIN_W
	_set_view(_cabin_camera(t), _shake("cabin"))
	var light := _cabin_light(t)
	var room = light[0]
	var crew = light[1]
	_canvas.draw_texture(_tex["cabin_bg"], Vector2.ZERO, mod_color(room))
	_monitor_text(t)
	_nav_mini(t, room)
	if t >= CAB_DOOR_OPEN[0]:
		_cabin_door(ease_out((t - CAB_DOOR_OPEN[0]) / (CAB_DOOR_OPEN[1] - CAB_DOOR_OPEN[0])), room)
	if room != null:
		_canvas.draw_texture(_tex["cabin_glass"], Vector2.ZERO)  # outside isn't lit by the alarm
		if t >= T_IMPACT + 0.8:
			_monitor_alert(t)
			var on := int(t * 3.2) % 2 == 0
			for bx in [120, 240, 360]:
				_rect(bx, 31, bx + 5, 34, Color8(255, 40, 60) if on else Color8(90, 10, 20))
	var seated := t < T_STAND
	if seated:
		for role in ROLES:
			var sx: int = SEAT_X[role]
			var asleep := t < (T_WAKE if role == "lost" else T_IMPACT)
			var top := _astro(role, sx, 124 + (1 if asleep else 0), 0.0, false, false, 20, 0, 0, [], crew)
			if role == "lost" and not asleep:
				_rect(sx + 3, top + 6, sx + 5, top + 7, tint(CYAN, crew))
			if t < T_STAND - 0.2:
				for k in 7:
					_blend(sx + 3 - k, int(top) + 12 + k, tint(AMBER, crew), 1.0)
				_rect(sx, top + 15, sx + 2, top + 17, tint(GRAY, crew))
			if asleep and t >= T_CABIN_A + 0.2:
				var ph := fmod(t + Z_PHASE[role], 1.6)
				var zx := sx + 6 + int(ph * 3)
				var zy := int(top) - 2 - int(ph * 8)
				var zrows := ["1111", "..1.", ".1..", "1111"]
				for dy in 4:
					for dx in 4:
						if zrows[dy][dx] == "1":
							_blend(zx + dx, zy + dy, GRAY, 0.9)
	for role in SEAT_X:
		_console(SEAT_X[role], t, room)
	if not seated:
		for i in ROLES.size():
			var role: String = ROLES[i]
			var sx: int = SEAT_X[role]
			var t0 := T_WALK + 0.08 * i
			if t < t0:
				_astro(role, sx, FEET, 0.0, false, t >= T_STAND + 0.25, -1, 0, 0, [], crew)
			else:
				var walk := t - t0
				var x := sx - CABIN_RUN * walk
				var clip := [CAB_DOOR[0], 0, CABIN_W, H] if x < CAB_DOOR[2] - 4 else []
				_astro(role, x, FEET, walk * 1.3, true, true, -1, 0, 0, clip, crew)
	if t >= T_IMPACT:
		_sparks(t, 232, 31)
	if T_IMPACT <= t and t < T_IMPACT + 0.067:  # impact flash
		_canvas.draw_rect(Rect2(0, 0, _src_w, H), Color(1, 1, 1, 0.85))


func _shot_nav(t: float) -> void:
	_src_w = W
	var lt := t - T_NAV
	_canvas.draw_texture(_tex["nav_bg"], Vector2.ZERO)
	var sx0: int = NAV_SCREEN[0]
	var sx1: int = NAV_SCREEN[2]
	var sy1: int = NAV_SCREEN[3]
	for k in 120:
		var u := k / 119.0
		var p := nav_point(u, NAV_P0, NAV_P1, NAV_P2)
		if u <= NAV_SHIP_U:
			_rect(int(p.x), int(p.y), int(p.x) + 1, int(p.y) + 1, CYAN)
		elif k % 3 == 0:
			_rect(int(p.x), int(p.y), int(p.x) + 1, int(p.y) + 1, Color8(60, 140, 160))
	var s := nav_point(NAV_SHIP_U, NAV_P0, NAV_P1, NAV_P2)
	if int(lt * 3) % 2 == 0:
		for dy in range(-2, 3):
			_rect(int(s.x) - 2 + absi(dy), int(s.y) + dy, int(s.x) + 3 - absi(dy), int(s.y) + dy + 1, WHITE)
		var r := 4 + int(lt * 6) % 4
		for i in 24:
			var a := 2 * PI * i / 23.0
			_blend(int(s.x + r * cos(a)), int(s.y + r * sin(a)), CYAN, 0.5)
	var d := DISTANCE_MI + pyround(30 * (1 - ease_out(lt / 0.7))) if lt < 0.7 else DISTANCE_MI
	var label := "DISTANCE TO EARTH"
	_text((sx0 + sx1) / 2 - text_w(label) / 2, sy1 - 31, label, Color8(90, 170, 190))
	var figure := "%s MI" % with_commas(d)
	var fw := (6 * figure.length() - 1) * 2
	_text((sx0 + sx1) / 2 - fw / 2, sy1 - 20, figure, WHITE, 2)
	var i2 := 0
	var x0 := 140
	while x0 < 190:
		var on := (int(lt * 4) + i2) % 3 != 0
		_rect(x0, sy1 + 14, x0 + 4, sy1 + 17, [GREEN, AMBER, CYAN][i2 % 3] if on else STEEL_D)
		x0 += 8
		i2 += 1
	if lt < 0.15:  # the screen wakes up
		_darken(0.3 + lt / 0.15 * 0.7)


func _corridor_light(t: float) -> Array:
	var pulse := 0.88 + 0.1 * sin(2 * PI * 1.6 * t)
	return [[1.0 * pulse, 0.42 * pulse, 0.46 * pulse], [1.0 * pulse, 0.7 * pulse, 0.72 * pulse]]


func _slab(t: float, m) -> void:
	var d0: int = CORR_DOOR[0]
	var d1: int = CORR_DOOR[1]
	var bottom: int
	if t < 21.4:
		bottom = 47
	else:
		bottom = int(lerpf(47, 132, ease_out((t - 21.4) / 0.1) if t < 21.5 else 1.0))
	_rect(d0 + 4, 41, d1 - 4, bottom, tint(STEEL_L, m))
	_rect(d0 + 9, 41, d0 + 11, bottom, tint(STEEL, m))
	var i := 0
	while i < d1 - d0 - 8:
		_rect(d0 + 4 + i, bottom - 4, d0 + 6 + i, bottom, tint(AMBER, m))
		i += 4
	_rect(d0 + 4, bottom - 1, d1 - 4, bottom, tint(INK, m))


func _button(t: float) -> void:
	var btn := WHITE if (21.3 <= t and t < 21.5) else (Color8(255, 30, 70) if t < 21.3 else Color8(120, 0, 30))
	_rect(CORR_PANEL[0] + 4, CORR_PANEL[1] + 4, CORR_PANEL[2] - 4, CORR_PANEL[3] - 4, btn)


func _breach(t: float, m) -> void:
	_canvas.draw_texture(_tex["breach_mask"], Vector2.ZERO, SPACE)
	_stars(_data["stars"]["breach"], t, 0.0, 0.0, 0, _breach_mask)
	_canvas.draw_texture(_tex["breach_edge"], Vector2.ZERO, tint(STEEL_LL, m))
	for seg in [[284, 52, 277, 49], [276, 78, 269, 82], [276, 106, 268, 103], [286, 120, 280, 125]]:
		for k in 8:
			var u := k / 7.0
			_blend(int(lerpf(seg[0], seg[2], u)), int(lerpf(seg[1], seg[3], u)), tint(GRAY, m), 1.0)


func _terminal(t: float) -> void:
	var on := false
	for f in FLICKER:
		if f[0] <= t and t < f[1]:
			on = true
	if not on:
		return
	var tx0: int = CORR_TERM[0]
	var ty0: int = CORR_TERM[1]
	var tx1: int = CORR_TERM[2]
	var ty1: int = CORR_TERM[3]
	_rect(tx0 + 2, ty0 + 2, tx1 - 2, ty1 - 2, Color8(46, 6, 14))
	var lines := ["MAIN POWER", "OFFLINE"]
	for i in 2:
		_text((tx0 + tx1) / 2 - text_w(lines[i]) / 2, ty0 + 7 + 11 * i, lines[i], RED)
	for x in range(tx0 - 6, tx1 + 6):
		for y in range(ty1 + 1, ty1 + 6):
			if (x + y) % 2 == 0:
				_blend(x, y, Color8(120, 10, 30), 0.25)


func _shot_breach(t: float) -> void:
	_src_w = W
	_set_view(0, _shake("breach"))
	var light := _corridor_light(t)
	var room = light[0]
	var crew = light[1]
	_canvas.draw_texture(_tex["corridor_bg"], Vector2.ZERO, mod_color(room))
	_slab(0, room)
	_button(0.0)
	var hit := t >= T_HIT2
	if hit:
		_breach(t, room)
	var lc := t - T_CORR
	var dx_ := maxf(AHEAD_WAIT_X, AHEAD_X0 - AHEAD_V * lc)
	var dhan_walking := dx_ > AHEAD_WAIT_X
	_astro("ahead", dx_, FEET, lc * 1.4, dhan_walking, dhan_walking, -1, 0, 0, [], crew)
	var run := minf(lc, T_HIT2 - T_CORR) / (T_HIT2 - T_CORR)
	var walk := minf(lc, T_HIT2 - T_CORR) * 1.3
	var to := 13.25 + (t - T_HIT2)
	if not hit:
		_astro("survivor", lerpf(CORR_RUN["survivor"][0], CORR_RUN["survivor"][1], run), FEET, walk, true, true, -1, 0, 0, [], crew)
	else:
		_astro("survivor", 170, FEET, 0.0, false, to < 13.4, -1, 0, -1 if to < 13.6 else 0, [], crew)
	var px := lerpf(CORR_RUN["player"][0], CORR_RUN["player"][1], run)
	var p_left := true
	if hit:
		p_left = to < 13.3
		if to < 13.45:
			px = 206.5
		elif to < 14.05:
			px = lerpf(206.5, 243, ease_out((to - 13.45) / 0.6))
		else:
			px = 243 + 7 * (to - 14.05) / 1.95
	var p_top := _astro("player", px, FEET, walk, not hit, p_left, -1, 0, 0, [], crew)
	if 13.5 <= to and to < 15.4:
		_arm("player", px, p_top, 9, false, crew)
	var bx := lerpf(CORR_RUN["lost"][0], CORR_RUN["lost"][1], run)
	var rot := 0
	var lift := 0
	if hit:
		if to < 13.4:
			bx = lerpf(246.5, 262, ease_out((to - 13.25) / 0.15))
		else:
			bx = 262 + 0.5 * 33 * (to - 13.4) ** 2
		lift = int(minf(6, maxf(0, (to - 14.2) * 6)))
		if to >= 14.9:
			rot = int((to - 14.9) / 0.22) % 4 + 1
	var b_top := _astro("lost", bx, FEET, walk, not hit, true, -1, rot % 4, lift, [], crew)
	if 13.5 <= to and to < 14.9:
		_arm("lost", bx, b_top, 7, true, crew)
	if hit:
		_flow("air1", t, false)
		_flow("deb1", t, true)
	if T_HIT2 <= t and t < T_HIT2 + 0.067:
		_canvas.draw_rect(Rect2(0, 0, W, H), Color(1, 1, 1, 0.8))


func _shot_outside(t: float) -> void:
	_src_w = W
	var lt := t - T_OUT
	_canvas.draw_rect(Rect2(0, 0, W, H), SPACE)
	_stars(_data["stars"]["ext_far"], t)
	_stars(_data["stars"]["ext_near"], t)
	var p0: Texture2D = _tex["far_planet_0"]
	_blit(p0, 276 - p0.get_width() / 2, 40 - p0.get_height() / 2)
	var ox := -44 + 3 * lt
	var oy := 28.0
	_engine(ox, oy, OUT_SCALE, t)
	_blit(_tex["ship4"], ox, oy)
	# The hole: dark with the corridor's red light inside, torn edges.
	var hole: Dictionary = _data["hole"]
	var k := _base - int(hole["first_frame"])
	if k >= 0 and k < hole["pos"].size():
		var tw := int(hole["tile"][0])
		var th := int(hole["tile"][1])
		var cols := int(hole["cols"])
		var src := Rect2((k % cols) * tw, (k / cols) * th, tw, th)
		var at := Vector2(float(hole["pos"][k][0]), float(hole["pos"][k][1]))
		var pulse := 0.86 + 0.1 * sin(2 * PI * 1.6 * t)
		var pm := [pulse, pulse, pulse]
		_canvas.draw_texture_rect_region(_tex["hole_atlas"], Rect2(at, src.size), src, tint(Color8(90, 12, 28), pm))
		_canvas.draw_texture_rect_region(_tex["hole_inner_atlas"], Rect2(at, src.size), src, tint(Color8(150, 20, 44), pm))
		_canvas.draw_texture_rect_region(_tex["hole_edge_atlas"], Rect2(at, src.size), src, STEEL_LL)
	for seg in [[140, 33, 134, 28], [160, 32, 166, 27], [162, 53, 168, 58], [139, 53, 133, 57]]:
		for j in 6:
			var u := j / 5.0
			_blend(int(ox + lerpf(seg[0], seg[2], u)), int(oy + lerpf(seg[1], seg[3], u)), GRAY, 1.0)
	var hx := ox + 150
	var hy := oy + 43
	for d in _data["outside_debris"]:
		var dt := fmod(lt + float(d[2]), 1.6)
		var x := hx + float(d[0]) * dt
		var y := hy + float(d[1]) * dt
		if d[3]:
			_rect(int(x), int(y), int(x) + 1, int(y) + 1, GRAY)
		else:
			for j in 3:
				_blend(int(x) - j, int(y), Color8(175, 195, 225), 0.5 * (1.0 - j / 3.0))
	var u2 := ease_out(lt / 3.0)
	var bx := lerpf(hx + 4, 262, u2)
	var by := lerpf(hy + 6, 146, u2)
	var size := 0 if lt < 1.0 else (1 if lt < 2.1 else 2)
	var skin: String = _crew["lost"]["skin"]
	var tiny := _tiny_tex(skin, size, int(lt / 0.4) % 4)
	_blit(tiny, bx - tiny.get_width() / 2.0, by - tiny.get_height() / 2.0)


func _tiny_tex(skin: String, size: int, rot: int) -> Texture2D:
	var key := "tiny/%s/%d/%d" % [skin, size, rot]
	if _frames.has(key):
		return _frames[key]
	var img: Image = _tex["tiny_%s_%d" % [skin, size]].get_image()
	for _r in rot:
		img.rotate_90(COUNTERCLOCKWISE)
	var tex := ImageTexture.create_from_image(img)
	_frames[key] = tex
	return tex


func _shot_seal(tf: float) -> void:
	_src_w = W
	var t := tf - SEAL_OFF
	_set_view(0, _shake("seal"))
	var light := _corridor_light(t)
	var room = light[0]
	var crew = light[1]
	_canvas.draw_texture(_tex["corridor_bg"], Vector2.ZERO, mod_color(room))
	_slab(t, room)
	var slammed := t >= 21.45
	if slammed:  # the breach side goes dark behind the door
		var dark := minf(0.6, (t - 21.5) / 1.5 * 0.6) if t > 21.5 else 0.0
		_canvas.draw_rect(Rect2(CORR_DOOR[1], 0, W - CORR_DOOR[1], H), Color(0, 0, 0, dark))
	_breach(t, room)
	if slammed and t > 21.5:
		var dark2 := minf(0.6, (t - 21.5) / 1.5 * 0.6)
		_canvas.draw_texture(_tex["breach_mask"], Vector2.ZERO, Color(0, 0, 0, dark2 * 0.7))
	_button(t)
	_terminal(t)
	var breath := fmod(t - 21.8, 3.2) if t >= 21.8 else 0.0
	var bob := 1 if (0.2 < breath and breath < 1.1) else 0
	# Dhan waits by the locker, facing back toward the rescue, then makes room for Johnny.
	if tf < T_LOCKER_LOOK:
		_astro("ahead", AHEAD_WAIT_X, FEET, 0.0, false, false, -1, 0, bob, [], crew)
	if tf >= T_LOCKER_LOOK:
		_draw_locker_look(tf, crew, bob)
	elif t < 19.65:
		var ax := lerpf(170, 226, ease_io((t - 19.0) / 0.65))
		var a_top := _astro("survivor", ax, FEET, t, true, false, -1, 0, 0, [], crew)
		var pxx := 250 + 6 * (t - 19.0)
		var p_top := _astro("player", pxx, FEET, 0.0, false, t >= 19.35, -1, 0, 0, [], crew)
		if t >= 19.35:
			_arm("survivor", ax, a_top, 10, false, crew)
		if t >= 19.4:
			_arm("player", pxx, p_top, 10, true, crew)
	elif t < 21.0:
		var u := ease_io((t - 19.7) / 1.3) if t >= 19.7 else 0.0
		var ax := lerpf(226, 90, u)
		var pxx := lerpf(254, 118, u)
		var a_top := _astro("survivor", ax, FEET, -(t - 19.7), t >= 19.7, false, -1, 0, 0, [], crew)
		var p_top := _astro("player", pxx, FEET, 0.0, false, true, -1, 0, 1 if (19.8 < t and t < 20.8) else 0, [], crew)
		_arm("survivor", ax, a_top, 10, false, crew)
		_arm("player", pxx, p_top, 10, true, crew)
	else:
		var ax := 90.0
		var pxx := 118.0
		var a_left := 24.3 <= t and t < 25.3
		var p_left := (24.3 <= t and t < 24.9) or t >= JOHNNY_TURNS - SEAL_OFF
		var p_walk := 24.9 <= t and t < 25.3
		if t >= 24.9:
			pxx = lerpf(118, 124, minf(1.0, (t - 24.9) / 0.4))
		_astro("survivor", ax, FEET, 0.0, false, a_left, -1, 0, bob, [], crew)
		var p_top := _astro("player", pxx, FEET, t, p_walk, p_left, -1, 0, bob, [], crew)
		if 21.15 <= t and t < 21.45:
			_arm("player", pxx, p_top, 10, false, crew)
	if not slammed:
		_flow("air2", t, false)
		_flow("deb2", t, true)
	else:
		_flow("air2", t, false, CORR_DOOR[1])
		var dt := t - 21.45
		if dt < 0.5:  # dust where the door hits the floor
			for k in 6:
				for side in [-1, 1]:
					var x := int((CORR_DOOR[0] + CORR_DOOR[1]) / 2.0 + side * (6 + k * 3 + dt * 30))
					_blend(x, int(130 - k % 2 - dt * 6), GRAY, 0.7 * (1 - dt * 2))
	if t >= 21.6:  # helmet vignette, breathing with the player
		var strength := minf(0.5, (t - 21.6) * 0.5) + (0.04 if bob else 0.0)
		_canvas.draw_texture(_tex["vignette"], Vector2.ZERO, Color(1, 1, 1, strength))


## After Johnny's line: Johnny steps up to the locker, the others make room; all face it.
func _locker_look_x(role: String, film_time: float) -> float:
	var e: Array = LOCKER_LOOK[role]
	return lerpf(float(e[0]), float(e[1]), ease_io((film_time - T_LOCKER_LOOK - float(e[2])) / float(e[3])))


func _draw_locker_look(film_time: float, crew, bob: int) -> void:
	for role in ["ahead", "survivor", "player"]:
		var e: Array = LOCKER_LOOK[role]
		var start := T_LOCKER_LOOK + float(e[2])
		var walking := start <= film_time and film_time < start + float(e[3])
		var left := (float(e[1]) < float(e[0])) if walking else true
		_astro(role, _locker_look_x(role, film_time), FEET, film_time * 1.4, walking, left, -1, 0,
			0 if walking else bob, [], crew)


## Draws whatever frame the film is on.
class Canvas extends Node2D:
	var film

	func _draw() -> void:
		if film != null and film.is_ready():
			film.draw_frame()
