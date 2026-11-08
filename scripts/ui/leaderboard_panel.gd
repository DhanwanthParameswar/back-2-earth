extends CanvasLayer
## Win-screen leaderboard. Owner: D. Shows after a win, beside the Earth:
##   left  = TOP 10 (ranks 1-10 always listed; empty slots show ---)
##   right = your time and the name it was saved under. Guests are saved as
##           GuestXXXX automatically and can create an account / log in to put
##           their own name on it; logged-in players see a log-out button.
## Typing in the boxes never triggers the HUD's R/E/Q keys (the text box takes them).

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const RunRecorder = preload("res://scripts/core/run_recorder.gd")

const SHOW_DELAY := 4.2  # after the pod flies off and the win text appears
const ROWS := 10

var _left: PanelContainer
var _right: PanelContainer
var _rank_labels: Array[Label] = []
var _name_labels: Array[Label] = []
var _time_labels: Array[Label] = []
var _board_footer: Label
var _time_label: Label
var _saved_label: Label
var _status_label: Label
var _guest_box: VBoxContainer
var _user_box: VBoxContainer
var _name_edit: LineEdit
var _pass_edit: LineEdit
var _create_button: Button
var _login_button: Button
var _recorder = null
var _busy := false


func _ready() -> void:
	layer = 12
	add_to_group("leaderboard_panel")
	_build()
	show_entries([])
	set_visible_panels(false)
	GameState.run_ended.connect(_on_run_ended)
	Settings.changed.connect(_refresh_account)


func _connect_recorder() -> void:
	if _recorder != null:
		return
	_recorder = get_tree().get_first_node_in_group("run_recorder")
	if _recorder != null:
		_recorder.run_saved.connect(func(_r): _refresh_account())
		_recorder.leaderboard_loaded.connect(show_entries)
		_recorder.leaderboard_offline.connect(func(): _board_footer.text = "Leaderboard offline")
		_recorder.auth_done.connect(_on_auth_done)


func set_visible_panels(value: bool) -> void:
	_left.visible = value
	_right.visible = value


func is_open() -> bool:
	return _left.visible


func _on_run_ended(won: bool) -> void:
	_connect_recorder()
	if not won:
		return
	var tw := create_tween()
	tw.tween_interval(SHOW_DELAY)
	tw.tween_callback(open)


func open() -> void:
	_connect_recorder()
	set_visible_panels(true)
	_refresh_account()


# --- Content ---------------------------------------------------------------------------

## Fills ranks 1-10; missing places stay as "---".
func show_entries(entries: Array, _me = null) -> void:
	_board_footer.text = ""
	var mine := Settings.player_name()
	for i in ROWS:
		var e = entries[i] if i < entries.size() and typeof(entries[i]) == TYPE_DICTIONARY else null
		_rank_labels[i].text = "%d." % (i + 1)
		if e == null:
			_name_labels[i].text = "---"
			_time_labels[i].text = ""
			_set_row_color(i, UiStyle.MUTED)
			continue
		var player := str(e.get("player", "?")).left(16)
		_rank_labels[i].text = "%d." % int(e.get("rank", i + 1))
		_name_labels[i].text = player
		_time_labels[i].text = RunRecorder.format_time(float(e.get("seconds", 0.0)))
		_set_row_color(i, UiStyle.CYAN if player == mine else UiStyle.TEXT)


func _set_row_color(i: int, color: Color) -> void:
	for l in [_rank_labels[i], _name_labels[i], _time_labels[i]]:
		l.add_theme_color_override("font_color", color)


func _refresh_account() -> void:
	if _recorder == null:
		return
	var result: Dictionary = _recorder.last_result
	var logged_in := Settings.is_logged_in()
	_guest_box.visible = not logged_in
	_user_box.visible = logged_in

	if result.has("duration_s"):
		_time_label.text = "YOUR TIME  " + RunRecorder.format_time(float(result["duration_s"]))
	elif _recorder.local_seconds > 0.0:
		_time_label.text = "YOUR TIME  " + RunRecorder.format_time(_recorder.local_seconds)
	else:
		_time_label.text = "YOUR TIME"

	var best = result.get("best")
	if typeof(best) == TYPE_DICTIONARY:
		_saved_label.text = "Saved as %s   #%d  (best %s)" % [
			str(best.get("player", Settings.player_name())), int(best.get("rank", 0)),
			RunRecorder.format_time(float(best.get("seconds", 0.0)))]
	elif result.has("duration_s"):
		_saved_label.text = "Saved as %s (not in the top 100)" % Settings.player_name()
	elif _recorder.last_error != "":
		_saved_label.text = save_error_text(_recorder.last_error)
	else:
		_saved_label.text = "Saving..."


## What to tell the player when their run wasn't saved.
static func save_error_text(error: String) -> String:
	match error:
		"implausible":
			return "Not saved: too fast for the server to verify."
		"offline", "db_unavailable":
			return "Not saved: the leaderboard is offline right now."
		"rate_limited":
			return "Not saved: too many requests, try again in a moment."
		_:
			return "Not saved (%s)." % error


