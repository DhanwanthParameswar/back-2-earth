extends Node2D
## Mission root (scenes/main.tscn). Owner: A (integration).
##
## Every load of this scene is a brand-new run: GameState.new_run() is called
## here, and "restart" simply reloads the scene. That resets the timer,
## objectives, sled, doors, debris, gravity phase, and pending dialogue together.

const ShipBuilder = preload("res://scripts/ship/ship_builder.gd")
const GravityDirector = preload("res://scripts/core/gravity_director.gd")
const CompanionClient = preload("res://scripts/ai/companion_client.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const Art = preload("res://scripts/ship/art.gd")

const LAYOUT_PATH := "res://data/ship_layout.txt"

# Untyped on purpose: these hold script instances whose custom methods we call.
var ship
var director
var player
var companion
var hud


func _ready() -> void:
	GameState.new_run()

	_add_backdrop()

	director = GravityDirector.new()
	director.name = "GravityDirector"
	add_child(director)

	ship = ShipBuilder.new()
	ship.name = "Ship"
	add_child(ship)
	ship.build_from_file(LAYOUT_PATH)

	player = PlayerScene.instantiate()
	player.position = ship.player_start
	add_child(player)
	player.set_camera_limits(ship.get_bounds())

	companion = CompanionClient.new()
	companion.name = "CompanionClient"
	add_child(companion)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)

	Sfx.start_ambient()


## The black hole sits in world space just outside the cockpit, so you see it
## through the cockpit windows (`w` tiles are left transparent).
func _add_backdrop() -> void:
	var t := Art.tex("res://assets/backdrops/black_hole.png")
	if t == null:
		return
	var bh := Sprite2D.new()
	bh.name = "BlackHole"
	bh.texture = t
	bh.z_index = -10
	# The hole is drawn 80 px right of the image center; park it at the window column.
	bh.position = Vector2(16 - 80, 192)
	add_child(bh)
