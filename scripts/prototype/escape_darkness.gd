extends Node2D
## Ship lighting for the escape mission. Without power the ship is dark, and it's
## lit the way real lights work:
##   - your own light: about 4 x 4 tiles around Johnny, fading smoothly into the
##     dark (bright near you, inverse-square falloff, black LIGHT_REACH further on);
##   - F toggles a FLASHLIGHT held in your hand. Like a real one, its beam is a
##     bright HOTSPOT inside a wider, dimmer SPILL, strongest close up and fading
##     with distance. It points the way you walk (diagonals too), swings round
##     when you turn, and sways a little in your hand as you walk;
##   - the beam lights the dusty air: a faint warm haze along it, with specks of
##     dust drifting through (only where the beam is);
##   - crewmates can be asked to turn on their own flashlight; it points the way
##     they walk (or the direction you asked for while they stand still);
##   - shadows are worked out per pixel by the shader: each floor pixel traces a
##     line back to the light across the map's tiles, so shadows run in straight
##     lines from wall corners. A wall lights where the light reaches its face
##     (including the upper half of 2-tile wall faces), and nothing behind it: you
##     see walls, never through them. Doorways stop light too: you see the
##     doorway, then the next room once you're in it;
##   - the jammed locker blocks light like a wall but shows when your light reaches it;
##   - beyond your light it's black; name labels show only within E range.
## When power comes back the overlay fades out and the whole map is visible.
## The same light is also worked out per tile on the CPU (`lit`, line_of_sight)
## for gameplay and for what's drawn above it (escape_alarm.gd, escape_impacts.gd).

const TILE := 32.0
const BASE_RADIUS := 2.0 * TILE         # your own light: about 4 x 4 tiles, then it fades out
const BEAM_RANGE := 5.0 * TILE          # a flashlight is still bright this far out...
const LIGHT_REACH := 2.25 * TILE        # ...and lights fade to black about this much further on
## Falloff: light / (1 + (d / NEAR)^2) (inverse square, softened up close), times a
## window that brings it smoothly to 0 at REACH.
const GLOW_NEAR := BASE_RADIUS * 1.6
const GLOW_REACH := BASE_RADIUS + LIGHT_REACH
const BEAM_NEAR := BEAM_RANGE * 1.25
const BEAM_REACH := BEAM_RANGE + LIGHT_REACH * 1.5
## Beam shape: a bright hotspot (full within 5 degrees, gone by 12) inside a wider
## spill (full within 20 degrees, gone by 32) at SPILL_LEVEL. Cosines of those angles.
const HOT_COS := Vector2(0.9781, 0.9962)
const SPILL_COS := Vector2(0.8480, 0.9397)
const SPILL_LEVEL := 0.42
const LENS := 7.0                       # the beam leaves the torch this far in front of you (px)
const BEAM_COLOR := Color(1.0, 0.9, 0.72)  # warm white: the haze and dust in the beam
const HAZE := 0.11                      # how much the beam lights the air
const DUST := 0.6                       # how bright dust specks in the beam are
## The hand holding the torch: it sways with each step and drifts a little at rest.
const STEP_LENGTH := 30.0               # px walked per step
const SWAY_WALK := deg_to_rad(3.0)
const SWAY_IDLE := deg_to_rad(0.7)
const BOB := 1.5                        # px the torch bobs with each step
const TURN_SPEED := 10.0                # how fast a beam swings to a new direction
const LABEL_RANGE := 52.0               # names show within E range (player reach 44)
const DARK_COLOR := Color(0.006, 0.007, 0.014)  # unlit = black: nothing shows beyond your light
const FADE_SECONDS := 1.5
## Map cells that stop light (walls, windows, doorways, barriers, outside the ship).
const OPAQUE := ["#", "w", "D", "B", " "]

