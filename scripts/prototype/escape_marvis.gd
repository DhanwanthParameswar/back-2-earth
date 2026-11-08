extends RefCounted
## M.A.R.V.I.S. (Maintenance, Atmosphere and Routine Vessel Information System).
## Deliberately not an assistant: it recognises a fixed set of queries and answers
## with template sentences filled from the real game state. It never generates text,
## never advises and never acts. Each sentence has an id so it can be pre-recorded
## (assets/voice/escape/marvis_<id>.mp3).

## Checked in order; the first group with a matching word wins.
const INTENTS := [
	# Requests for it to *do* something it physically can't. "How do I fix X" falls through.
	["unavailable", ["fly ", "pilot the", "launch", "take off", "you fix", "fix it", "you repair", "repair it",
		"open the clamp", "release the clamp", "rescue", "carry", "lift ", "do it", "help dhan", "heal", "save us"]],
	["codes", ["e-3", "e-6", "e-9", "e3", "e6", "e9", "fault code", "error code", "what does e", "which fuse", "which box", "aux-", "which switch", "which setting", "selector"]],
	["kien", ["kien"]],
	["medical", ["medical", "injur", "hurt", "health", "vital", "is dhan", "dhan okay", "dhan ok", "condition", "leg", "pain", "bleed", "alive", "dying"]],
	["crew", ["crew", "where is", "where's", "locate", "who is", "anyone", "everyone", "aaron", "dhan", "people"]],
	["power", ["power", "battery", "energy", "electric", "cabinet", "fuse", "engineering", "juice", "freezer", "sample", "lab"]],
	["shuttle", ["shuttle", "clamp", "dock", "escape", "leave", "bay", "get home", "earth"]],
	["doors", ["door", "hatch", "airlock", "lock"]],
	["life", ["oxygen", "air", "atmosphere", "life support", "breathe", "how long", "time left"]],
	["status", ["status", "report", "what's wrong", "what is wrong", "what happened", "damage", "diagnos", "systems", "situation", "what's working", "what is working", "broken"]],
	["greeting", ["hello", "hi ", "hey", "marvis", "you there", "online"]],
]

var lines: Dictionary = {}   # sentence id -> text (data/escape_lines.json "marvis")

func _init() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/escape_lines.json"))
	if data is Dictionary: lines = data.get("marvis", {})

static func classify(message: String) -> String:
	var m := " " + message.to_lower().strip_edges() + " "
	for group in INTENTS:
		for word in group[1]:
			if m.contains(word): return group[0]
	return "unknown"

func text(ids: Array) -> String:
	var parts: PackedStringArray = []
	for id in ids: parts.append(str(lines.get(id, id)))
	return " ".join(parts)

## Sentence ids answering one query, built from the current state.
## Also logs what the player learned (state.learn).
func reply(intent: String, mission) -> Array:
	var s = mission.state
	var ids: Array = []
	match intent:
		"status":
			ids = [_main(s), "shuttle_intact", _clamps(s), "hull_sealed"]
			ids.append_array(_crew_summary(s))
			_learn_clamps(s)
		"power":
			ids.append(_main(s))
			if not s.has_flag("engineering_power"):
				ids.append("cabinet_isolated" if s.has_flag("isolated") else "fault_engineering")
				s.learn("m_fault", "M.A.R.V.I.S.: Fault in the engineering distribution cabinet.")
			if s.has_flag("battery_connected"): ids.append("battery_bay")
			elif s.has_flag("freezer_off"): ids.append("battery_free")
			else:
				ids.append("battery_freezer")
				s.learn("m_battery", "M.A.R.V.I.S.: The lab's emergency battery is running the freezer.")
			_learn_clamps(s)
		"shuttle":
			ids = ["shuttle_nominal", _clamps(s)]
			if not s.has_flag("clamps"): ids.append("manual_release")
			_learn_clamps(s)
		"crew":
			ids = _crew_summary(s)
			ids.append_array(_locations(mission))
		"medical":
			if not s.dhan_alive(): ids = ["dhan_no_vitals"]
			else:
				ids = ["dhan_fracture", "condition_%d" % s.stage()]
				ids.append("dhan_splinted" if s.has_flag("dhan_treated") else "dhan_recommend")
				if not s.has_flag("dhan_treated"):
					s.learn("m_medbay", "M.A.R.V.I.S.: Dhan's leg needs a splint. Medbay cabinet.")
		"kien": ids = ["crew_kien"]
		"doors": ids = ["doors_open"]
		"life": ids = ["life_support"]
		"codes":
			ids = ["codes_unavailable"]
			s.learn("m_codes", "M.A.R.V.I.S.: Ask the engineer what the codes mean.")
		"unavailable": ids = ["unavailable"]
		"greeting": ids = ["greeting"]
		_: ids = ["unknown"]
	return ids

func _main(s) -> String:
	if s.has_flag("engineering_power"): return "main_engineering"
	if s.has_flag("battery_connected"): return "main_battery"
	return "main_offline"

func _clamps(s) -> String:
	if s.has_flag("clamps"): return "clamps_released"
	return "clamps_engaged_powered" if s.powered() else "clamps_engaged_unpowered"

func _learn_clamps(s) -> void:
	if not s.powered():
		s.learn("m_clamps", "M.A.R.V.I.S.: Shuttle is intact. Its docking clamps have no power.")

func _crew_summary(s) -> Array:
	if not s.dhan_alive(): return ["crew_two", "dhan_no_vitals"]
	return ["crew_three", "dhan_injured"]

func _locations(mission) -> Array:
	var out: Array = []
	var near := 140.0
	var p: Vector2 = mission.player.position
	for entry in [["mara", "aaron"], ["ivo", "dhan"]]:
		if entry[0] == "ivo" and not mission.state.dhan_alive(): continue
		var actor = mission.crew[entry[0]]
		if not actor.visible:
			out.append_array([entry[1] + "_at", "room_SHUTTLE"])
		elif actor.position.distance_to(p) < near:
			out.append(entry[1] + "_with_you")
		else:
			var room: String = mission.room_at(actor.position)
			out.append_array([entry[1] + "_at", "room_" + room if lines.has("room_" + room) else "room_PASSAGE"])
	return out
