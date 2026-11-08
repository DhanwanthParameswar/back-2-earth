extends Node
## Player-facing settings that survive restarts (autoload "Settings").
## Owner: D (presentation). Saved to user://settings.cfg.

signal changed
## Fired when the player switches between keyboard/mouse and a controller, so
## on-screen hints can show the right buttons.
signal input_device_changed

const InputSetup = preload("res://scripts/core/input_setup.gd")
const SAVE_PATH := "user://settings.cfg"
var save_path := SAVE_PATH

var muted := false
var reduced_shake := false
var fullscreen := false
## Set false to force the scripted (offline) companion, e.g. for a web build
## with no HTTPS backend.
var companion_enabled := true
## Crew chat in the escape mission: true = talk with your microphone (voice),
## false = type in the chat box (text). Voice falls back to text where the
## browser has no speech recognition (Firefox, desktop builds).
var voice_chat := true
## Controller rumble (scripts/core/haptics.gd).
var vibration := true
## True while the last thing the player touched was a controller (not saved).
var using_controller := false
## The /companion backend. Default matches server/companion_server.py.
var companion_url := "http://127.0.0.1:8787/companion"
## The hosted backend (server/companion_server.py behind Cloudflare). Crewmate
## chat always uses it; set the B2E_BACKEND environment variable (e.g.
## http://127.0.0.1:8787) to test a local server from the editor.
const BACKEND_URL := "https://api.back2earth.pp.ua"
## Web builds (https://back2earth.pp.ua) call the hosted backend for ECHO too: a
## page served over HTTPS can't reach a local http:// server.
const WEB_COMPANION_URL := BACKEND_URL + "/companion"

## Astronaut suits. Art: assets/sprites/astronaut_<id>.png (6-frame walk strip)
## and assets/ui/portrait_<id>.png (portrait). The player always wears
## PLAYER_SKIN (no suit picker); the in-game crewmate picks another one.
const SKINS := [
	{"id": "classic", "name": "CLASSIC", "blurb": "Standard issue"},
	{"id": "hazard", "name": "HAZARD", "blurb": "Engineering yellow"},
	{"id": "nebula", "name": "NEBULA", "blurb": "Deep-space violet"},
	{"id": "mint", "name": "MINT", "blurb": "Medbay mint"},
]
## The player is Johnny, who wears this suit in the opening film.
const PLAYER_SKIN := "classic"
var skin := PLAYER_SKIN
## Set by the main menu's START so the opening story (intro_cutscene.gd) plays
## once before that run. The HUD clears it; restarts (R) skip the story.
## Not saved.
var intro_pending := false

## Leaderboard account (optional: everyone starts as a guest). The token is a
## login session from the server; the password is never stored.
var account_name := ""
var account_token := ""
## Random id made once per device: guest wins show as Guest + its first 4 characters.
var guest_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.ensure_actions()
	if OS.get_environment("B2E_SETTINGS_PATH") != "": save_path = OS.get_environment("B2E_SETTINGS_PATH")
	_load()
	if guest_id.length() < 8:
		guest_id = Crypto.new().generate_random_bytes(6).hex_encode()  # 12 lowercase hex chars
		_save()
	if OS.has_feature("web"):
		# Not saved per player, so a changed backend address takes effect for everyone.
		companion_url = WEB_COMPANION_URL
	_apply_audio()
	if fullscreen and not OS.has_feature("web"):
		_apply_window()


func backend_url() -> String:
	var override := OS.get_environment("B2E_BACKEND").strip_edges()
	return override.trim_suffix("/") if override != "" else BACKEND_URL


func is_logged_in() -> bool:
	return account_token != ""


## How this player appears on the leaderboard (matches the server's view).
func player_name() -> String:
	return account_name if is_logged_in() else "Guest" + guest_id.left(4).to_upper()


func set_account(username: String, token: String) -> void:
	account_name = username
	account_token = token
	_save()
	changed.emit()


