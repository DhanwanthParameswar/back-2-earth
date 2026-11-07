extends "res://scripts/interactables/interactable.gd"
## A console that completes one objective when used (terminal, power, clamp).
## Owner: B. Configure with setup() before adding to the tree.

var objective_id := ""
var texture_path := ""
var fallback_color := Color.WHITE


func setup(p_objective_id: String, p_prompt: String, p_texture: String, p_fallback: Color) -> void:
	objective_id = p_objective_id
	prompt_text = p_prompt
	texture_path = p_texture
	fallback_color = p_fallback
	highlight_when_current = p_objective_id


func _ready() -> void:
	super._ready()
	set_visual(texture_path, fallback_color)
	GameState.objective_changed.connect(_on_objective_changed)
	_on_objective_changed("")


func can_interact(_player) -> bool:
	return GameState.is_current_objective(objective_id)


func interact(_player) -> void:
	if GameState.complete_objective(objective_id):
		Sfx.play("objective")


func _on_objective_changed(_id: String) -> void:
	# Dim the console once its job is done.
	if _visual != null and GameState.is_objective_complete(objective_id):
		_visual.self_modulate = Color(0.55, 0.55, 0.6)
