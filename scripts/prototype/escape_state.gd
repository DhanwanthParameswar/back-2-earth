extends RefCounted
## Story rules (docs/Game Design.md). Model output is only a proposal: this reducer
## is the one place progress is granted. It knows nothing about positions or nodes;
## escape_mission.gd checks who is standing where before calling apply().

## Every permanent progress flag (saves are validated against this list).
const FLAGS := ["dhan_free", "locker_clear", "isolated", "code_read", "fuse_installed",
	"fault_found", "aux_off", "engineering_power", "freezer_off", "battery_out",
	"battery_loaded", "battery_taken", "battery_connected", "case_requested", "case_arrived",
	"samples_saved", "samples_wrong", "splint_taken", "dhan_treated", "dhan_dead", "vial_given", "vial_wrong",
	"dhan_aboard", "clamps", "aaron_aboard", "departed"]
const CARRY := ["", "fuse_A", "fuse_B", "fuse_C", "splint", "battery cart",
	"vial_0", "vial_1", "vial_2", "splint_vial_0", "splint_vial_1", "splint_vial_2"]
## The medbay cabinet's three vials (names change every run). Only Aaron knows which is which.
const PAINKILLERS := ["MORPHIDONE", "ANALVEX", "DOLORIN"]
const SEDATIVES := ["SOMNAREX", "DORMICAL", "LETHEX"]
const STIMULANTS := ["ADRENACOR", "VIGORAL", "KARDIX"]
const VIAL_BOOST := 12.0        # the right painkiller
const VIAL_COST := 8.0          # a wrong vial
const BOXES := ["A", "B", "C"]
const CODES := [3, 6, 9]
const SELECTOR := ["I", "II", "III"]

## Dhan's condition (section 5 of the design doc). Tune here.
const DRAIN := 0.25            # per second, untreated
const DRAIN_TREATED := 0.12    # after the splint kit
const AARON_FACTOR := 0.85     # Aaron staying beside him
const SPLINT_BOOST := 10.0
const FAIL_COST := 5.0
const WRONG_SWITCH_COST := 3.0

## Quick failures (section 6): id -> title card.
const FAILS := {
	"F1": "Dhan did mention the handle.",
	"F2": "Fresh air. Briefly.",
	"F3": "Parking brake.",
	"F4": "Forgetting someone?",
	"F5": "Read the label.",
}

var flags: Dictionary = {}
var carrying := ""
var version := 0
## What the player has learned, in the words of whoever said it (the log on the map).
var journal: Array[String] = []
var learned: Dictionary = {}       # fact id -> true (each fact is logged once)
## Per-run puzzle answers. Only Dhan knows the code book; the player has to ask.
var puzzle: Dictionary = {}
var vitality := 100.0
var fails: Dictionary = {}         # fail ids hit this run
var promises: Dictionary = {}      # question id -> the player's own words
var fuse_at_cabinet := ""          # a fuse Aaron left beside the cabinet ("A"/"B"/"C")
var selector := 0                  # socket selector position the player has set (0 = I)

func _init() -> void:
	new_puzzle()

## Random answers so a judge's run differs from a rehearsal.
func new_puzzle(seed_value := -1) -> void:
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0: rng.seed = seed_value
	else: rng.randomize()
	var boxes := BOXES.duplicate()
	_shuffle(boxes, rng)
	var toggles := [0, 1, 2]
	_shuffle(toggles, rng)
	puzzle = {
		"code": CODES[rng.randi_range(0, 2)],
		# Dhan's code book: fault code -> spare fuse box.
		"fuse_for": {"3": boxes[0], "6": boxes[1], "9": boxes[2]},
		"aux": rng.randi_range(1, 3),
		# Dhan's wiring memory: AUX branch -> toggle position (0 = left).
		"toggle_for": {"1": toggles[0], "2": toggles[1], "3": toggles[2]},
		"selector": rng.randi_range(0, 2),
	}
	var vials := [PAINKILLERS[rng.randi_range(0, 2)], SEDATIVES[rng.randi_range(0, 2)], STIMULANTS[rng.randi_range(0, 2)]]
	_shuffle(vials, rng)
	puzzle["vials"] = vials
	puzzle["painkiller"] = vials.find(vials.filter(func(v): return v in PAINKILLERS)[0])

func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = list[i]
		list[i] = list[j]
		list[j] = t

func fault_code() -> String: return "E-%d" % int(puzzle.code)
func vial_names() -> Array:
	return puzzle.get("vials", [])

## What a vial name is, for Aaron: "painkiller", "sedative", "stimulant" or "".
static func vial_kind(name: String) -> String:
	var n := name.to_upper()
	if n in PAINKILLERS: return "painkiller"
	if n in SEDATIVES: return "sedative"
	if n in STIMULANTS: return "stimulant"
	return ""

