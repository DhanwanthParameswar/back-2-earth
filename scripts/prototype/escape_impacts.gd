extends Node2D
## Debris keeps striking the hull while the crew work their way to the shuttle.
##
## Real debris doesn't hit on a metronome, so the strikes are random: the first
## comes 22-32 s into play (the opening already had its aftershock), then one
## every 20-45 s (about 30 s on average). About half are big hits close by; the
## rest land further along the hull and are quieter. A big hit sometimes brings
## a smaller second one a couple of seconds later.
##
## A big hit: the impact sound (tools/make_impact_sounds.py), controller rumble,
## a camera jolt, the lights dipping twice, dust shaken down from the ceiling,
## and a wall panel near you shorting out in a shower of sparks with a crackle,
## a flash and a second smaller pop. A distant hit: a deeper, quieter thud, a
## light rumble and jolt, and a little dust.
##
## Strikes wait while a scripted moment, a voiced line or an open panel is going
## on, and stop for the launch. "Reduced shake & flash" (Settings) softens the
## jolt, the flashes and the flicker; controller rumble follows its own setting.

const Haptics = preload("res://scripts/core/haptics.gd")
const TILE := 32.0
const FIRST_DELAY := Vector2(22.0, 32.0)      # seconds into play (min, max)
const GAP := Vector2(20.0, 45.0)              # seconds between strikes (min, max)
const BIG_CHANCE := 0.55                      # the rest are distant hits
const AFTERSHOCK_CHANCE := 0.3                # after a big hit
const AFTERSHOCK_DELAY := Vector2(1.6, 3.5)
const RETRY := 1.5                            # busy right now: check again this soon
const SPARK_RANGE := 7                        # tiles: sparks come from a wall you can see, this close

var mission
var rng := RandomNumberGenerator.new()
var _next_at := -1.0
var _aftershock_at := -1.0
var _additive: CanvasItemMaterial
var _spark_tex: ImageTexture
var _spark_ramp: Gradient
var _glow_tex: GradientTexture2D
var _dust_ramp: Gradient


func _ready() -> void:
	rng.randomize()
	_additive = CanvasItemMaterial.new()
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# A spark is a short streak: bright at its head, fading back along its tail.
	var img := Image.create(2, 7, false, Image.FORMAT_RGBA8)
	for y in 7:
		for x in 2:
			img.set_pixel(x, y, Color(1, 1, 1, (y + 1) / 7.0))
	_spark_tex = ImageTexture.create_from_image(img)
	_spark_ramp = Gradient.new()
	_spark_ramp.set_color(0, Color(1.0, 1.0, 0.9, 1.0))       # white-hot
	_spark_ramp.set_color(1, Color(0.7, 0.1, 0.05, 0.0))      # dull red, gone
	_spark_ramp.add_point(0.25, Color(1.0, 0.85, 0.4, 1.0))   # yellow
	_spark_ramp.add_point(0.6, Color(1.0, 0.45, 0.12, 0.9))   # orange
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.45))
	_glow_tex = GradientTexture2D.new()
	_glow_tex.gradient = g
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 64
	_glow_tex.height = 64
	_dust_ramp = Gradient.new()
	_dust_ramp.set_color(0, Color(0.8, 0.78, 0.74, 0.0))
	_dust_ramp.set_color(1, Color(0.8, 0.78, 0.74, 0.0))
	_dust_ramp.add_point(0.2, Color(0.8, 0.78, 0.74, 0.75))


func _process(_delta: float) -> void:
	if mission == null or not mission.active or mission.ending or mission.launching:
		return
	var now: float = mission.elapsed      # the mission clock: stops while paused
	if _next_at < 0.0:
		_next_at = now + rng.randf_range(FIRST_DELAY.x, FIRST_DELAY.y)
	if _aftershock_at >= 0.0 and now >= _aftershock_at:
		_aftershock_at = -1.0
		strike(false)
	if now < _next_at:
		return
	if _busy():
		_next_at = now + RETRY
		return
	var big := rng.randf() < BIG_CHANCE
	strike(big)
	_next_at = now + rng.randf_range(GAP.x, GAP.y)
	if big and rng.randf() < AFTERSHOCK_CHANCE:
		_aftershock_at = now + rng.randf_range(AFTERSHOCK_DELAY.x, AFTERSHOCK_DELAY.y)


## Don't talk over the story: wait for scripted moments, voiced lines and panels.
func _busy() -> bool:
	if mission.scripted or mission.seated:
		return true
	if mission.ui != null and mission.ui.is_open():
		return true
	return mission.voice != null and mission.voice.playing


## One strike on the hull. Also callable directly (tests, scripted moments).
func strike(big: bool) -> void:
	var reduced: bool = Settings.reduced_shake
	if big:
		Sfx.play("hull_impact", rng.randf_range(-3.0, 0.0), rng.randf_range(0.9, 1.08))
		Haptics.play("impact")
		mission.ui.shake(0.55)
		_flicker_lights(reduced)
		_dust_fall(26)
		var spot := _spark_spot()
		if spot != Vector2.INF:
			_sparks(spot, reduced)
	else:
		Sfx.play("hull_impact", rng.randf_range(-15.0, -10.0), rng.randf_range(0.72, 0.85))
		Haptics.play("impact_far")
		mission.ui.shake(0.22)
		_dust_fall(8)


