extends Node
## Player-facing settings that survive restarts (autoload "Settings").
## Owner: D (presentation). Saved to user://settings.cfg.

signal changed

const InputSetup = preload("res://scripts/core/input_setup.gd")
const SAVE_PATH := "user://settings.cfg"

var muted := false
var reduced_shake := false
## Set false to force the scripted (offline) companion, e.g. for a web build
## with no HTTPS backend.
var companion_enabled := true
## The /companion backend. Default matches server/companion_server.py.
var companion_url := "http://127.0.0.1:8787/companion"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.ensure_actions()
	_load()
	_apply_audio()


func toggle_mute() -> void:
	muted = not muted
	_apply_audio()
	_save()
	changed.emit()


func toggle_reduced_shake() -> void:
	reduced_shake = not reduced_shake
	_save()
	changed.emit()


func _apply_audio() -> void:
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		AudioServer.set_bus_mute(bus_idx, muted)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	muted = bool(cfg.get_value("audio", "muted", muted))
	reduced_shake = bool(cfg.get_value("video", "reduced_shake", reduced_shake))
	companion_enabled = bool(cfg.get_value("companion", "enabled", companion_enabled))
	companion_url = str(cfg.get_value("companion", "url", companion_url))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("video", "reduced_shake", reduced_shake)
	cfg.set_value("companion", "enabled", companion_enabled)
	cfg.set_value("companion", "url", companion_url)
	cfg.save(SAVE_PATH)