func right_fuse() -> String: return str(puzzle.fuse_for.get(str(int(puzzle.code)), ""))
func fuse_for(code: int) -> String: return str(puzzle.fuse_for.get(str(code), ""))
func short_branch() -> String: return "AUX-%d" % int(puzzle.aux)
func right_toggle() -> int: return int(puzzle.toggle_for.get(str(int(puzzle.aux)), -1))
func toggle_for(branch: int) -> int: return int(puzzle.toggle_for.get(str(branch), -1))
func right_selector() -> String: return SELECTOR[int(puzzle.selector)]

func has_flag(key: String) -> bool:
	return bool(flags.get(key, false))

func powered() -> bool:
	return has_flag("engineering_power") or has_flag("battery_connected")

func dhan_alive() -> bool:
	return not has_flag("dhan_dead")

## 1 joking · 2 strained · 3 fading · 4 critical · 0 dead.
func stage() -> int:
	if has_flag("dhan_dead"): return 0
	if vitality >= 70.0: return 1
	if vitality >= 45.0: return 2
	if vitality >= 20.0: return 3
	return 4

## Which way the player is going (for the HUD and the AI). Only the freezer commits.
func route() -> String:
	if has_flag("freezer_off"): return "battery"
	if has_flag("isolated"): return "engineering"
	return ""

## Goal only, never the steps (section 11).
func objective() -> String:
	if has_flag("departed"): return "Back to Earth."
	if not has_flag("dhan_free"): return "Help Dhan."
	if not powered(): return "Get the shuttle working."
	return "Get everyone aboard. Launch."

func samples() -> String:
	if not has_flag("freezer_off"): return "all"
	if has_flag("samples_saved"): return "priority"
	return "none"

## Section 7. Checked in this order.
func ending() -> String:
	if has_flag("dhan_dead"): return "two_came_home"
	if stage() >= 3: return "barely"
	match samples():
		"all": return "everyone_home"
		"priority": return "what_he_left"
	return "kept_each_other"

## Log a fact once. Returns true the first time.
func learn(id: String, text: String) -> bool:
	if learned.has(id): return false
	learned[id] = true
	journal.append(text)
	while journal.size() > 40: journal.pop_front()
	return true

## Dhan's clock. Returns "died" the moment he dies, else "".
func tick(delta: float, aaron_beside: bool) -> String:
	if not has_flag("dhan_free") or has_flag("dhan_dead") or has_flag("departed") or has_flag("dhan_aboard"):
		return ""
	var rate := DRAIN_TREATED if has_flag("dhan_treated") else DRAIN
	if aaron_beside: rate *= AARON_FACTOR
	vitality = maxf(0.0, vitality - rate * delta)
	if vitality <= 0.0:
		flags["dhan_dead"] = true
		version += 1
		return "died"
	return ""

func hurt(amount: float) -> void:
	if has_flag("dhan_free") and dhan_alive() and not has_flag("dhan_aboard"):
		vitality = maxf(1.0, vitality - amount)  # a mistake never kills him outright

