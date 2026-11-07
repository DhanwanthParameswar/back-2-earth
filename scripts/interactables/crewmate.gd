extends "res://scripts/interactables/interactable.gd"
## The surviving crewmate (layout char `M`). Owner: B.
## Walk up to her and she greets you out loud (pre-recorded line, works offline).
## Press E to open the chat box and ask her anything (scripts/ui/npc_chat.gd).

const UiStyle = preload("res://scripts/ui/ui_style.gd")

const GREETING := "Get the power back. Then we find them."
const GREETING_VOICE := "res://assets/voice/crewmate_greeting.mp3"
const GREET_RADIUS := 96.0
const BUBBLE_TIME := 4.5
const BUBBLE_WIDTH := 150.0
## Bubble's bottom edge, above her feet.
const BUBBLE_LIFT := 52.0
const WALK_FRAMES := 6
const IDLE_FRAME := 5
## Suit she wears: the first of these the player is not wearing.
const SUIT_PREFERENCE := ["hazard", "mint", "nebula", "classic"]

var display_name := "Crewmate"
## Her most recent line (the chat box shows it when it opens).
var last_line := ""
var greeted := false

var _sprite: Sprite2D = null
var _bubble: Label
var _bubble_left := 0.0
var _voice_player: AudioStreamPlayer
var _player = null


func _ready() -> void:
	super._ready()
	add_to_group("npc")
	prompt_text = "Talk to %s" % display_name.to_lower()
	shadow_radius = 12.0
	_build_sprite()
	add_solid_base(Vector2(16, 8))
	_build_bubble()
	_voice_player = AudioStreamPlayer.new()
	add_child(_voice_player)
	queue_redraw()


func can_interact(_p) -> bool:
	return GameState.is_playing()


func interact(_p) -> void:
	if not greeted:
		greet()
	var chat = get_tree().get_first_node_in_group("npc_chat")
	if chat != null:
		chat.open(self)


## Show a line in her speech bubble and play its voice (if any).
func say(text: String, stream: AudioStream = null) -> void:
	last_line = text
	_bubble.text = text
	_bubble.size = Vector2(BUBBLE_WIDTH, 0)
	_bubble.reset_size()
	# Centered over her head, but never past the left edge of the map.
	var x := maxf(-BUBBLE_WIDTH / 2.0, 4.0 - global_position.x)
	_bubble.position = Vector2(x, -BUBBLE_LIFT - _bubble.get_combined_minimum_size().y)
	_bubble.visible = true
	_bubble_left = BUBBLE_TIME + text.length() * 0.03
	if stream != null:
		play_voice(stream)


func play_voice(stream: AudioStream) -> void:
	_voice_player.stop()
	_voice_player.stream = stream
	_voice_player.play()


func greet() -> void:
	greeted = true
	var stream: AudioStream = null
	if ResourceLoader.exists(GREETING_VOICE):
		stream = load(GREETING_VOICE)
	say(GREETING, stream)


func _process(delta: float) -> void:
	super._process(delta)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and _sprite != null:
		_sprite.flip_h = _player.global_position.x < global_position.x  # face the player
	if not greeted and _player != null and GameState.is_playing() \
			and global_position.distance_to(_player.global_position) <= GREET_RADIUS:
		greet()
	if _bubble_left > 0.0:
		_bubble_left -= delta
		_bubble.modulate.a = clampf(_bubble_left / 0.5, 0.0, 1.0)
		_bubble.visible = _bubble_left > 0.0


func _build_sprite() -> void:
	var suit := "classic"
	for id in SUIT_PREFERENCE:
		if id != Settings.skin:
			suit = id
			break
	var tex := Art.tex(Settings.skin_sheet_path(suit))
	if tex == null:
		set_visual("", Art.AMBER, Vector2(18, 30))
		return
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.hframes = WALK_FRAMES
	_sprite.frame = IDLE_FRAME
	_sprite.offset = Vector2(0, -tex.get_height() / 2.0)
	add_child(_sprite)
	_visual = _sprite


func _build_bubble() -> void:
	_bubble = Label.new()
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
	_bubble.size = Vector2(BUBBLE_WIDTH, 0)
	_bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bubble.add_theme_font_size_override("font_size", 10)
	_bubble.add_theme_color_override("font_color", UiStyle.TEXT)
	var box := UiStyle.box(Color(UiStyle.NAVY, 0.92), UiStyle.CYAN, 1)
	box.set_content_margin_all(4)
	_bubble.add_theme_stylebox_override("normal", box)
	_bubble.z_index = 50
	_bubble.visible = false
	add_child(_bubble)
