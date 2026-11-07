extends "res://scripts/interactables/interactable.gd"
## The signature puzzle: a cargo sled on a rail with two stops. Owner: B.
##
## Scripted, not physics: while a pull points along the rail, the sled glides
## toward that end. Reaching the pressure plate completes "open_compartment"
## and latches the sled there for the rest of the run.
## The sled is unpowered (frozen) until "restore_power" is complete, so it can
## never solve the puzzle out of order.
## It lives in a channel the player can't enter, so it can't trap anyone.

const SPEED := 64.0  # px/s along the rail (4 tiles ~= 2 s, well inside a 6 s pull)

var start_pos := Vector2.ZERO
var end_pos := Vector2.ZERO
var latched := false
var moving := false

var _director = null
var _plate = null  # Sprite2D, or ColorRect if art is missing
var _plate_on_tex: Texture2D = null


func setup(p_start: Vector2, p_end: Vector2) -> void:
	start_pos = p_start
	end_pos = p_end
	position = p_start


func _ready() -> void:
	super._ready()
	z_index = 2
	prompt_text = "Reset cargo sled"
	set_visual("res://assets/sprites/crate.png", Art.AMBER.darkened(0.4))
	# The plate is drawn by a sibling so it stays put while the sled moves.
	_plate = Art.make_sprite("res://assets/sprites/plate.png", Art.STEEL_LIGHT)
	_plate_on_tex = Art.tex("res://assets/sprites/plate_on.png")
	_plate.z_index = -1
	_plate.top_level = true
	_plate.position = end_pos if _plate is Node2D else end_pos - Vector2(16, 16)
	add_child(_plate)


func is_powered() -> bool:
	return GameState.is_objective_complete("restore_power")


## Reset is offered only if the sled is stranded away from its start.
func can_interact(_player) -> bool:
	return GameState.is_playing() and not latched and not moving \
		and position.distance_to(start_pos) > 1.0


func interact(_player) -> void:
	position = start_pos


func _physics_process(delta: float) -> void:
	if latched or not GameState.is_playing():
		moving = false
		return
	if _director == null or not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("gravity_director")

	# Unpowered: sled stays parked and dark.
	if _visual != null:
		_visual.self_modulate = Color.WHITE if is_powered() else Color(0.5, 0.5, 0.6)
	if not is_powered() or _director == null:
		moving = false
		return

	var lane := (end_pos - start_pos).normalized()
	var along := 0.0
	if _director.is_pulling():
		along = lane.dot(_director.current_direction)
	var target := position
	if along > 0.5:
		target = end_pos
	elif along < -0.5:
		target = start_pos
	moving = position.distance_to(target) > 0.01
	position = position.move_toward(target, SPEED * delta)

	if position.distance_to(end_pos) <= 0.5:
		position = end_pos
		_try_latch()


func _try_latch() -> void:
	if GameState.complete_objective("open_compartment"):
		latched = true
		moving = false
		Sfx.play("objective")
		if _plate is Sprite2D and _plate_on_tex != null:
			_plate.texture = _plate_on_tex
		elif _plate is ColorRect:
			_plate.color = Art.CYAN
