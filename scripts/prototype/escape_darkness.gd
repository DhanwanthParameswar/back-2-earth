extends Node2D
## Ship lighting for the escape mission. Without power the ship is dark:
##   - a small round light (about 4 x 4 tiles) always surrounds Johnny. Around it are
##     RINGS, each RING_WIDTH wide and half as bright as the one inside it, until
##     black (beams end in the same rings);
##   - F toggles a flashlight BEAM pointing the way you face (up/down/left/right);
##     it swings smoothly when you turn and widens out from your light circle;
##   - crewmates can be asked to turn on their own flashlight; it points the way
##     they walk (or the direction you asked for while they stand still);
##   - the shapes are drawn per pixel by a shader (smooth circles), and a tile is
##     lit only if there's a clear line from the light to it. The first
##     wall a ray hits is lit (including the upper half of 2-tile wall faces), and
##     nothing behind it: you see walls, never through them. Doorways stop light
##     too: you see the doorway, then the next room once you're in it;
##   - the jammed locker blocks light like a wall but shows when your light reaches it;
##   - beyond your light it's black; name labels show only within E range.
## When power comes back the overlay fades out and the whole map is visible.

const TILE := 32.0
const BASE_RADIUS := 2.0 * TILE         # the bright circle around you (~4 x 4 tiles); rings go further
const BEAM_RANGE := 5.0 * TILE          # how far a flashlight beam is fully bright
## Rings around the bright circle (and past a beam's end): each one is RING_WIDTH
## wide and RING_FACTOR as bright as the one inside it; after the last one, black.
const RING_WIDTH := 0.75 * TILE
const RING_FACTOR := 0.5
const RINGS := 3                        # 100% -> 50% -> 25% -> 12% -> black
const RING_SOFT := RING_WIDTH * 0.45   # blending between rings: smooth steps, not hard lines
const LIGHT_REACH := RINGS * RING_WIDTH # how far the rings reach past the bright part
const BEAM_HALF_ANGLE := deg_to_rad(24.0)
const BEAM_START_WIDTH := BASE_RADIUS * 0.6  # beam leaves your circle this wide: no sharp tip
const TURN_SPEED := 10.0                # how fast a beam swings to a new direction
const LABEL_RANGE := 52.0               # names show within E range (player reach 44)
const DARK_COLOR := Color(0.006, 0.007, 0.014)  # unlit = black: nothing shows beyond your light
const FADE_SECONDS := 1.5
## Map cells that stop light (walls, windows, doorways, barriers, outside the ship).
const OPAQUE := ["#", "w", "D", "B", " "]

var mission
var flashlight := false
## Direction you face (last way you moved), snapped to up/down/left/right.
var facing := Vector2.RIGHT
## Beam directions as drawn ("player" and crew ids); they swing toward their target.
var _beam_dirs := {}
var _dark := 1.0             # 1 = no power, 0 = lights on (fades between)
## Light per cell this frame (Vector2i -> 0..1). Cells not in it are dark.
var lit := {}
## Speed: walls in a byte grid (built once), line of sight cached per light cell,
## and which tiles each light can see kept in ONE small image (a pixel per tile:
## red = from you, green = Aaron, blue = Dhan), rebuilt only when a light changes tile.
## The shader draws the round light and rings per pixel, masked by that image.
var _opaque := PackedByteArray()
var _locker := {}
var _locker_clear := false
var _sight_cache := {}       # source cell -> {cell: true} visible from it (within beam range)
var _image: Image
var _texture: ImageTexture
var _material: ShaderMaterial
var _mask_key := ""
const CREW_CHANNEL := {"mara": 1, "ivo": 2}

