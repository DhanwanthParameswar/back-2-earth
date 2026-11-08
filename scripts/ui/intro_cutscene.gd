extends Control
## The 30-second opening story. Owner: D.
##
## Plays when a run is started from the main menu, right after the suit picker,
## then hands over to gameplay ("RESTORE EMERGENCY POWER"). The film is
## pre-rendered by tools/make_intro.py: one silent video per suit, so the player
## wears the suit they picked (and the crewmate who pulls them to safety wears
## the in-game crewmate's suit), plus one shared soundtrack played alongside.
##
## E / Enter / Space / Esc / click skips, after a short grace period so the key
## that launched the run doesn't skip it too. M still toggles sound.

signal finished

const VIDEO_PATH := "res://assets/video/intro_%s.ogv"
const AUDIO_PATH := "res://assets/audio/intro.ogg"
const FALLBACK_SKIN := "classic"
## Film length in seconds (LENGTH in tools/make_intro.py). If the video never
## reports that it finished, the cutscene ends a moment after this anyway.
const LENGTH := 30.0
const SAFETY_MARGIN := 1.5
const SKIP_GRACE := 0.5
const HINT_DELAY := 1.0
const SKIP_ACTIONS := ["confirm", "interact", "pause", "ui_accept", "ui_cancel"]

var _video: VideoStreamPlayer = null
var _audio: AudioStreamPlayer = null
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

	# Sits in the film's bottom letterbox bar, clear of its captions.
	_hint = Label.new()
	_hint.text = "E / click  skip"
	_hint.position = Vector2(440, 336)
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


func is_running() -> bool:
	return _started and not _done


func skip() -> void:
	_finish()


func _process(delta: float) -> void:
	if not is_running():
		return
	_t += delta
	_hint.visible = _t >= HINT_DELAY
	if _t >= LENGTH + SAFETY_MARGIN:
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
