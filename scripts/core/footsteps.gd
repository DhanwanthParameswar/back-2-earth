extends Node2D
## Footsteps for anyone walking: the player and the crew. Owner: A.
##
## Call step() each time a foot lands (player.gd and escape_actor.gd do, on the
## walk frames where a foot is down: is_step_frame()). Each step:
##   - sounds like the floor underfoot: metal deck plating, the engineering
##     grating, or carpet and mats (the room's floor style, from the ship's
##     floor_style_at(); anywhere else, metal);
##   - picks one of six variations, never the same one twice running, with a
##     little random pitch and level, the left foot a touch lower than the right,
##     so a walk never sounds like a loop;
##   - plays on this node's own players, not Sfx's shared pool, so walking can't
##     cut off other sounds. With `positional` on (the crew), steps come from where
##     they walk: quieter further from the camera, panned left or right.
## Sounds: tools/make_footstep_sounds.py (assets/audio/steps/).

const DIR := "res://assets/audio/steps/"
const VARIATIONS := 6
## Floor style (escape_map.json rooms) -> footstep sound. Anything else is metal.
const SURFACE_OF := {"grate": "grate", "carpet": "soft", "hydro": "soft"}
## Walk frames (of the 6-frame suit sheets) where a foot comes down.
const STEP_FRAMES := [0, 3]

## Set before adding to the tree: steps come from this node's position (the crew).
var positional := false
var volume_db := -12.0
## How far away (px) positional steps can still be heard.
var hearing_distance := 480.0

var _players: Array = []
var _next := 0
var _last := -1
var _left_foot := false
var _streams := {}


func _ready() -> void:
	for i in 3:
		var p: Node
		if positional:
			var p2 := AudioStreamPlayer2D.new()
			p2.max_distance = hearing_distance
			p2.attenuation = 1.4
			p = p2
		else:
			p = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## One footstep, on whatever floor is under this node.
func step() -> void:
	if _players.is_empty():
		return
	var surface := surface_at(global_position)
	var k := randi() % VARIATIONS
	if k == _last:
		k = (k + 1) % VARIATIONS
	_last = k
	var stream := _stream("%s_%d" % [surface, k + 1])
	if stream == null:
		return
	_left_foot = not _left_foot
	var p = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = randf_range(0.95, 1.05) * (0.97 if _left_foot else 1.0)
	p.volume_db = volume_db + randf_range(-1.5, 1.0)
	p.play()


## True on the walk frames where a foot lands.
static func is_step_frame(frame: int) -> bool:
	return frame in STEP_FRAMES


## Which footstep sound fits the floor at a point: "metal", "grate" or "soft".
func surface_at(point: Vector2) -> String:
	var ship = get_tree().get_first_node_in_group("ship") if is_inside_tree() else null
	if ship != null and ship.has_method("floor_style_at"):
		return str(SURFACE_OF.get(ship.floor_style_at(point), "metal"))
	return "metal"


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := DIR + sound + ".wav"
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]
