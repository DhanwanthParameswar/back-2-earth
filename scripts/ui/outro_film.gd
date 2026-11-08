extends Control
## The ending film, drawn live like the opening (intro_film.gd): 320x180 pixel art in a
## SubViewport, scaled up with nearest filtering, using the opening's stars, font, ship
## and planet art and the menu's spinning Earth and logo.
##
##   1. The shuttle drops out of the Wayfarer; asteroids hit the ship; it breaks apart.
##   2. Aboard the shuttle: a short exchange that depends on the ending.
##   3. "11 DAYS LATER", dithered in like "THE YEAR 2126".
##   4. Earth grows in the window; the shuttle arrives. Fade to black.
##   5. The logo. 6. Credits roll (data/credits.json). Then `finished`.
##
## E / Enter / Space / Esc / click skips to the end, after a short grace period.

signal finished

const ART := "res://assets/intro/"
const MENU := "res://assets/menu/"
const DATA_PATH := "res://data/intro_film.json"
const CREDITS_PATH := "res://data/credits.json"
const EARTH_SHADER := preload("res://scripts/ui/menu_earth.gdshader")
const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Haptics = preload("res://scripts/core/haptics.gd")
const W := 320
const H := 180
const LB := 16
const LB_BOTTOM := 28
const CPS := 26.0

# Palette (the opening's).
const SPACE := Color8(5, 6, 20)
const STEEL_D := Color8(40, 44, 64)
const STEEL_L := Color8(95, 92, 112)
const WHITE := Color8(255, 241, 232)
const GRAY := Color8(194, 195, 199)
const CYAN := Color8(61, 240, 255)
const BLUE := Color8(41, 173, 255)
const AMBER := Color8(255, 163, 0)
const YELLOW := Color8(255, 236, 39)
const RED := Color8(255, 0, 77)
const STAR_COLORS := [Color8(64, 72, 112), Color8(150, 160, 200), Color8(255, 241, 232)]
const BAYER4 := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
const SPEAKER_COLORS := {"AARON": Color8(224, 173, 101), "DHAN": Color8(177, 138, 218), "SHUTTLE": RED}

## Aboard the shuttle, after the Wayfarer goes (ending id -> [speaker, line]).
const DIALOGUE := {
	"everyone_home": [["DHAN", "THERE GOES THE WAYFARER."], ["AARON", "EVERY ONE OF KIEN'S SAMPLES IS IN THE BACK."], ["DHAN", "SO ARE WE. MOSTLY IN ONE PIECE."]],
	"what_he_left": [["AARON", "JUST THE PRIORITY RACK."], ["AARON", "IT'S THE PART HE CARED ABOUT MOST."], ["DHAN", "THEN WE BROUGHT SOME OF HIM HOME."]],
	"kept_each_other": [["AARON", "SIX MONTHS OF WORK. GONE WITH HER."], ["DHAN", "WE'RE NOT."], ["AARON", "...HE'D HAVE UNDERSTOOD."]],
	"barely": [["SHUTTLE", "MEDICAL ALERT. SEAT TWO."], ["DHAN", "...WORTH IT?"], ["AARON", "ASK ME WHEN YOU CAN WALK."]],
	"two_came_home": [["AARON", "..."], ["AARON", "I KEEP LOOKING AT HIS SEAT."], ["AARON", "LET'S JUST GET HOME, JOHNNY."]],
}

# Shot boundaries (seconds); the dialogue's length sets the rest (_plan()).
const T_DROP := 0.4
const T_SPLIT := 5.4
const T_EXT_END := 7.6
const HIT_TIMES := [1.5, 2.1, 2.6, 3.05, 3.5, 3.9, 4.3, 4.75, 5.1]
const SKIP_GRACE := 0.6

