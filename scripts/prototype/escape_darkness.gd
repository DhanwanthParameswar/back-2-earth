extends Node2D
## Ship lighting for the escape mission: tile-based line of sight (like a
## top-down roguelike), drawn as a smooth dark overlay over the world.
## Without power the ship is dark:
##   - a soft light of about 6 x 6 tiles always surrounds Johnny;
##   - F toggles a flashlight BEAM pointing the way you face (up/down/left/right);
##     it swings smoothly when you turn and widens out from your light circle;
##   - crewmates can be asked to turn on their own flashlight; it points the way
##     they walk (or the direction you asked for while they stand still);
##   - a tile is lit only if there's a clear line from the light to it. The first
##     wall a ray hits is lit (including the upper half of 2-tile wall faces), and
##     nothing behind it: you see walls, never through them. Doorways stop light
##     too: you see the doorway, then the next room once you're in it;
##   - the jammed locker blocks light like a wall but shows when your light reaches it;
##   - beyond your light it's black; name labels show only within E range.
## When power comes back the overlay fades out and the whole map is visible.

const TILE := 32.0
const BASE_RADIUS := 3.0 * TILE         # always lit around you: ~6 x 6 tiles
const SOFT_EDGE := 0.9 * TILE
const BEAM_RANGE := 8.0 * TILE          # how far a flashlight beam reaches
const BEAM_HALF_ANGLE := deg_to_rad(24.0)
const BEAM_START_WIDTH := BASE_RADIUS * 0.75  # beam leaves your circle this wide: no sharp tip
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


func _ready() -> void:
	z_index = 100            # above the ship, crew and props; the HUD is a separate layer
	z_as_relative = false
	_dark = 0.0 if is_powered() else 1.0


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
	if mission.cell_char(cell) in OPAQUE:
		return true
	return not mission.state.has_flag("locker_clear") and mission._locker_cells().has(cell)


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
	lit.clear()
	var me: Vector2 = mission.player.position + Vector2(0, -8)
	_add_circle(me, BASE_RADIUS)
	if flashlight:
		_add_beam(me, _beam_dirs.get("player", facing))
	for id in mission.crew.keys():
		var actor = mission.crew[id]
		if actor.light_on and _beam_dirs.has(id):
			_add_beam(actor.position + Vector2(0, -8), _beam_dirs[id])


func _add_circle(origin: Vector2, radius: float) -> void:
	var src := _cell(origin)
	var r := ceili(radius / TILE) + 1
	for y in range(src.y - r, src.y + r + 1):
		for x in range(src.x - r, src.x + r + 1):
			var c := Vector2i(x, y)
			var dist := origin.distance_to(Vector2(c) * TILE + Vector2(TILE, TILE) / 2.0)
			var v := 1.0 - smoothstep(radius - SOFT_EDGE, radius, dist)
			if v > 0.0:
				_light(src, c, v)


func _add_beam(origin: Vector2, dir: Vector2) -> void:
	var src := _cell(origin)
	var r := ceili(BEAM_RANGE / TILE) + 1
	var spread := tan(BEAM_HALF_ANGLE)
	for y in range(src.y - r, src.y + r + 1):
		for x in range(src.x - r, src.x + r + 1):
			var c := Vector2i(x, y)
			var v: Vector2 = Vector2(c) * TILE + Vector2(TILE, TILE) / 2.0 - origin
			var along := v.dot(dir)
			var perp := absf(v.cross(dir))
			var half_w := BEAM_START_WIDTH + maxf(along, 0.0) * spread
			var side := 1.0 - smoothstep(half_w * 0.5, half_w, perp)
			var back := smoothstep(-BEAM_START_WIDTH * 0.5, BEAM_START_WIDTH * 0.6, along)
			var reach := 1.0 - smoothstep(BEAM_RANGE * 0.55, BEAM_RANGE, along)
			var amount := side * back * reach
			if amount > 0.0:
				_light(src, c, amount)


## Light a cell if it's in sight; a lit wall also lights the wall tile above it
## (the upper half of a 2-tile wall face).
func _light(src: Vector2i, c: Vector2i, amount: float) -> void:
	if not line_of_sight(src, c):
		return
	_add(c, amount)
	if is_opaque(c):
		var above := c + Vector2i.UP
		if is_opaque(above) and mission.cell_char(above) != " ":
			_add(above, amount)


func _add(c: Vector2i, amount: float) -> void:
	lit[c] = 1.0 - (1.0 - lit.get(c, 0.0)) * (1.0 - amount)


# --- Drawing -------------------------------------------------------------------------

## The dark overlay: each tile is a quad whose corners blend the light of the four
## tiles around them, so edges are soft instead of blocky.
func _draw() -> void:
	if not is_dark():
		return
	var view := get_viewport().get_visible_rect()
	var to_world := get_viewport().get_canvas_transform().affine_inverse()
	var area := to_world * view
	var c0 := _cell(area.position) - Vector2i(1, 1)
	var c1 := _cell(area.end) + Vector2i(1, 1)
	var colors := PackedColorArray([Color(), Color(), Color(), Color()])
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var corners := [_corner(x, y), _corner(x + 1, y), _corner(x + 1, y + 1), _corner(x, y + 1)]
			if corners[0] >= 0.999 and corners[1] >= 0.999 and corners[2] >= 0.999 and corners[3] >= 0.999:
				continue  # fully lit tile: nothing to draw
			for i in 4:
				colors[i] = Color(DARK_COLOR, _dark * (1.0 - corners[i]))
			var p := Vector2(x, y) * TILE
			draw_polygon(PackedVector2Array([p, p + Vector2(TILE, 0), p + Vector2(TILE, TILE), p + Vector2(0, TILE)]), colors)


## Light at a tile corner: the average of the four tiles that share it.
func _corner(x: int, y: int) -> float:
	return (lit.get(Vector2i(x - 1, y - 1), 0.0) + lit.get(Vector2i(x, y - 1), 0.0)
		+ lit.get(Vector2i(x - 1, y), 0.0) + lit.get(Vector2i(x, y), 0.0)) / 4.0


## Names under crew and objects show only when you're close enough to press E.
func _update_labels() -> void:
	var me: Vector2 = mission.player.position
	for actor in mission.crew.values():
		if is_instance_valid(actor) and actor.name_label != null:
			actor.name_label.visible = actor.position.distance_to(me) <= LABEL_RANGE
	for prop in mission.props.values():
		if is_instance_valid(prop) and prop.caption != null:
			prop.caption.visible = prop.position.distance_to(me) <= LABEL_RANGE