var mission
var flashlight := false
## Direction you face: the way you last moved (any angle, so diagonals too).
var facing := Vector2.RIGHT
## Beam directions ("player" and crew ids); they swing toward their target.
var _beam_dirs := {}
var _dark := 1.0             # 1 = no power, 0 = lights on (fades between)
## Light per cell this frame (Vector2i -> 0..1). Cells not in it are dark.
var lit := {}
## Walls in a byte grid (built once) and line of sight cached per light cell, for
## the CPU light; the shader gets the same walls as a small image (a pixel per tile:
## red = stops light, green = outside the ship), rebuilt only when the locker moves.
var _opaque := PackedByteArray()
var _locker := {}
var _locker_clear := false
var _sight_cache := {}       # source cell -> {cell: true} visible from it (within beam range)
var _occ_image: Image
var _occ_texture: ImageTexture
var _material: ShaderMaterial
## For the hand's sway: how far each light-holder has walked, how much they're
## walking right now (0..1, eased) and where they were last frame.
var _walked := {}
var _walking := {}
var _last_pos := {}
var _time := 0.0
const CREW_CHANNEL := {"mara": 1, "ivo": 2}

const SHADER := """
shader_type canvas_item;
uniform vec2 rect_pos;        // world rect this overlay covers
uniform vec2 rect_size;
uniform sampler2D occ : filter_nearest;  // a pixel per tile: r = stops light, g = outside the ship
uniform vec2 map_cells;
uniform float tile;
uniform vec2 me;              // centre of your own light
uniform float glow_near;
uniform float glow_reach;
uniform vec4 beam0;           // xy = the torch's lens, zw = direction (zero = off): you
uniform vec4 beam1;           // Aaron
uniform vec4 beam2;           // Dhan
uniform float lens;
uniform float beam_near;
uniform float beam_reach;
uniform vec2 hot_cos;         // x = edge, y = full
uniform vec2 spill_cos;
uniform float spill_level;
uniform vec3 dark_color;
uniform vec3 beam_color;
uniform float haze;
uniform float dust;
uniform float dark;

const int MAX_STEPS = 32;

bool stops_light(ivec2 c) {
	if (c.x < 0 || c.y < 0 || float(c.x) >= map_cells.x || float(c.y) >= map_cells.y) return true;
	return texelFetch(occ, c, 0).r > 0.5;
}

bool outside_ship(ivec2 c) {
	if (c.x < 0 || c.y < 0 || float(c.x) >= map_cells.x || float(c.y) >= map_cells.y) return true;
	return texelFetch(occ, c, 0).g > 0.5;
}

// A clear line from a to b (px): no light-stopping tile between their tiles (b's
// own tile may stop light: the first wall a ray reaches is lit). Walks the tiles
// the line crosses, one by one.
bool clear_path(vec2 a, vec2 b) {
	vec2 ta = a / tile;
	vec2 tb = b / tile;
	ivec2 c = ivec2(floor(ta));
	ivec2 goal = ivec2(floor(tb));
	vec2 d = tb - ta;
	ivec2 dir = ivec2(sign(d));
	vec2 inv = 1.0 / max(abs(d), vec2(0.00001));
	vec2 next = vec2(
		d.x > 0.0 ? floor(ta.x) + 1.0 - ta.x : ta.x - floor(ta.x),
		d.y > 0.0 ? floor(ta.y) + 1.0 - ta.y : ta.y - floor(ta.y)) * inv;
	for (int i = 0; i < MAX_STEPS; i++) {
		if (all(equal(c, goal))) return true;
		if (next.x < next.y) {
			c.x += dir.x;
			next.x += inv.x;
		} else {
			c.y += dir.y;
			next.y += inv.y;
		}
		if (all(equal(c, goal))) return true;
		if (stops_light(c)) return false;
	}
	return false;
}

// A wall tile is lit when light reaches the open floor right in front of it (the
// point just outside the tile on the light's side), so a whole face lights evenly.
bool wall_lit(vec2 o, ivec2 c) {
	vec2 lo = vec2(c) * tile;
	vec2 q = clamp(o, lo - vec2(0.5), lo + vec2(tile + 0.5));
	ivec2 qc = ivec2(floor(q / tile));
	bool open = !stops_light(qc) || all(equal(qc, ivec2(floor(o / tile))));
	return open && clear_path(o, q);
}

// 1 if light from o reaches p: floors per pixel; walls by their face, including
// the upper tile of a 2-tile wall face when the tile below it is lit.
float reach(vec2 o, vec2 p) {
	ivec2 c = ivec2(floor(p / tile));
	if (!stops_light(c) || outside_ship(c) || all(equal(c, ivec2(floor(o / tile))))) return clear_path(o, p) ? 1.0 : 0.0;
	if (wall_lit(o, c)) return 1.0;
	ivec2 below = c + ivec2(0, 1);
	return stops_light(below) && wall_lit(o, below) ? 1.0 : 0.0;
}

// Inverse square, softened up close (knee), brought smoothly to 0 at limit.
float falloff(float d, float knee, float limit) {
	float x = clamp(d / limit, 0.0, 1.0);
	float window = 1.0 - x * x * x * x;
	return window * window / (1.0 + (d / knee) * (d / knee));
}

// A torch: bright hotspot inside a wider, dimmer spill, fading with distance.
float beam_light(vec2 p, vec4 b) {
	if (dot(b.zw, b.zw) < 0.25) return 0.0;
	vec2 v = p - b.xy;
	float d = length(v);
	if (d > beam_reach) return 0.0;
	float c = d > 0.001 ? dot(v / d, normalize(b.zw)) : 1.0;
	float hot = smoothstep(hot_cos.x, hot_cos.y, c);
	float spill = smoothstep(spill_cos.x, spill_cos.y, c);
	return max(hot, spill * spill_level) * falloff(d, beam_near, beam_reach);
}

// Shadows are traced from the torch-holder's body, not the lens (which can poke
// into a wall when you stand right against it).
float lit_by(vec2 p, vec4 b) {
	float l = beam_light(p, b);
	if (l < 0.002) return 0.0;
	return l * reach(b.xy - normalize(b.zw) * lens, p);
}

float add(float a, float b) { return 1.0 - (1.0 - a) * (1.0 - b); }

float hash(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }

// Dust drifting in the air: a 2 px speck (one art pixel) in some 12 px cells.
float dust_speck(vec2 p) {
	vec2 cell = floor(p / 12.0);
	float h = hash(cell);
	if (h < 0.82) return 0.0;
	vec2 home = cell * 12.0 + vec2(3.0) + vec2(hash(cell + 17.0), hash(cell + 41.0)) * 6.0;
	vec2 drift = vec2(sin(TIME * 0.6 + h * 40.0), cos(TIME * 0.45 + h * 23.0)) * 1.8;
	vec2 q = p - floor((home + drift) / 2.0) * 2.0;
	if (q.x < 0.0 || q.y < 0.0 || q.x >= 2.0 || q.y >= 2.0) return 0.0;
	return 0.55 + 0.45 * sin(TIME * 2.3 + h * 70.0);
}

void fragment() {
	vec2 p = rect_pos + UV * rect_size;
	float glow = 0.0;
	float gd = distance(p, me);
	if (gd < glow_reach) {
		glow = falloff(gd, glow_near, glow_reach);
		glow = glow > 0.002 ? glow * reach(me, p) : 0.0;
	}
	float beams = add(add(lit_by(p, beam0), lit_by(p, beam1)), lit_by(p, beam2));
	float light = add(glow, beams);
	float specks = beams > 0.02 ? dust_speck(p) * beams : 0.0;
	// Mix blend: darken by what isn't lit, and wash the beam with warm haze and dust.
	float shade = dark * (1.0 - light);
	float glaze = dark * (beams * haze + specks * dust);
	float a = clamp(shade + glaze, 0.0, 1.0);
	vec3 col = a > 0.0001 ? (dark_color * shade + beam_color * glaze) / a : dark_color;
	COLOR = vec4(col, a);
}
"""