var ending_id := "everyone_home"
var dhan_promise := false      # Johnny answered Dhan's "don't wait for me" (and Dhan lived)
var lines: Array = []          # [speaker, text] actually shown
var t := 0.0
var _starts: Array = []        # when each line starts
var t_later := 0.0
var t_earth := 0.0
var t_logo := 0.0
var t_credits := 0.0
var t_end := 0.0
var _data := {}
var _tex := {}
var _glyph := {}
var _hits: Array = []          # [{t, at, from, rock}]
var _debris: Array = []
var _viewport: SubViewport
var _back: Node2D
var _front: Node2D
var _earth: ColorRect
var _title: TextureRect
var _title_glow: TextureRect
var _credits: VBoxContainer
var _hint: Label
var _cover: ColorRect
var _playing := false
var _done := false
var _sounds_done := {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = Vector2(640, 360)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	_data = parsed if parsed is Dictionary else {}
	for name in ["ship2", "far_planet_0", "far_planet_1", "far_planet_2"]:
		if ResourceLoader.exists(ART + name + ".png"): _tex[name] = load(ART + name + ".png")
	for name in ["rock_a", "rock_b", "rock_c", "hull", "canister"]:
		if ResourceLoader.exists(MENU + name + ".png"): _tex[name] = load(MENU + name + ".png")
	for ch in _data.get("font", {}):
		var rows: PackedStringArray = str(_data["font"][ch]).split(" ")
		var img := Image.create(5, 7, false, Image.FORMAT_RGBA8)
		for y in 7:
			for x in 5:
				if rows[y][x] == "1": img.set_pixel(x, y, Color.WHITE)
		_glyph[ch] = ImageTexture.create_from_image(img)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(W, H)
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_back = Layer.new()
	_back.film = self
	_back.front = false
	_viewport.add_child(_back)
	_earth = ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = EARTH_SHADER
	if ResourceLoader.exists(MENU + "earth_map.png"): mat.set_shader_parameter("world_map", load(MENU + "earth_map.png"))
	_earth.material = mat
	_earth.visible = false
	_viewport.add_child(_earth)
	for name in ["title", "title_two"]:
		var r := TextureRect.new()
		if ResourceLoader.exists(MENU + name + ".png"): r.texture = load(MENU + name + ".png")
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.visible = false
		if name == "title_two":
			var add := CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			r.material = add
			_title_glow = r
		else:
			_title = r
		_viewport.add_child(r)
	_front = Layer.new()
	_front.film = self
	_front.front = true
	_viewport.add_child(_front)
	var view := TextureRect.new()
	view.texture = _viewport.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size = size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_build_credits()
	_hint = Label.new()
	_hint.text = "E / click  skip"
	_hint.position = Vector2(440, 8)
	_hint.size = Vector2(190, 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.75, 0.75))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_cover = ColorRect.new()
	_cover.color = Color(0, 0, 0, 0)
	_cover.size = size
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	_plan()

## Everything that depends on the ending: the lines and the shot timings.
func _plan() -> void:
	lines = DIALOGUE.get(ending_id, DIALOGUE.kept_each_other).duplicate()
	if dhan_promise and ending_id != "two_came_home":
		lines.insert(1, ["DHAN", "I HEARD WHAT YOU SAID BACK THERE, CAPTAIN."])
	_starts.clear()
	var at := T_EXT_END + 0.8
	for line in lines:
		_starts.append(at)
		at += 0.8 + str(line[1]).length() / CPS + 1.5
	t_later = at + 0.3
	t_earth = t_later + 3.6
	t_logo = t_earth + 8.0
	t_credits = t_logo + 5.6
	t_end = t_credits + (_credits.get_combined_minimum_size().y + 380.0) / 24.0 if _credits != null else t_credits + 30.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2126
	var rocks := ["rock_a", "rock_b", "rock_c"]
	_hits.clear()
	for i in HIT_TIMES.size():
		var target := Vector2(rng.randf_range(68, 168), rng.randf_range(66, 98))
		_hits.append({"t": HIT_TIMES[i], "at": target, "from": target + Vector2(rng.randf_range(-260, -160), rng.randf_range(-150, -60)), "rock": rocks[i % 3]})
	_debris.clear()
	for i in 70:
		_debris.append([Vector2(rng.randf_range(80, 160), rng.randf_range(70, 96)), Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6, 48), rng.randi_range(0, 3)])

## Configure before adding to the tree, or call _plan() again after changing these.
func setup(id: String, promised: bool) -> void:
	ending_id = id
	dhan_promise = promised
	if is_inside_tree(): _plan()

func play() -> void:
	_plan()
	_playing = true
	t = 0.0

func is_running() -> bool:
	return _playing and not _done

func length() -> float:
	return t_end

func set_time(seconds: float) -> void:
	t = seconds
	_update_nodes()
	_back.queue_redraw()
	_front.queue_redraw()

func _process(delta: float) -> void:
	if not is_running(): return
	var before := t
	set_time(t + delta)
	_cues(before, t)
	_hint.visible = t > SKIP_GRACE and t < t_credits
	if t >= t_end: skip()

