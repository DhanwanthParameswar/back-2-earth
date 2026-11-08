extends Control
## The opening story (36.8 s). Owner: D.
##
## Plays when a run is started from the main menu, then hands over to gameplay
## ("RESTORE EMERGENCY POWER"). The picture is drawn live by intro_film.gd (a
## port of tools/make_intro.py, crisp at any size, timed to the team's final
## cut), and the sound is the final cut's track with the voices
## (assets/audio/intro.ogg). The film follows the sound's clock so they stay in
## sync. If the film's art is missing, the old video (intro.ogv) plays instead.
## Johnny wears the classic suit in it, so the player does too
## (Settings.PLAYER_SKIN). See README "Opening story".
##
## E / Enter / Space / Esc / click skips, after a short grace period so the key
## that started the game doesn't skip it too. M still toggles sound.

signal finished

const IntroFilm = preload("res://scripts/ui/intro_film.gd")
const VIDEO_PATH := "res://assets/video/intro.ogv"
const AUDIO_PATH := "res://assets/audio/intro.ogg"
## Film length in seconds. If the video never reports that it finished, the
## cutscene ends a moment after this anyway.
const LENGTH := 36.8
const SAFETY_MARGIN := 1.5
const SKIP_GRACE := 0.5
const HINT_DELAY := 1.0
const SKIP_ACTIONS := ["confirm", "interact", "pause", "ui_accept", "ui_cancel"]

var _film: Control = null
var _video: VideoStreamPlayer = null
var _audio: AudioStreamPlayer = null
var _hint: Label
var _length := LENGTH
var _t := 0.0
var _started := false
var _done := false


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


func play() -> void:
	if _started:
		return
	_started = true
	_film = IntroFilm.new()
	_film.size = size
	add_child(_film)
	move_child(_film, 1)  # above the black backing, below the skip hint
	if _film.is_ready():
		_length = _film.length()
		_play_audio()
		return
	_film.queue_free()
	_film = null
	if not ResourceLoader.exists(VIDEO_PATH):
		push_warning("Intro film and video missing; starting the run without them.")
		_finish.call_deferred()
		return

	_video = VideoStreamPlayer.new()
	_video.stream = load(VIDEO_PATH)
	_video.expand = true
	_video.size = size
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.finished.connect(_on_video_finished)
	add_child(_video)
	move_child(_video, 1)  # above the black backing, below the skip hint
	_video.play()
	_length = maxf(LENGTH, _video.get_stream_length())
	_play_audio()


func _play_audio() -> void:
	if ResourceLoader.exists(AUDIO_PATH):
		_audio = AudioStreamPlayer.new()
		_audio.stream = load(AUDIO_PATH)
		add_child(_audio)
		_audio.play()


## Seconds into the film: the sound's clock while it plays (keeps lips and
## captions on the voices), otherwise our own.
func _film_time() -> float:
	if _audio != null and _audio.playing:
		return _audio.get_playback_position() + AudioServer.get_time_since_last_mix()
	return _t


## The picture can end a hair before the sound; let the last moment of audio
## finish rather than cutting it off.
func _on_video_finished() -> void:
	if _audio != null and _audio.playing and _audio.stream != null \
			and _audio.stream.get_length() - _audio.get_playback_position() < 0.6:
		_audio.finished.connect(_finish, CONNECT_ONE_SHOT)
	else:
		_finish()


func is_running() -> bool:
	return _started and not _done


func skip() -> void:
	_finish()


func _process(delta: float) -> void:
	if not is_running():
		return
	_t += delta
	_hint.visible = _t >= HINT_DELAY
	if _film != null:
		var ft := _film_time()
		_film.set_time(ft)
		# The picture ends a hair before the sound: let the last of it play out.
		var audio_left := 0.0
		if _audio != null and _audio.playing and _audio.stream != null:
			audio_left = _audio.stream.get_length() - _audio.get_playback_position()
		if _t >= _length and audio_left <= 0.0:
			_finish()
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
	finished.emit()
	queue_free()
