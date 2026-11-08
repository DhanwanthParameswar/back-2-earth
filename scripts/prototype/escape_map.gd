extends Control
## The Tab map: the ship's rooms from data/escape_map.json, crew and player dots.
const UiStyle = preload("res://scripts/ui/ui_style.gd")

var mission

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if mission == null or mission.map_data.is_empty(): return
	var world: Vector2 = Vector2(mission.map_size * mission.TILE)
	var k := minf(size.x / world.x, size.y / world.y)
	var origin := (size - world * k) / 2.0
	var cell: float = mission.TILE * k
	for y in mission.map_size.y:
		var row: String = mission._room_grid[y]
		for x in mission.map_size.x:
			var key := row[x]
			if not mission._room_by_key.has(key): continue
			var room: Dictionary = mission._room_by_key[key]
			var ch: String = mission.cell_char(Vector2i(x, y))
			var c := Color(room.color)
			var fill := Color(c, 0.18) if room.sealed else Color(c.darkened(0.55), 0.95)
			if ch == "D" or ch == "L": fill = Color(c, 0.6)
			draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell)), fill)
	for room in mission.rooms:
		var rr: Array = room.rect
		var rect := Rect2(origin + Vector2(rr[0], rr[1]) * cell, Vector2(rr[2], rr[3]) * cell)
		draw_rect(rect, Color(room.color), false, 1)
		var label: String = room.name + (" (SEALED)" if room.sealed else "")
		draw_string(UiStyle.font(), rect.position + Vector2(3, 10), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(room.color))
	for actor in mission.crew.values(): draw_circle(origin + actor.position * k, 3, actor.tint)
	draw_circle(origin + mission.player.position * k, 4, Color.WHITE)
