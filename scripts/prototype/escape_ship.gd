extends Node2D
## Draws the ship interior from data/escape_map.json (tools/make_escape_map.py):
## per-room floors, two-tile wall faces with vents/screens/lights, windows, door
## frames, the film's sealed barrier and the torn hull past it, room signs,
## floor and wall decals. Furniture becomes y-sorted sprites in the world
## (build_decor). Lighting: dim emergency light until the shuttle bay has power,
## rotating red alarm beacons spread around the ship (escape_alarm.gd), a pulsing reactor.
## Art: tools/make_ship_art.py.

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const ART := "res://assets/ship/"
const TILE := 32
const FACE_KINDS := ["plain", "plain", "plain", "plain", "vent", "screen", "pipe", "light", "panel", "plain", "light"]
const DIM := Color(0.74, 0.74, 0.86)       # emergency power
const LIT := Color(1, 1, 1)

var mission
var _tex := {}
var _fx: Node2D
var _modulate: CanvasModulate
var _t := 0.0
var _stars: Array[Vector3] = []
var _outside_crew: Sprite2D
## Rotating alarm beacons: about one per this many tiles of a room's width ...
const ALARM_WALL_PER_LAMP := 12.0
## ... and never closer together than this (tiles).
const ALARM_SPACING := 6.0
var _alarm_cells := {}
var _alarm_cells_ready := false


func _ready() -> void:
	z_index = -10
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var rng := RandomNumberGenerator.new()
	rng.seed = 2126
	var w: float = mission.map_size.x * TILE
	var h: float = mission.map_size.y * TILE
	for i in 520:
		_stars.append(Vector3(rng.randf_range(-600, w + 600), rng.randf_range(-400, h + 400), rng.randf()))
	_fx = FX.new()
	_fx.ship = self
	_fx.z_index = 5
	_fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mission.add_child.call_deferred(_fx)
	_modulate = CanvasModulate.new()
	_modulate.color = DIM
	mission.add_child.call_deferred(_modulate)
	_build_observation_view()


func _build_observation_view() -> void:
	var observation := _room_rect("OBSERVATION")
	if observation.size == Vector2.ZERO: return
	# Keep the distant figure behind the glass, inside its steel frame.
	var glass := Control.new()
	glass.position = Vector2(observation.position.x + 3 * TILE + 2, observation.position.y - TILE + 2)
	glass.size = Vector2(28, 20)
	glass.clip_contents = true
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass)
	_outside_crew = Sprite2D.new()
	_outside_crew.texture = preload("res://assets/intro/tiny_mint_0.png")
	_outside_crew.scale = Vector2(1.5, 1.5)
	_outside_crew.position = glass.size / 2.0
	_outside_crew.modulate = Color(0.8, 0.9, 1.0)
	glass.add_child(_outside_crew)


func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := ART + name + ".png"
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func _process(delta: float) -> void:
	_t += delta
	if _outside_crew != null:
		_outside_crew.position = Vector2(14 + roundf(3 * sin(_t * 0.23)), 10 + roundf(sin(_t * 0.31)))
		_outside_crew.rotation = -0.5 + 0.35 * sin(_t * 0.13)
	if _modulate != null and mission.state != null:
		var target := LIT if mission.state.powered() else DIM
		_modulate.color = _modulate.color.lerp(target, minf(1.0, delta * 2.0))


## Solid bases of the furniture (px rects), for collision and crew pathfinding.
func solid_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for d in mission.map_data.decor:
		if d.solid != null:
			out.append(Rect2(d.solid[0], d.solid[1], d.solid[2], d.solid[3]))
	# The shuttle's hull (its prop only has a small base where you board).
	var s: Dictionary = mission.map_data.props.shuttle
	out.append(Rect2(s.pos[0] - 70, s.pos[1] - 62, 150, 34))
	return out


## Furniture and standing objects as y-sorted sprites (bottom-centre on their spot).
func build_decor(world: Node2D) -> void:
	for d in mission.map_data.decor:
		if d.layer != "obj" and d.layer != "soft":
			continue
		var t := tex(d.sprite)
		if t == null:
			continue
		var node := Node2D.new()
		node.position = Vector2(d.pos[0], d.pos[1])
		var spr := Sprite2D.new()
		spr.texture = t
		spr.offset = Vector2(0, -t.get_height() / 2.0)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node.add_child(spr)
		world.add_child(node)


# --- Map queries -------------------------------------------------------------------

func _ch(x: int, y: int) -> String:
	return mission.cell_char(Vector2i(x, y))