# --- Effects ----------------------------------------------------------------------

## The ship's lights dip (twice) and come back over about a second (escape_ship.gd
## eases its CanvasModulate back to the current lighting on its own).
func _flicker_lights(reduced: bool) -> void:
	var m = mission.ship._modulate if mission.ship != null else null
	if m == null:
		return
	m.color = m.color.darkened(0.2 if reduced else 0.5)
	if reduced:
		return
	get_tree().create_timer(0.14).timeout.connect(func():
		if is_instance_valid(m):
			m.color = m.color.darkened(0.35))


## Dust and grit shaken loose from the ceiling, drifting down around you. Drawn
## under the darkness, so you see it only where it's lit.
func _dust_fall(amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = mission.player.position + Vector2(0, -60)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(230, 120)
	p.amount = amount
	p.lifetime = 1.8
	p.lifetime_randomness = 0.4
	p.one_shot = true
	p.explosiveness = 0.75
	p.direction = Vector2.DOWN
	p.spread = 20.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 35.0
	p.gravity = Vector2(0, 45)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color_ramp = _dust_ramp
	p.z_index = 4
	mission.add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


## A point on a wall face near you that you can see (same line of sight as the
## darkness), on screen. Vector2.INF if there isn't one.
func _spark_spot() -> Vector2:
	var pos: Vector2 = mission.player.position
	var me := Vector2i(floori(pos.x / TILE), floori((pos.y - 8.0) / TILE))
	var dark = mission.darkness
	var view := _view_rect().grow(-24.0)
	var spots: Array[Vector2] = []
	for y in range(me.y - SPARK_RANGE, me.y + SPARK_RANGE + 1):
		for x in range(me.x - SPARK_RANGE, me.x + SPARK_RANGE + 1):
			if not mission.ship.is_wall_face(x, y):
				continue
			if dark != null and not dark.line_of_sight(me, Vector2i(x, y + 1)):
				continue
			var p := Vector2(x * TILE + rng.randf_range(6.0, 26.0), y * TILE + rng.randf_range(4.0, 18.0))
			if view.has_point(p):
				spots.append(p)
	if spots.is_empty():
		return Vector2.INF
	return spots[rng.randi() % spots.size()]


## A panel shorts out: a burst of sparks spraying out and falling to the floor,
## a crackle and flash, sparks sputtering for a moment, then one more pop.
func _sparks(at: Vector2, reduced: bool) -> void:
	Sfx.play("sparks", -4.0, rng.randf_range(0.92, 1.1))
	var burst := _spark_emitter(at, 46, 0.75, true)
	burst.initial_velocity_min = 90.0
	burst.initial_velocity_max = 260.0
	var sputter := _spark_emitter(at, 14, 0.55, false)
	sputter.initial_velocity_min = 40.0
	sputter.initial_velocity_max = 150.0
	get_tree().create_timer(0.9).timeout.connect(func():
		if is_instance_valid(sputter):
			sputter.emitting = false)
	_flash(at, reduced, 1.0)
	mission._dust(at + Vector2(0, 6))    # grit knocked off the panel
	get_tree().create_timer(rng.randf_range(0.35, 0.7)).timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			var again := _spark_emitter(at + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-3.0, 3.0)), 18, 0.6, true)
			again.initial_velocity_max = 180.0
			_flash(at, reduced, 0.5)
			Sfx.play("sparks", -12.0, 1.2))


## Sparks are light: additive and above the darkness, so they show in the dark.
func _spark_emitter(at: Vector2, amount: int, life: float, one_shot: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.lifetime_randomness = 0.5
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.randomness = 0.5
	p.texture = _spark_tex
	p.particle_flag_align_y = true        # each streak points the way it flies
	p.direction = Vector2.DOWN             # out of the wall, toward the floor
	p.spread = 75.0
	p.gravity = Vector2(0, 520)
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 240.0
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.color_ramp = _spark_ramp
	p.material = _additive
	p.z_index = 102                       # above escape_darkness.gd (100) and the beacons (101)
	p.z_as_relative = false
	add_child(p)
	p.emitting = true
	get_tree().create_timer(life * 2.0 + 1.5).timeout.connect(p.queue_free)
	return p


## The short's flash: a hot core and a wider glow on the wall and floor, flickering out.
func _flash(at: Vector2, reduced: bool, strength: float) -> void:
	var a := (0.35 if reduced else 0.9) * strength
	for layer in [[2.2, a], [6.0, a * 0.35]]:
		var s := Sprite2D.new()
		s.texture = _glow_tex
		s.position = at
		s.scale = Vector2.ONE * float(layer[0]) * (0.7 + 0.3 * strength)
		s.material = _additive
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s.z_index = 101
		s.z_as_relative = false
		var alpha: float = layer[1]
		s.modulate = Color(1.0, 0.78, 0.5, alpha)
		add_child(s)
		var tw := s.create_tween()
		tw.tween_property(s, "modulate:a", alpha * 0.25, 0.05)
		tw.tween_property(s, "modulate:a", alpha * 0.8, 0.05)
		tw.tween_property(s, "modulate:a", 0.0, 0.35)
		tw.tween_callback(s.queue_free)


## The part of the map on screen (px).
func _view_rect() -> Rect2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
