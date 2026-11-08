extends RefCounted
## Registers the game's input actions at startup: keyboard keys and controller
## buttons for each. Owner: A. Actions defined in Project Settings > Input Map
## win: we only add an action here if it does not exist yet, so the team can
## move these into the editor later without changing any code.
##
## Controller layout (Xbox names; PlayStation/Switch pads map to the same spots):
##   left stick / d-pad  move            A  use / talk / confirm
##   B  back / close                     X  push-to-talk (voice chat)
##   Y  flashlight                       LB / RB  radio Aaron / Dhan
##   Back (Select)  deck map             Start  pause

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"interact": [KEY_E],
	"help": [KEY_H],
	"pause": [KEY_ESCAPE, KEY_P],
	"confirm": [KEY_E, KEY_ENTER, KEY_KP_ENTER],
	"restart": [KEY_R],
	"toggle_mute": [KEY_M],
	"toggle_shake": [KEY_V],
	"to_menu": [KEY_Q],
	"radio_1": [KEY_1],
	"radio_2": [KEY_2],
	"deck_map": [KEY_TAB],
	"flashlight": [KEY_F],
	"talk": [KEY_SPACE],
	"back": [KEY_ESCAPE],
}

const PAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP],
	"move_down": [JOY_BUTTON_DPAD_DOWN],
	"interact": [JOY_BUTTON_A],
	"confirm": [JOY_BUTTON_A],
	"pause": [JOY_BUTTON_START],
	"radio_1": [JOY_BUTTON_LEFT_SHOULDER],
	"radio_2": [JOY_BUTTON_RIGHT_SHOULDER],
	"deck_map": [JOY_BUTTON_BACK],
	"flashlight": [JOY_BUTTON_Y],
	"talk": [JOY_BUTTON_X],
	"back": [JOY_BUTTON_B],
}

## action: [axis, direction]
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

## Analog movement reacts to a gentle tilt; buttons use the usual threshold.
const MOVE_DEADZONE := 0.25


static func ensure_actions() -> void:
	for action in KEYS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, MOVE_DEADZONE if action.begins_with("move_") else 0.5)
		for keycode in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
		for button in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.device = -1  # any controller
			jb.button_index = button
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.device = -1
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, jm)
