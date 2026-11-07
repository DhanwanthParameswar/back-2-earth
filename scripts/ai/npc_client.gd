extends Node
## Talks to an NPC through the backend. Owner: C.
##
## Flow: ask(text) -> POST /npc/talk (Gemini writes the reply) -> `reply` signal
##       -> GET /npc/audio/<id>.mp3 (ElevenLabs voice) -> `voice` signal.
## Text arrives first; the voice follows when ready. If the server is down, slow,
## or refuses, the NPC answers with a scripted line built from the real hint, so
## talking never blocks the game.

signal reply(text: String, source: String)  # source: "live", "mock", or "offline"
signal voice(stream: AudioStream)
signal busy_changed(is_busy: bool)

const CompanionClient = preload("res://scripts/ai/companion_client.gd")

const TALK_TIMEOUT := 8.0
const VOICE_TIMEOUT := 10.0
const MAX_HISTORY := 6
const MAX_MESSAGE := 200
const MAX_LINE := 240

var npc_id := "crewmate"
## The conversation so far, oldest first: {"role": "player"|"npc", "text": String}.
var history: Array = []
var busy := false

var _talk: HTTPRequest
var _audio: HTTPRequest
var _sent_run_id := -1
var _last_message := ""


func _ready() -> void:
	add_to_group("npc_client")
	_talk = HTTPRequest.new()
	_talk.timeout = TALK_TIMEOUT
	add_child(_talk)
	_talk.request_completed.connect(_on_talk_completed)
	_audio = HTTPRequest.new()
	_audio.timeout = VOICE_TIMEOUT
	add_child(_audio)
	_audio.request_completed.connect(_on_audio_completed)


## Send what the player typed. Returns false if empty or still waiting.
func ask(message: String) -> bool:
	message = message.strip_edges().left(MAX_MESSAGE)
	if message == "" or busy:
		return false
	var canonical: Dictionary = GameState.get_canonical()
	var body := {
		"npc_id": npc_id,
		"run_id": GameState.run_id,
		"message": message,
		"history": history.duplicate(true),
		"objective_id": canonical["id"],
		"canonical_hint": canonical["hint"],
		"room_id": GameState.current_room,
		"time_band": GameState.time_band(),
	}
	_remember("player", message)
	_last_message = message
	_sent_run_id = GameState.run_id
	_audio.cancel_request()  # an older answer's voice should not start now
	var err := _talk.request(
		Settings.backend_url() + "/npc/talk",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if err != OK:
		_answer_offline()
		return true
	_set_busy(true)
	return true


func _on_talk_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_set_busy(false)
	if _sent_run_id != GameState.run_id:
		return  # a reply for a previous run
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_answer_offline()
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	var line := validate_reply(data, npc_id)
	if line == "":
		_answer_offline()
		return
	_remember("npc", line)
	reply.emit(line, "mock" if str(data.get("source", "")) == "mock" else "live")
	var audio_url = data.get("audio_url")
	if typeof(audio_url) == TYPE_STRING and str(audio_url).begins_with("/npc/audio/"):
		_audio.request(Settings.backend_url() + str(audio_url))


func _on_audio_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() < 200:
		return  # no voice this time; the text is already on screen
	var stream := AudioStreamMP3.new()
	stream.data = body
	voice.emit(stream)


func _answer_offline() -> void:
	var line := offline_line(_last_message, str(GameState.get_canonical()["hint"]))
	_remember("npc", line)
	reply.emit(line, "offline")


func _remember(role: String, text: String) -> void:
	history.append({"role": role, "text": text})
	while history.size() > MAX_HISTORY:
		history.pop_front()


func _set_busy(value: bool) -> void:
	busy = value
	busy_changed.emit(value)


# --- Pure helpers (covered by tests/test_runner.gd) ---------------------------------

## The cleaned line, or "" if the reply must be rejected.
static func validate_reply(data, expected_npc: String) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	if str(data.get("npc_id", "")) != expected_npc or typeof(data.get("line")) != TYPE_STRING:
		return ""
	var line := CompanionClient.sanitize(data["line"])
	if line.is_empty() or line.length() > MAX_LINE:
		return ""
	return line


## What the NPC says without the server: always the real hint, never invented.
static func offline_line(message: String, hint: String) -> String:
	if hint == "":
		return "The radio's breaking up. Stay close to me."
	var m := message.to_lower()
	for word in ["instruction", "help", "what do", "what now", "what should", "where", "how do", "objective", "next", "plan"]:
		if m.contains(word):
			return "Radio's patchy, so listen: %s" % hint
	return "Comms are down, I only caught half of that. Focus: %s" % hint
