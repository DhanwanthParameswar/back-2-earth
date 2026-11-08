extends Control

var mission

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if mission == null: return
	var scale_factor := minf(size.x / 1184.0, size.y / 896.0)
	for cell in mission.floors:
		draw_rect(Rect2(Vector2(cell * 32) * scale_factor, Vector2(32, 32) * scale_factor), Color("263b53"))
	for key in mission.ROOMS:
		var grid: Rect2i = mission.ROOMS[key]
		var rect := Rect2(Vector2(grid.position * 32) * scale_factor, Vector2(grid.size * 32) * scale_factor)
		var color: Color = mission.COLORS[key]
		draw_rect(rect, Color(color, 0.15))
		draw_rect(rect, color, false, 1)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 13), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
	for actor in mission.crew.values(): draw_circle(actor.position * scale_factor, 3, actor.tint)
	draw_circle(mission.player.position * scale_factor, 4, Color.WHITE)