## Sounds and rumble as the picture reaches them.
func _cues(before: float, now: float) -> void:
	for h in _hits:
		var at: float = h.t
		if before < at and at <= now:
			Sfx.play("hit", -6)
			Haptics.play("thud")
	if before < T_SPLIT and T_SPLIT <= now:
		Sfx.play("launch", -2)
		Haptics.play("breach")
	if before < t_earth and t_earth <= now:
		Sfx.start_ambient()

func skip() -> void:
	if _done: return
	_done = true
	_hint.hide()
	var tw := create_tween()
	tw.tween_property(_cover, "color:a", 1.0, 0.5)
	tw.tween_callback(func(): finished.emit())

func _input(event: InputEvent) -> void:
	if not is_running(): return
	var pressed := false
	if event is InputEventKey: pressed = event.is_pressed() and not event.is_echo()
	elif event is InputEventMouseButton or event is InputEventJoypadButton: pressed = event.is_pressed()
	if not pressed: return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("toggle_mute"):
		Settings.toggle_mute()
		return
	if t < SKIP_GRACE: return
	skip()

# --- Nodes that aren't plain drawing: Earth, logo, credits ----------------------------------

func _update_nodes() -> void:
	var show_earth := false
	var earth_size := 0.0
	var earth_center := Vector2(160, 90)
	var earth_alpha := 1.0
	if t >= t_earth and t < t_logo - 1.0:
		var u := clampf((t - t_earth) / (t_logo - 1.0 - t_earth), 0.0, 1.0)
		show_earth = true
		earth_size = lerpf(34.0, 170.0, _ease(u))
		earth_center = Vector2(lerpf(214, 186, u), lerpf(76, 96, u))
	elif t >= t_logo and t < t_credits:
		show_earth = true
		earth_size = 50.0
		earth_center = Vector2(160, 78)
		earth_alpha = _logo_alpha()
	_earth.visible = show_earth
	if show_earth:
		var px := roundf(earth_size)
		_earth.size = Vector2(px, px)
		_earth.position = (earth_center - Vector2(px, px) / 2.0).round()
		_earth.modulate.a = earth_alpha
		var mat: ShaderMaterial = _earth.material
		mat.set_shader_parameter("grid", px)
		mat.set_shader_parameter("planet_radius", px * 0.46)
	var logo := t >= t_logo and t < t_credits
	for r in [_title, _title_glow]:
		r.visible = logo and r.texture != null
		if r.visible:
			r.position = Vector2(160 - r.texture.get_width() / 2.0, 66).round()
			r.modulate.a = _logo_alpha() * (0.5 + 0.5 * sin(t * 2.0) if r == _title_glow else 1.0)
	_credits.visible = t >= t_credits
	if _credits.visible:
		_credits.position.y = 360.0 - (t - t_credits) * 24.0

func _logo_alpha() -> float:
	return clampf((t - t_logo - 0.8) / 1.2, 0.0, 1.0) * clampf((t_credits - 0.6 - t) / 1.0, 0.0, 1.0)

func _build_credits() -> void:
	_credits = VBoxContainer.new()
	_credits.position = Vector2(0, 360)
	_credits.custom_minimum_size = Vector2(640, 0)
	_credits.add_theme_constant_override("separation", 6)
	_credits.visible = false
	add_child(_credits)
	var data = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH)) if FileAccess.file_exists(CREDITS_PATH) else {}
	if not data is Dictionary: data = {}
	_credit(str(data.get("title", "BACK2EARTH")), 22, UiStyle.CYAN_BRIGHT)
	_credit(str(data.get("subtitle", "")), 10, UiStyle.MUTED)
	_credit("", 18)
	_credit("CAST", 12, UiStyle.CYAN)
	for line in ["JOHNNY · the pilot · you", "AARON · the researcher", "DHAN · the engineer", "KIEN · who didn't come home", "M.A.R.V.I.S. · as itself"]:
		_credit(line, 11, UiStyle.TEXT)
	for section in data.get("sections", []):
		if not section is Dictionary: continue
		_credit("", 12)
		_credit(str(section.get("heading", "")), 12, UiStyle.CYAN)
		for line in section.get("lines", []):
			_credit(str(line), 11, UiStyle.TEXT)
	_credit("", 40)
	_credit("THANK YOU FOR PLAYING", 14, UiStyle.AMBER)

