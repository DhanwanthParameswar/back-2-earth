extends CanvasLayer
## Ship lighting for the escape mission. Without power the ship is dark:
##   - you always see about 6 x 6 tiles around Johnny;
##   - F toggles a flashlight BEAM pointing the way you face (up/down/left/right);
##     it swings smoothly when you turn, and widens out from your light circle;
##   - crewmates can be asked to point their own flashlight a direction;
##   - people and objects (crew, consoles, the locker...) only appear when light
##     reaches them; the floor stays faintly visible so you can find your way.
##   - name labels (AARON, DHAN, SPARE FUSE...) show only within E range.
## When power comes back the dark fades out and everything is visible again.
## Sits above the ship and below the HUD (layer 10), so text stays readable.

const TILE := 32.0
const BASE_RADIUS := 3.0 * TILE         # always lit around you: ~6 x 6 tiles
const SOFT_EDGE := 0.9 * TILE
const BEAM_RANGE := 8.0 * TILE          # how far a flashlight beam reaches
const BEAM_HALF_ANGLE := deg_to_rad(24.0)
const BEAM_START_WIDTH := BASE_RADIUS * 0.75  # beam leaves your circle this wide: no sharp tip
const TURN_SPEED := 10.0                      # how fast a beam swings to a new direction
const LABEL_RANGE := 52.0                     # names show within E range (player reach 44)
const DARKNESS := 0.96                  # how black the unlit floor is
const FADE_SECONDS := 1.5

var mission
var flashlight := false
## Direction you face (last way you moved), snapped to up/down/left/right.
var facing := Vector2.RIGHT
## Beam directions as drawn (they swing toward facing / the crew's light_dir).
var _beam_dirs := {}
var _rect: ColorRect
var _material: ShaderMaterial
var _alpha := DARKNESS

const SHADER := """
shader_type canvas_item;
uniform vec2 rect_size;
uniform vec2 center;          // Johnny, in this rect's pixels
uniform float radius;
uniform float softness;
uniform float darkness;
uniform vec4 beam0;           // xy = origin, zw = direction (zero = off)
uniform vec4 beam1;
uniform vec4 beam2;
uniform float beam_range;
uniform float beam_spread;    // tan(half angle): how fast the beam widens

uniform float start_width;   // beam width where it leaves your circle

// A flashlight beam: starts as wide as the light circle and widens with
// distance, with soft sides and a soft far end (no triangle tip).
float beam_light(vec2 p, vec4 b) {
	if (length(b.zw) < 0.5) return 0.0;
	vec2 dir = normalize(b.zw);
	vec2 d = p - b.xy;
	float along = dot(d, dir);
	float perp = abs(d.x * dir.y - d.y * dir.x);
	float half_w = start_width + max(along, 0.0) * beam_spread;
	float side = 1.0 - smoothstep(half_w * 0.5, half_w, perp);
	float back = smoothstep(-start_width * 0.5, start_width * 0.6, along);
	float reach = 1.0 - smoothstep(beam_range * 0.55, beam_range, along);
	return side * back * reach;
}

void fragment() {
	vec2 p = UV * rect_size;
	float light = 1.0 - smoothstep(radius - softness, radius, distance(p, center));
	// Soft union, so the circle and the beam blend instead of meeting at a hard line.
	light = 1.0 - (1.0 - light) * (1.0 - beam_light(p, beam0));
	light = 1.0 - (1.0 - light) * (1.0 - beam_light(p, beam1));
	light = 1.0 - (1.0 - light) * (1.0 - beam_light(p, beam2));
	COLOR = vec4(0.0, 0.01, 0.03, darkness * (1.0 - light));
}
"""


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_rect.material = _material
	add_child(_rect)
	_alpha = 0.0 if is_powered() else DARKNESS


func is_powered() -> bool:
	return mission != null and mission.state.powered()


## True while the ship is dark (flashlights matter).
func is_dark() -> bool:
	return _alpha > 0.01


func toggle_flashlight() -> void:
	if not is_dark():
		return
	flashlight = not flashlight
	Sfx.play("boots", -10.0)  # a soft click


static func snap_direction(v: Vector2) -> Vector2:
	if absf(v.x) >= absf(v.y):
		return Vector2.RIGHT if v.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if v.y >= 0.0 else Vector2.UP


