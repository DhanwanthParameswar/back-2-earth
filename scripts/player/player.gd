extends CharacterBody2D
## Top-down astronaut. Owner: A.
## velocity = input * speed + gravity drift, applied in the physics step.
## SPACE (held) = mag-boots: slower walking, much less drift.

const SPEED := 150.0
const BOOTS_SPEED := 60.0
const INTERACT_RADIUS := 44.0
const WALK_FRAME_TIME := 0.15

## The interactable the HUD should prompt for (null if none in range).
var current_target = null  # untyped: interactables are duck-typed
var braced := false

var _director = null
var _walk_timer := 0.0
var _shake_left := 0.0
var _hit_flash_left := 0.0
var _ship = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	GameState.damaged.connect(_on_damaged)


func set_camera_limits(rect: Rect2) -> void:
	camera.limit_left = int(rect.position.x)
	camera.limit_top = int(rect.position.y)
	camera.limit_right = int(rect.end.x)
	camera.limit_bottom = int(rect.end.y)


func _physics_process(delta: float) -> void:
	if not GameState.is_playing():
		velocity = Vector2.ZERO
		braced = false
		current_target = null
		queue_redraw()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var was_braced := braced
	braced = Input.is_action_pressed("boots")
	if braced and not was_braced:
		GameState.note_boots_engaged()
		Sfx.play("boots", -6.0)

	var speed := BOOTS_SPEED if braced else SPEED
	velocity = input * speed + _get_director_drift()
	move_and_slide()

	_update_room()
	_update_target()
	_update_visuals(input, delta)


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_playing():
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		if current_target != null and current_target.can_interact(self):
			current_target.interact(self)
			get_viewport().set_input_as_handled()


func _get_director_drift() -> Vector2:
	if _director == null or not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("gravity_director")
	if _director == null:
		return Vector2.ZERO
	return _director.get_drift(braced)


## Nearest valid interactable within reach (handles overlapping targets).
func _update_target() -> void:
	var best = null
	var best_dist := INTERACT_RADIUS
	for target in get_tree().get_nodes_in_group("interactable"):
		if not target.can_interact(self):
			continue
		var d: float = global_position.distance_to(target.global_position)
		if d <= best_dist:
			best_dist = d
			best = target
	current_target = best


func _update_room() -> void:
	if _ship == null or not is_instance_valid(_ship):
		_ship = get_tree().get_first_node_in_group("ship")
	if _ship != null:
		GameState.set_room(_ship.room_at(global_position))


func _update_visuals(input: Vector2, delta: float) -> void:
	# 2-frame walk cycle, flip for left/right. No rotation (keeps pixels on grid).
	if input.length() > 0.1:
		_walk_timer += delta
		if _walk_timer >= WALK_FRAME_TIME:
			_walk_timer = 0.0
			sprite.frame = 1 - sprite.frame
		if absf(input.x) > 0.1:
			sprite.flip_h = input.x < 0.0
	else:
		sprite.frame = 0
		_walk_timer = 0.0

	# Hit flash.
	if _hit_flash_left > 0.0:
		_hit_flash_left -= delta
		sprite.modulate = Color(1.0, 0.35, 0.35) if int(_hit_flash_left * 20.0) % 2 == 0 else Color.WHITE
	else:
		sprite.modulate = Color.WHITE

	# Camera shake in whole pixels.
	if _shake_left > 0.0:
		_shake_left -= delta
		camera.offset = Vector2(randi_range(-2, 2), randi_range(-2, 2))
	else:
		camera.offset = Vector2.ZERO

	queue_redraw()


func _draw() -> void:
	# Mag-boots cue: a cyan ring under the feet while braced.
	if braced:
		draw_arc(Vector2(0, 6), 13.0, 0.0, TAU, 20, Color(0.16, 0.68, 1.0), 2.0)
		draw_arc(Vector2(0, 6), 9.0, 0.0, TAU, 16, Color(0.16, 0.68, 1.0, 0.5), 1.0)


func _on_damaged(_seconds: float) -> void:
	_hit_flash_left = 0.6
	Sfx.play("hit")
	if not Settings.reduced_shake:
		_shake_left = 0.25
