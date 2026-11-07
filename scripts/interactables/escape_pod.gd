extends "res://scripts/interactables/interactable.gd"
## The escape pod. Owner: B.
## Boarding is validated centrally: GameState.complete_objective("board_pod")
## refuses unless power + core + clamp are all done, then ends the run as won.

const OBJECTIVE := "board_pod"


func _ready() -> void:
	super._ready()
	prompt_text = "Board the pod and launch"
	highlight_when_current = OBJECTIVE
	set_visual("res://assets/sprites/pod.png", Art.STEEL_LIGHT, Vector2(64, 64))


func can_interact(_player) -> bool:
	return GameState.is_current_objective(OBJECTIVE) and GameState.launch_requirements_met()


func interact(player) -> void:
	if GameState.complete_objective(OBJECTIVE):
		Sfx.play("launch")
		if player != null:
			player.visible = false  # "inside" the pod