func _credit(text: String, font_size: int, color := UiStyle.TEXT) -> void:
	var l := UiStyle.label(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(640, font_size + 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits.add_child(l)

# --- Drawing ----------------------------------------------------------------------------

func _ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)

func _shake() -> Vector2:
	var k := 0.0
	for h in _hits:
		var a: float = t - float(h.t)
		if a >= 0.0 and a < 0.3: k = maxf(k, 2.0 * (1.0 - a / 0.3))
	var b := t - T_SPLIT
	if b >= 0.0 and b < 0.9: k = maxf(k, 4.0 * (1.0 - b / 0.9))
	if k <= 0.0: return Vector2.ZERO
	return Vector2(roundf(sin(t * 91.0) * k), roundf(cos(t * 73.0) * k))

func draw_back(c: CanvasItem) -> void:
	c.draw_rect(Rect2(0, 0, W, H), SPACE if t < t_logo else Color.BLACK)
	if t < T_EXT_END:
		c.draw_set_transform(_shake())
		_stars(c, "ext_far", -2.0 * t)
		_stars(c, "ext_near", -5.0 * t)
		_planets(c)
		_station(c)
		_asteroids(c)
		_shuttle(c, _shuttle_pos(), 1, true)
		c.draw_set_transform(Vector2.ZERO)
	elif t < t_later:
		_stars(c, "ext_far", -30.0 * t)
		_stars(c, "ext_near", -70.0 * t)
		_shuttle(c, Vector2(150, 78 + roundf(sin(t * 1.7) * 2.0)), 2, true)
	elif t < t_earth:
		pass  # the "later" card is on the front layer, over black
	elif t < t_logo:
		_stars(c, "ext_far", -1.5 * (t - t_earth))
		_stars(c, "ext_near", -4.0 * (t - t_earth))
		var u := clampf((t - t_earth) / (t_logo - 1.0 - t_earth), 0.0, 1.0)
		# Atmosphere glow behind the planet.
		var r := lerpf(34.0, 170.0, _ease(u)) * 0.5
		var centre := Vector2(lerpf(214, 186, u), lerpf(76, 96, u))
		for k in 4:
			c.draw_circle(centre, r + 2.0 + k * 2.0, Color(BLUE, 0.10 - k * 0.02))

func draw_front(c: CanvasItem) -> void:
	if t >= t_earth and t < t_logo:
		var u := clampf((t - t_earth) / (t_logo - 1.0 - t_earth), 0.0, 1.0)
		var at := Vector2(lerpf(40, 176, _ease(u)), lerpf(150, 100, _ease(u)))
		_shuttle(c, at, 2 if u < 0.55 else 1, u < 0.92)
		if t > t_earth + 4.2: _caption(c, "SHUTTLE", "EARTH ORBIT. WELCOME HOME.", t - (t_earth + 4.2))
	if t >= T_EXT_END and t < t_later:
		_letterbox(c)
		for i in lines.size():
			var s0: float = _starts[i]
			var s1: float = _starts[i + 1] if i + 1 < lines.size() else t_later
			if t >= s0 and t < s1 - 0.2: _caption(c, str(lines[i][0]), str(lines[i][1]), t - s0)
	if t >= t_later and t < t_earth:
		c.draw_rect(Rect2(0, 0, W, H), Color.BLACK)
		_later_card(c, t - t_later)
	# Flash when the Wayfarer breaks up; fades between shots.
	var f := t - T_SPLIT
	if f >= 0.0 and f < 0.35: c.draw_rect(Rect2(0, 0, W, H), Color(WHITE, 0.9 * (1.0 - f / 0.35)))
	var fade := 0.0
	fade = maxf(fade, 1.0 - clampf(t / 0.6, 0.0, 1.0))
	fade = maxf(fade, _edge(T_EXT_END, 0.5))
	fade = maxf(fade, _edge(t_earth, 0.6))
	if t >= t_logo - 1.2 and t < t_logo: fade = maxf(fade, clampf((t - (t_logo - 1.2)) / 1.0, 0.0, 1.0))
	if t >= t_logo and t < t_credits:
		var a := _logo_alpha()
		if a > 0.0: _text(c, 160 - _text_w("MADE IN 24 HOURS AT UBHACKS 2026") / 2, 112, "MADE IN 24 HOURS AT UBHACKS 2026", Color(GRAY, a))
	if t >= t_credits: c.draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	if fade > 0.0: c.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, fade))

## A dip to black centred on a shot change.
func _edge(at: float, half: float) -> float:
	var d := absf(t - at)
	return clampf(1.0 - d / half, 0.0, 1.0)

