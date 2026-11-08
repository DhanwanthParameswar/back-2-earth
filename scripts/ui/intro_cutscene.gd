extends Control
## The opening story (38 s). Owner: D.
##
## Plays when a run is started from the main menu, right after the suit picker,
## then hands over to gameplay ("RESTORE EMERGENCY POWER"). The film is
## pre-rendered by tools/make_intro.py: one silent video per suit, so the player
## wears the suit they picked (and the crewmate who pulls them to safety wears
## the in-game crewmate's suit), plus one shared soundtrack played alongside.
##
## Voice-over: drop recordings into assets/audio/intro_vo/ named after the line
## ids in data/intro_timing.json (crew_1, system_1, crew_2, and optionally
## kien_1; .ogg, .wav or .mp3) and each plays when its caption appears. A single full-length track named
## full.ogg (or .wav/.mp3) plays from the first frame instead, if you'd rather
## edit the voices against the video yourself. The soundtrack leaves the spoken
## lines clear, so voices sit on top of it.
##
## E / Enter / Space / Esc / click skips, after a short grace period so the key
## that launched the run doesn't skip it too. M still toggles sound.

signal finished

const VIDEO_PATH := "res://assets/video/intro_%s.ogv"
const AUDIO_PATH := "res://assets/audio/intro.ogg"
const FALLBACK_SKIN := "classic"
const TIMING_PATH := "res://data/intro_timing.json"
const VO_DIR := "res://assets/audio/intro_vo/"
const VO_EXTS := ["ogg", "wav", "mp3"]
const FULL_VO_ID := "full"
## Film length in seconds, used if data/intro_timing.json is missing. If the
## video never reports that it finished, the cutscene ends a moment after the
## length anyway.
const LENGTH := 38.0
const SAFETY_MARGIN := 1.5
const SKIP_GRACE := 0.5
const HINT_DELAY := 1.0
const SKIP_ACTIONS := ["confirm", "interact", "pause", "ui_accept", "ui_cancel"]

var _video: VideoStreamPlayer = null
var _audio: AudioStreamPlayer = null
var _voices: Array[AudioStreamPlayer] = []
var _cues: Array = []  # [{"at": seconds, "path": res path}], soonest first
var _length := LENGTH
var _hint: Label
var _t := 0.0
var _started := false
var _done := false


## The intro video for a suit, or the classic one if that suit has none.
## "" when no intro video is in the build at all.
static func video_path_for(skin_id: String) -> String:
	var path := VIDEO_PATH % skin_id
	if ResourceLoader.exists(path):
		return path
	path = VIDEO_PATH % FALLBACK_SKIN
	return path if ResourceLoader.exists(path) else ""


## The recording for a voice line id, or "" if none was added.
static func vo_path_for(line_id: String) -> String:
	for ext in VO_EXTS:
		var path := "%s%s.%s" % [VO_DIR, line_id, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


## data/intro_timing.json ({"length", "lines": [{"id", "at", "end", "speaker", "text"}]}),
## or {} if it's missing or broken.
static func load_timing() -> Dictionary:
	if not FileAccess.file_exists(TIMING_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TIMING_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind it can be clicked
	position = Vector2.ZERO
	size = Vector2(640, 360)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Sits in the film's top letterbox bar; the captions use the bottom one.
	_hint = Label.new()
	_hint.text = "E / click  skip"
	_hint.position = Vector2(440, 8)
	_hint.size = Vector2(190, 16)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.62, 0.75, 0.75))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	add_child(_hint)


func play_for_skin(skin_id: String) -> void:
	if _started:
		return
	_started = true
	var path := video_path_for(skin_id)
	if path == "":
		push_warning("Intro video missing (%s); starting the run without it." % (VIDEO_PATH % skin_id))
		_finish.call_deferred()
		return

	_video = VideoStreamPlayer.new()
	_video.stream = load(path)
	_video.expand = true
	_video.size = size
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(_finish)
	add_child(_video)
	move_child(_video, 1)  # above the black backing, below the skip hint
	_video.play()

	if ResourceLoader.exists(AUDIO_PATH):
		_audio = AudioStreamPlayer.new()
		_audio.stream = load(AUDIO_PATH)
		add_child(_audio)
		_audio.play()
	_load_voice_cues()


func _load_voice_cues() -> void:
	var timing := load_timing()
	_length = float(timing.get("length", LENGTH))
	var full := vo_path_for(FULL_VO_ID)
	if full != "":
		_cues.append({"at": 0.0, "path": full})
	else:
		for line in timing.get("lines", []):
			if typeof(line) != TYPE_DICTIONARY:
				continue
			var path := vo_path_for(str(line.get("id", "")))
			if path != "":
				_cues.append({"at": float(line.get("at", 0.0)), "path": path})
	_cues.sort_custom(func(a, b): return a["at"] < b["at"])
	_play_due_voices()


func _play_due_voices() -> void:
	while not _cues.is_empty() and _t >= float(_cues[0]["at"]):
		var cue: Dictionary = _cues.pop_front()
		var voice := AudioStreamPlayer.new()
		voice.stream = load(cue["path"])
		add_child(voice)
		voice.play()
		_voices.append(voice)


func is_running() -> bool:
	return _started and not _done


func skip() -> void:
	_finish()


func _process(delta: float) -> void:
	if not is_running():
		return
	_t += delta
	_hint.visible = _t >= HINT_DELAY
	_play_due_voices()
	if _t >= _length + SAFETY_MARGIN:
		_finish()


func _input(event: InputEvent) -> void:
	if not is_running():
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.is_pressed() and not event.is_echo()
	elif event is InputEventMouseButton or event is InputEventJoypadButton:
		pressed = event.is_pressed()
	if not pressed:
		return
	# Swallow every press so the HUD, player and chat box stay asleep underneath.
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("toggle_mute"):
		Settings.toggle_mute()
		return
	if _t < SKIP_GRACE:
		return
	var mb := event as InputEventMouseButton
	var wants_skip := event is InputEventJoypadButton
	if mb != null and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		wants_skip = true
	for action in SKIP_ACTIONS:
		if event.is_action_pressed(action):
			wants_skip = true
	var key := event as InputEventKey
	if key != null and key.keycode == KEY_SPACE:
		wants_skip = true
	if wants_skip:
		skip()


func _finish() -> void:
	if _done:
		return
	_done = true
	if _video != null:
		_video.stop()
	if _audio != null:
		_audio.stop()
	for voice in _voices:
		voice.stop()
	finished.emit()
	queue_free()