func _is_floorish(ch: String) -> bool:
	return ch in [".", "D", "L", "s", "B"]


## A plain wall with its front face showing (floor below it, not the barrier).
func is_wall_face(x: int, y: int) -> bool:
	var below := _ch(x, y + 1)
	return _ch(x, y) == "#" and _is_floorish(below) and below != "B"


## Where the rotating alarm beacons hang (escape_alarm.gd makes them spin and flash).
func is_alarm_cell(x: int, y: int) -> bool:
	return alarm_cells().has(Vector2i(x, y))


## The beacons' wall tiles (Vector2i -> true), worked out once from the map:
## spread along the back wall of every open room, about one per ALARM_WALL_PER_LAMP
## tiles of room width and at least ALARM_SPACING tiles apart, never on a door
## frame, a wall screen or poster, or a room's name plate.
func alarm_cells() -> Dictionary:
	if not _alarm_cells_ready:
		_alarm_cells_ready = true
		_place_alarms()
	return _alarm_cells


func _place_alarms() -> void:
	var blocked := _alarm_blocked_rects()
	var placed: Array[Vector2i] = []
	var size: Vector2i = mission.map_size
	for room in mission.rooms:
		if room.sealed:
			continue
		var candidates: Array[Vector2i] = []
		for y in size.y:
			for x in size.x:
				if _alarm_spot_ok(x, y, room, blocked):
					candidates.append(Vector2i(x, y))
		if candidates.is_empty():
			continue  # no plain back wall (the observation lounge is all window)
		var rr: Array = room.rect
		var left: float = float(rr[0])
		var width: float = float(rr[2])
		var count: int = maxi(1, roundi(width / ALARM_WALL_PER_LAMP))
		# Each beacon gets an equal share of the room's width and hangs at the free
		# wall tile nearest its share's middle (ties: furthest from other beacons).
		var share: float = width / count
		for i in count:
			var target: float = left + (i + 0.5) * share
			var best := Vector2i(-1, -1)
			var best_d := INF
			var best_gap := -1.0
			for c in candidates:
				var d := absf(c.x + 0.5 - target)
				var gap := _gap(c, placed)
				if d > maxf(share / 2.0, 2.0) or gap < ALARM_SPACING:
					continue
				if d < best_d - 0.01 or (absf(d - best_d) <= 0.01 and gap > best_gap):
					best = c
					best_d = d
					best_gap = gap
			if best.x >= 0:
				placed.append(best)
				_alarm_cells[best] = true


func _alarm_spot_ok(x: int, y: int, room: Dictionary, blocked: Array[Rect2]) -> bool:
	if _ch(x, y) != "#" or _ch(x, y + 1) != ".":
		return false  # a plain wall with this room's floor right below
	if _room_at_cell(x, y + 1).get("key", "") != room.key:
		return false
	if _ch(x - 1, y) == "D" or _ch(x + 1, y) == "D":
		return false  # door frame
	var r := Rect2(x * TILE, y * TILE, TILE, TILE)
	for b in blocked:
		if b.intersects(r):
			return false
	return true


## Distance (tiles) from `c` to the nearest beacon already placed (INF if none).
func _gap(c: Vector2i, placed: Array[Vector2i]) -> float:
	var nearest := INF
	for p in placed:
		nearest = minf(nearest, Vector2(c - p).length())
	return nearest


## Wall decorations (screens, posters, boards) and the room name plates.
func _alarm_blocked_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for d in mission.map_data.decor:
		if d.layer == "wall":
			var t := tex(d.sprite)
			if t != null:
				out.append(Rect2(d.pos[0] - t.get_width() / 2.0, d.pos[1] - t.get_height(), t.get_width(), t.get_height()).grow(4.0))
	var font := UiStyle.font()
	for room in mission.rooms:
		var rr: Array = room.rect
		var label: String = room.name
		var plate := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		out.append(Rect2(rr[0] * TILE + 5, rr[1] * TILE - 23, plate.x + 6, 12).grow(4.0))  # as _draw_signs
	return out


func _room_at_cell(x: int, y: int) -> Dictionary:
	if y < 0 or y >= mission._room_grid.size() or x < 0 or x >= mission._room_grid[y].length():
		return {}
	return mission._room_by_key.get(mission._room_grid[y][x], {})


func _hash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663))


# --- Drawing -----------------------------------------------------------------------