func _ready() -> void:
	z_index = 100            # above the ship, crew and props; the HUD is a separate layer
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_dark = 0.0 if is_powered() else 1.0
	var size: Vector2i = mission.map_size
	_opaque.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			_opaque[y * size.x + x] = 1 if mission.cell_char(Vector2i(x, y)) in OPAQUE else 0
	for c in mission._locker_cells():
		_locker[c] = true
	_locker_clear = mission.state.has_flag("locker_clear")
	_occ_image = Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	_occ_texture = ImageTexture.create_from_image(_occ_image)
	_build_occupancy()
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("occ", _occ_texture)
	_material.set_shader_parameter("map_cells", Vector2(size))
	_material.set_shader_parameter("tile", TILE)
	_material.set_shader_parameter("glow_near", GLOW_NEAR)
	_material.set_shader_parameter("glow_reach", GLOW_REACH)
	_material.set_shader_parameter("lens", LENS)
	_material.set_shader_parameter("beam_near", BEAM_NEAR)
	_material.set_shader_parameter("beam_reach", BEAM_REACH)
	_material.set_shader_parameter("hot_cos", HOT_COS)
	_material.set_shader_parameter("spill_cos", SPILL_COS)
	_material.set_shader_parameter("spill_level", SPILL_LEVEL)
	_material.set_shader_parameter("dark_color", Vector3(DARK_COLOR.r, DARK_COLOR.g, DARK_COLOR.b))
	_material.set_shader_parameter("beam_color", Vector3(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b))
	_material.set_shader_parameter("haze", HAZE)
	_material.set_shader_parameter("dust", DUST)
	material = _material


