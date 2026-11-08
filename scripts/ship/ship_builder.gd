extends Node2D
## Builds the whole ship from data/ship_layout.txt (see data/LAYOUT_LEGEND.md).
## Owner: B. One connected map, no scene transitions.
##
## Walls become merged rectangle colliders; objects are instantiated at their
## characters. Swapping art never changes collisions: tiles are always 32x32.
##
## Stardew-style 3/4 view:
##   - Walls with floor below them draw a FRONT FACE (2 tiles tall where two
##     walls are stacked, like the back wall); other walls draw their top cap.
##   - This node has y_sort_enabled: the player, props, and debris are its
##     children and draw in order of their base/feet y. Tiles and doors are the
##     ground layer underneath.
##   - The floor is ONE continuous texture sampled by world position (no tile
##     grid). assets/tiles/floor.png can be any size that is a multiple of 32.
##   - `W` cells form windows onto space: main.gd puts a SpaceWindow (video)
##     behind each one; this script draws the frame, sill, and glare on top.
##   - `~` is open space outside the hull: blocking, drawn as nothing, so the
##     Starfield (and the black hole) behind the ship shows through. A wall
##     with space below it draws the hull's side (`hull` tile), so the outline
##     of the map reads as the ship from the opening film.
##   - Rooms can be any shape: they're found by flood fill from `@` through
##     doors 1, 2, 3 (cockpit, engineering, cargo, pod bay), not by columns.

const Art = preload("res://scripts/ship/art.gd")
const Door = preload("res://scripts/interactables/door.gd")
const ObjectiveConsole = preload("res://scripts/interactables/objective_console.gd")
const CorePickup = preload("res://scripts/interactables/core_pickup.gd")
const EscapePod = preload("res://scripts/interactables/escape_pod.gd")
const CargoSled = preload("res://scripts/interactables/cargo_sled.gd")
const Debris = preload("res://scripts/interactables/debris.gd")
const Crewmate = preload("res://scripts/interactables/crewmate.gd")

const TILE := Art.TILE
const VOID := "~"
const BLOCKING := "#wW|CS~"
const SOLID_WALL := "#wW"
## How far below a cell's center an object's base (y-sort point) sits.
const CONSOLE_BASE := 14.0
const CORE_BASE := 6.0
const POD_BASE := 28.0
const SLED_BASE := 14.0
const NPC_BASE := 10.0
const CHANNEL := "|CS"

## Door char -> objective that opens it.
const DOOR_UNLOCKS := {
	"1": "start_evacuation",
	"2": "restore_power",
	"K": "open_compartment",
	"3": "collect_core",
}

## Console char -> [objective_id, prompt, texture, fallback color]
const CONSOLES := {
	"T": ["start_evacuation", "Restore emergency power", "res://assets/sprites/terminal.png", Art.CYAN],
	"P": ["restore_power", "Restore main power", "res://assets/sprites/power_console.png", Art.AMBER],
	"L": ["release_clamp", "Release pod clamp", "res://assets/sprites/clamp_console.png", Art.AMBER],
}

## Rooms in the order you reach them: the one with `@`, then through door 1, 2, 3.
const ROOM_ORDER := ["cockpit", "engineering", "cargo", "pod_bay"]
const ROOM_DOORS := ["1", "2", "3"]

## Used only if data/ship_layout.txt is missing (e.g. a build that forgot the
## export filter). Keep in sync when the layout settles.
const DEFAULT_LAYOUT := """
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~##C##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~#.|.##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~##.|..##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~##..|...#~~~~~#################~~~~~~~~~~~~~~~~
~~~~~~~~~#...|...########################WWWW~~~~~~~~~~~
~~~~~#####...|....#####..#.........P...##WWWW###~~~~~~~~
~#########...S......x....#.............#..T..#####~~~~~~
~####.L..#...............#..x..........#M.......###~~~~~
~#.......3...............2.....####....1..........###~~~
~#.......3...............2.....####....1....@......##~~~
~#.O.....#...............#.......##....#.........###~~~~
~#.......#.............x.#...........x.#.......###~~~~~~
~#####...#...............#.............#....####~~~~~~~~
~~~~~#####...............#.............######~~~~~~~~~~~
~~~~~~~~~###KK###################..#####~~~~~~~~~~~~~~~~
~~~~~~~~~##.....##~~~~~~~~~~~~~~####~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~#..N.##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~##..##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~#.##~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~###~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
"""

