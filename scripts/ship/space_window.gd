extends Node2D
## A window onto space (layout char `W`). Owner: D.
##
## Plays the looping nebula video behind the glass. The video is clipped to the
## window so it can't leak into other transparent tiles, and it shifts a little
## as the camera moves (parallax), so it reads as far away rather than a poster.
## The frame, sill, and glare are drawn by the ship on top (ShipBuilder._draw).

const VIDEO_PATH := "res://assets/video/nebula_loop.ogv"
## Video size in world px. The file is 480x270, and each of its art pixels is
## 2x2 px, matching the rest of the game. Change both together.
const VIDEO_SIZE := Vector2(480, 270)
## 0 = painted on the glass, 1 = fixed on screen (infinitely far). 0.35 feels deep.
const PARALLAX := 0.35
## Which part of the video (video px) sits in the middle of the window when the
## run starts: the ringed planet and the edge of the nebula band.
const FOCUS := Vector2(330, 40)

var window_rect := Rect2()

var _clip: Control
var _video: VideoStreamPlayer = null
var _cam_ref = null  # camera position on the first frame (parallax is relative to it)


func setup(rect: Rect2) -> void:
	window_rect = rect


func _ready() -> void:
	add_to_group("space_window")
	z_index = -5  # behind the ship's tiles; the glass cells are left transparent

	_clip = Control.new()
	_clip.position = window_rect.position
	_clip.size = window_rect.size
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)

	var bg := ColorRect.new()  # shows if the video is missing or still loading
	bg.color = Color("080d26")
	bg.size = window_rect.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(bg)

	if ResourceLoader.exists(VIDEO_PATH):
		_video = VideoStreamPlayer.new()
		_video.stream = load(VIDEO_PATH)
		_video.expand = true
		_video.size = VIDEO_SIZE
		_video.volume_db = -80.0
		_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_video.finished.connect(_on_video_finished)
		_clip.add_child(_video)
		_video.play()
	else:
		push_warning("Space window video missing: %s" % VIDEO_PATH)
	_update_parallax()


func _process(_delta: float) -> void:
	_update_parallax()


func _on_video_finished() -> void:
	_video.play()  # seamless 12 s loop


func _update_parallax() -> void:
	if _video == null:
		return
	var shift := Vector2.ZERO
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		var cam_pos := cam.get_screen_center_position()
		if _cam_ref == null:
			_cam_ref = cam_pos
		# Camera moves down -> the view slides down inside the frame, like distant scenery.
		shift = (cam_pos - _cam_ref) * PARALLAX
	# Video position inside the window box; keep the video covering the glass.
	var pos := window_rect.size / 2.0 - FOCUS + shift
	pos = pos.clamp(window_rect.size - VIDEO_SIZE, Vector2.ZERO)
	# Move in whole art pixels (2 px) so the stars don't shimmer.
	_video.position = Vector2(roundf(pos.x / 2.0) * 2.0, roundf(pos.y / 2.0) * 2.0)
