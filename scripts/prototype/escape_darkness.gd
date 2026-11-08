extends Node
## Ship lighting for the escape mission, using Godot's 2D lights and shadows.
## Without power the ship is dark:
##   - a soft light of about 6 x 6 tiles always surrounds Johnny;
##   - F toggles a flashlight BEAM pointing the way you face (up/down/left/right);
##     it swings smoothly when you turn and widens out from your light circle;
##   - crewmates can be asked to turn on their own flashlight; it points the way
##     they walk (or the direction you asked for while they stand still);
##   - WALLS BLOCK LIGHT: every wall casts shadows, so you can't see through walls
##     (doorways let light through; the jammed locker blocks it until it's pushed);
##   - unlit people and objects stay in the dark (unlit = black);
##   - exception: the jammed locker shows when your light reaches it, even through its wall;
##   - name labels (AARON, DHAN, SPARE FUSE...) show only within E range.
## When power comes back the ship lights up and the flashlights switch off.

const TILE := 32.0
const BASE_RADIUS := 3.0 * TILE         # always lit around you: ~6 x 6 tiles
const BEAM_RANGE := 8.0 * TILE          # how far a flashlight beam reaches
const BEAM_HALF_ANGLE := deg_to_rad(24.0)
const BEAM_START_WIDTH := BASE_RADIUS * 0.75  # beam leaves your circle this wide: no sharp tip
const TURN_SPEED := 10.0                # how fast a beam swings to a new direction
const LABEL_RANGE := 52.0               # names show within E range (player reach 44)
const DARK_TINT := Color(0.006, 0.007, 0.014)  # unlit = black: nothing shows beyond your light
const FADE_SECONDS := 1.5
const TEX := 256                        # light texture size
## Light layers: 1 = everything; 2 = SEE_THROUGH: lit when in reach but never shadowed
## (the jammed locker, so you can find it even though it sits in the wall line).
const LAYER_NORMAL := 1
## Which occluder edges are ignored, so light can enter a wall from the front.
const OCCLUDER_CULL := OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
const LAYER_SEE_THROUGH := 2

static var _glow_tex: Texture2D
static var _beam_tex: Texture2D

var mission
var flashlight := false
## Direction you face (last way you moved), snapped to up/down/left/right.
var facing := Vector2.RIGHT
## Beam directions as drawn ("player" and crew ids); they swing toward their target.
var _beam_dirs := {}
var _tint: CanvasModulate
var _glow: PointLight2D
var _beam: PointLight2D
var _crew_beams := {}        # crew id -> PointLight2D
var _locker_occluder: LightOccluder2D
var occluder_count := 0
var _dark := 1.0             # 1 = no power, 0 = lights on (fades between)


func _ready() -> void:
	_make_textures()
	_tint = CanvasModulate.new()
	mission.add_child(_tint)
	_build_occluders()
	_glow = _make_light(_glow_tex, BASE_RADIUS / (TEX / 2.0), 1.0)
	mission.player.add_child(_glow)
	_beam = _make_light(_beam_tex, BEAM_RANGE / (TEX / 2.0), 1.15)
	mission.player.add_child(_beam)
	for id in mission.crew.keys():
		var light := _make_light(_beam_tex, BEAM_RANGE / (TEX / 2.0), 1.0)
		mission.crew[id].add_child(light)
		_crew_beams[id] = light
	_mark_see_through()
	_dark = 0.0 if is_powered() else 1.0
	_apply(0.0)


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
		return _beam.enabled
	return _crew_beams.has(id) and _crew_beams[id].enabled


func _process(delta: float) -> void:
	if mission == null or mission.player == null:
		return
	_dark = move_toward(_dark, 0.0 if is_powered() else 1.0, delta / FADE_SECONDS)
	if mission.player.velocity.length() > 5.0:
		facing = snap_direction(mission.player.velocity)
	_apply(delta)
	_update_labels()


func _apply(delta: float) -> void:
	_tint.color = DARK_TINT.lerp(Color.WHITE, 1.0 - _dark)
	_tint.visible = _dark > 0.001
	var weight := 1.0 - exp(-TURN_SPEED * delta) if delta > 0.0 else 1.0
	# Your light circle and flashlight.
	_glow.enabled = _dark > 0.001
	_glow.energy = _dark
	_beam_dirs["player"] = _swing(_beam_dirs.get("player", facing), facing, weight)
	_beam.enabled = flashlight and _dark > 0.001
	_beam.energy = 1.15 * _dark
	_beam.rotation = _beam_dirs["player"].angle()
	# Crew flashlights: they point where the crewmate walks.
	for id in _crew_beams.keys():
		var actor = mission.crew[id]
		var light: PointLight2D = _crew_beams[id]
		if actor.light_on and _dark > 0.001:
			var want: Vector2 = actor.facing
			_beam_dirs[id] = _swing(_beam_dirs.get(id, want), want, weight)
			light.rotation = _beam_dirs[id].angle()
			light.energy = _dark
			light.enabled = true
		else:
			_beam_dirs.erase(id)
			light.enabled = false
	if _locker_occluder != null:
		_locker_occluder.visible = not mission.state.has_flag("locker_clear")
	if not is_dark():
		flashlight = false