func _draw() -> void:
	if mission == null or mission.map_data.is_empty():
		return
	var w: int = mission.map_size.x
	var h: int = mission.map_size.y
	draw_rect(Rect2(-800, -600, w * TILE + 1600, h * TILE + 1200), Color("05060f"))
	for s in _stars:
		draw_rect(Rect2(s.x, s.y, 2 if s.z > 0.9 else 1, 2 if s.z > 0.9 else 1),
			Color(0.6, 0.7, 0.95, 0.35 + 0.5 * s.z))
	for y in h:
		for x in w:
			var ch := _ch(x, y)
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			if _is_floorish(ch):
				_draw_floor(x, y, r)
			elif ch == "#" or ch == "w":
				_draw_wall(x, y, ch, r)
	_draw_doors()
	_draw_sealed()
	for d in mission.map_data.decor:
		if d.layer == "floor":
			_draw_decal(d)
	for d in mission.map_data.decor:
		if d.layer == "wall":
			_draw_decal(d)
	_draw_signs()
	if mission.state.has_flag("aux_off"):  # the cabin's lighting branch is cut
		for room in mission.rooms:
			if room.name == "CABIN":
				var rr: Array = room.rect
				draw_rect(Rect2(rr[0] * TILE, rr[1] * TILE, rr[2] * TILE, rr[3] * TILE), Color(0, 0, 0, 0.45))
	if mission.state.powered():  # bay guide lights come on
		var bay := _room_rect("SHUTTLE BAY")
		var x0 := bay.position.x + 16
		while x0 < bay.end.x - 16:
			draw_rect(Rect2(x0, bay.end.y - 10, 12, 3), Color("87d5b3"))
			x0 += 32


func _room_rect(name: String) -> Rect2:
	for room in mission.rooms:
		if room.name == name:
			var rr: Array = room.rect
			return Rect2(rr[0] * TILE, rr[1] * TILE, rr[2] * TILE, rr[3] * TILE)
	return Rect2()


func _draw_floor(x: int, y: int, r: Rect2) -> void:
	var room := _room_at_cell(x, y)
	var style: String = room.get("style", "deck")
	var sheet := tex("floor_" + style)
	if sheet == null:
		draw_rect(r, Color("343444"))
		return
	var hsh := _hash(x, y)
	var v := (hsh >> 3) % 4 if hsh % 5 == 0 else 0
	draw_texture_rect_region(sheet, r, Rect2((v % 2) * TILE, (v / 2) * TILE, TILE, TILE))
	# A soft shadow along the foot of the wall above.
	if _ch(x, y - 1) in ["#", "w"]:
		draw_rect(Rect2(r.position, Vector2(TILE, 6)), Color(0, 0, 0, 0.28))


func _draw_wall(x: int, y: int, ch: String, r: Rect2) -> void:
	var below := _ch(x, y + 1)
	var below2 := _ch(x, y + 2)
	if _is_floorish(below) and below != "B":
		var room := _room_at_cell(x, y + 1)
		var tint := Color.WHITE.lerp(Color(room.get("color", "ffffff")), 0.12)
		if ch == "w":
			draw_texture_rect(tex("window"), r, false)
		else:
			var kind: String = FACE_KINDS[_hash(x, y) % FACE_KINDS.size()]
			if is_alarm_cell(x, y):
				kind = "alarm"
			draw_texture_rect(tex("wall_face_" + kind), r, false, tint)
	elif (below == "#" or below == "w") and _is_floorish(below2) and below2 != "B":
		var room := _room_at_cell(x, y + 2)
		var tint := Color.WHITE.lerp(Color(room.get("color", "ffffff")), 0.12)
		draw_texture_rect(tex("window" if ch == "w" else "wall_face_upper"), r, false, tint)
	else:
		draw_texture_rect(tex("wall_cap"), r, false)


## Door frames: steel jambs either side of each opening, a dark track across it.
func _draw_doors() -> void:
	var w: int = mission.map_size.x
	var h: int = mission.map_size.y
	for y in h:
		for x in w:
			var ch := _ch(x, y)
			if ch != "D" and ch != "L":
				continue
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			var wall_l := _ch(x - 1, y) in ["#", "w"]
			var wall_r := _ch(x + 1, y) in ["#", "w"]
			var wall_u := _ch(x, y - 1) in ["#", "w"]
			var wall_d := _ch(x, y + 1) in ["#", "w"]
			if wall_l:
				draw_rect(Rect2(r.position.x, r.position.y, 5, TILE), Color("5f5c70"))
				draw_rect(Rect2(r.position.x + 1, r.position.y, 2, TILE), Color("7e7e8c"))
			if wall_r:
				draw_rect(Rect2(r.end.x - 5, r.position.y, 5, TILE), Color("5f5c70"))
				draw_rect(Rect2(r.end.x - 3, r.position.y, 2, TILE), Color("7e7e8c"))
			if wall_u:
				draw_rect(Rect2(r.position.x, r.position.y, TILE, 5), Color("5f5c70"))
			if wall_d:
				draw_rect(Rect2(r.position.x, r.end.y - 5, TILE, 5), Color("5f5c70"))
			# Amber dashes on the threshold, like the film's bulkhead frame.
			if (wall_l or wall_r) and not (wall_u or wall_d):
				var yy := r.position.y + (TILE - 4 if _ch(x, y + 1) not in ["D", "L"] else 0)
				if _ch(x, y + 1) not in ["D", "L"] or _ch(x, y - 1) not in ["D", "L"]:
					for k in 4:
						draw_rect(Rect2(r.position.x + 4 + k * 7, yy, 4, 3), Color("ffa300"))


