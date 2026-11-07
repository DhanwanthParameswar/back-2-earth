extends Node2D
## Base for anything the player can press E on. Owner: B.
##
## Contract: the player calls can_interact(player) to decide whether to show a
## prompt, then interact(player) on E. Interactables never change rules
## themselves — they ask GameState (e.g. complete_objective), which validates.
##
## 3/4 view: the node's position is the object's BASE (where it touches the
## floor). The ship y-sorts by that point, so the player walks behind an object
## when their feet are above its base and in front when below.

const Art = preload("res://scripts/ship/art.gd")

var prompt_text := "Interact"
## Pulse the sprite while this is the current objective (readability).
var highlight_when_current := ""
## Soft floor shadow radius (0 = none).
var shadow_radius := 0.0

var _visual: CanvasItem = null  # Sprite2D, or a ColorRect if art is missing
var _pulse_t := 0.0


func _ready() -> void:
	add_to_group("interactable")


func can_interact(_player) -> bool:
	return false


func get_prompt() -> String:
	return prompt_text


func interact(_player) -> void:
	pass


## Sprite drawn so its bottom edge sits `lift` px above the base point.
func set_visual(path: String, fallback: Color, size := Vector2(32, 32), lift := 0.0) -> void:
	if _visual != null:
		_visual.queue_free()
	var v = Art.make_sprite(path, fallback, size)  # untyped: Sprite2D or ColorRect
	if v is Sprite2D:
		var tex_h: float = v.texture.get_height()
		v.position = Vector2(0, -tex_h / 2.0 - lift)
	else:
		v.position = Vector2(-size.x / 2.0, -size.y - lift)
	add_child(v)
	_visual = v


## Makes the object's footprint solid (layer 1, like walls).
func add_solid_base(footprint: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = footprint
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = Vector2(0, -footprint.y / 2.0)
	body.add_child(cs)
	add_child(body)


func _draw() -> void:
	if shadow_radius > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, shadow_radius, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _process(delta: float) -> void:
	if _visual == null or highlight_when_current == "":
		return
	if GameState.is_current_objective(highlight_when_current):
		_pulse_t += delta
		var k := 0.75 + 0.25 * sin(_pulse_t * 6.0)
		_visual.modulate = Color(k + 0.25, k + 0.25, k + 0.25)
	else:
		_visual.modulate = Color.WHITE
