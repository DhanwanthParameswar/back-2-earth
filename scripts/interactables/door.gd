extends StaticBody2D
## A door that opens (and stays open) once an objective is complete. Owner: B.
## Placed at the ship origin; `cells` are tile coordinates it covers.

const Art = preload("res://scripts/ship/art.gd")

var cells: Array[Vector2i] = []
var unlock_objective := ""
var is_open := false

var _shape: CollisionShape2D
var _tex_closed: Texture2D
var _tex_open: Texture2D


func setup(p_cells: Array, p_unlock_objective: String) -> void:
	cells.clear()
	for c in p_cells:
		cells.append(c)
	unlock_objective = p_unlock_objective


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_tex_closed = Art.tex("res://assets/tiles/door_closed.png")
	_tex_open = Art.tex("res://assets/tiles/door_open.png")

	# One rectangle covering every cell.
	var min_c := cells[0]
	var max_c := cells[0]
	for c in cells:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2((max_c - min_c + Vector2i.ONE) * Art.TILE)
	_shape = CollisionShape2D.new()
	_shape.shape = rect_shape
	_shape.position = Vector2(min_c * Art.TILE) + rect_shape.size / 2.0
	add_child(_shape)

	GameState.objective_changed.connect(_on_objective_changed)
	_refresh(false)


func _on_objective_changed(_id: String) -> void:
	_refresh(true)


func _refresh(play_sound: bool) -> void:
	var should_open: bool = GameState.is_objective_complete(unlock_objective)
	if should_open == is_open:
		return
	is_open = should_open
	_shape.set_deferred("disabled", is_open)
	if is_open and play_sound:
		Sfx.play("door")
	queue_redraw()


func _draw() -> void:
	for c in cells:
		var pos := Vector2(c * Art.TILE)
		var t := _tex_open if is_open else _tex_closed
		if t != null:
			draw_texture(t, pos)
		elif is_open:
			draw_rect(Rect2(pos, Vector2(Art.TILE, Art.TILE)), Art.NAVY.lightened(0.15))
		else:
			draw_rect(Rect2(pos, Vector2(Art.TILE, Art.TILE)), Art.AMBER.darkened(0.3))