## One player or crew action. Returns {ok, line} plus "fail" (an F-id) for a quick failure,
## or "hurt" when a wrong guess cost Dhan something.
func apply(action: String, arg := "") -> Dictionary:
	if has_flag("departed"): return _no("We're already on our way home.")
	match action:
		"free_dhan":
			if has_flag("dhan_free"): return _no("Dhan's already free.")
			flags["locker_clear"] = true
			return _grant("dhan_free", "")
		"airlock":
			return _fail("F2")
		"isolate":
			if has_flag("isolated"): return _no("The isolator is already pulled. The cabinet is dead.")
			return _grant("isolated", "")
		"cabinet_touch":
			if not has_flag("isolated"): return _fail("F1")
			return {"ok": true, "line": ""}
		"read_code":
			flags["code_read"] = true
			return {"ok": true, "line": ""}
		"take_fuse":
			if not arg in BOXES: return _no("Pick a box.")
			if carrying == "fuse_" + arg: return _no("You're already holding a fuse from box %s." % arg)
			if carrying != "" and not carrying.begins_with("fuse_"): return _no("Your hands are full.")
			carrying = "fuse_" + arg
			version += 1
			return {"ok": true, "line": "Fuse from box %s." % arg}
		"seat_fuse":
			if not has_flag("isolated"): return _fail("F1")
			if has_flag("fuse_installed"): return _no("The new fuse is already seated.")
			var box := carrying.trim_prefix("fuse_") if carrying.begins_with("fuse_") else fuse_at_cabinet
			if box == "": return _no("The slot's empty. It needs a spare fuse.")
			if box != right_fuse():
				return _no("The box %s fuse is the wrong size. It won't seat." % box)
			if carrying.begins_with("fuse_"): carrying = ""
			else: fuse_at_cabinet = ""
			return _grant("fuse_installed", "")
		"test":
			if not has_flag("isolated"): return _fail("F1")
			if not has_flag("fuse_installed"): return _no("Nothing happens. The fuse slot is empty.")
			if has_flag("fault_found"): return _no("It trips again. %s is still shorting." % short_branch()) if not has_flag("aux_off") else _no("Test passes. Press RESTART.")
			return _grant("fault_found", "")
		"toggle":
			if not has_flag("fault_found"): return _no("Nothing to isolate yet. Test the cabinet first.")
			if has_flag("aux_off"): return _no("The shorted branch is already cut.")
			if int(arg) != right_toggle():
				version += 1
				return {"ok": false, "line": "Clunk. Wrong branch. The short is still there.", "hurt": WRONG_SWITCH_COST}
			return _grant("aux_off", "")
		"restart":
			if not has_flag("isolated"): return _fail("F1")
			if not has_flag("fuse_installed"): return _no("Restart fails. No fuse.")
			if not has_flag("aux_off"): return _no("Breaker trips. %s is still shorting." % short_branch()) if has_flag("fault_found") else _no("Test the circuit before restarting.")
			if powered(): return _no("The bay already has power.")
			# Two places at once: the shuttle bay's breaker has to be held shut while RESTART is pressed.
			if arg != "held": return _no("RESTART REJECTED. The shuttle bay breaker is open. Someone has to hold it shut at the bay power panel while you press RESTART.")
			return _grant("engineering_power", "")
		"fetch_case":
			if has_flag("freezer_off"): return _no("The freezer's already off. The samples are gone.")
			if has_flag("case_requested"): return _no("The case is already on its way.")
			return _grant("case_requested", "")
		"case_arrived":
			return _grant("case_arrived", "")
		"pack_rack":
			if has_flag("freezer_off"): return _no("Too late. They've warmed.")
			if not has_flag("case_arrived"): return _no("Nothing to pack them into.")
			if has_flag("samples_saved") or has_flag("samples_wrong"): return _no("The case is full.")
			return _grant("samples_saved" if arg == "priority" else "samples_wrong", "")
		"freezer_off":
			if has_flag("freezer_off"): return _no("The freezer's already off.")
			return _grant("freezer_off", "")
		"battery_latch":
			if has_flag("battery_out"): return _no("The latch is already open.")
			if not has_flag("freezer_off"): return _fail("F5")
			return _grant("battery_out", "")
		"load_battery":
			if not has_flag("battery_out"): return _no("It's still latched in.")
			return _grant("battery_loaded", "")
		"take_cart":
			if not has_flag("battery_loaded"): return _no("The cart's empty.")
			if has_flag("battery_taken"): return _no("You've already got the cart.")
			if carrying != "": return _no("Put down what you're holding first.")
			carrying = "battery cart"
			return _grant("battery_taken", "")
		"set_selector":
			selector = clampi(int(arg), 0, 2)
			version += 1
			return {"ok": true, "line": ""}
		"connect_battery":
			if powered(): return _no("The bay already has power.")
			if carrying != "battery cart": return _no("Nothing to plug in. The battery is still in the lab.")
			if selector != int(puzzle.selector):
				version += 1
				return {"ok": false, "line": "Pop. The breaker trips. Wrong setting for this battery."}
			carrying = ""
			return _grant("battery_connected", "")
		"take_splint":
			if has_flag("splint_taken"): return _no("You already took the splint kit.")
			if carrying != "" and not carrying.begins_with("vial_"): return _no("Your hands are full.")
			carrying = "splint" + ("_" + carrying if carrying != "" else "")
			return _grant("splint_taken", "")
		"take_vial":
			if has_flag("vial_given") or has_flag("vial_wrong") or carrying.contains("vial_"): return _no("You've already taken a vial.")
			if carrying != "" and carrying != "splint": return _no("Your hands are full.")
			if not arg in ["0", "1", "2"]: return _no("")
			carrying = ("splint_" if carrying == "splint" else "") + "vial_" + arg
			version += 1
			return {"ok": true, "line": ""}
		"give_vial":
			if not carrying.contains("vial_"): return _no("You need a vial from the medbay cabinet.")
			if not dhan_alive(): return _no("It's too late for that.")
			var index := int(carrying.right(1))
			carrying = "splint" if carrying.begins_with("splint") else ""
			if index == int(puzzle.get("painkiller", -1)):
				vitality = minf(100.0, vitality + VIAL_BOOST)
				return _grant("vial_given", "")
			flags["vial_wrong"] = true
			version += 1
			hurt(VIAL_COST)
			return {"ok": false, "line": "", "wrong": true}
		"apply_splint":
			if not carrying.begins_with("splint"): return _no("You need the splint kit from the medbay.")
			if not dhan_alive(): return _no("It's too late for that.")
			carrying = carrying.trim_prefix("splint").trim_prefix("_")
			vitality = minf(100.0, vitality + SPLINT_BOOST)
			return _grant("dhan_treated", "")
		"carry_dhan":
			if not powered(): return _no("Not yet. The shuttle can't leave until the clamps have power.")
			if not dhan_alive() or has_flag("dhan_aboard"): return _no("")
			return _grant("dhan_aboard", "")
		"release":
			if not powered(): return _no("Docking controls have no power.")
			if has_flag("clamps"): return _no("The clamps are already open.")
			# On Johnny's mark: the clamps only open while the hold thrusters keep the shuttle steady.
			if arg != "thrust": return _no("The clamps stay shut with the engines cold. The shuttle would drift into the wall. Fire the hold thrusters first.")
			return _grant("clamps", "")
		"aaron_aboard":
			if not has_flag("clamps"): return _no("")
			return _grant("aaron_aboard", "")
		"launch":
			if not has_flag("clamps"): return _fail("F3")
			if dhan_alive() and not has_flag("dhan_aboard"): return _no("Not without Dhan.")
			if not has_flag("aaron_aboard"): return _fail("F4")
			return _grant("departed", "")
	return _no("That isn't possible right now.")