## The walls the shader traces shadows against: a pixel per tile.
func _build_occupancy() -> void:
	var size: Vector2i = mission.map_size
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			var outside: bool = mission.cell_char(c) == " "
			_occ_image.set_pixel(x, y, Color(1.0 if is_opaque(c) else 0.0, 1.0 if outside else 0.0, 0.0, 1.0))
	_occ_texture.update(_occ_image)


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


## The direction a beam is pointing right now ("player", "mara", "ivo"), without
## the hand's sway (that's only drawn).
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
		facing = mission.player.velocity.normalized()
	if not is_dark():
		flashlight = false
	_check_locker()
	_turn_beams(delta)
	_track_walking(delta)
	if is_dark():
		_compute_light()
	visible = is_dark()
	queue_redraw()
	_update_labels()


## The hallway opens when the locker is pushed clear: sight lines change.
func _check_locker() -> void:
	var clear: bool = mission.state.has_flag("locker_clear")
	if clear != _locker_clear:
		_locker_clear = clear
		_sight_cache.clear()
		_build_occupancy()


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


## How far each light-holder has walked, and whether they're walking right now.
func _track_walking(delta: float) -> void:
	_time += delta
	var bodies := {"player": mission.player.position}
	for id in mission.crew.keys():
		bodies[id] = mission.crew[id].position
	for id in bodies:
		var p: Vector2 = bodies[id]
		var moved := 0.0
		if _last_pos.has(id):
			moved = p.distance_to(_last_pos[id])
		_last_pos[id] = p
		if moved > 40.0:
			moved = 0.0  # moved by the game (resume, restart), not a step
		_walked[id] = float(_walked.get(id, 0.0)) + moved
		var target := 1.0 if delta > 0.0 and moved / delta > 10.0 else 0.0
		_walking[id] = move_toward(float(_walking.get(id, 0.0)), target, delta * 4.0)


## The beam as drawn: where it points, plus the sway and bob of the hand holding
## it. xy = the torch's lens, zw = direction (the shader's beam uniform).
func _held(id: String, eye: Vector2, dir: Vector2) -> Vector4:
	var walking: float = _walking.get(id, 0.0)
	var step := float(_walked.get(id, 0.0)) / STEP_LENGTH * PI
	var idle := sin(_time * 0.9 + float(CREW_CHANNEL.get(id, 0)) * 2.1) * SWAY_IDLE
	var d := dir.rotated(sin(step) * SWAY_WALK * walking + idle)
	var lens := eye + d * LENS + Vector2(0.0, -absf(sin(step)) * BOB * walking)
	return Vector4(lens.x, lens.y, d.x, d.y)


## Where a light is held: chest height above the feet.
static func _eye(feet: Vector2) -> Vector2:
	return feet + Vector2(0, -8)


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


