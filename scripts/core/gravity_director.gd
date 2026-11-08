extends Node
## Authored gravity surges (not an orbital simulation). Owner: A.
##
## Cycle: CALM -> WARNING (3 s) -> PULL (6 s) -> CALM (7 s) -> ...
## Pull directions alternate through `directions` in ship coordinates.
## Lives under the mission root (scenes/main.tscn), so a restart resets it.
## Other nodes find it with get_tree().get_first_node_in_group("gravity_director").

signal gravity_warning(direction: Vector2)
## direction is Vector2.ZERO and drift_speed 0 when the pull ends.
signal gravity_changed(direction: Vector2, drift_speed: float)

enum State { CALM, WARNING, PULL }

const WARNING_TIME := 3.0
const PULL_TIME := 6.0
const CALM_TIME := 7.0
## Calm before the very first warning, so the player can read the cockpit.
const FIRST_CALM_TIME := 6.0

const PULL_DRIFT := 90.0       # px/s pushed during a pull (the player walks at 150)

## Order matters: the cargo sled slides DOWN, so DOWN comes first.
var directions: Array[Vector2] = [Vector2.DOWN, Vector2.UP]

var state: int = State.CALM
var time_in_state_left := FIRST_CALM_TIME
var current_direction := Vector2.ZERO   # non-zero only during PULL
var _dir_index := 0


func _ready() -> void:
	add_to_group("gravity_director")
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(delta: float) -> void:
	if not GameState.is_playing():
		return
	advance(delta)


## Separate from _physics_process so tests can drive the clock.
func advance(delta: float) -> void:
	time_in_state_left -= delta
	var guard := 0
	while time_in_state_left <= 0.0 and guard < 8:
		guard += 1
		_next_state()


func _next_state() -> void:
	match state:
		State.CALM:
			state = State.WARNING
			time_in_state_left += WARNING_TIME
			gravity_warning.emit(next_direction())
			Sfx.play("warning")
		State.WARNING:
			state = State.PULL
			time_in_state_left += PULL_TIME
			current_direction = next_direction()
			gravity_changed.emit(current_direction, PULL_DRIFT)
		State.PULL:
			state = State.CALM
			time_in_state_left += CALM_TIME
			current_direction = Vector2.ZERO
			_dir_index = (_dir_index + 1) % directions.size()
			gravity_changed.emit(Vector2.ZERO, 0.0)


## The direction of the upcoming (or current) pull.
func next_direction() -> Vector2:
	return directions[_dir_index]


func is_pulling() -> bool:
	return state == State.PULL


## Drift to add to a body's velocity this frame.
func get_drift() -> Vector2:
	if state != State.PULL:
		return Vector2.ZERO
	return current_direction * PULL_DRIFT


## Seconds until the state changes (HUD countdown).
func seconds_left() -> float:
	return maxf(0.0, time_in_state_left)


static func direction_name(dir: Vector2) -> String:
	if dir == Vector2.DOWN:
		return "DOWN"
	if dir == Vector2.UP:
		return "UP"
	if dir == Vector2.LEFT:
		return "LEFT"
	if dir == Vector2.RIGHT:
		return "RIGHT"
	return ""