## Past the barrier: the slab itself, the sealed area lit red, torn hull edges.
func _draw_sealed() -> void:
	var w: int = mission.map_size.x
	var h: int = mission.map_size.y
	var bounds := Rect2()
	for y in h:
		for x in w:
			var ch := _ch(x, y)
			if ch == "B":
				var r := Rect2(x * TILE, y * TILE, TILE, TILE)
				bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)
			elif ch == "s":
				draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), Color(0.35, 0.02, 0.08, 0.28))
			elif ch == " ":
				# Void touching the sealed floor = the torn hull: jagged steel edge.
				for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
					if _ch(x + d.x, y + d.y) == "s":
						var hsh := _hash(x, y)
						for k in 8:
							var off := float((hsh >> k) % 7)
							var p := Vector2(x * TILE + k * 4, y * TILE + TILE - 4 - off) if d.y == 1 \
								else Vector2(x * TILE + (TILE - 4 - off if d.x == 1 else off), y * TILE + k * 4)
							draw_rect(Rect2(p, Vector2(4, 4)), Color("7e7e8c"))
	if bounds.size != Vector2.ZERO and tex("bulkhead") != null:
		draw_texture_rect(tex("bulkhead"), bounds, false)


func _draw_decal(d: Dictionary) -> void:
	var t := tex(d.sprite)
	if t == null:
		return
	draw_texture(t, Vector2(d.pos[0] - t.get_width() / 2.0, d.pos[1] - t.get_height()))


## Room names as small plates on each room's back wall.
func _draw_signs() -> void:
	var font := UiStyle.font()
	for room in mission.rooms:
		var rr: Array = room.rect
		var label: String = room.name
		var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		var p := Vector2(rr[0] * TILE + 8, rr[1] * TILE - 14)
		draw_rect(Rect2(p - Vector2(3, 9), Vector2(size.x + 6, 12)), Color(0.02, 0.03, 0.08, 0.8))
		draw_string(font, p, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(room.color))


## Things that move every frame: the reactor glow, the flickering
## MAIN POWER OFFLINE screen, the red wash past the barrier.
class FX extends Node2D:
	var ship

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var m = ship.mission
		if m == null or m.map_data.is_empty():
			return
		var t: float = ship._t
		var powered: bool = m.state.powered()
		# The corridor's rotating alarm beacons are escape_alarm.gd (above the dark).
		var pulse := 0.5 + 0.5 * sin(t * TAU * 1.6)
		# The reactor breathes; brighter once power is restored.
		for d in m.map_data.decor:
			if d.sprite == "reactor":
				var c := Vector2(d.pos[0], d.pos[1] - 44)
				var k := (0.6 if powered else 0.3) + 0.15 * sin(t * 2.4)
				draw_circle(c, 26, Color(0.25, 0.8, 1.0, 0.10 * k))
				draw_circle(c, 14, Color(0.4, 0.95, 1.0, 0.25 * k))
			elif d.sprite == "power_terminal" and not powered:
				# The screen flickers like in the film.
				if int(t * 7.0) % 9 == 0:
					var tt: Texture2D = ship.tex(d.sprite)
					draw_rect(Rect2(d.pos[0] - tt.get_width() / 2.0 + 4, d.pos[1] - tt.get_height() + 4,
						tt.get_width() - 8, tt.get_height() - 14), Color(0, 0, 0, 0.6))
		# Red emergency wash past the barrier.
		for room in m.rooms:
			if room.sealed:
				var rr: Array = room.rect
				draw_rect(Rect2(rr[0] * TILE, rr[1] * TILE, rr[2] * TILE, rr[3] * TILE),
					Color(1, 0.05, 0.15, 0.05 + 0.05 * pulse))
