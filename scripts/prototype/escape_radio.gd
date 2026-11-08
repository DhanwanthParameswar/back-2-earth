extends Node
## Crew replies: Gemini (via /escape/talk) + ElevenLabs voice. If the server is
## unreachable or the reply is unusable, the local scripted interpreter answers.

signal answered(data: Dictionary)
signal status_changed(text: String)
signal transcribed(text: String)

var mission
var live_enabled := true
var busy := false
var histories := {"mara": [], "ivo": []}
var request: HTTPRequest
var audio_request: HTTPRequest
var voice: AudioStreamPlayer
var pending_id := ""
var pending_message := ""
var pending_version := -1
var audio_version := -1
var _speech_callback = null
var _speech_error = null

func _ready() -> void:
	request = HTTPRequest.new()
	request.timeout = 8
	add_child(request)
	request.request_completed.connect(_on_reply)
	audio_request = HTTPRequest.new()
	audio_request.timeout = 10
	add_child(audio_request)
	audio_request.request_completed.connect(_on_audio)
	voice = AudioStreamPlayer.new()
	add_child(voice)
	if OS.has_feature("web"):
		_speech_callback = JavaScriptBridge.create_callback(_on_speech)
		_speech_error = JavaScriptBridge.create_callback(_on_speech_error)

func ask(id: String, message: String) -> void:
	if busy or message.strip_edges() == "": return
	voice.stop()
	audio_request.cancel_request()
	pending_id = id
	pending_message = message.strip_edges().left(200)
	pending_version = mission.state.version
	if not live_enabled:
		_deliver(mission.offline_response(id, pending_message))
		return
	busy = true
	status_changed.emit("Contacting Gemini…")
	var body: Dictionary = mission.snapshot(id)
	body["message"] = pending_message
	body["history"] = histories[id]
	var error := request.request(Settings.backend_url() + "/escape/talk", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK: _fallback()

func cancel() -> void:
	request.cancel_request()
	audio_request.cancel_request()
	voice.stop()
	busy = false
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.b2eRecognition){window.b2eRecognition.onresult=null;window.b2eRecognition.onerror=null;window.b2eRecognition.onend=null;window.b2eRecognition.abort();window.b2eRecognition=null;}", true)

func _on_reply(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	busy = false
	if pending_version != mission.state.version or mission.ending:
		status_changed.emit("Situation changed. Ask again for the current plan.")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fallback()
		return
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary or not data.get("line") is String or not data.get("action") is String or str(data.get("npc_id", "")) != pending_id or data.get("state_version", -1) != pending_version:
		_fallback()
		return
	if data.line.length() > 420 or not mission.available_actions(pending_id).has(data.action):
		_fallback()
		return
	if data.get("source", "") != "live":
		_fallback()
		return
	_deliver(data)
	var url: String = str(data.get("audio_url", ""))
	if url.begins_with("/npc/audio/"):
		audio_version = mission.state.version
		audio_request.request(Settings.backend_url() + url)

func _fallback() -> void:
	busy = false
	var response: Dictionary = mission.offline_response(pending_id, pending_message)
	response["source"] = "offline · live unavailable"
	_deliver(response)

func _deliver(data: Dictionary) -> void:
	var correction: String = mission.act_on_dialogue(pending_id, str(data.get("action", "none")))
	if correction != "": data["line"] = correction
	histories[pending_id].append({"role": "player", "text": pending_message})
	histories[pending_id].append({"role": "npc", "text": data.line})
	while histories[pending_id].size() > 6: histories[pending_id].pop_front()
	data["npc_id"] = pending_id
	answered.emit(data)

func _on_audio(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or bytes.size() < 200 or audio_version != mission.state.version or mission.ending: return
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	voice.stream = stream
	voice.play()

func speech_supported() -> bool:
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.SpeechRecognition || window.webkitSpeechRecognition)", true))

func listen() -> void:
	if not speech_supported():
		status_changed.emit("Speech input needs a supported web browser. You can always type.")
		return
	voice.stop()
	var window = JavaScriptBridge.get_interface("window")
	window.b2eSpeechResult = _speech_callback
	window.b2eSpeechError = _speech_error
	JavaScriptBridge.eval("""
		if(window.b2eRecognition) window.b2eRecognition.abort();
		const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
		const recognition = new Recognition();
		window.b2eRecognition = recognition;
		recognition.lang = 'en-US';
		recognition.interimResults = false;
		recognition.continuous = false;
		recognition.onresult = e => window.b2eSpeechResult(e.results[0][0].transcript);
		recognition.onerror = e => window.b2eSpeechError(e.error);
		recognition.onend = () => { window.b2eRecognition = null; };
		try { recognition.start(); } catch(e) { window.b2eSpeechError(String(e)); }
	""", true)
	status_changed.emit("Listening… transcript appears below. Review it, then send.")

func _on_speech(args: Array) -> void:
	if not args.is_empty(): transcribed.emit(str(args[0]))

func _on_speech_error(args: Array) -> void:
	status_changed.emit("Microphone: " + str(args[0] if not args.is_empty() else "unavailable") + ". You can type instead.")

func _exit_tree() -> void:
	cancel()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.b2eSpeechResult=null;window.b2eSpeechError=null;", true)
