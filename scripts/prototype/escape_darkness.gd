extends Node2D
## Ship lighting for the escape mission: tile-based line of sight (like a
## top-down roguelike), drawn as a smooth dark overlay over the world.
## Without power the ship is dark:
##   - a soft light of about 6 x 6 tiles always surrounds Johnny, fading into a
##     dim zone where you can still make things out, then black (same for beams);
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
## Gradient: a bright core, a gentle fade, then a DIM zone where you can still make
## things out, then black.
const BRIGHT_EDGE := 0.6                # light left at the end of the bright part
const DIM_LEVEL := 0.22                 # light left at the end of the dim zone
const CIRCLE_DIM := 2.0 * TILE          # dim zone beyond your 6 x 6 circle
const BEAM_DIM := 1.5 * TILE            # dim tail beyond the beam's reach
const EDGE := 1.0 * TILE                # from dim to black
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
## Speed: walls in a byte grid (built once), line of sight cached per light cell,
## and the dark drawn as ONE small image (a pixel per tile) stretched with smoothing.
var _opaque := PackedByteArray()
var _locker := {}
var _locker_clear := false
var _sight_cache := {}       # source cell -> {cell: true} visible from it (within beam range)
var _image: Image
var _texture: ImageTexture


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
	var r := ceili((BEAM_RANGE + BEAM_DIM + EDGE) / TILE) + 1
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
		var amount := falloff(dist, radius, radius + CIRCLE_DIM, radius + CIRCLE_DIM + EDGE)
		if amount > 0.0:
			_add(c, amount)


func _add_beam(origin: Vector2, dir: Vector2) -> void:
	var seen := _sight(_cell(origin))
	var spread := tan(BEAM_HALF_ANGLE)
	for c in seen.keys():
		var v: Vector2 = Vector2(c) * TILE + Vector2(TILE, TILE) / 2.0 - origin
		var along := v.dot(dir)
		if along < -BEAM_START_WIDTH * 0.5 or along > BEAM_RANGE + BEAM_DIM + EDGE:
			continue
		var perp := absf(v.cross(dir))
		var half_w := BEAM_START_WIDTH + maxf(along, 0.0) * spread
		if perp > half_w * 1.5:
			continue
		# Bright in the middle of the beam, fading to its sides (with a dim fringe),
		# and bright near you, fading along its length (with a dim tail).
		var side := falloff(perp, half_w * 0.75, half_w * 1.2, half_w * 1.5)
		var reach := falloff(maxf(along, 0.0), BEAM_RANGE, BEAM_RANGE + BEAM_DIM, BEAM_RANGE + BEAM_DIM + EDGE)
		var back := smoothstep(-BEAM_START_WIDTH * 0.5, BEAM_START_WIDTH * 0.6, along)
		_add(c, side * back * reach)


## Light from 1 (bright) down to 0 over distance `d`: bright core, gentle fade to
## BRIGHT_EDGE at `full`, a dim zone down to DIM_LEVEL at `dim_end`, then black at `black_end`.
static func falloff(d: float, full: float, dim_end: float, black_end: float) -> float:
	if d <= full * 0.45:
		return 1.0
	if d <= full:
		return lerpf(1.0, BRIGHT_EDGE, smoothstep(full * 0.45, full, d))
	if d <= dim_end:
		return lerpf(BRIGHT_EDGE, DIM_LEVEL, smoothstep(full, dim_end, d))
	if d <= black_end:
		return lerpf(DIM_LEVEL, 0.0, smoothstep(dim_end, black_end, d))
	return 0.0


func _add(c: Vector2i, amount: float) -> void:
	lit[c] = 1.0 - (1.0 - lit.get(c, 0.0)) * (1.0 - amount)


# --- Drawing -------------------------------------------------------------------------

## The dark overlay: ONE image with a pixel per tile (alpha = how dark), drawn
## over the whole map. Linear filtering blends neighbouring tiles: soft edges.
func _draw() -> void:
	if not is_dark():
		return
	_image.fill(Color(DARK_COLOR, _dark))
	var size: Vector2i = mission.map_size
	for c in lit.keys():
		if c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y:
			_image.set_pixel(c.x, c.y, Color(DARK_COLOR, _dark * (1.0 - lit[c])))
	_texture.update(_image)
	# Black beyond the map edges, then the map-sized light image.
	var m := Vector2(size) * TILE
	var edge := Color(DARK_COLOR, _dark)
	var pad := 3000.0
	draw_rect(Rect2(-pad, -pad, m.x + 2.0 * pad, pad), edge)        # above the map
	draw_rect(Rect2(-pad, m.y, m.x + 2.0 * pad, pad), edge)         # below
	draw_rect(Rect2(-pad, 0, pad, m.y), edge)                       # left
	draw_rect(Rect2(m.x, 0, pad, m.y), edge)                        # right
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(size) * TILE), false)


## Names under crew and objects show only when you're close enough to press E.
func _update_labels() -> void:
	var me: Vector2 = mission.player.position
	for actor in mission.crew.values():
		if is_instance_valid(actor) and actor.name_label != null:
			actor.name_label.visible = actor.position.distance_to(me) <= LABEL_RANGE
	for prop in mission.props.values():
		if is_instance_valid(prop) and prop.caption != null:
			prop.caption.visible = prop.position.distance_to(me) <= LABEL_RANGE