func _grant(key: String, line: String) -> Dictionary:
	if has_flag(key): return _no("Already done.")
	flags[key] = true
	version += 1
	return {"ok": true, "line": line}

func _fail(id: String) -> Dictionary:
	fails[id] = true
	return {"ok": false, "fail": id, "line": FAILS[id]}

func _no(line: String) -> Dictionary:
	return {"ok": false, "line": line}

# --- What the player said: codes and letters, however speech-to-text spelled them ---

const _DIGITS := {"one": 1, "won": 1, "two": 2, "to": 2, "too": 2, "three": 3, "tree": 3,
	"free": 3, "six": 6, "sicks": 6, "nine": 9, "nein": 9}

## "E-6", "e6", "e six", "eat six", "error six", "the six one" -> 6. 0 when none found.
static func parse_code(message: String) -> int:
	var m := message.to_lower()
	var re := RegEx.new()
	re.compile("\\b(?:e|ee|eat|easy|echo|error|code|fault)\\s*[-:#]?\\s*(3|6|9|three|tree|free|six|sicks|nine|nein)\\b")
	var hit := re.search(m)
	if hit == null:
		re.compile("\\b(?:e|ee)(3|6|9)\\b")
		hit = re.search(m)
	if hit == null:
		# A bare number only counts in a message that's about the code, and never
		# when it's a switch number ("it says aux 3").
		if parse_aux(message) > 0: return 0
		if not (m.contains("code") or m.contains("display") or m.contains("screen") or m.contains("says") or m.contains("reads") or m.contains("fault")):
			return 0
		re.compile("\\b(3|6|9|three|six|nine)\\b")
		hit = re.search(m)
		if hit == null: return 0
	var word := hit.get_string(1)
	return int(word) if word.is_valid_int() else int(_DIGITS.get(word, 0))

## "aux two", "AUX-2", "ox 2", "auxiliary two", "branch two" -> 2. 0 when none found.
static func parse_aux(message: String) -> int:
	var m := message.to_lower()
	var re := RegEx.new()
	re.compile("\\b(?:aux|ox|awks|auks|ax|axe|oaks|ops|auxiliary|branch)\\s*[-:#]?\\s*(1|2|3|one|won|two|to|too|three|tree|free)\\b")
	var hit := re.search(m)
	if hit == null:
		re.compile("\\baux(1|2|3)\\b")
		hit = re.search(m)
	if hit == null: return 0
	var word := hit.get_string(1)
	return int(word) if word.is_valid_int() else int(_DIGITS.get(word, 0))

## "box B", "fuse bee", "the C box", "letter a" -> "B"/"C"/"A". "" when none found.
static func parse_box(message: String) -> String:
	var m := message.to_lower()
	var letters := {"a": "A", "ay": "A", "eh": "A", "alpha": "A", "alfa": "A", "b": "B", "bee": "B", "be": "B", "bravo": "B",
		"c": "C", "see": "C", "sea": "C", "cee": "C", "charlie": "C"}
	var re := RegEx.new()
	re.compile("\\b(?:box|boxes|fuse|letter|crate|bin)\\s*[-:#]?\\s*(a|ay|eh|alpha|alfa|b|bee|be|bravo|c|see|sea|cee|charlie)\\b")
	var hit := re.search(m)
	if hit == null:
		re.compile("\\b(b|c|bee|cee|alpha|bravo|charlie)\\s+(?:box|fuse)\\b")  # not "a": "a fuse" is just English
		hit = re.search(m)
	if hit == null: return ""
	return str(letters.get(hit.get_string(1), ""))