var grid: Array[String] = []
var width := 0
var height := 0
var player_start := Vector2(64, 64)
## World rects of each `W` window (one per connected group of cells).
var space_windows: Array[Rect2] = []
var _side_windows: Array[Rect2] = []  # `w` groups (black-hole view)
var _room_of := {}  # Vector2i cell -> room id
var _debris_cols: Array[int] = []

var _tex := {}


func _ready() -> void:
	add_to_group("ship")
	y_sort_enabled = true


func build_from_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		push_warning("Ship layout missing or empty (%s); using the built-in copy." % path)
		text = DEFAULT_LAYOUT
	build_from_text(text)


func build_from_text(text: String) -> void:
	grid.clear()
	for line in text.split("\n"):
		var l := line.strip_edges(false, true)  # keep leading spaces, drop \r
		if l != "":
			grid.append(l)
	height = grid.size()
	width = 0
	for row in grid:
		width = maxi(width, row.length())
	for i in height:
		grid[i] = grid[i].rpad(width, VOID)

	_load_textures()
	_build_walls()
	_build_doors()
	_build_objects()
	_find_rooms()
	_find_space_windows()
	queue_redraw()


func cell(c: int, r: int) -> String:
	if r < 0 or r >= height or c < 0 or c >= width:
		return VOID
	return grid[r][c]


func cell_center(c: int, r: int) -> Vector2:
	return Vector2(c * TILE + TILE / 2.0, r * TILE + TILE / 2.0)


func get_bounds() -> Rect2:
	return Rect2(0, 0, width * TILE, height * TILE)


## Room id for a world position (used by the player -> GameState.set_room).
## Off the walkable cells (e.g. inside a wall), the nearest room within 2 cells.
func room_at(world_pos: Vector2) -> String:
	var here := Vector2i(int(floor(world_pos.x / TILE)), int(floor(world_pos.y / TILE)))
	for radius in 3:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var key := here + Vector2i(dx, dy)
				if _room_of.has(key):
					return _room_of[key]
	return ROOM_ORDER[0]


## The tip of the nose (right edge of the rightmost hull cell), in world px.
## main.gd parks the black hole just ahead of it.
func nose_point() -> Vector2:
	for c in range(width - 1, -1, -1):
		var rows: Array[int] = []
		for r in height:
			if cell(c, r) != VOID:
				rows.append(r)
		if not rows.is_empty():
			return Vector2((c + 1) * TILE, (rows[0] + rows[-1] + 1) * TILE / 2.0)
	return Vector2(width * TILE, height * TILE / 2.0)


# --- Building -----------------------------------------------------------------

func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	# Merge horizontal runs of blocking cells into one rectangle each.
	for r in height:
		var c := 0
		while c < width:
			if BLOCKING.contains(cell(c, r)):
				var start := c
				while c < width and BLOCKING.contains(cell(c, r)):
					c += 1
				var shape := RectangleShape2D.new()
				shape.size = Vector2((c - start) * TILE, TILE)
				var cs := CollisionShape2D.new()
				cs.shape = shape
				cs.position = Vector2(start * TILE, r * TILE) + shape.size / 2.0
				walls.add_child(cs)
			else:
				c += 1


func _build_doors() -> void:
	for door_char in DOOR_UNLOCKS.keys():
		var cells: Array = []
		for r in height:
			for c in width:
				if cell(c, r) == door_char:
					cells.append(Vector2i(c, r))
		if cells.is_empty():
			push_warning("Layout has no door '%s'" % door_char)
			continue
		var door := Door.new()
		door.name = "Door_%s" % door_char
		door.setup(cells, DOOR_UNLOCKS[door_char])
		add_child(door)


