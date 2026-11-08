extends Node2D
## Mission root (scenes/main.tscn). Owner: A (integration).
##
## Every load of this scene is a brand-new run: GameState.new_run() is called
## here, and "restart" simply reloads the scene. That resets the timer,
## objectives, sled, doors, debris, gravity phase, and pending dialogue together.

const ShipBuilder = preload("res://scripts/ship/ship_builder.gd")
const GravityDirector = preload("res://scripts/core/gravity_director.gd")
const CompanionClient = preload("res://scripts/ai/companion_client.gd")
const NpcClient = preload("res://scripts/ai/npc_client.gd")
const NpcChat = preload("res://scripts/ui/npc_chat.gd")
const RunRecorder = preload("res://scripts/core/run_recorder.gd")
const LeaderboardPanel = preload("res://scripts/ui/leaderboard_panel.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PlayerScene = preload("res://scenes/player/player.tscn")
const Art = preload("res://scripts/ship/art.gd")
const SpaceWindow = preload("res://scripts/ship/space_window.gd")
const Starfield = preload("res://scripts/ship/starfield.gd")
## How far past the nose the camera may look (so the black hole ahead is visible).
const LOOK_AHEAD := 320.0

const LAYOUT_PATH := "res://data/ship_layout.txt"

# Untyped on purpose: these hold script instances whose custom methods we call.
var ship
var director
var player
var companion
var hud


func _ready() -> void:
	GameState.new_run()

	director = GravityDirector.new()
	director.name = "GravityDirector"
	add_child(director)

	ship = ShipBuilder.new()
	ship.name = "Ship"
	add_child(ship)
	ship.build_from_file(LAYOUT_PATH)
	_add_backdrop()

	# A looping nebula video behind every `W` window in the layout.
	for rect in ship.space_windows:
		var view = SpaceWindow.new()
		view.setup(rect)
		add_child(view)

	# The player lives inside the ship so it y-sorts with props and debris.
	player = PlayerScene.instantiate()
	player.position = ship.player_start
	ship.add_child(player)
	player.set_camera_limits(ship.get_bounds().grow_individual(0, 0, LOOK_AHEAD, 0))
	player.snap_camera()

	companion = CompanionClient.new()
	companion.name = "CompanionClient"
	add_child(companion)

	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)

	# Crewmate chat (layout char M): server client + the chat box.
	var npc_client = NpcClient.new()
	npc_client.name = "NpcClient"
	add_child(npc_client)
	var npc_chat = NpcChat.new()
	npc_chat.name = "NpcChat"
	add_child(npc_chat)

	# Runs -> Tiger Cloud database; leaderboard + optional account on the win screen.
	var recorder = RunRecorder.new()
	recorder.name = "RunRecorder"
	add_child(recorder)
	var board = LeaderboardPanel.new()
	board.name = "LeaderboardPanel"
	add_child(board)

	if not hud.is_intro_playing():  # the opening film has its own sound; the HUD starts the music after it
		Sfx.start_ambient()


## Space around the ship (seen through the `~` cells) and the black hole just
## ahead of the nose, where the ship is being pulled.
func _add_backdrop() -> void:
	var stars = Starfield.new()
	stars.name = "Starfield"
	stars.setup(ship.get_bounds().grow(800.0))
	add_child(stars)
	move_child(stars, 0)
	var t := Art.tex("res://assets/backdrops/black_hole_space.png")
	if t == null:
		return
	var bh := Sprite2D.new()
	bh.name = "BlackHole"
	bh.texture = t
	bh.z_index = -10
	# The hole is drawn 80 px right of the image center; its disk reaches ~146 px
	# out, so park the hole ~190 px past the nose.
	bh.position = ship.nose_point() + Vector2(190 - 80, 0)
	add_child(bh)
	move_child(bh, 1)
