extends Node2D
## Existing astronaut art, with visible walking along the ship's floor grid.

var mission
var actor_id := "mara"
var display_name := "AARON · RESEARCHER"
var suit := "hazard"
var tint := Color("e0ad65")
var sprite: Sprite2D
var bubble: Label
var path := PackedVector2Array()
var arrived: Callable
var following := false
var walking_time := 0.0
var bubble_left := 0.0
## Flashlight (dark ship only): on/off by asking on the radio. It points where they walk;
## standing still, it keeps the last direction (or the one you asked for).
var light_on := false
var facing := Vector2.DOWN
const BUBBLE_WIDTH := 190.0
var name_label: Label
var cargo: Sprite2D
## stand · pinned (under the locker) · straining (lifting) · sit · carried · dead
var pose := "stand"
const WALK_SPEED := 125.0
var speed := WALK_SPEED

func _ready() -> void:
	add_to_group("interactable")
	sprite = Sprite2D.new()
	sprite.texture = load(Settings.skin_sheet_path(suit))
	sprite.hframes = 6
	sprite.frame = 5
	sprite.position.y = -26
	add_child(sprite)
	name_label = Label.new()
	name_label.text = display_name.split(" · ")[0]
	name_label.position = Vector2(-48, 5)
	name_label.size.x = 96
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_outline_color", Color("050a19"))
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.modulate = tint
	add_child(name_label)
	# Speech bubble: navy box with a border in the crewmate's color, above the head.
	bubble = Label.new()
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.custom_minimum_size = Vector2(BUBBLE_WIDTH, 0)
	bubble.size = Vector2(BUBBLE_WIDTH, 0)
	bubble.add_theme_font_size_override("font_size", 9)
	bubble.add_theme_color_override("font_color", Color("fff1e8"))
	var box := StyleBoxFlat.new()
	box.bg_color = Color("0b1233", 0.93)
	box.border_color = tint
	box.set_border_width_all(1)
	box.set_content_margin_all(4)
	bubble.add_theme_stylebox_override("normal", box)
	bubble.z_index = 50
	bubble.visible = false
	add_child(bubble)
	cargo = Sprite2D.new()
	cargo.texture = load("res://assets/sprites/core.png")
	cargo.scale = Vector2(0.8, 0.8)
	cargo.position = Vector2(15, -15)
	cargo.visible = false
	add_child(cargo)

func set_cargo(carrying: bool) -> void:
	cargo.visible = carrying

func can_interact(_player) -> bool:
	return mission.actor_interactable(actor_id)

func get_prompt() -> String:
	return mission.actor_prompt(actor_id)

func interact(_player) -> void:
	mission.interact_actor(actor_id)

func say(line: String) -> void:
	bubble.text = line
	bubble.size = Vector2(BUBBLE_WIDTH, 0)
	bubble.reset_size()
	# Bottom edge just above the head, however many lines the text wraps to.
	bubble.position = Vector2(-BUBBLE_WIDTH / 2.0, -50.0 - bubble.get_combined_minimum_size().y)
	bubble_left = 4.0 + minf(line.length() * 0.05, 8.0)  # longer lines stay up longer

func go_to(point: Vector2, callback: Callable = Callable()) -> void:
	following = false
	arrived = callback
	path = mission.find_path(position, point)
	if path.is_empty():
		if position.distance_to(point) < 24.0:
			# Already there: finish the task right away.
			position = point
			arrived = Callable()
			if callback.is_valid(): callback.call()
			return
		arrived = Callable()
		mission.announce(display_name.split(" · ")[0], "I can't get there from here.")

func _process(delta: float) -> void:
	if not mission.active or mission.ending: return
	bubble_left = maxf(0.0, bubble_left - delta)
	bubble.visible = bubble_left > 0.0
	_apply_pose()
	if pose in ["pinned", "sit", "dead"]: return
	if following and path.is_empty() and position.distance_to(mission.player.position) > 75:
		path = mission.find_path(position, mission.player.position + Vector2(35, 20))
	if not path.is_empty():
		var direction := position.direction_to(path[0])
		if direction.length() > 0.1:
			facing = Vector2.RIGHT if absf(direction.x) >= absf(direction.y) and direction.x >= 0.0 else Vector2.LEFT if absf(direction.x) >= absf(direction.y) else Vector2.DOWN if direction.y >= 0.0 else Vector2.UP
		position = position.move_toward(path[0], delta * 125.0)
		walking_time += delta * 9.0
		sprite.frame = int(walking_time) % 6
		if absf(direction.x) > 0.1: sprite.flip_h = direction.x < 0
		if position.distance_to(path[0]) < 1:
			path.remove_at(0)
			if path.is_empty() and arrived.is_valid():
				var callback := arrived
				arrived = Callable()
				callback.call()
	else:
		sprite.frame = 5

## The same walk sheet, turned or squashed for each pose.
func _apply_pose() -> void:
	match pose:
		"pinned":
			sprite.rotation = PI / 2.0
			sprite.position = Vector2(6, -10)
			sprite.scale = Vector2.ONE
			sprite.frame = 5
			sprite.modulate = Color.WHITE
			name_label.position = Vector2(-15, 6)
		"dead":
			sprite.rotation = -PI / 2.0
			sprite.position = Vector2(0, -8)
			sprite.scale = Vector2.ONE
			sprite.frame = 5
			sprite.modulate = Color(0.55, 0.55, 0.62)
			name_label.position = Vector2(-48, 5)
		"sit":
			sprite.rotation = 0.0
			sprite.position = Vector2(0, -20)
			sprite.scale = Vector2(1.0, 0.78)
			sprite.frame = 5
			sprite.modulate = Color.WHITE
			name_label.position = Vector2(-48, 5)
		"straining":
			sprite.rotation = 0.06 * sin(Time.get_ticks_msec() / 60.0)
			sprite.position = Vector2(0, -26)
			sprite.scale = Vector2.ONE
		_:
			sprite.rotation = 0.0
			sprite.position = Vector2(0, -26 if pose != "carried" else -30)
			sprite.scale = Vector2.ONE
			sprite.modulate = Color.WHITE

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 12, Color(0, 0, 0, 0.35))