## Exception to "walls block light": the jammed locker shows whenever your light
## reaches it, even through the wall it sits in.
func _mark_see_through() -> void:
	var nodes: Array = []
	if mission.locker_visual != null:
		nodes.append(mission.locker_visual)
	if mission.props.has("locker"):
		nodes.append(mission.props["locker"])
	for node in nodes:
		_set_light_layer(node, LAYER_SEE_THROUGH)


static func _set_light_layer(node: Node, layer: int) -> void:
	if node is CanvasItem:
		node.light_mask = layer
	for child in node.get_children():
		_set_light_layer(child, layer)


static func _swing(current: Vector2, target: Vector2, weight: float) -> Vector2:
	return Vector2.from_angle(lerp_angle(current.angle(), target.angle(), weight))


func _make_light(texture: Texture2D, scale: float, energy: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = texture
	light.texture_scale = scale
	light.energy = energy
	light.position = Vector2(0, -16)  # from the body, not the feet
	light.shadow_enabled = true
	light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	light.shadow_filter_smooth = 1.5
	light.shadow_color = Color(0, 0, 0, 1)
	light.range_item_cull_mask = LAYER_NORMAL | LAYER_SEE_THROUGH  # lights reach both layers
	light.shadow_item_cull_mask = LAYER_NORMAL                    # ...but only layer 1 gets shadows
	light.enabled = false
	return light


## Walls cast shadows. The occluders cover the whole wall mass (including the
## two-tile wall faces), merged into rectangles, and are ONE-SIDED: light enters a
## wall and lights it, then stops at its far edge. So walls in your light or
## flashlight are visible, and nothing behind them is.
func _build_occluders() -> void:
	var cells := {}
	for cell in mission.walls.keys():
		cells[cell] = true
	for y in mission.map_size.y:
		for x in mission.map_size.x:
			if mission.cell_char(Vector2i(x, y)) in ["#", "w"]:
				cells[Vector2i(x, y)] = true
	# Greedy rectangles: run right, then grow down while the same run is all wall.
	var used := {}
	for y in mission.map_size.y:
		for x in mission.map_size.x:
			var c := Vector2i(x, y)
			if not cells.has(c) or used.has(c):
				continue
			var w := 1
			while cells.has(Vector2i(x + w, y)) and not used.has(Vector2i(x + w, y)):
				w += 1
			var h := 1
			while true:
				var full := true
				for dx in w:
					var n := Vector2i(x + dx, y + h)
					if not cells.has(n) or used.has(n):
						full = false
						break
				if not full:
					break
				h += 1
			for dy in h:
				for dx in w:
					used[Vector2i(x + dx, y + dy)] = true
			_add_occluder(Rect2(Vector2(x, y) * TILE, Vector2(w, h) * TILE))
	# The jammed locker blocks light until it's pushed out of the hallway.
	var locker: Array = mission._locker_cells()
	if not locker.is_empty():
		var r := Rect2(Vector2(locker[0]) * TILE, Vector2(TILE, TILE))
		for c in locker:
			r = r.merge(Rect2(Vector2(c) * TILE, Vector2(TILE, TILE)))
		_locker_occluder = _add_occluder(r)


func _add_occluder(r: Rect2) -> LightOccluder2D:
	var poly := OccluderPolygon2D.new()
	poly.cull_mode = OCCLUDER_CULL  # one-sided: the wall itself gets lit
	poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	mission.add_child(occ)
	occluder_count += 1
	return occ


## Light textures, made once: a soft round glow and a flashlight beam that
## starts as wide as the glow and widens with distance (no triangle tip).
static func _make_textures() -> void:
	if _glow_tex != null:
		return
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.55, Color(1, 1, 1, 0.9))
	var glow := GradientTexture2D.new()
	glow.gradient = grad
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	glow.width = TEX
	glow.height = TEX
	_glow_tex = glow
	# Beam: the texture's centre is the light's origin; it points to +x.
	var half := TEX / 2.0
	var px_per_world := half / BEAM_RANGE
	var start_w := BEAM_START_WIDTH * px_per_world
	var spread := tan(BEAM_HALF_ANGLE)
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	for y in TEX:
		for x in TEX:
			var along := x - half
			var perp := absf(y - half)
			var half_w := start_w + maxf(along, 0.0) * spread
			var side := 1.0 - smoothstep(half_w * 0.5, half_w, perp)
			var back := smoothstep(-start_w * 0.5, start_w * 0.6, along)
			var reach := 1.0 - smoothstep(half * 0.55, half, along)
			img.set_pixel(x, y, Color(1, 1, 1, side * back * reach))
	_beam_tex = ImageTexture.create_from_image(img)


## Names under crew and objects show only when you're close enough to press E.
func _update_labels() -> void:
	var me: Vector2 = mission.player.position
	for actor in mission.crew.values():
		if is_instance_valid(actor) and actor.name_label != null:
			actor.name_label.visible = actor.position.distance_to(me) <= LABEL_RANGE
	for prop in mission.props.values():
		if is_instance_valid(prop) and prop.caption != null:
			prop.caption.visible = prop.position.distance_to(me) <= LABEL_RANGE