func _stars(c: CanvasItem, list: String, offx: float) -> void:
	for s in _data.get("stars", {}).get(list, []):
		var x := int(fposmod(float(s[0]) + offx, W))
		var y := int(s[1])
		var b := int(s[2])
		if b == 2 and sin(t * 3.0 + float(s[3])) < -0.6: b = 1
		c.draw_rect(Rect2(x, y, 1, 1), STAR_COLORS[b])

func _planets(c: CanvasItem) -> void:
	for k in 3:
		var tex: Texture2D = _tex.get("far_planet_%d" % k)
		if tex == null or _data.get("far_planets", []).size() <= k: continue
		var p: Array = _data.far_planets[k]
		c.draw_texture(tex, Vector2(int(p[0]) - tex.get_width() / 2, int(p[1]) - tex.get_height() / 2))

const STATION := Vector2(54, 58)

## The Wayfarer: whole until the big hit, then two halves drifting apart, burning.
func _station(c: CanvasItem) -> void:
	var tex: Texture2D = _tex.get("ship2")
	if tex == null: return
	var drift := Vector2(roundf(sin(t * 0.8)), 0)
	if t < T_SPLIT:
		c.draw_texture(tex, STATION + drift)
	else:
		var a := t - T_SPLIT
		var half := tex.get_width() / 2.0
		var dark := Color(0.55 + 0.45 * maxf(0.0, 1.0 - a), 0.5, 0.5)
		c.draw_texture_rect_region(tex, Rect2(STATION + Vector2(-a * 9.0, -a * 4.0), Vector2(half, tex.get_height())), Rect2(0, 0, half, tex.get_height()), dark)
		c.draw_texture_rect_region(tex, Rect2(STATION + Vector2(half + a * 11.0, a * 5.0), Vector2(half, tex.get_height())), Rect2(half, 0, half, tex.get_height()), dark)
		for d in _debris:
			var p: Vector2 = d[0] + d[1] * a
			c.draw_rect(Rect2(p.round(), Vector2.ONE * (2 if int(d[2]) == 0 else 1)), [STEEL_L, GRAY, AMBER, STEEL_D][int(d[2])])
		for k in 3:  # fires along the break
			var at := STATION + Vector2(half + 2.0, 12.0 + k * 10.0) + Vector2(a * (k - 1) * 3.0, 0)
			_blast(c, at, fmod(a * 1.3 + k * 0.33, 1.0), 6.0)
	# Burning wounds where rocks hit, until the break-up.
	for h in _hits:
		var age: float = t - float(h.t)
		if age >= 0.0 and t < T_SPLIT + 0.4:
			_blast(c, h.at, minf(age, 1.0) if age < 1.0 else 0.6 + 0.2 * sin(t * 9.0 + h.at.x), 9.0)
	if t >= T_SPLIT:
		var b := t - T_SPLIT
		if b < 1.6: _blast(c, STATION + Vector2(62, 24), b / 1.6, 44.0)

func _asteroids(c: CanvasItem) -> void:
	for h in _hits:
		var u: float = (t - (float(h.t) - 0.9)) / 0.9
		if u < 0.0 or u >= 1.0: continue
		var p: Vector2 = h.from.lerp(h.at, u)
		var tex: Texture2D = _tex.get(h.rock)
		for k in 6:  # streak behind it
			var q: Vector2 = p - (h.at - h.from).normalized() * (k * 3.0)
			c.draw_rect(Rect2(q.round(), Vector2.ONE), Color(AMBER, 0.5 - k * 0.08))
		if tex != null: c.draw_texture(tex, (p - tex.get_size() / 2.0).round())

## An explosion at `at`: u 0..1 grows a fireball and smoke ring; r is its full size.
func _blast(c: CanvasItem, at: Vector2, u: float, r: float) -> void:
	u = clampf(u, 0.0, 1.0)
	var rr := 1.0 + r * sqrt(u)
	c.draw_circle(at, rr * 1.15, Color(STEEL_D, 0.5 * (1.0 - u)))
	c.draw_circle(at, rr, Color(RED, 0.8 * (1.0 - u)))
	c.draw_circle(at, rr * 0.7, Color(AMBER, 0.9 * (1.0 - u)))
	c.draw_circle(at, rr * 0.4, Color(YELLOW, 1.0 - u))
	if u < 0.25: c.draw_circle(at, rr * 0.25, WHITE)

func _shuttle_pos() -> Vector2:
	if t < T_DROP: return Vector2(-40, -40)
	var a := t - T_DROP
	if a < 1.0: return Vector2(112, 104 + a * 12.0).round()  # dropping out of the hatch
	var b := a - 1.0
	return Vector2(112 + b * b * 7.5 + b * 8.0, 116 - b * 6.0).round()

