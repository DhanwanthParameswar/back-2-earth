extends RefCounted
## Controller rumble for the big physical moments. Owner: D.
##   Haptics.play("impact")
## Each preset is a list of pulses [delay s, weak 0-1, strong 0-1, length s]
## (weak = the small high motor, strong = the big low one). Does nothing when
## no controller is connected or Settings.vibration is off. In the browser it
## uses the Gamepad API's dual-rumble (Chrome/Edge); elsewhere Godot's own.

const PRESETS := {
	"tick": [[0.0, 0.25, 0.0, 0.05]],                         # a button, a pickup
	"click": [[0.0, 0.45, 0.1, 0.07]],                        # a switch or lever
	"deny": [[0.0, 0.3, 0.0, 0.05], [0.1, 0.3, 0.0, 0.05]],   # can't do that yet
	"jolt": [[0.0, 0.9, 0.7, 0.18]],                          # a breaker trips
	"shove": [[0.0, 0.5, 0.8, 0.22]],                         # pushing something heavy
	"thud": [[0.0, 0.2, 1.0, 0.28]],                          # it lands
	"heavy": [[0.0, 0.3, 0.7, 0.45]],                         # lifting together
	"power_up": [[0.0, 0.2, 0.2, 0.25], [0.25, 0.4, 0.4, 0.25], [0.5, 0.7, 0.6, 0.35]],
	"power_down": [[0.0, 0.6, 0.6, 0.3], [0.3, 0.3, 0.3, 0.3], [0.6, 0.1, 0.1, 0.3]],
	"clamps": [[0.0, 0.8, 0.5, 0.15], [0.25, 0.8, 0.5, 0.15]],
	"impact": [[0.0, 1.0, 1.0, 0.5], [0.5, 0.4, 0.6, 0.6]],   # the asteroid hits
	"breach": [[0.0, 1.0, 1.0, 0.8], [0.8, 0.3, 0.7, 1.2]],   # the hull tears open
	"slam": [[0.0, 0.6, 1.0, 0.3]],                           # the barrier comes down
	"launch": [[0.0, 0.2, 0.5, 0.6], [0.6, 0.5, 0.8, 0.8], [1.4, 0.9, 1.0, 1.2]],
}


static func play(preset: String) -> void:
	if not _enabled() or not has_controller():
		return
	var pulses: Array = PRESETS.get(preset, [])
	var tree := Engine.get_main_loop() as SceneTree
	for p in pulses:
		if float(p[0]) <= 0.0:
			pulse(p[1], p[2], p[3])
		elif tree != null:
			tree.create_timer(float(p[0])).timeout.connect(pulse.bind(p[1], p[2], p[3]))


## One rumble on every connected controller.
static func pulse(weak: float, strong: float, length: float) -> void:
	if not _enabled():
		return
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, weak, strong, length)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(() => { for (const g of navigator.getGamepads ? navigator.getGamepads() : []) {
			if (g && g.vibrationActuator) g.vibrationActuator.playEffect('dual-rumble',
				{duration: %d, weakMagnitude: %f, strongMagnitude: %f}).catch(() => {}); } })()"""
			% [int(length * 1000.0), clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0)], true)


## Settings.vibration, looked up at runtime (works in tools and tests too).
static func _enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var settings = tree.root.get_node_or_null("Settings") if tree != null else null
	return settings == null or bool(settings.vibration)


static func has_controller() -> bool:
	return not Input.get_connected_joypads().is_empty()