func _build_objects() -> void:
	var sled_start := Vector2.INF
	var sled_end := Vector2.INF
	var found_player := false
	_debris_cols.clear()

	for r in height:
		for c in width:
			var ch := cell(c, r)
			var pos := cell_center(c, r)
			if CONSOLES.has(ch):
				var cfg: Array = CONSOLES[ch]
				var console := ObjectiveConsole.new()
				console.name = "Console_%s" % cfg[0]
				console.setup(cfg[0], cfg[1], cfg[2], cfg[3])
				console.position = pos + Vector2(0, CONSOLE_BASE)
				add_child(console)
			elif ch == "N":
				var core := CorePickup.new()
				core.name = "NavigationCore"
				core.position = pos + Vector2(0, CORE_BASE)
				add_child(core)
			elif ch == "O":
				var pod := EscapePod.new()
				pod.name = "EscapePod"
				pod.position = pos + Vector2(0, POD_BASE)
				add_child(pod)
			elif ch == "C":
				sled_start = pos + Vector2(0, SLED_BASE)
			elif ch == "S":
				sled_end = pos + Vector2(0, SLED_BASE)
			elif ch == "x":
				var d := Debris.new()
				d.position = pos
				add_child(d)
				if not _debris_cols.has(c):
					_debris_cols.append(c)
			elif ch == "@":
				player_start = pos
				found_player = true
			elif ch == "M":
				var mate := Crewmate.new()
				mate.name = "Crewmate"
				mate.position = pos + Vector2(0, NPC_BASE)
				add_child(mate)

	if sled_start != Vector2.INF and sled_end != Vector2.INF:
		var sled := CargoSled.new()
		sled.name = "CargoSled"
		sled.setup(sled_start, sled_end)
		add_child(sled)
	else:
		push_warning("Layout needs both C (sled start) and S (pressure plate).")
	if not found_player:
		push_warning("Layout has no @ player start.")


## Label every walkable cell with its room: flood from `@` without crossing
## doors 1/2/3 (cockpit), then from beyond door 1 (engineering), and so on.
## Door cells belong to the room they open into.
func _find_rooms() -> void:
	_room_of.clear()
	var start := Vector2i(int(player_start.x / TILE), int(player_start.y / TILE))
	_flood_room(start, ROOM_ORDER[0])
	for i in ROOM_DOORS.size():
		var room: String = ROOM_ORDER[mini(i + 1, ROOM_ORDER.size() - 1)]
		for r in height:
			for c in width:
				if cell(c, r) != ROOM_DOORS[i]:
					continue
				_room_of[Vector2i(c, r)] = room
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n: Vector2i = Vector2i(c, r) + d
					if not _room_of.has(n):
						_flood_room(n, room)


func _flood_room(from: Vector2i, room: String) -> void:
	var stack: Array[Vector2i] = [from]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		var ch := cell(p.x, p.y)
		if _room_of.has(p) or BLOCKING.contains(ch) or ROOM_DOORS.has(ch):
			continue
		_room_of[p] = room
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(p + d)


func _find_space_windows() -> void:
	space_windows = _find_groups("W")
	_side_windows = _find_groups("w")


