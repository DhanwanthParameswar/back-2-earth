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
	var cutscene_script = load("res://scripts/ui/intro_cutscene.gd")
	var intro = cutscene_script.new()
	intro._t = 0.01
	check(is_equal_approx(intro._clamp_audio_clock(3.0), 0.01), "A stale mixer timestamp cannot flash the year card before the intro begins")
	intro._t = 0.03
	check(is_equal_approx(intro._clamp_audio_clock(0.0), 0.01), "The first fresh audio mix cannot rewind the picture")
	intro._t = 1.0
	check(is_equal_approx(intro._clamp_audio_clock(0.95), 0.95), "Normal playback follows the soundtrack clock")
	intro.free()
	intro = cutscene_script.new()
	root.add_child(intro)
	intro.play()
	intro._process(5.0)
	check(intro._t < 0.3, "A long scene-loading frame does not advance a newly started intro")
	check(intro._film_time() < 0.3, "Cold-start playback stays before the year-card cue")
	intro.queue_free()
	var film = Film.new()
	root.add_child(film)
	check(film.is_ready(), "Intro art and timing load")
	check(Film.MONITOR_LINES[1][1] == "REPAIR MISSION:", "Monitor uses singular REPAIR")
	check(film._cabin_light(Film.T_IMPACT - 0.01)[0] == null, "Cabin lights remain on before the impact")
	check(film._cabin_light(Film.T_IMPACT)[0] == Film.POWER_OUT_ROOM, "Main lights cut immediately at the impact")
	check(film._cabin_light(Film.T_IMPACT + 1.0)[0] == Film.POWER_OUT_ROOM, "Cabin lights do not relight after the power failure")
	for t in [19.5, 24.0, 33.8, 40.0]:
		check(film._corridor_light(t)[0] == Film.POWER_OUT_ROOM, "Corridor remains unpowered at %s" % t)
	check(film.length() > 39.8, "Intro leaves time for the crew to face the locker in the hallway")
	check(Film.AHEAD_WAIT_X < Film.CORR_DOOR[0], "Dhan waits on the safe side of the barrier, at the locker")
	var end := Film.LENGTH - 0.5
	check(film._locker_look_x("player", 39.5) < film._locker_look_x("player", Film.T_LOCKER_LOOK), "Johnny walks up to the locker after his line")
	check(film._locker_look_x("player", end) < film._locker_look_x("survivor", end) and film._locker_look_x("player", end) < film._locker_look_x("ahead", end), "Johnny ends nearest the locker, like the game's start")
	for role in ["ahead", "survivor"]:
		check(film._locker_look_x(role, end) > film._locker_look_x("player", end) + 30, "%s ends back toward the barrier" % role)
	check(film._edit.size() > 1100 and film._edit[1099] == 1139 and film._edit[1100] == 1140, "New ending follows the original voice-timed cut without a jump")
	print("INTRO: %d checks, %d failures" % [checks, failures])
	film.queue_free()
	await process_frame
	quit(failures)
