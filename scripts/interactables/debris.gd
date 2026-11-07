extends CharacterBody2D
## Loose wreckage that slides with each gravity pull. Owner: B.
## Contact costs 10 s (GameState applies the 1 s hit cooldown).
## It collides with walls and closed doors only — never with the player —
## so it can't pin or trap anyone.

const Art = preload("res://scripts/ship/art.gd")
const SPEED_FACTOR := 1.6   # moves faster than the player drifts
const HIT_RADIUS := 18.0

var _director = null
var _player = null


func _ready() -> void:
	add_to_group("debris")
	z_index = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = 1
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)
	add_child(Art.make_sprite("res://assets/sprites/debris.png", Art.RED, Vector2(24, 24)))


func _physics_process(_delta: float) -> void:
	if not GameState.is_playing():
		return
	if _director == null or not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("gravity_director")
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")

	velocity = Vector2.ZERO
	if _director != null:
		velocity = _director.get_drift(false) * SPEED_FACTOR
	move_and_slide()

	if _player != null and global_position.distance_to(_player.global_position) < HIT_RADIUS:
		GameState.apply_debris_hit()
