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

const EscapeState = preload("res://scripts/prototype/escape_state.gd")

var mission
var live_enabled := true
var busy := false
var histories := {"mara": [], "ivo": []}
var memory_notes := {"mara": [], "ivo": []}
var request: HTTPRequest
var audio_request: HTTPRequest
var voice: AudioStreamPlayer
var pending_id := ""
var pending_message := ""
var pending_version := -1
var pending_answering := ""  # the crew question this message answers
var audio_version := -1
var _audio_loading := false            # a reply's voice is downloading
var _held: AudioStream = null           # a reply's voice waiting for a scripted line to finish
var _speech_callback = null
var _speech_error = null
var _speech_end = null
var listening := false
var _heard := ""      # latest transcript of the current listen
var _final_sent := false
var _heard_sure := true  # the browser was confident, or it heard words the game knows

## Speech recognition help. The browser often mishears the crew's names and spoken
## letters / numbers, and picks up background talk:
##  - it gives several guesses; we take the one with the most game words (names, codes),
##  - known mishearings of the names become the names ("dawn" -> "Dhan"),
##  - a low-confidence guess with no game words in it is thrown away, not sent.
const HINT_PHRASES := ["Aaron", "Dhan", "Kien", "MARVIS", "Johnny", "box A", "box B", "box C", "fuse",
	"E3", "E6", "E9", "aux 1", "aux 2", "aux 3", "locker", "battery", "shuttle", "medbay", "splint", "sample case"]
const LOW_CONFIDENCE := 0.45
const NAME_FIXES := {
	"Dhan": "dawn|dahn|dhaan|don|dan|dun|thon",
	"Aaron": "erin|aron|arron|aarin",
	"Kien": "kian|keon|kean|keane|kyan|keen|kiyan|cayenne",
	"MARVIS": "marvis|mavis|jarvis|marvin|mervis|marvel|marv is|mar vis|maris",
}
## The last few things the crew / M.A.R.V.I.S. said out loud. If the mic "hears"
## one of them, it came from your speakers, not from you: it's thrown away.
var recent_lines: Array[String] = []
const ECHO_MATCH := 0.75   # share of the heard words found in a recent crew line

## Mic rules (tap to talk): the mic is only on after you press Space, Space again
## sends, and it never listens while a crew voice is playing (no speaker echo loop).
func _process(_delta: float) -> void:
	if _held != null and not (mission != null and mission.voice != null and mission.voice.playing):
		voice.stream = _held
		_held = null
		voice.play()
	if listening and crew_talking():
		stop_listening()
		status_changed.emit("Mic off while the crew talks. Press %s when they're done." % Settings.button_label("talk"))

## A reply's voice is playing, downloading or waiting its turn: scripted lines hold off.
func voice_pending() -> bool:
	return voice.playing or _audio_loading or _held != null

## Drop the reply's voice (something timed has to be heard now).
func hush() -> void:
	voice.stop()
	_held = null
	_audio_loading = false
	audio_request.cancel_request()

## Any crew / M.A.R.V.I.S. voice playing right now (replies or scripted lines).
func crew_talking() -> bool:
	return voice.playing or (mission != null and mission.voice != null and mission.voice.playing)

## Remember a line that was just spoken, for the echo check.
func note_spoken(text: String) -> void:
	if text.strip_edges() == "": return
	recent_lines.append(text)
	while recent_lines.size() > 6: recent_lines.pop_front()

static func _words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var clean := RegEx.create_from_string("[^a-z0-9' ]").sub(text.to_lower(), " ", true)
	for w in clean.split(" ", false): out.append(w)
	return out

## True when what the mic heard is mostly a line the crew just said (3+ words, so a
## short "yes" or "okay" is never thrown away).
func is_echo(heard: String) -> bool:
	var words := _words(heard)
	if words.size() < 3: return false
	for line in recent_lines:
		var said := {}
		for w in _words(line): said[w] = true
		var hits := 0
		for w in words: if said.has(w): hits += 1
		if float(hits) / words.size() >= ECHO_MATCH: return true
	return false

