extends "res://scripts/interactables/interactable.gd"
## The navigation core. Owner: B.
## GameState grants the "navigation_core" item when collect_core completes.

const OBJECTIVE := "collect_core"


func _ready() -> void:
	super._ready()
	prompt_text = "Take the navigation core"
	highlight_when_current = OBJECTIVE
	shadow_radius = 6.0
	set_visual("res://assets/sprites/core.png", Art.CYAN, Vector2(16, 16), 6.0)  # floats a little
	queue_redraw()
	GameState.inventory_changed.connect(_refresh)
	_refresh()


func can_interact(_player) -> bool:
	return visible and GameState.is_current_objective(OBJECTIVE)


func interact(_player) -> void:
	if GameState.complete_objective(OBJECTIVE):
		Sfx.play("objective")


func _refresh() -> void:
	visible = not GameState.has_item("navigation_core")