func clear_account() -> void:
	account_name = ""
	account_token = ""
	_save()
	changed.emit()


func toggle_mute() -> void:
	muted = not muted
	_apply_audio()
	_save()
	changed.emit()


func set_skin(skin_id: String) -> void:
	if skin_index(skin_id) < 0 or skin_id == skin:
		return
	skin = skin_id
	_save()
	changed.emit()


func skin_index(skin_id: String) -> int:
	for i in SKINS.size():
		if SKINS[i]["id"] == skin_id:
			return i
	return -1


static func skin_sheet_path(skin_id: String) -> String:
	return "res://assets/sprites/astronaut_%s.png" % skin_id


static func skin_portrait_path(skin_id: String) -> String:
	return "res://assets/ui/portrait_%s.png" % skin_id


func toggle_reduced_shake() -> void:
	reduced_shake = not reduced_shake
	_save()
	changed.emit()


## Live model replies for ECHO on/off (off = authored lines only, no network).
func toggle_voice_chat() -> void:
	voice_chat = not voice_chat
	_save()
	changed.emit()


func toggle_vibration() -> void:
	vibration = not vibration
	_save()
	changed.emit()


## Name of the connected controller, or "" when there is none.
func controller_name() -> String:
	var pads := Input.get_connected_joypads()
	return Input.get_joy_name(pads[0]) if not pads.is_empty() else ""


## The button to show in a hint for an action, for whatever the player is using.
func button_label(action: String) -> String:
	if using_controller:
		return {"interact": "A", "confirm": "A", "back": "B", "talk": "X", "flashlight": "Y",
			"radio_1": "LB", "radio_2": "RB", "radio_3": "L3", "deck_map": "BACK", "pause": "START", "move": "L-STICK"}.get(action, "?")
	return {"interact": "E", "confirm": "ENTER", "back": "ESC", "talk": "SPACE", "flashlight": "F",
		"radio_1": "1", "radio_2": "2", "radio_3": "3", "deck_map": "TAB", "pause": "ESC", "move": "WASD"}.get(action, "?")


## Notice which device the player is using (keys/mouse vs a controller).
func _input(event: InputEvent) -> void:
	var pad := event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4)
	var keys := event is InputEventKey or event is InputEventMouseButton
	if (pad and not using_controller) or (keys and using_controller):
		using_controller = pad
		input_device_changed.emit()


func toggle_companion() -> void:
	companion_enabled = not companion_enabled
	_save()
	changed.emit()


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	_apply_window()
	_save()
	changed.emit()


func _apply_window() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _apply_audio() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_mute(bus_idx, muted)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	muted = bool(cfg.get_value("audio", "muted", muted))
	reduced_shake = bool(cfg.get_value("video", "reduced_shake", reduced_shake))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	companion_enabled = bool(cfg.get_value("companion", "enabled", companion_enabled))
	companion_url = str(cfg.get_value("companion", "url", companion_url))
	voice_chat = bool(cfg.get_value("companion", "voice_chat", voice_chat))
	vibration = bool(cfg.get_value("controller", "vibration", vibration))
	skin = PLAYER_SKIN  # ignore a suit saved back when there was a picker
	account_name = str(cfg.get_value("account", "name", ""))
	account_token = str(cfg.get_value("account", "token", ""))
	guest_id = str(cfg.get_value("player", "guest_id", ""))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("video", "reduced_shake", reduced_shake)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("companion", "enabled", companion_enabled)
	cfg.set_value("companion", "url", companion_url)
	cfg.set_value("companion", "voice_chat", voice_chat)
	cfg.set_value("controller", "vibration", vibration)
	cfg.set_value("player", "skin", skin)
	cfg.set_value("account", "name", account_name)
	cfg.set_value("account", "token", account_token)
	cfg.set_value("player", "guest_id", guest_id)
	cfg.save(save_path)
