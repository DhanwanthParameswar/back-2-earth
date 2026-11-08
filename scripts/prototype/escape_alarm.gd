extends Node2D
## Rotating red emergency beacons on the corridor wall (the wall_face_alarm lamps).
##
## Each one works like a real rotating warning light: a bulb that stays on, and
## a reflector spinning around it. So:
##   - a narrow beam sweeps round the corridor: across the floor, along the
##     walls (stretching out as it grazes them), stopping at walls, the barrier
##     and the jammed locker;
##   - when it points at the wall behind the lamp, a hot spot slides along it;
##   - inside the glass dome you see the reflector's bright band travel across
##     as it turns, and the dome brightens as it comes round to face you;
##   - each time the beam faces you (the camera) it FLASHES: glare, a horizontal
##     lens streak and a red spill on the floor and wall.
## Drawn additively above the dark overlay (escape_darkness.gd): a beacon is a
## light source, so you see it, and its sweeping red light, in the dark.
## The unlit dome and its mount are tile art (tools/make_ship_art.py, "alarm").

const TILE := 32.0
## Real rotating beacons turn at about 60-90 RPM: one flash per turn.
const RPM := 72.0
const BEAM_HALF_ANGLE := deg_to_rad(20.0)
const BEAM_RANGE := 6.5 * TILE
const RAYS := 14
const CENTRE_RAY := 7
const STEP := 4.0                     # ray-march step (px)
## The lamp sits this far out from the wall (px), for where its beam hits the wall.
const MOUNT_DEPTH := 18.0
const RED := Color(1.0, 0.04, 0.07)
const HOT := Color(1.0, 0.62, 0.52)
## The glass dome inside a wall_face_alarm tile, in art pixels (1 art px = 2 px):
## top row x 6-9 at y 1, body x 5-10 at y 2-4 (matches tools/make_ship_art.py).
const ART_PX := 2.0
const DOME_ROWS := {1: Vector2i(6, 9), 2: Vector2i(5, 10), 3: Vector2i(5, 10), 4: Vector2i(5, 10)}
## Beams look fainter once the ship's own lights are back on.
const LIT_STRENGTH := 0.45

var mission
## {cell: Vector2i (the wall tile), tile: Vector2 (its top-left px), dome: Vector2
##  (dome centre px), origin: Vector2 (floor point under the lamp), phase, speed,
##  wall_min, wall_max (px: where the wall face behind it ends)}
var beacons: Array[Dictionary] = []
var _t := 0.0
var _glow: GradientTexture2D


func _ready() -> void:
	z_index = 101                     # just above escape_darkness.gd (100); the HUD is a CanvasLayer
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.5))
	_glow = GradientTexture2D.new()
	_glow.gradient = g
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 64
	_glow.height = 64
	_find_beacons()


func _find_beacons() -> void:
	beacons.clear()
	var size: Vector2i = mission.map_size
	for y in size.y:
		for x in size.x:
			if not mission.ship.is_alarm_cell(x, y):
				continue
			var tile := Vector2(x * TILE, y * TILE)
			var wall_min: int = x
			while mission.ship.is_wall_face(wall_min - 1, y): wall_min -= 1
			var wall_max: int = x
			while mission.ship.is_wall_face(wall_max + 1, y): wall_max += 1
			beacons.append({
				"cell": Vector2i(x, y),
				"tile": tile,
				"dome": tile + Vector2(16, 6),
				"origin": Vector2(tile.x + 16, tile.y + TILE + 3),
				# Independent motors: each lamp starts somewhere else and runs a touch faster or slower.
				"phase": fmod(x * 2.39996, TAU),
				"speed": 1.0 + 0.035 * float((x * 7) % 5 - 2),
				"wall_min": wall_min * TILE,
				"wall_max": (wall_max + 1) * TILE,
			})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Beam direction on screen right now (0 = right, PI/2 = down, toward the camera).
func angle_of(b: Dictionary) -> float:
	return b.phase + TAU * RPM / 60.0 * b.speed * _t


## 1 when the beam points straight at the camera (the flash), quickly falling to 0.
static func flash_of(angle: float) -> float:
	return pow(maxf(0.0, sin(angle)), 12.0)


func _strength() -> float:
	var dark: float = mission.darkness._dark if mission.darkness != null else 1.0
	return lerpf(LIT_STRENGTH, 1.0, dark)


# --- Beam geometry -------------------------------------------------------------------

## Where the beam's centre meets the wall behind the lamp (x px), or NAN if it
## points away from that wall.
func _wall_hit_x(b: Dictionary, angle: float) -> float:
	var s := sin(angle)
	if s > -0.02:
		return NAN
	var x: float = b.origin.x + cos(angle) * MOUNT_DEPTH / -s
	if x < b.wall_min or x > b.wall_max:
		return NAN
	return x


