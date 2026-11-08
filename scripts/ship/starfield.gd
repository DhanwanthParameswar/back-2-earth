extends Node2D
## Space around the ship (the `~` cells show it). Owner: D.
## Same look as the opening film: near-black blue with small stars, a few
## brighter ones with a cross. Static and deterministic; drawn once.

const SPACE := Color8(5, 6, 20)
const STAR_COLORS := [Color8(255, 241, 232), Color8(194, 195, 199), Color8(131, 118, 156), Color8(41, 173, 255)]

var area := Rect2()


func setup(rect: Rect2) -> void:
	area = rect
	queue_redraw()


func _ready() -> void:
	z_index = -20  # behind the black hole (-10) and the ship


func _draw() -> void:
	draw_rect(area, SPACE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2126
	var count := int(area.get_area() / 2600.0)
	for i in count:
		# Whole art pixels (2x2 world px), like everything else.
		var p := Vector2(
			floorf(rng.randf_range(area.position.x, area.end.x) / 2.0) * 2.0,
			floorf(rng.randf_range(area.position.y, area.end.y) / 2.0) * 2.0)
		var c: Color = STAR_COLORS[rng.randi() % STAR_COLORS.size()]
		if rng.randf() < 0.04:  # a bright one with a cross
			draw_rect(Rect2(p - Vector2(2, 0), Vector2(6, 2)), c)
			draw_rect(Rect2(p - Vector2(0, 2), Vector2(2, 6)), c)
		else:
			draw_rect(Rect2(p, Vector2(2, 2)), Color(c, rng.randf_range(0.45, 1.0)))
