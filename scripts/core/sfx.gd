extends Node
## Tiny sound player (autoload "Sfx"). Owner: D.
## Call Sfx.play("warning"). Missing files are skipped silently, so audio can
## be swapped or deleted without breaking gameplay.

const SOUNDS := {
	"warning": "res://assets/audio/warning.wav",
	"boots": "res://assets/audio/boots.wav",
	"hit": "res://assets/audio/hit.wav",
	"objective": "res://assets/audio/objective.wav",
	"door": "res://assets/audio/door.wav",
	"launch": "res://assets/audio/launch.wav",
	"hull_impact": "res://assets/audio/hull_impact.wav",  # tools/make_impact_sounds.py
	"sparks": "res://assets/audio/sparks.wav",
}
const BACKGROUND_MUSIC := "res://assets/audio/game_music_loop.ogg"
const POOL_SIZE := 6  # room for a long impact or the launch under other sounds

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _ambient: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.volume_db = -14.0
	add_child(_ambient)


## pitch_scale below 1 sounds bigger and further away (it also plays slower).
func play(sound_name: String, volume_db := 0.0, pitch_scale := 1.0) -> void:
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	p.play()


func start_ambient() -> void:
	if _ambient.playing:
		return
	if ResourceLoader.exists(BACKGROUND_MUSIC):
		# The Ogg resource loops in the audio mixer, keeping the join gapless.
		_ambient.stream = load(BACKGROUND_MUSIC)
		_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


func _get_stream(sound_name: String) -> AudioStream:
	if _streams.has(sound_name):
		return _streams[sound_name]
	var path: String = SOUNDS.get(sound_name, "")
	var stream: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		stream = load(path)
	_streams[sound_name] = stream
	return stream
