extends Control
## Account access and the single resumable mission slot on the start menu.
signal start_requested(resume: bool)
const Style = preload("res://scripts/ui/ui_style.gd")
var panel: PanelContainer
var content: VBoxContainer
var status_label: Label
var username: LineEdit
var password: LineEdit
var screen := ""
var working := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.02, 0.06, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.box(Style.NAVY_DEEP, Style.CYAN))
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)
	resized.connect(_layout)
	SaveGame.changed.connect(_save_changed)
	_layout()
	hide()

func _layout() -> void:
	if panel == null: return
	panel.size = Vector2(minf(390, size.x - 24), minf(326, size.y - 24))
	panel.position = (size - panel.size) / 2.0

func open() -> void:
	show()
	if Settings.is_logged_in():
		_show_games()
		SaveGame.refresh_cloud()
	else: _show_auth()

func _clear(title: String) -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	status_label = null
	_text(title, 17, Style.CYAN_BRIGHT)

func _text(text: String, font_size := 11, color := Style.TEXT) -> Label:
	var label := Style.label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 270
	content.add_child(label)
	return label

func _button(text: String, action: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 27
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", Style.box(Style.NAVY, Style.CYAN))
	button.add_theme_stylebox_override("focus", Style.box(Style.NAVY, Style.TEXT))
	button.add_theme_stylebox_override("hover", Style.box(Style.NAVY, Style.CYAN_BRIGHT))
	button.disabled = disabled
	button.pressed.connect(action)
	content.add_child(button)
	return button

func _show_auth() -> void:
	screen = "auth"
	_clear("YOUR JOURNEY HOME")
	_text("Sign in or create an account for cloud saves and crew memory. Guest progress is saved on this device.", 10, Style.MUTED)
	username = LineEdit.new()
	username.placeholder_text = "Username (3–16 letters, numbers or _)"
	username.max_length = 16
	username.text = Settings.account_name
	username.add_theme_font_size_override("font_size", 11)
	content.add_child(username)
	password = LineEdit.new()
	password.placeholder_text = "Password (8+ characters)"
	password.secret = true
	password.max_length = 128
	password.add_theme_font_size_override("font_size", 11)
	password.text_submitted.connect(func(_value): _authenticate("login"))
	content.add_child(password)
	status_label = _text("", 10, Style.MUTED)
	_button("SIGN IN", _authenticate.bind("login"))
	_button("CREATE ACCOUNT", _authenticate.bind("register"))
	_button("CONTINUE AS GUEST", _guest)
	_button("Back", hide)
	username.grab_focus.call_deferred()

func _authenticate(mode: String) -> void:
	if working: return
	var name := username.text.strip_edges()
	var secret := password.text
	if name.length() < 3 or secret.length() < 8:
		status_label.text = "Use a username of 3–16 characters and a password of at least 8 characters."
		return
	working = true
	for child in content.get_children():
		if child is Button or child is LineEdit: child.set("editable" if child is LineEdit else "disabled", false if child is LineEdit else true)
	status_label.text = "Creating account…" if mode == "register" else "Signing in…"
	var result := await SaveGame.authenticate(mode, name, secret)
	secret = ""
	working = false
	if not is_instance_valid(password): return
	password.clear()
	if result.code == 200: _show_games()
	else:
		for child in content.get_children():
			if child is Button: child.disabled = false
			elif child is LineEdit: child.editable = true
		status_label.text = str(result.get("message", "Account service unavailable. Try again, or play as a guest."))

func _guest() -> void:
	if working: return
	if Settings.is_logged_in(): await SaveGame.sign_out()
	_show_games()

func _show_games() -> void:
	screen = "games"
	_clear("WELCOME, " + Settings.account_name.to_upper() if Settings.is_logged_in() else "GUEST MISSION")
	_text("Progress saves automatically. " + ("Your account also syncs across devices." if Settings.is_logged_in() else "Sign in for cloud saves across devices."), 10, Style.MUTED)
	status_label = _text(SaveGame.status, 10, Style.MUTED)
	if SaveGame.has_progress():
		var data := SaveGame.checkpoint()
		var seconds := int(data.get("elapsed", 0))
		_text("SAVED MISSION  ·  %02d:%02d\n%s" % [seconds / 60, seconds % 60, str(data.state.route).to_upper() + " ROUTE" if data.state.route != "" else "ESCAPE THE SHIP"], 11, Style.CYAN)
		_button("RESUME GAME", _start.bind(true), SaveGame.busy)
		_button("NEW GAME", _confirm_new, SaveGame.busy)
		_button("DELETE SAVED GAME", _confirm_delete, SaveGame.busy)
	else:
		_text("No saved mission yet.", 11, Style.CYAN)
		_button("START NEW GAME", _start.bind(false), SaveGame.busy)
		if Settings.is_logged_in() and not SaveGame.guest_checkpoint().is_empty():
			_button("USE THIS DEVICE'S GUEST SAVE", SaveGame.import_guest, SaveGame.busy)
	if SaveGame.conflict:
		_button("KEEP CLOUD SAVE", SaveGame.resolve_conflict.bind(true), SaveGame.busy)
		_button("KEEP THIS DEVICE'S SAVE", SaveGame.resolve_conflict.bind(false), SaveGame.busy)
	if Settings.is_logged_in():
		_button("REFRESH CLOUD SAVE", SaveGame.refresh_cloud, SaveGame.busy)
		_button("SIGN OUT / SWITCH ACCOUNT", _sign_out, SaveGame.busy)
	else: _button("SIGN IN / CREATE ACCOUNT", _show_auth)
	_button("Back", hide)
	_layout()

func _confirm_new() -> void:
	screen = "confirm"
	_clear("START A NEW GAME?")
	_text("This replaces your saved mission and resets the crew's memory. Your account is kept.")
	_button("Keep current save", _show_games)
	_button("Replace save and start", _replace_and_start)

func _replace_and_start() -> void:
	if SaveGame.delete_progress(): _start(false)
	else: _show_games()

func _confirm_delete() -> void:
	screen = "confirm"
	_clear("DELETE SAVED GAME?")
	_text("This deletes your saved mission and its crew memories from this device and your account. Your account is kept.")
	_button("Cancel", _show_games)
	_button("Delete saved mission", _delete)

func _delete() -> void:
	SaveGame.delete_progress()
	_show_games()

func _sign_out() -> void:
	await SaveGame.sign_out()
	_show_auth()

func _start(resume: bool) -> void:
	if SaveGame.busy: return
	if resume and not SaveGame.has_progress(): return
	hide()
	start_requested.emit(resume)

func _save_changed() -> void:
	if not visible: return
	if screen == "games": _show_games()
	elif is_instance_valid(status_label) and not working: status_label.text = SaveGame.status

func _input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		if not working: hide()