## Bounding rects (world px) of each connected group of `ch` cells.
func _find_groups(ch: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var seen := {}
	for r in height:
		for c in width:
			if cell(c, r) != ch or seen.has(Vector2i(c, r)):
				continue
			var lo := Vector2i(c, r)
			var hi := Vector2i(c, r)
			var stack: Array[Vector2i] = [Vector2i(c, r)]
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				if seen.has(p) or cell(p.x, p.y) != ch:
					continue
				seen[p] = true
				lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
				hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					stack.append(p + d)
			out.append(Rect2(Vector2(lo * TILE), Vector2((hi - lo + Vector2i.ONE) * TILE)))
	return out


# --- Drawing ------------------------------------------------------------------

## Which wall tile to draw (3/4 view): a front face where the floor is visible
## below it, the upper half of a 2-tall face above that, otherwise the top cap.
func wall_kind(c: int, r: int) -> String:
	if cell(c, r + 1) == VOID:
		return "hull"
	if not SOLID_WALL.contains(cell(c, r + 1)):
		return "wall_face" if cell(c, r - 1) == "#" else "wall_face_single"
	if cell(c, r + 1) == "#" and not SOLID_WALL.contains(cell(c, r + 2)):
		return "wall_face_upper"
	return "wall"


func _load_textures() -> void:
	for key in ["floor", "wall", "wall_face", "wall_face_upper", "wall_face_single", "rail", "hull"]:
		_tex[key] = Art.tex("res://assets/tiles/%s.png" % key)


func _draw() -> void:
	for r in height:
		for c in width:
			var ch := cell(c, r)
			var pos := Vector2(c * TILE, r * TILE)
			var rect := Rect2(pos, Vector2(TILE, TILE))
			if ch == VOID:
				continue  # open space: the Starfield behind shows through
			if ch == "#":
				var kind := wall_kind(c, r)
				_draw_tile(kind, pos, rect, Art.STEEL if kind == "wall" else Art.STEEL_LIGHT.darkened(0.4))
			elif ch == "w" or ch == "W":
				pass  # glass: the view behind shows through; one frame per window below
			elif CHANNEL.contains(ch):
				_draw_tile("rail", pos, rect, Art.NAVY.darkened(0.4))
			else:
				_draw_floor(rect)

	# Debris lanes: two faint red guide lines down each lane (danger by shape too).
	for c in _debris_cols:
		var x := c * TILE + TILE / 2.0
		for r in height:
			if not BLOCKING.contains(cell(c, r)):
				for side in [-11.0, 11.0]:
					draw_rect(Rect2(Vector2(x + side - 1.0, r * TILE), Vector2(2, TILE)), Color(Art.RED, 0.35))

	for wr in space_windows:
		_draw_window_frame(wr)
	for wr in _side_windows:
		_draw_window_frame(wr)


## Continuous floor: each cell shows its own part of one big texture.
func _draw_floor(rect: Rect2) -> void:
	var t: Texture2D = _tex.get("floor")
	if t == null:
		draw_rect(rect, Art.NAVY)
		return
	var src := Rect2(
		Vector2(fposmod(rect.position.x, t.get_width()), fposmod(rect.position.y, t.get_height())),
		rect.size
	)
	draw_texture_rect_region(t, rect, src)


## One pane, no grid: thick frame, a lit inner edge, a sill, and soft glare.
func _draw_window_frame(r: Rect2) -> void:
	var frame := Color("3a3848")
	var lit := Color("707a9c")
	var sill := Color("5f5c70")
	var t := 6.0
	draw_rect(Rect2(r.position, Vector2(r.size.x, t)), frame)                                  # top
	draw_rect(Rect2(r.position, Vector2(t, r.size.y)), frame)                                  # left
	draw_rect(Rect2(Vector2(r.end.x - t, r.position.y), Vector2(t, r.size.y)), frame)          # right
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - 8.0), Vector2(r.size.x, 8.0)), sill)       # sill
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - 2.0), Vector2(r.size.x, 2.0)), Color("282c40"))
	draw_rect(Rect2(r.position + Vector2(t, t), Vector2(r.size.x - 2.0 * t, 2.0)), lit)         # inner lit edge
	# Glare: two soft diagonal streaks across wide panes.
	if r.size.x <= r.size.y:
		return
	var glass_top := r.position.y + t
	var glass_bottom := r.end.y - 8.0
	for gx in [r.position.x + r.size.x * 0.22, r.position.x + r.size.x * 0.3]:
		draw_line(Vector2(gx, glass_bottom), Vector2(gx + 18.0, glass_top), Color(1, 1, 1, 0.07), 6.0)


func _draw_tile(key: String, pos: Vector2, rect: Rect2, fallback: Color) -> void:
	var t: Texture2D = _tex.get(key)
	if t != null:
		draw_texture(t, pos)
	elif fallback.a > 0.0:
		draw_rect(rect, fallback)