func _process(delta: float) -> void:
	var view := get_viewport().get_visible_rect().size
	_rect.position = Vector2.ZERO
	_rect.size = view
	var target_alpha := 0.0 if is_powered() else DARKNESS
	_alpha = move_toward(_alpha, target_alpha, delta * DARKNESS / FADE_SECONDS)
	if mission == null or mission.player == null:
		return
	if mission.player.velocity.length() > 5.0:
		facing = snap_direction(mission.player.velocity)
	_turn_beams(delta)
	_rect.visible = _alpha > 0.01
	var beams := _beams()
	if _rect.visible:
		_material.set_shader_parameter("rect_size", view)
		_material.set_shader_parameter("center", _screen(mission.player))
		_material.set_shader_parameter("radius", BASE_RADIUS)
		_material.set_shader_parameter("softness", SOFT_EDGE)
		_material.set_shader_parameter("darkness", _alpha)
		_material.set_shader_parameter("beam_range", BEAM_RANGE)
		_material.set_shader_parameter("beam_spread", tan(BEAM_HALF_ANGLE))
		_material.set_shader_parameter("start_width", BEAM_START_WIDTH)
		for i in 3:
			_material.set_shader_parameter("beam%d" % i, beams[i] if i < beams.size() else Vector4.ZERO)
	_update_object_visibility(beams)


## Light origin on screen for a character (their body, not their feet).
func _screen(node: Node2D) -> Vector2:
	return node.get_global_transform_with_canvas().origin + Vector2(0, -16)


## Up to 3 beams as (origin.x, origin.y, dir.x, dir.y): yours, then the crew's.
func _beams() -> Array:
	var out := []
	if flashlight:
		var o := _screen(mission.player)
		var d: Vector2 = _beam_dirs.get("player", facing)
		out.append(Vector4(o.x, o.y, d.x, d.y))
	for id in mission.crew.keys():
		var actor = mission.crew[id]
		if actor.light_dir != Vector2.ZERO:
			var o := _screen(actor)
			var d: Vector2 = _beam_dirs.get(id, actor.light_dir)
			out.append(Vector4(o.x, o.y, d.x, d.y))
	return out


## Swing each beam toward where it should point (D then W = right, then round to up).
func _turn_beams(delta: float) -> void:
	var weight := 1.0 - exp(-TURN_SPEED * delta)
	_beam_dirs["player"] = _swing(_beam_dirs.get("player", facing), facing, weight)
	for id in mission.crew.keys():
		var want: Vector2 = mission.crew[id].light_dir
		if want == Vector2.ZERO:
			_beam_dirs.erase(id)
		else:
			_beam_dirs[id] = _swing(_beam_dirs.get(id, want), want, weight)


static func _swing(current: Vector2, target: Vector2, weight: float) -> Vector2:
	return Vector2.from_angle(lerp_angle(current.angle(), target.angle(), weight))


## How lit a screen point is (0..1), matching the shader.
func light_at(p: Vector2, beams: Array) -> float:
	var light := 1.0 - smoothstep(BASE_RADIUS - SOFT_EDGE, BASE_RADIUS, p.distance_to(_screen(mission.player)))
	for b in beams:
		var dir := Vector2(b.z, b.w).normalized()
		var d: Vector2 = p - Vector2(b.x, b.y)
		var along := d.dot(dir)
		var perp := absf(d.cross(dir))
		var half_w := BEAM_START_WIDTH + maxf(along, 0.0) * tan(BEAM_HALF_ANGLE)
		var side := 1.0 - smoothstep(half_w * 0.5, half_w, perp)
		var back := smoothstep(-BEAM_START_WIDTH * 0.5, BEAM_START_WIDTH * 0.6, along)
		var reach := 1.0 - smoothstep(BEAM_RANGE * 0.55, BEAM_RANGE, along)
		light = 1.0 - (1.0 - light) * (1.0 - side * back * reach)
	return light


## Crewmates, consoles and the locker show only where light reaches them.
func _update_object_visibility(beams: Array) -> void:
	var things: Array = mission.crew.values() + mission.props.values()
	if mission.locker_visual != null:
		things.append(mission.locker_visual)
	for node in things:
		if not is_instance_valid(node):
			continue
		var target := 1.0
		if _rect.visible:
			var lit := light_at(_screen(node), beams)
			target = lerpf(1.0, clampf(lit * 1.4, 0.0, 1.0), _alpha / DARKNESS)
		node.modulate.a = target
	_update_labels()


## Names under crew and objects show only when you're close enough to press E.
func _update_labels() -> void:
	var me: Vector2 = mission.player.position
	for actor in mission.crew.values():
		if is_instance_valid(actor) and actor.name_label != null:
			actor.name_label.visible = actor.position.distance_to(me) <= LABEL_RANGE
	for prop in mission.props.values():
		if is_instance_valid(prop) and prop.caption != null:
			prop.caption.visible = prop.position.distance_to(me) <= LABEL_RANGE
