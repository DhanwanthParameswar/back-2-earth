extends Control
## The Tab map: the ship's rooms from data/escape_map.json, crew and player dots.
const UiStyle = preload("res://scripts/ui/ui_style.gd")

var mission

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if mission == null or mission.map_data.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.035, 0.09, 0.95))  # the game doesn't show through
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
		_label(rect, str(room.name), room.sealed, Color(room.color))
	for actor in mission.crew.values(): draw_circle(origin + actor.position * k, 3, actor.tint)
	draw_circle(origin + mission.player.position * k, 4, Color.WHITE)

## Shorter names for rooms too small for the full one.
const SHORT := {"FLIGHT DECK": "FLIGHT", "OBSERVATION": "OBS", "ENGINEERING": "ENGINE", "LABORATORY": "LAB",
	"HYDROPONICS": "HYDRO", "SUIT ROOM": "SUITS", "SHUTTLE BAY": "BAY", "CORRIDOR": "CORR", "JUNCTION": "JUNCT",
	"STORAGE": "STORE", "PASSAGE": "PASS", "BREACH": "BREACH", "CABIN": "CABIN", "GALLEY": "GALLEY", "MEDBAY": "MED"}

## A room's name inside its box, never spilling out: the full name if it fits, else a short
## one, else smaller. Sealed rooms say SEALED on a second line when there's room.
func _label(rect: Rect2, name: String, sealed: bool, color: Color) -> void:
	var font := UiStyle.font()
	var room_w := rect.size.x - 5.0
	for text in [name, str(SHORT.get(name, name))]:
		for font_size in [7, 6, 5]:
			if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room_w: continue
			draw_string(font, rect.position + Vector2(3, 3 + font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			if sealed and rect.size.y >= font_size * 2 + 8 and font.get_string_size("SEALED", HORIZONTAL_ALIGNMENT_LEFT, -1, 5).x <= room_w:
				draw_string(font, rect.position + Vector2(3, 6 + font_size * 2), "SEALED", HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(color, 0.8))
			return
