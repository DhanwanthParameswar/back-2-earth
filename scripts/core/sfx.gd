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
}
const AMBIENT := "res://assets/audio/ambient_hum.wav"
const POOL_SIZE := 4

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
	_ambient.finished.connect(_on_ambient_finished)


func play(sound_name: String, volume_db := 0.0) -> void:
	var stream := _get_stream(sound_name)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.play()


func start_ambient() -> void:
	if _ambient.playing:
		return
	if ResourceLoader.exists(AMBIENT):
		_ambient.stream = load(AMBIENT)
		_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


func _on_ambient_finished() -> void:
	# Manual loop so the WAV needs no special import settings.
	_ambient.play()


func _get_stream(sound_name: String) -> AudioStream:
	if _streams.has(sound_name):
		return _streams[sound_name]
	var path: String = SOUNDS.get(sound_name, "")
	var stream: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		stream = load(path)
	_streams[sound_name] = stream
	return stream