func _on_auth_done(ok: bool, message: String) -> void:
	_set_busy(false)
	if ok:
		_pass_edit.text = ""
	_status_label.text = message
	_status_label.visible = message != ""
	_status_label.add_theme_color_override("font_color", UiStyle.MUTED if ok else UiStyle.AMBER)
	_refresh_account()


func _submit(create: bool) -> void:
	if _busy or _recorder == null:
		return
	var username := _name_edit.text.strip_edges()
	var password := _pass_edit.text
	if username.length() < 3 or password.length() < 8:
		_status_label.text = "Username 3+ characters, password 8+"
		_status_label.visible = true
		_status_label.add_theme_color_override("font_color", UiStyle.AMBER)
		return
	_set_busy(true)
	_status_label.text = "Creating account..." if create else "Logging in..."
	_status_label.visible = true
	_status_label.add_theme_color_override("font_color", UiStyle.MUTED)
	if create:
		_recorder.register(username, password)
	else:
		_recorder.login(username, password)


func _set_busy(value: bool) -> void:
	_busy = value
	_create_button.disabled = value
	_login_button.disabled = value


# --- Construction ----------------------------------------------------------------------

func _panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = size
	p.custom_minimum_size = size
	var style := UiStyle.panel()
	style.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", style)
	add_child(p)
	return p


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.max_length = 128 if secret else 16
	e.add_theme_font_size_override("font_size", 10)
	e.add_theme_color_override("font_color", UiStyle.TEXT)
	e.add_theme_color_override("font_placeholder_color", UiStyle.MUTED)
	e.add_theme_stylebox_override("normal", UiStyle.box(UiStyle.NAVY_DEEP, Color(UiStyle.CYAN, 0.5), 1))
	e.add_theme_stylebox_override("focus", UiStyle.box(UiStyle.NAVY_DEEP, UiStyle.CYAN, 1))
	return e


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	UiStyle.style_button(b, 9)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _small(text: String, color := UiStyle.TEXT, size := 9) -> Label:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(210, 0)
	return l


func _build() -> void:
	# Left: ranks 1-10 in a 3-column grid (rank, name, time).
	_left = _panel(Vector2(12, 34), Vector2(228, 168))
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 2)
	_left.add_child(lcol)
	lcol.add_child(UiStyle.label("TOP 10 ESCAPES", 11, UiStyle.CYAN))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 0)
	lcol.add_child(grid)
	for i in ROWS:
		var r := UiStyle.label("", 9, UiStyle.MUTED)
		r.custom_minimum_size = Vector2(20, 0)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var n := UiStyle.label("", 9, UiStyle.MUTED)
		n.custom_minimum_size = Vector2(120, 0)
		var t := UiStyle.label("", 9, UiStyle.MUTED)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		t.custom_minimum_size = Vector2(46, 0)
		for l in [r, n, t]:
			grid.add_child(l)
		_rank_labels.append(r)
		_name_labels.append(n)
		_time_labels.append(t)
	_board_footer = UiStyle.label("", 8, UiStyle.AMBER)
	lcol.add_child(_board_footer)

	# Right: your time, where it was saved, and the account form.
	_right = _panel(Vector2(400, 34), Vector2(228, 168))
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 3)
	_right.add_child(rcol)
	_time_label = UiStyle.label("YOUR TIME", 12, UiStyle.CYAN)
	rcol.add_child(_time_label)
	_saved_label = _small("Saving...")
	rcol.add_child(_saved_label)

	_guest_box = VBoxContainer.new()
	_guest_box.add_theme_constant_override("separation", 3)
	rcol.add_child(_guest_box)
	_guest_box.add_child(_small("Put your own name on it:", UiStyle.MUTED))
	_name_edit = _edit("Username (3-16: letters, 0-9, _)", false)
	_guest_box.add_child(_name_edit)
	_pass_edit = _edit("Password (8+ characters)", true)
	_pass_edit.text_submitted.connect(func(_t): _submit(false))
	_guest_box.add_child(_pass_edit)
	var buttons := HBoxContainer.new()
	_guest_box.add_child(buttons)
	_create_button = _button("CREATE ACCOUNT")
	_create_button.pressed.connect(func(): _submit(true))
	buttons.add_child(_create_button)
	_login_button = _button("LOG IN")
	_login_button.pressed.connect(func(): _submit(false))
	buttons.add_child(_login_button)

	_user_box = VBoxContainer.new()
	rcol.add_child(_user_box)
	var out := _button("LOG OUT")
	out.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	out.pressed.connect(func():
		if _recorder != null:
			_recorder.logout())
	_user_box.add_child(out)

	_status_label = _small("", UiStyle.MUTED)
	_status_label.visible = false  # only takes space when there is something to say
	rcol.add_child(_status_label)
