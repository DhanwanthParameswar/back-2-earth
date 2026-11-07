extends RefCounted
## Registers the game's input actions at startup.
## Owner: A. Actions defined in Project Settings > Input Map win: we only add
## an action here if it does not exist yet, so the team can move these into the
## editor later without changing any code.

const ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"interact": [KEY_E],
	"boots": [KEY_SPACE],
	"help": [KEY_H],
	"pause": [KEY_ESCAPE, KEY_P],
	"confirm": [KEY_E, KEY_ENTER, KEY_KP_ENTER],
	"restart": [KEY_R],
	"toggle_mute": [KEY_M],
	"toggle_shake": [KEY_V],
	"to_menu": [KEY_Q],
}


static func ensure_actions() -> void:
	for action in ACTIONS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		for keycode in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