## The light per tile, for gameplay (`lit`, light_of): the same shapes the shader
## draws, at tile resolution.
func _compute_light() -> void:
	lit.clear()
	var me := _eye(mission.player.position)
	_add_glow(me)
	if flashlight:
		_add_beam(me, _beam_dirs.get("player", facing))
	for id in mission.crew.keys():
		var actor = mission.crew[id]
		if actor.light_on and _beam_dirs.has(id):
			_add_beam(_eye(actor.position), _beam_dirs[id])


## Everything visible from a cell, worked out once per cell (walls don't move).
func _sight(src: Vector2i) -> Dictionary:
	if _sight_cache.has(src):
		return _sight_cache[src]
	var seen := {}
	var r := ceili(BEAM_REACH / TILE) + 1
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


## Inverse square, softened up close (`near`), brought smoothly to 0 at `far`. Matches the shader.
static func falloff(d: float, near: float, far: float) -> float:
	var x := clampf(d / far, 0.0, 1.0)
	var window := 1.0 - x * x * x * x
	return window * window / (1.0 + (d / near) * (d / near))


## How much of a beam reaches a direction `cos_angle` off its axis: hotspot, then spill.
static func beam_shape(cos_angle: float) -> float:
	var hot := smoothstep(HOT_COS.x, HOT_COS.y, cos_angle)
	var spill := smoothstep(SPILL_COS.x, SPILL_COS.y, cos_angle)
	return maxf(hot, spill * SPILL_LEVEL)


func _add_glow(origin: Vector2) -> void:
	for c in _sight(_cell(origin)).keys():
		var dist := origin.distance_to(Vector2(c) * TILE + Vector2(TILE, TILE) / 2.0)
		if dist < GLOW_REACH:
			_add(c, falloff(dist, GLOW_NEAR, GLOW_REACH))


func _add_beam(origin: Vector2, dir: Vector2) -> void:
	var lens := origin + dir * LENS
	for c in _sight(_cell(origin)).keys():
		var v: Vector2 = Vector2(c) * TILE + Vector2(TILE, TILE) / 2.0 - lens
		var d := v.length()
		if d > BEAM_REACH:
			continue
		var cos_angle := v.dot(dir) / d if d > 0.001 else 1.0
		var amount := beam_shape(cos_angle) * falloff(d, BEAM_NEAR, BEAM_REACH)
		if amount > 0.0:
			_add(c, amount)


func _add(c: Vector2i, amount: float) -> void:
	lit[c] = 1.0 - (1.0 - lit.get(c, 0.0)) * (1.0 - amount)


# --- Drawing -------------------------------------------------------------------------

## The dark overlay: one rectangle over the map (and well past its edges), drawn by
## the shader, which lights and shadows it per pixel.
func _draw() -> void:
	if not is_dark():
		return
	var size: Vector2i = mission.map_size
	var m := Vector2(size) * TILE
	var pad := 3000.0
	var rect := Rect2(-pad, -pad, m.x + 2.0 * pad, m.y + 2.0 * pad)
	_material.set_shader_parameter("rect_pos", rect.position)
	_material.set_shader_parameter("rect_size", rect.size)
	_material.set_shader_parameter("me", _eye(mission.player.position))
	_material.set_shader_parameter("dark", _dark)
	_material.set_shader_parameter("beam0",
		_held("player", _eye(mission.player.position), _beam_dirs.get("player", facing)) if flashlight else Vector4.ZERO)
	for id in CREW_CHANNEL:
		var on: bool = mission.crew.has(id) and mission.crew[id].light_on and _beam_dirs.has(id)
		_material.set_shader_parameter("beam%d" % CREW_CHANNEL[id],
			_held(id, _eye(mission.crew[id].position), _beam_dirs[id]) if on else Vector4.ZERO)
	draw_texture_rect(_occ_texture, rect, false)  # the shader ignores the texture; this gives it UVs


## Names under crew and objects show only when you're close enough to press E.
func _update_labels() -> void:
	var me: Vector2 = mission.player.position
	for actor in mission.crew.values():
		if is_instance_valid(actor) and actor.name_label != null:
			actor.name_label.visible = actor.position.distance_to(me) <= LABEL_RANGE
	for prop in mission.props.values():
		if is_instance_valid(prop) and prop.caption != null:
			prop.caption.visible = prop.position.distance_to(me) <= LABEL_RANGE