const SHADER := """
shader_type canvas_item;
uniform vec2 rect_pos;        // world rect this overlay covers
uniform vec2 rect_size;
uniform vec2 map_px;          // the map's size in pixels (the mask covers it)
uniform vec2 me;
uniform float radius;
uniform float ring_width;
uniform float ring_factor;
uniform int rings;
uniform float ring_soft;
uniform vec4 beam0;           // xy = origin, zw = direction (zero = off): you
uniform vec4 beam1;           // Aaron
uniform vec4 beam2;           // Dhan
uniform float beam_range;
uniform float beam_spread;
uniform float start_width;
uniform vec3 dark_color;
uniform float dark;

// Full light up to `bright`, then each ring is ring_factor as bright, then black.
float ringed(float d, float bright) {
	float light = 1.0;
	for (int i = 0; i <= rings; i++) {
		float b = bright + float(i) * ring_width;
		float f = i < rings ? ring_factor : 0.0;
		light *= mix(1.0, f, smoothstep(b - ring_soft, b + ring_soft, d));
	}
	return light;
}

float beam_light(vec2 p, vec4 b) {
	if (length(b.zw) < 0.5) return 0.0;
	vec2 dir = normalize(b.zw);
	vec2 d = p - b.xy;
	float along = dot(d, dir);
	float perp = abs(d.x * dir.y - d.y * dir.x);
	float half_w = start_width + max(along, 0.0) * beam_spread;
	float side = 1.0 - smoothstep(half_w * 0.6, half_w, perp);
	float back = smoothstep(-start_width * 0.5, start_width * 0.6, along);
	return side * back * ringed(max(along, 0.0), beam_range);
}

float add(float a, float b) { return 1.0 - (1.0 - a) * (1.0 - b); }

void fragment() {
	vec2 p = rect_pos + UV * rect_size;
	vec2 m = p / map_px;
	vec3 seen = vec3(0.0);
	if (m.x >= 0.0 && m.y >= 0.0 && m.x <= 1.0 && m.y <= 1.0) seen = texture(TEXTURE, m).rgb;
	float light = ringed(distance(p, me), radius);
	light = add(light, beam_light(p, beam0));
	light *= seen.r;
	light = add(light, beam_light(p, beam1) * seen.g);
	light = add(light, beam_light(p, beam2) * seen.b);
	COLOR = vec4(dark_color, dark * (1.0 - light));
}
"""


func _ready() -> void:
	z_index = 100            # above the ship, crew and props; the HUD is a separate layer
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # the smoothing between tiles
	_dark = 0.0 if is_powered() else 1.0
	var size: Vector2i = mission.map_size
	_opaque.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			_opaque[y * size.x + x] = 1 if mission.cell_char(Vector2i(x, y)) in OPAQUE else 0
	for c in mission._locker_cells():
		_locker[c] = true
	_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	material = _material


func is_powered() -> bool:
	return mission != null and mission.state.powered()


## True while the ship is dark (flashlights matter).
func is_dark() -> bool:
	return _dark > 0.01


func toggle_flashlight() -> void:
	if not is_dark():
		return
	flashlight = not flashlight
	Sfx.play("boots", -10.0)  # a soft click


static func snap_direction(v: Vector2) -> Vector2:
	if absf(v.x) >= absf(v.y):
		return Vector2.RIGHT if v.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if v.y >= 0.0 else Vector2.UP


## The direction a beam is pointing right now ("player", "mara", "ivo").
func beam_direction(id: String) -> Vector2:
	return _beam_dirs.get(id, Vector2.ZERO)


func is_beam_on(id: String) -> bool:
	if id == "player":
		return flashlight and is_dark()
	return is_dark() and mission.crew.has(id) and mission.crew[id].light_on


## How lit a cell is right now (0..1).
func light_of(cell: Vector2i) -> float:
	return lit.get(cell, 0.0)


func _process(delta: float) -> void:
	if mission == null or mission.player == null:
		return
	_dark = move_toward(_dark, 0.0 if is_powered() else 1.0, delta / FADE_SECONDS)
	if mission.player.velocity.length() > 5.0:
		facing = snap_direction(mission.player.velocity)
	if not is_dark():
		flashlight = false
	_turn_beams(delta)
	if is_dark():
		_compute_light()
	visible = is_dark()
	queue_redraw()
	_update_labels()


func _turn_beams(delta: float) -> void:
	var weight := 1.0 - exp(-TURN_SPEED * delta) if delta > 0.0 else 1.0
	_beam_dirs["player"] = _swing(_beam_dirs.get("player", facing), facing, weight)
	for id in mission.crew.keys():
		var actor = mission.crew[id]
		if actor.light_on:
			_beam_dirs[id] = _swing(_beam_dirs.get(id, actor.facing), actor.facing, weight)
		else:
			_beam_dirs.erase(id)


