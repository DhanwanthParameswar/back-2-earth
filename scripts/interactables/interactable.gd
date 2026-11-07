extends Node2D
## Base for anything the player can press E on. Owner: B.
##
## Contract: the player calls can_interact(player) to decide whether to show a
## prompt, then interact(player) on E. Interactables never change rules
## themselves — they ask GameState (e.g. complete_objective), which validates.

const Art = preload("res://scripts/ship/art.gd")

var prompt_text := "Interact"
## Pulse the sprite while this is the current objective (readability).
var highlight_when_current := ""

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


func set_visual(path: String, fallback: Color, size := Vector2(32, 32)) -> void:
	if _visual != null:
		_visual.queue_free()
	_visual = Art.make_sprite(path, fallback, size)
	add_child(_visual)


func _process(delta: float) -> void:
	if _visual == null or highlight_when_current == "":
		return
	if GameState.is_current_objective(highlight_when_current):
		_pulse_t += delta
		var k := 0.75 + 0.25 * sin(_pulse_t * 6.0)
		_visual.modulate = Color(k + 0.25, k + 0.25, k + 0.25)
	else:
		_visual.modulate = Color.WHITE
