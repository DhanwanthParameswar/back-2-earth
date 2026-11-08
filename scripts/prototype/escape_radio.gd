extends Node
## Crew replies: Gemini (via /escape/talk) + ElevenLabs voice. If the server is
## unreachable or the reply is unusable, the local scripted interpreter answers.

signal answered(data: Dictionary)
signal status_changed(text: String)
signal transcribed(text: String)
## Voice chat: words as you speak, the final sentence, mic on/off, crew voice done.
signal speech_partial(text: String)
signal speech_final(text: String)
signal listening_changed(on: bool)
signal voice_finished

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
var _speech_end = null
var listening := false
var _heard := ""      # latest transcript of the current listen
var _final_sent := false

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
	voice.finished.connect(func(): voice_finished.emit())
	if OS.has_feature("web"):
		_speech_callback = JavaScriptBridge.create_callback(_on_speech)
		_speech_error = JavaScriptBridge.create_callback(_on_speech_error)
		_speech_end = JavaScriptBridge.create_callback(_on_speech_end)

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

func cancel(stop_voice := true) -> void:
	request.cancel_request()
	if stop_voice:
		audio_request.cancel_request()
		voice.stop()
	busy = false
	_set_listening(false)
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
	# An older hosted backend may still use the original prototype names.
	# Keep displayed replies consistent and skip any voice that says an old name.
	var current_line: String = data.line
	for old_name in ["mara", "ivo"]:
		var name_pattern := RegEx.new()
		name_pattern.compile("(?i)\\b" + old_name + "\\b")
		current_line = name_pattern.sub(current_line, "Aaron" if old_name == "mara" else "Dhan", true)
	if current_line != data.line:
		data.line = current_line
		data["audio_url"] = ""
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
	# True when the crewmate actually started doing something (the chat then closes so you can watch).
	data["started"] = str(data.get("action", "none")) != "none" and correction == ""
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

## Browser speech recognition (Chrome / Edge). Words arrive live as
## speech_partial; when you stop talking, speech_final carries the sentence.
func listen() -> void:
	if not speech_supported():
		status_changed.emit("Speech input needs Chrome or Edge. You can always type.")
		return
	voice.stop()
	_heard = ""
	_final_sent = false
	var window = JavaScriptBridge.get_interface("window")
	window.b2eSpeechResult = _speech_callback
	window.b2eSpeechError = _speech_error
	window.b2eSpeechEnd = _speech_end
	JavaScriptBridge.eval("""
		if(window.b2eRecognition){window.b2eRecognition.onend=null;window.b2eRecognition.abort();}
		const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
		const recognition = new Recognition();
		window.b2eRecognition = recognition;
		recognition.lang = 'en-US';
		recognition.interimResults = true;
		recognition.continuous = false;
		recognition.onresult = e => {
			let text = '', done = false;
			for (let i = 0; i < e.results.length; i++) { text += e.results[i][0].transcript; if (e.results[i].isFinal) done = true; }
			window.b2eSpeechResult(text, done);
		};
		recognition.onerror = e => window.b2eSpeechError(e.error);
		recognition.onend = () => { window.b2eRecognition = null; if (window.b2eSpeechEnd) window.b2eSpeechEnd(); };
		try { recognition.start(); } catch(e) { window.b2eSpeechError(String(e)); }
	""", true)
	_set_listening(true)

func stop_listening() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.b2eRecognition){window.b2eRecognition.onend=null;window.b2eRecognition.abort();window.b2eRecognition=null;}", true)
	_set_listening(false)

func _set_listening(on: bool) -> void:
	if listening == on: return
	listening = on
	listening_changed.emit(on)

func _on_speech(args: Array) -> void:
	if args.is_empty(): return
	_heard = str(args[0]).strip_edges()
	var done := args.size() > 1 and bool(args[1])
	if done:
		_send_heard()
	else:
		speech_partial.emit(_heard)

## Recognition stopped (you went quiet). Send whatever was heard, if anything.
func _on_speech_end(_args: Array) -> void:
	_set_listening(false)
	_send_heard()

func _send_heard() -> void:
	if _final_sent or _heard == "": return
	_final_sent = true
	transcribed.emit(_heard)
	speech_final.emit(_heard)

func _on_speech_error(args: Array) -> void:
	var error := str(args[0] if not args.is_empty() else "unavailable")
	_set_listening(false)
	match error:
		"no-speech": status_changed.emit("Didn't hear anything. Press Space to talk.")
		"aborted": pass
		"not-allowed", "service-not-allowed": status_changed.emit("Microphone blocked. Allow it in the browser, or pick TEXT chat in Settings.")
		_: status_changed.emit("Microphone: " + error + ". Press Space to try again.")

func _exit_tree() -> void:
	cancel()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.b2eSpeechResult=null;window.b2eSpeechError=null;window.b2eSpeechEnd=null;", true)