static func _swing(current: Vector2, target: Vector2, weight: float) -> Vector2:
	return Vector2.from_angle(lerp_angle(current.angle(), target.angle(), weight))


# --- Line of sight ------------------------------------------------------------------

func is_opaque(cell: Vector2i) -> bool:
	var size: Vector2i = mission.map_size
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return true
	if _opaque[cell.y * size.x + cell.x] == 1:
		return true
	return not _locker_clear and _locker.has(cell)


## Clear straight line from `from` to `to` (the end cell itself may be a wall: it gets lit).
func line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var d := to - from
	var steps := maxi(absi(d.x), absi(d.y))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var c := Vector2i(roundi(from.x + d.x * t), roundi(from.y + d.y * t))
		if c != from and c != to and is_opaque(c):
			return false
	return true


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func _compute_light() -> void:
	var clear: bool = mission.state.has_flag("locker_clear")
	if clear != _locker_clear:
		_locker_clear = clear
		_sight_cache.clear()  # the hallway opened: sight lines change
	lit.clear()
	var me: Vector2 = mission.player.position + Vector2(0, -8)
	_add_circle(me, BASE_RADIUS)
	if flashlight:
		_add_beam(me, _beam_dirs.get("player", facing))
	for id in mission.crew.keys():
		var actor = mission.crew[id]
		if actor.light_on and _beam_dirs.has(id):
			_add_beam(actor.position + Vector2(0, -8), _beam_dirs[id])


## Everything visible from a cell, worked out once per cell (walls don't move).
func _sight(src: Vector2i) -> Dictionary:
	if _sight_cache.has(src):
		return _sight_cache[src]
	var seen := {}
	var r := ceili((BEAM_RANGE + LIGHT_REACH) / TILE) + 1
	for y in range(src.y - r, src.y + r + 1):
		for x in range(src.x - r, src.x + r + 1):
			var c := Vector2i(x, y)
			if line_of_sight(src, c):
				seen[c] = true
				if is_opaque(c) and is_opaque(c + Vector2i.UP) and mission.cell_char(c + Vector2i.UP) != " ":
					seen[c + Vector2i.UP] = true  # upper half of a 2-tile wall face
	if _sight_cache.size() > 400:
		_sight_cache.clear()
	_sight_cache[src] = seen
	return seen


func _add_circle(origin: Vector2, radius: float) -> void:
	var seen := _sight(_cell(origin))
	for c in seen.keys():
		var dist := origin.distance_to(Vector2(c) * TILE + Vector2(TILE, TILE) / 2.0)
		var amount := ringed(dist, radius)
		if amount > 0.0:
			_add(c, amount)


func _add_beam(origin: Vector2, dir: Vector2) -> void:
	var seen := _sight(_cell(origin))
	var spread := tan(BEAM_HALF_ANGLE)
	for c in seen.keys():
		var v: Vector2 = Vector2(c) * TILE + Vector2(TILE, TILE) / 2.0 - origin
		var along := v.dot(dir)
		if along < -BEAM_START_WIDTH * 0.5 or along > BEAM_RANGE + LIGHT_REACH:
			continue
		var perp := absf(v.cross(dir))
		var half_w := BEAM_START_WIDTH + maxf(along, 0.0) * spread
		if perp > half_w:
			continue
		# Same shape as the shader: soft sides, bright to BEAM_RANGE, then rings.
		var side := 1.0 - smoothstep(half_w * 0.6, half_w, perp)
		var reach := ringed(maxf(along, 0.0), BEAM_RANGE)
		var back := smoothstep(-BEAM_START_WIDTH * 0.5, BEAM_START_WIDTH * 0.6, along)
		_add(c, side * back * reach)


## Full light (1) up to `bright`, then rings: each RING_WIDTH wide and RING_FACTOR
## as bright as the one inside it; black after the last ring. Matches the shader.
static func ringed(d: float, bright: float) -> float:
	var light := 1.0
	for i in RINGS + 1:
		var b := bright + i * RING_WIDTH
		var f := RING_FACTOR if i < RINGS else 0.0
		light *= lerpf(1.0, f, smoothstep(b - RING_SOFT, b + RING_SOFT, d))
	return light