# --- Drawing -------------------------------------------------------------------------

func _draw() -> void:
	if mission == null or beacons.is_empty():
		return
	var view := _view_rect().grow(BEAM_RANGE + 64.0)
	var k := _strength()
	for b in beacons:
		if not view.has_point(b.dome):
			continue
		var angle := angle_of(b)
		var flash := flash_of(angle)
		var front := smoothstep(-0.2, 1.0, sin(angle))      # dome brightness as it turns toward you
		var seen := _not_blocked(b.dome)                      # someone standing in front of the lamp
		_draw_spill(b, flash, front, k)
		_draw_floor_beam(b, angle, k)
		_draw_wall_beam(b, angle, k)
		_draw_dome(b, angle, front, flash, seen)
		_draw_glare(b, flash, seen, k)


## Soft red light the bulb throws on the wall and the floor just under it.
func _draw_spill(b: Dictionary, flash: float, front: float, k: float) -> void:
	var under: Vector2 = b.origin + Vector2(0, 8)
	_blob(under, Vector2(150, 72), Color(RED, (0.06 + 0.2 * flash) * k))
	_blob(b.dome + Vector2(0, 6), Vector2(84, 38), Color(RED, (0.07 + 0.12 * front) * k))


## The sweeping beam across the floor: a fan of rays that stop at walls.
func _draw_floor_beam(b: Dictionary, angle: float, k: float) -> void:
	var origin: Vector2 = b.origin
	var ends: Array[Vector2] = []
	var alphas: Array[float] = []
	var centre_hit := Vector2.INF
	for i in RAYS + 1:
		var f := float(i) / RAYS
		var a := angle + lerpf(-BEAM_HALF_ANGLE, BEAM_HALF_ANGLE, f)
		var profile := pow(sin(f * PI), 1.5)                 # bright core, soft edges
		if sin(a) <= 0.0:
			ends.append(origin)                              # into the wall behind: drawn on the wall
			alphas.append(0.0)
			continue
		var dir := Vector2.from_angle(a)
		var reach := _march(origin, dir)
		ends.append(origin + dir * reach.x)
		# Fade along the beam, and a little in from the floor's edge (rays skimming the wall).
		var fade := pow(1.0 - reach.x / BEAM_RANGE, 1.2) * smoothstep(0.0, 0.18, sin(a))
		alphas.append(0.7 * profile * fade * k)
		if i == CENTRE_RAY and reach.y > 0.5:
			centre_hit = origin + dir * reach.x
	for i in RAYS:
		if alphas[i] <= 0.0 and alphas[i + 1] <= 0.0:
			continue
		# Brightest where it leaves the lamp; the fan's edges stay soft there too.
		var start := Color(RED, 0.45 * k * minf(1.0, (alphas[i] + alphas[i + 1]) * 2.0))
		draw_primitive(PackedVector2Array([origin, ends[i], ends[i + 1]]),
			PackedColorArray([start, Color(RED, alphas[i]), Color(RED, alphas[i + 1])]), PackedVector2Array())
	# Where the beam lands on a wall, it splashes.
	if centre_hit != Vector2.INF:
		var dist := origin.distance_to(centre_hit)
		var size := 22.0 + dist * 0.35
		_blob(centre_hit, Vector2(size, size * 0.7), Color(RED, 0.6 * (1.0 - dist / BEAM_RANGE) * k))