## The shuttle, drawn in pixels (scale s): hull, canopy, fin, engine flame.
func _shuttle(c: CanvasItem, at: Vector2, s: int, engine: bool) -> void:
	if at.x < -40: return
	var x := at.x
	var y := at.y
	if engine:
		var n := 6 + int(t * 30.0) % 3
		for k in n:
			c.draw_rect(Rect2(x - (k + 1) * s, y + s, s, 2 * s), AMBER if k > 1 else YELLOW)
	c.draw_rect(Rect2(x, y, 12 * s, 4 * s), GRAY)
	c.draw_rect(Rect2(x, y + 3 * s, 12 * s, s), STEEL_L)
	c.draw_rect(Rect2(x + 12 * s, y + s, 2 * s, 2 * s), GRAY)
	c.draw_rect(Rect2(x + 8 * s, y + s, 3 * s, s), CYAN)
	c.draw_rect(Rect2(x + s, y - 2 * s, 3 * s, 2 * s), STEEL_L)
	c.draw_rect(Rect2(x + 4 * s, y + 2 * s, 2 * s, s), RED)

func _letterbox(c: CanvasItem) -> void:
	c.draw_rect(Rect2(0, 0, W, LB), Color.BLACK)
	c.draw_rect(Rect2(0, H - LB_BOTTOM, W, LB_BOTTOM), Color.BLACK)

## A typed caption in the bottom bar: SPEAKER: TEXT, wrapped to two rows.
func _caption(c: CanvasItem, speaker: String, text: String, age: float) -> void:
	_letterbox(c)
	var n := int(age * CPS)
	var rows := _wrap(speaker + ": " + text, 50)
	var top := H - LB_BOTTOM + (LB_BOTTOM - (9 * rows.size() - 2)) / 2
	var shown := 0
	for k in rows.size():
		var row: String = rows[k]
		var x := W / 2 - _text_w(row) / 2
		var typed := clampi(n - shown, 0, row.length())
		shown += row.length() + 1
		if k == 0:
			var spk := speaker + ":"
			_text(c, x, top, spk.substr(0, mini(typed, spk.length())), SPEAKER_COLORS.get(speaker, CYAN))
			if typed > spk.length():
				_text(c, x + 6 * (spk.length()), top, row.substr(spk.length(), typed - spk.length()), WHITE)
		else:
			_text(c, x, top + 9 * k, row.substr(0, typed), WHITE)

func _wrap(s: String, width: int) -> Array:
	var rows: Array = []
	var cur := ""
	for word in s.split(" "):
		if cur.length() + word.length() + 1 > width and cur != "":
			rows.append(cur)
			cur = word
		else:
			cur = word if cur == "" else cur + " " + word
	if cur != "": rows.append(cur)
	return rows

func _later_card(c: CanvasItem, a: float) -> void:
	var text := "11 DAYS LATER"
	var kk := 3
	var tw := (6 * text.length() - 1) * kk
	var x0 := (W - tw) / 2
	var appear := a / 0.8
	var leave := (a - 2.6) / 0.8
	for i in text.length():
		if text[i] == " ": continue
		for gy in 7:
			for gx in 5:
				if not _glyph_on(text[i], gx, gy): continue
				for sy in kk:
					for sx in kk:
						var x := x0 + 6 * kk * i + gx * kk + sx
						var y := 80 + gy * kk + sy
						var th: float = BAYER4[(y / 2) % 4][(x / 2) % 4] / 16.0
						if th < appear and th >= leave:
							c.draw_rect(Rect2(x, y, 1, 1), WHITE)

func _glyph_on(ch: String, gx: int, gy: int) -> bool:
	var rows: PackedStringArray = str(_data.get("font", {}).get(ch, "00000 00000 00000 00000 00000 00000 00000")).split(" ")
	return rows[gy][gx] == "1"

func _text(c: CanvasItem, x: int, y: int, s: String, color: Color) -> void:
	s = s.to_upper()
	for i in s.length():
		var g: Texture2D = _glyph.get(s[i])
		if g != null and s[i] != " ":
			c.draw_texture_rect(g, Rect2(x + 6 * i, y, 5, 7), false, color)

func _text_w(s: String) -> int:
	return 6 * s.length() - 1

class Layer extends Node2D:
	var film
	var front := false

	func _draw() -> void:
		if film == null: return
		if front: film.draw_front(self)
		else: film.draw_back(self)