func _ready() -> void:
	live_enabled = Settings.companion_enabled  # Settings · CREW LIVE AI (off = scripted replies)
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
	if message.strip_edges() == "": return
	if busy:
		status_changed.emit("Still waiting for the last answer…")
		return
	hush()
	pending_id = id
	pending_message = message.strip_edges().left(200)
	mission.note_player_spoke()
	var body: Dictionary = mission.snapshot(id, pending_message)
	pending_answering = mission.answering(id, pending_message)
	mission.capture_answer(id, pending_message)
	pending_version = mission.state.version
	if not live_enabled:
		_deliver(mission.offline_response(id, pending_message, pending_answering))
		return
	busy = true
	status_changed.emit("Contacting Gemini…")
	body["state_version"] = pending_version
	body["message"] = pending_message
	body["history"] = histories[id]
	body["memory_notes"] = memory_notes[id]
	# Conversations and remembered facts belong to this saved mission.
	body["guest_id"] = Settings.guest_id
	var headers := PackedStringArray(["Content-Type: application/json"])
	if Settings.account_token != "":
		headers.append("Authorization: Bearer " + Settings.account_token)
	var error := request.request(Settings.backend_url() + "/escape/talk", headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK: _fallback()

func cancel(stop_voice := true) -> void:
	request.cancel_request()
	if stop_voice:
		hush()
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
	var checked: String = mission.check_reply(pending_id, current_line, pending_message)
	if current_line != data.line or checked != current_line:
		data.line = checked
		data["audio_url"] = ""  # the voice would say the unchecked words
	var url: String = str(data.get("audio_url", ""))
	# Mark the voice as on its way first: what the reply sets off (Aaron starting the lift)
	# can queue lines of its own, and those wait for him to finish talking.
	_audio_loading = url.begins_with("/npc/audio/")
	_deliver(data)
	if _audio_loading:
		audio_version = mission.state.version
		if audio_request.request(Settings.backend_url() + url) != OK: _audio_loading = false

func _fallback() -> void:
	busy = false
	var response: Dictionary = mission.offline_response(pending_id, pending_message, pending_answering)
	response["source"] = "offline · live unavailable"
	_deliver(response)

func _deliver(data: Dictionary) -> void:
	var correction: String = mission.act_on_dialogue(pending_id, str(data.get("action", "none")), pending_message)
	if correction != "": data["line"] = correction
	# True when the crewmate actually started doing something (the chat then closes so you can watch).
	data["started"] = str(data.get("action", "none")) != "none" and correction == ""
	histories[pending_id].append({"role": "player", "text": pending_message})
	histories[pending_id].append({"role": "npc", "text": data.line})
	while histories[pending_id].size() > 6: histories[pending_id].pop_front()
	var note = data.get("memory_note")
	if note is String and note.length() > 0 and note.length() <= 120:
		if not memory_notes[pending_id].has(note): memory_notes[pending_id].append(note)
		while memory_notes[pending_id].size() > 12: memory_notes[pending_id].pop_front()
	mission.save_progress()
	note_spoken(str(data.line))
	data["npc_id"] = pending_id
	answered.emit(data)

## A pre-written line this crewmate just said: part of their conversation from now on.
func remember_line(id: String, text: String) -> void:
	note_spoken(text)
	if not histories.has(id): return
	histories[id].append({"role": "npc", "text": text.left(420)})
	while histories[id].size() > 6: histories[id].pop_front()

func add_memory(id: String, note: String) -> void:
	if not memory_notes.has(id) or note.strip_edges() == "": return
	note = note.strip_edges().left(120)
	if not memory_notes[id].has(note): memory_notes[id].append(note)
	while memory_notes[id].size() > 12: memory_notes[id].pop_front()

func _on_audio(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	_audio_loading = false
	# The reply's own action moves the state on (version + 1 or 2), so only drop the voice
	# when a lot has happened since, or the mission is over.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or bytes.size() < 200 or mission.state.version - audio_version > 3 or mission.ending: return
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	if mission.voice != null and mission.voice.playing:
		_held = stream  # wait for the scripted line to finish (_process)
		return
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
	# You pressed talk: the crew stop talking (and a reply still downloading won't play).
	hush()
	if mission != null: mission.stop_voice()
	_heard = ""
	_heard_sure = true
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
		recognition.maxAlternatives = 4;
		// Hint the game's words where the browser supports it (newer Chrome).
		try {
			if (window.SpeechRecognitionPhrase) recognition.phrases = %s.map(p => new SpeechRecognitionPhrase(p, 5.0));
		} catch(e) {}
		recognition.onresult = e => {
			// Every guess the browser has, as [{t: text, c: confidence}], best first.
			let alts = [], done = false;
			const n = Math.max(...Array.from(e.results, r => r.length));
			for (let k = 0; k < n; k++) {
				let text = '', conf = 1;
				for (let i = 0; i < e.results.length; i++) {
					const a = e.results[i][Math.min(k, e.results[i].length - 1)];
					text += a.transcript;
					if (e.results[i].isFinal) conf = Math.min(conf, a.confidence || 1);
				}
				alts.push({t: text, c: conf});
			}
			for (let i = 0; i < e.results.length; i++) if (e.results[i].isFinal) done = true;
			window.b2eSpeechResult(JSON.stringify(alts), done);
		};
		recognition.onerror = e => window.b2eSpeechError(e.error);
		recognition.onend = () => {
			window.b2eRecognition = null;
			if (window.b2eMicTrack) { window.b2eMicTrack.stop(); window.b2eMicTrack = null; }
			if (window.b2eSpeechEnd) window.b2eSpeechEnd();
		};
		// A mic with the browser's noise suppression, where recognition can take one
		// (newer Chrome); otherwise the browser's default mic.
		const begin = track => { try { track ? recognition.start(track) : recognition.start(); } catch(e) { if (track) { try { recognition.start(); } catch(e2) { window.b2eSpeechError(String(e2)); } } else window.b2eSpeechError(String(e)); } };
		if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia && recognition.start.length > 0) {
			navigator.mediaDevices.getUserMedia({audio: {noiseSuppression: true, echoCancellation: true, autoGainControl: true}})
				.then(stream => { window.b2eMicTrack = stream.getAudioTracks()[0]; if (window.b2eRecognition === recognition) begin(window.b2eMicTrack); else window.b2eMicTrack.stop(); })
				.catch(() => begin(null));
		} else begin(null);
	""" % JSON.stringify(HINT_PHRASES), true)
	_set_listening(true)

## The crew's names, fixed where the browser misheard them ("hey dawn" -> "hey Dhan").
static func fix_names(text: String) -> String:
	for name in NAME_FIXES:
		# "dawn's" -> "Dhan's", but never "don't" -> "Dhan't".
		var re := RegEx.create_from_string("(?i)\\b(?:" + str(NAME_FIXES[name]) + ")\\b(?!['’][a-rt-z])")
		text = re.sub(text, name, true)
	return text

## How many words in this guess the game understands (names, codes, switches, boxes).
static func game_words(text: String) -> int:
	var score := 0
	var low := text.to_lower()
	for name in ["aaron", "dhan", "kien", "marvis", "johnny"]:
		if RegEx.create_from_string("\\b" + name + "\\b").search(low) != null: score += 1
	if EscapeState.parse_code(text) > 0: score += 2
	if EscapeState.parse_aux(text) > 0: score += 2
	if EscapeState.parse_box(text) != "": score += 2
	return score

## The browser's best guess for the game: names fixed, the most game words wins
## (ties keep the browser's own order). Returns {t, c, score}.
static func pick_heard(alts: Array) -> Dictionary:
	var best := {"t": "", "c": 0.0, "score": -1}
	for a in alts:
		if not a is Dictionary: continue
		var text := fix_names(str(a.get("t", "")).strip_edges())
		if text == "": continue
		var score := game_words(text)
		if score > int(best.score):
			best = {"t": text, "c": float(a.get("c", 1.0)), "score": score}
	if int(best.score) < 0: best.score = 0
	return best

## Space while listening: send what you've said so far (or just turn the mic off).
func finish_listening() -> void:
	var heard := _heard
	stop_listening()
	if heard != "": _send_heard()

func stop_listening() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(window.b2eRecognition){window.b2eRecognition.onend=null;window.b2eRecognition.abort();window.b2eRecognition=null;} if(window.b2eMicTrack){window.b2eMicTrack.stop();window.b2eMicTrack=null;}", true)
	_set_listening(false)

func _set_listening(on: bool) -> void:
	if listening == on: return
	listening = on
	listening_changed.emit(on)

func _on_speech(args: Array) -> void:
	if args.is_empty(): return
	var alts = JSON.parse_string(str(args[0]))
	var best := pick_heard(alts if alts is Array else [{"t": str(args[0]), "c": 1.0}])
	_heard = str(best.t)
	_heard_sure = float(best.c) >= LOW_CONFIDENCE or float(best.score) > 0.0
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
	if is_echo(_heard):
		status_changed.emit("That was the crew's voice, not yours. Press %s to talk." % Settings.button_label("talk"))
		return
	if not _heard_sure:
		status_changed.emit("Didn't catch that clearly (\"%s\"). Press %s and say it again." % [_heard, Settings.button_label("talk")])
		return
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
