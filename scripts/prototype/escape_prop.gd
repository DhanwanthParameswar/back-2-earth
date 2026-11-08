extends "res://scripts/interactables/interactable.gd"

var mission
var prop_id := ""
var title := ""
var texture_path := ""
var accent := Color("29adff")
var solid := true          # false: walk-through (the locker's label, the sample case)
var caption: Label

func _ready() -> void:
	super._ready()
	if texture_path != "":
		shadow_radius = 15
		set_visual(texture_path, accent)
		_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if solid:
		add_solid_base(Vector2(24, 12))
	visibility_changed.connect(func():
		for child in get_children():
			if child is StaticBody2D:
				child.get_child(0).set_deferred("disabled", not visible))
	caption = Label.new()
	caption.text = title
	caption.position = Vector2(-72, 7)
	caption.size = Vector2(144, 16)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 9)
	caption.add_theme_color_override("font_outline_color", Color("050a19"))
	caption.add_theme_constant_override("outline_size", 4)
	caption.modulate = accent
	add_child(caption)

func can_interact(_player) -> bool:
	return mission.active and not mission.ending and visible and not mission.scripted and not mission.seated

func get_prompt() -> String:
	return mission.prompt_for(prop_id)

func interact(_player) -> void:
	mission.use_prop(prop_id)

func refresh() -> void:
	var done: bool = mission.prop_done(prop_id)
	if _visual != null: _visual.modulate = Color("8edcb4") if done else Color.WHITE
	caption.modulate = Color("8edcb4") if done else accent