## Rays toward the wall behind the lamp: the hot spot sliding along the wall face,
## tight right behind the lamp and stretched out when the beam grazes the wall.
func _draw_wall_beam(b: Dictionary, angle: float, k: float) -> void:
	var top: float = b.tile.y - TILE + 6.0                   # up the 2-tile wall face
	var bottom: float = b.tile.y + TILE - 1.0
	var xs: Array[float] = []
	var alphas: Array[float] = []
	for i in RAYS + 1:
		var f := float(i) / RAYS
		var a := angle + lerpf(-BEAM_HALF_ANGLE, BEAM_HALF_ANGLE, f)
		var s := sin(a)
		if s > -0.01:
			xs.append(NAN)
			alphas.append(0.0)
			continue
		var x: float = clampf(b.origin.x + cos(a) * MOUNT_DEPTH / -s, b.wall_min, b.wall_max)
		var spread := absf(x - b.origin.x)
		xs.append(x)
		alphas.append(0.6 * pow(sin(f * PI), 1.5) / (1.0 + spread / 60.0) * k)
	for i in RAYS:
		if is_nan(xs[i]) or is_nan(xs[i + 1]) or absf(xs[i + 1] - xs[i]) < 0.5:
			continue
		var c0 := Color(RED, alphas[i])
		var c1 := Color(RED, alphas[i + 1])
		var e0 := Color(RED, 0.0)
		# Brightest at the lamp's height, fading up the wall and down to the floor.
		var mid: float = b.dome.y + 2.0
		draw_primitive(PackedVector2Array([Vector2(xs[i], top), Vector2(xs[i + 1], top), Vector2(xs[i + 1], mid), Vector2(xs[i], mid)]),
			PackedColorArray([e0, e0, c1, c0]), PackedVector2Array())
		draw_primitive(PackedVector2Array([Vector2(xs[i], mid), Vector2(xs[i + 1], mid), Vector2(xs[i + 1], bottom), Vector2(xs[i], bottom)]),
			PackedColorArray([c0, c1, Color(RED, alphas[i + 1] * 0.35), Color(RED, alphas[i] * 0.35)]), PackedVector2Array())
	# The bright spot where the beam's centre lands on the wall (soft, so a beam
	# aimed straight at the wall isn't just a thin line).
	var hit_x := _wall_hit_x(b, angle)
	if not is_nan(hit_x):
		var off := absf(hit_x - b.origin.x)
		_blob(Vector2(hit_x, b.dome.y + 4.0), Vector2(22.0 + off * 0.5, 44.0), Color(RED, 0.55 / (1.0 + off / 60.0) * k))


## The lit glass dome, pixel by pixel: the bulb's glow, plus the reflector's bright
## band sliding across the dome as it turns (from the side the beam points to).
func _draw_dome(b: Dictionary, angle: float, front: float, flash: float, seen: float) -> void:
	var tile: Vector2 = b.tile
	var band := 8.0 + cos(angle) * 2.4 - 0.5                 # art-px column of the reflector's face
	var band_on := smoothstep(-0.35, 0.6, sin(angle))         # hidden behind the bulb when facing away
	for row in DOME_ROWS:
		var span: Vector2i = DOME_ROWS[row]
		for col in range(span.x, span.y + 1):
			var near := clampf(1.0 - absf(col - band) / 1.6, 0.0, 1.0) * band_on
			var c := RED * (0.3 + 0.5 * front) + HOT * (near * 0.85 + flash * 0.7)
			c.a = clampf((0.55 + 0.45 * front + near) * seen, 0.0, 1.0)
			draw_rect(Rect2(tile + Vector2(col, row) * ART_PX, Vector2(ART_PX, ART_PX)), c)


## The flash when the beam faces you: a red halo, a white-hot core and a lens streak.
func _draw_glare(b: Dictionary, flash: float, seen: float, k: float) -> void:
	var c: Vector2 = b.dome
	_blob(c, Vector2.ONE * (26.0 + 34.0 * flash), Color(RED, (0.16 + 0.5 * flash) * seen))
	if flash < 0.02:
		return
	var f := flash * seen
	_blob(c, Vector2.ONE * (60.0 + 70.0 * flash), Color(RED, 0.4 * f * k))
	_blob(c, Vector2(40.0 + 190.0 * flash, 5.0), Color(1.0, 0.35, 0.32, 0.85 * f))
	_blob(c, Vector2(4.0, 10.0 + 22.0 * flash), Color(1.0, 0.35, 0.32, 0.35 * f))
	_blob(c, Vector2.ONE * 14.0, Color(HOT, f))


## A soft round (or stretched) light centred on `at`.
func _blob(at: Vector2, size: Vector2, color: Color) -> void:
	if color.a <= 0.003:
		return
	draw_texture_rect(_glow, Rect2(at - size / 2.0, size), false, color)


## Walk a ray across the map grid. x = how far it got (px), y = 1 if it hit
## something solid (a wall, the barrier, the jammed locker), 0 if it ran out of range.
func _march(origin: Vector2, dir: Vector2) -> Vector2:
	var dark = mission.darkness
	var s := STEP
	while s < BEAM_RANGE:
		var p := origin + dir * s
		if dark.is_opaque(Vector2i(floori(p.x / TILE), floori(p.y / TILE))):
			return Vector2(s, 1.0)
		s += STEP
	return Vector2(BEAM_RANGE, 0.0)


## 0.15 if the player or a crewmate is standing in front of this lamp (their
## sprite covers it), else 1.
func _not_blocked(at: Vector2) -> float:
	var bodies: Array = [mission.player]
	bodies.append_array(mission.crew.values())
	for body in bodies:
		if body != null and is_instance_valid(body):
			var p: Vector2 = body.position
			if Rect2(p.x - 13.0, p.y - 52.0, 26.0, 52.0).has_point(at):
				return 0.15
	return 1.0


## The part of the map on screen (px).
func _view_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