func _add(c: Vector2i, amount: float) -> void:
	lit[c] = 1.0 - (1.0 - lit.get(c, 0.0)) * (1.0 - amount)


# --- Drawing -------------------------------------------------------------------------

## The dark overlay: one rectangle over the map (and well past its edges) drawn by
## the shader, with the per-tile sight image as its texture (linear filtering gives
## soft edges where walls stop the light).
func _draw() -> void:
	if not is_dark():
		return
	_update_mask()
	var size: Vector2i = mission.map_size
	var m := Vector2(size) * TILE
	var pad := 3000.0
	var rect := Rect2(-pad, -pad, m.x + 2.0 * pad, m.y + 2.0 * pad)
	var me: Vector2 = mission.player.position + Vector2(0, -8)
	_material.set_shader_parameter("rect_pos", rect.position)
	_material.set_shader_parameter("rect_size", rect.size)
	_material.set_shader_parameter("map_px", m)
	_material.set_shader_parameter("me", me)
	_material.set_shader_parameter("radius", BASE_RADIUS)
	_material.set_shader_parameter("ring_width", RING_WIDTH)
	_material.set_shader_parameter("ring_factor", RING_FACTOR)
	_material.set_shader_parameter("rings", RINGS)
	_material.set_shader_parameter("ring_soft", RING_SOFT)
	_material.set_shader_parameter("beam_range", BEAM_RANGE)
	_material.set_shader_parameter("beam_spread", tan(BEAM_HALF_ANGLE))
	_material.set_shader_parameter("start_width", BEAM_START_WIDTH)
	_material.set_shader_parameter("dark_color", Vector3(DARK_COLOR.r, DARK_COLOR.g, DARK_COLOR.b))
	_material.set_shader_parameter("dark", _dark)
	_material.set_shader_parameter("beam0", _beam_uniform(me, "player") if flashlight else Vector4.ZERO)
	for id in CREW_CHANNEL:
		var on: bool = mission.crew.has(id) and mission.crew[id].light_on and _beam_dirs.has(id)
		_material.set_shader_parameter("beam%d" % CREW_CHANNEL[id],
			_beam_uniform(mission.crew[id].position + Vector2(0, -8), id) if on else Vector4.ZERO)
	draw_texture_rect(_texture, rect, false)


func _beam_uniform(origin: Vector2, id: String) -> Vector4:
	var d: Vector2 = _beam_dirs.get(id, facing)
	return Vector4(origin.x, origin.y, d.x, d.y)


## Which tiles each light can see (red = you, green = Aaron, blue = Dhan). Only
## rebuilt when a light moves to another tile or turns on/off.
func _update_mask() -> void:
	var sources := {0: _cell(mission.player.position + Vector2(0, -8))}
	for id in CREW_CHANNEL:
		if mission.crew.has(id) and mission.crew[id].light_on:
			sources[CREW_CHANNEL[id]] = _cell(mission.crew[id].position + Vector2(0, -8))
	var key := str(sources) + str(_locker_clear)
	if key == _mask_key:
		return
	_mask_key = key
	_image.fill(Color(0, 0, 0, 1))
	var size: Vector2i = mission.map_size
	for ch in sources:
		for c in _sight(sources[ch]).keys():
			if c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y:
				var px := _image.get_pixel(c.x, c.y)
				px[ch] = 1.0
				_image.set_pixel(c.x, c.y, px)
	_texture.update(_image)


## Names under crew and objects show only when you're close enough to press E.
func _update_labels() -> void:
	var me: Vector2 = mission.player.position
	for actor in mission.crew.values():
		if is_instance_valid(actor) and actor.name_label != null:
			actor.name_label.visible = actor.position.distance_to(me) <= LABEL_RANGE
	for prop in mission.props.values():
		if is_instance_valid(prop) and prop.caption != null:
			prop.caption.visible = prop.position.distance_to(me) <= LABEL_RANGE
