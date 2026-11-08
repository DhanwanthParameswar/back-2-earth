extends SceneTree
## Check with: godot --headless --path . --script res://tests/intro_runner.gd
const Film = preload("res://scripts/ui/intro_film.gd")
var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var film = Film.new()
	root.add_child(film)
	check(film.is_ready(), "Intro art and timing load")
	check(film.length() > 39.8, "Intro leaves time for all three survivors to enter the cabin")
	check(film._hatch_open_amount(21.5) == 0.0, "Dhan cannot enter the cabin during the breach")
	check(film._hatch_open_amount(37.5) == 0.0, "Cabin stays closed through Johnny's line")
	check(film._hatch_open_amount(37.9) == 1.0, "Cabin opens before the crew walks in")
	check(Film.AHEAD_WAIT_X > Film.HATCH[2] and Film.AHEAD_WAIT_X < Film.CORR_DOOR[0], "Dhan waits beyond the barrier but outside the cabin")
	for role in ["ahead", "survivor", "player"]:
		check(film.cabin_entry_x(role, 37.5) > Film.HATCH[2], "%s waits outside during the speech" % role)
		check(film.cabin_entry_x(role, 40.5) < Film.HATCH[0], "%s enters the cabin before the fade" % role)
		check(film.cabin_entry_x(role, 39.0) < film.cabin_entry_x(role, 37.5), "%s walks toward the cabin" % role)
	check(film._edit.size() > 1100 and film._edit[1099] == 1139 and film._edit[1100] == 1140, "New ending follows the original voice-timed cut without a jump")
	print("INTRO: %d checks, %d failures" % [checks, failures])
	film.queue_free()
	await process_frame
	quit(failures)
