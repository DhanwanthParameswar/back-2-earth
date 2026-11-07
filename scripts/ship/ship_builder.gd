extends Node2D
## Builds the whole ship from data/ship_layout.txt (see data/LAYOUT_LEGEND.md).
## Owner: B. One connected map, no scene transitions.
##
## Walls become merged rectangle colliders; objects are instantiated at their
## characters. Swapping art never changes collisions: tiles are always 32x32.

const Art = preload("res://scripts/ship/art.gd")
const Door = preload("res://scripts/interactables/door.gd")
const ObjectiveConsole = preload("res://scripts/interactables/objective_console.gd")
const CorePickup = preload("res://scripts/interactables/core_pickup.gd")
const EscapePod = preload("res://scripts/interactables/escape_pod.gd")
const CargoSled = preload("res://scripts/interactables/cargo_sled.gd")
const Debris = preload("res://scripts/interactables/debris.gd")

const TILE := Art.TILE
const BLOCKING := "#w|CS"
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
	"T": ["start_evacuation", "Start evacuation", "res://assets/sprites/terminal.png", Art.CYAN],
	"P": ["restore_power", "Restore power", "res://assets/sprites/power_console.png", Art.AMBER],
	"L": ["release_clamp", "Release pod clamp", "res://assets/sprites/clamp_console.png", Art.AMBER],
}

## Rooms, left to right, split at the columns of doors 1, 2, 3.
const ROOM_ORDER := ["cockpit", "engineering", "cargo", "pod_bay"]
const ROOM_SPLIT_DOORS := ["1", "2", "3"]

## Used only if data/ship_layout.txt is missing (e.g. a build that forgot the
## export filter). Keep in sync when the layout settles.
const DEFAULT_LAYOUT := """
##############################################
#.........#.........#.C...x..#....#..x.......#
#....T....#.........#.|......#.N..#....L.....#
w.........#.........#.|......#....#..........#
w.........#.........#.S......##KK##..........#
w.........1.........2.............3..........#
w..@......1.........2.............3.......O..#
w.........#.........#.............#..........#
w.........#.........#.............#..........#
#.........#....P....#.............#..........#
#.........#.........#......x......#..........#
##############################################
"""

var grid: Array[String] = []
var width := 0
var height := 0
var player_start := Vector2(64, 64)
var _room_split_cols: Array[int] = []
var _debris_cols: Array[int] = []

var _tex := {}


func _ready() -> void:
	add_to_group("ship")


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
		grid[i] = grid[i].rpad(width, "#")

	_load_textures()
	_build_walls()
	_build_doors()
	_build_objects()
	_find_room_splits()
	queue_redraw()


func cell(c: int, r: int) -> String:
	if r < 0 or r >= height or c < 0 or c >= width:
		return "#"
	return grid[r][c]


func cell_center(c: int, r: int) -> Vector2:
	return Vector2(c * TILE + TILE / 2.0, r * TILE + TILE / 2.0)


func get_bounds() -> Rect2:
	return Rect2(0, 0, width * TILE, height * TILE)


## Room id for a world position (used by the player -> GameState.set_room).
func room_at(world_pos: Vector2) -> String:
	var col := int(floor(world_pos.x / TILE))
	for i in _room_split_cols.size():
		if col <= _room_split_cols[i]:
			return ROOM_ORDER[i]
	return ROOM_ORDER[mini(_room_split_cols.size(), ROOM_ORDER.size() - 1)]


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
				console.position = pos
				add_child(console)
			elif ch == "N":
				var core := CorePickup.new()
				core.name = "NavigationCore"
				core.position = pos
				add_child(core)
			elif ch == "O":
				var pod := EscapePod.new()
				pod.name = "EscapePod"
				pod.position = pos
				add_child(pod)
			elif ch == "C":
				sled_start = pos
			elif ch == "S":
				sled_end = pos
			elif ch == "x":
				var d := Debris.new()
				d.position = pos
				add_child(d)
				if not _debris_cols.has(c):
					_debris_cols.append(c)
			elif ch == "@":
				player_start = pos
				found_player = true

	if sled_start != Vector2.INF and sled_end != Vector2.INF:
		var sled := CargoSled.new()
		sled.name = "CargoSled"
		sled.setup(sled_start, sled_end)
		add_child(sled)
	else:
		push_warning("Layout needs both C (sled start) and S (pressure plate).")
	if not found_player:
		push_warning("Layout has no @ player start.")


func _find_room_splits() -> void:
	_room_split_cols.clear()
	for door_char in ROOM_SPLIT_DOORS:
		var col := -1
		for r in height:
			var idx := grid[r].find(door_char)
			if idx >= 0:
				col = idx
				break
		if col >= 0:
			_room_split_cols.append(col)
	_room_split_cols.sort()


# --- Drawing ------------------------------------------------------------------

func _load_textures() -> void:
	for key in ["floor", "wall", "window", "rail"]:
		_tex[key] = Art.tex("res://assets/tiles/%s.png" % key)


func _draw() -> void:
	for r in height:
		for c in width:
			var ch := cell(c, r)
			var pos := Vector2(c * TILE, r * TILE)
			var rect := Rect2(pos, Vector2(TILE, TILE))
			if ch == "#":
				_draw_tile("wall", pos, rect, Art.STEEL)
			elif ch == "w":
				# Leave the glass empty so the black-hole backdrop shows through.
				_draw_tile("window", pos, rect, Color(0, 0, 0, 0))
			elif CHANNEL.contains(ch):
				_draw_tile("rail", pos, rect, Art.NAVY.darkened(0.4))
			else:
				_draw_tile("floor", pos, rect, Art.NAVY)
	# Hazard lane markers under each debris column (danger shown by shape too).
	for c in _debris_cols:
		for r in range(1, height - 1):
			if not BLOCKING.contains(cell(c, r)):
				var p := cell_center(c, r)
				draw_rect(Rect2(p + Vector2(-2, -2), Vector2(4, 4)), Color(Art.RED, 0.45))


func _draw_tile(key: String, pos: Vector2, rect: Rect2, fallback: Color) -> void:
	var t: Texture2D = _tex.get(key)
	if t != null:
		draw_texture(t, pos)
	elif fallback.a > 0.0:
		draw_rect(rect, fallback)
