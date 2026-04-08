extends Control
## In-game options menu. Key remapping + dev tools (host only) + exit.

signal dev_command(cmd: String)

var _hover_idx: int = -1
var _rebinding_idx: int = -1
var _actions: Array = []
var _hover_btn: String = ""
var _dev_mode_on: bool = false


func _ready() -> void:
	visible = false
	_refresh()


func _refresh() -> void:
	_actions = InputConfig.get_action_list()


func open() -> void:
	_refresh()
	_rebinding_idx = -1
	visible = true


func close() -> void:
	visible = false
	_rebinding_idx = -1


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _rebinding_idx >= 0 and event is InputEventKey and event.pressed:
		var action: String = _actions[_rebinding_idx]["action"]
		InputConfig.set_binding(action, event.keycode)
		InputConfig.save_config()
		_rebinding_idx = -1
		_refresh()
		get_viewport().set_input_as_handled()
		return

	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5

	if event is InputEventMouseMotion:
		_hover_idx = _get_row_at(event.position)
		_hover_btn = _get_btn_at(event.position)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Key binding rows
		var base_y: float = 140.0
		var actions_end_y: float = base_y + _actions.size() * 38.0

		if _hover_idx >= 0 and _hover_idx < _actions.size():
			_rebinding_idx = _hover_idx
			get_viewport().set_input_as_handled()
			return

		match _hover_btn:
			"dev_mode":
				_dev_mode_on = not _dev_mode_on
				dev_command.emit("toggle_dev_mode")
				get_viewport().set_input_as_handled()
			"reset_keys":
				InputConfig.reset_defaults()
				_refresh()
				get_viewport().set_input_as_handled()
			"close":
				close()
				get_viewport().set_input_as_handled()
			"main_menu":
				get_viewport().set_input_as_handled()
				_quit_to_main_menu()
			"exit":
				get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
				get_tree().quit()
			"dev_pause":
				GameClock.is_paused = not GameClock.is_paused
				dev_command.emit("pause")
				get_viewport().set_input_as_handled()
			"dev_next_phase":
				GameClock.advance_phase()
				dev_command.emit("next_phase")
				get_viewport().set_input_as_handled()
			"dev_reset":
				dev_command.emit("reset")
				get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _get_row_at(pos: Vector2) -> int:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	var base_y: float = 140.0
	for i in _actions.size():
		var ry: float = base_y + i * 38.0
		if Rect2(cx + 40, ry, 160, 34).has_point(pos):
			return i
	return -1


func _quit_to_main_menu() -> void:
	## Clean up session state and return to title screen.
	TutorialManager.active = false
	TutorialManager.current_phase = 0
	TutorialManager._pending_advance = false
	SaveManager.delete_save()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


func _get_btn_at(pos: Vector2) -> String:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	var btn_y: float = 140.0 + _actions.size() * 38.0 + 20.0
	var btn_w: float = 180.0
	var btn_h: float = 34.0
	var gap: float = 40.0

	# Left column buttons
	var left_x: float = cx - 200.0
	if Rect2(left_x, btn_y, btn_w, btn_h).has_point(pos): return "reset_keys"
	if Rect2(left_x, btn_y + gap, btn_w, btn_h).has_point(pos): return "close"
	if Rect2(left_x, btn_y + gap * 2, btn_w, btn_h).has_point(pos): return "main_menu"
	if Rect2(left_x, btn_y + gap * 3, btn_w, btn_h).has_point(pos): return "exit"
	if Rect2(left_x, btn_y + gap * 4, btn_w, btn_h).has_point(pos): return "dev_mode"

	# Right column: dev tools (host only)
	if NetworkManager.is_authority():
		var right_x: float = cx + 20.0
		if Rect2(right_x, btn_y, btn_w, btn_h).has_point(pos): return "dev_pause"
		if Rect2(right_x, btn_y + gap, btn_w, btn_h).has_point(pos): return "dev_next_phase"
		if Rect2(right_x, btn_y + gap * 2, btn_w, btn_h).has_point(pos): return "dev_reset"
	return ""


func _draw() -> void:
	if not visible:
		return
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5

	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.75))

	draw_string(ThemeDB.fallback_font, Vector2(cx - 60, 60),
		"OPTIONS", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	if GameClock.is_paused:
		draw_string(ThemeDB.fallback_font, Vector2(cx - 40, 90),
			"** PAUSED **", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(1.0, 0.8, 0.2))

	draw_string(ThemeDB.fallback_font, Vector2(cx - 180, 125),
		"Click a key to remap", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.55))

	# Key bindings
	var base_y: float = 140.0
	for i in _actions.size():
		var a: Dictionary = _actions[i]
		var ry: float = base_y + i * 38.0
		var hovered: bool = (_hover_idx == i)
		var rebinding: bool = (_rebinding_idx == i)

		draw_string(ThemeDB.fallback_font, Vector2(cx - 180, ry + 22),
			a["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.7, 0.7))

		var bg: Color
		if rebinding: bg = Color(0.4, 0.25, 0.1, 0.9)
		elif hovered: bg = Color(0.2, 0.25, 0.3, 0.9)
		else: bg = Color(0.12, 0.14, 0.18, 0.8)
		draw_rect(Rect2(cx + 40, ry, 160, 34), bg)
		draw_rect(Rect2(cx + 40, ry, 160, 34), Color(0.4, 0.4, 0.4, 0.4), false, 1.0)

		var key_text: String = "Press key..." if rebinding else a["key"]
		var key_col: Color = Color(1, 0.8, 0.3) if rebinding else Color(0.9, 0.9, 0.85)
		draw_string(ThemeDB.fallback_font, Vector2(cx + 55, ry + 22),
			key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, key_col)

	# Buttons area
	var btn_y: float = base_y + _actions.size() * 38.0 + 20.0
	var btn_w: float = 180.0
	var btn_h: float = 34.0
	var gap: float = 40.0

	# Left column: general buttons
	var left_x: float = cx - 200.0
	_draw_button(left_x, btn_y, btn_w, btn_h, "Reset Keys", "reset_keys", Color(0.5, 0.3, 0.3))
	_draw_button(left_x, btn_y + gap, btn_w, btn_h, "Close", "close", Color(0.3, 0.5, 0.3))
	_draw_button(left_x, btn_y + gap * 2, btn_w, btn_h, "Quit to Main Menu", "main_menu", Color(0.35, 0.25, 0.15))
	_draw_button(left_x, btn_y + gap * 3, btn_w, btn_h, "Exit to Desktop", "exit", Color(0.6, 0.15, 0.15))
	var dev_label: String = "Dev Mode: ON" if _dev_mode_on else "Dev Mode: OFF"
	var dev_col: Color = Color(0.45, 0.2, 0.55) if _dev_mode_on else Color(0.25, 0.2, 0.35)
	_draw_button(left_x, btn_y + gap * 4, btn_w, btn_h, dev_label, "dev_mode", dev_col)

	# Right column: dev tools (host only)
	if NetworkManager.is_authority():
		var right_x: float = cx + 20.0
		draw_string(ThemeDB.fallback_font, Vector2(right_x, btn_y - 6),
			"HOST DEV TOOLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.6))
		var pause_label: String = "Unpause" if GameClock.is_paused else "Pause Game"
		_draw_button(right_x, btn_y, btn_w, btn_h, pause_label, "dev_pause", Color(0.5, 0.5, 0.2))
		_draw_button(right_x, btn_y + gap, btn_w, btn_h, "Next Phase", "dev_next_phase", Color(0.3, 0.4, 0.5))
		_draw_button(right_x, btn_y + gap * 2, btn_w, btn_h, "Reset Game", "dev_reset", Color(0.5, 0.2, 0.2))


func _draw_button(x: float, y: float, w: float, h: float, label: String, btn_id: String, col: Color) -> void:
	var hovered: bool = (_hover_btn == btn_id)
	var bg: Color = col.lightened(0.2) if hovered else col.darkened(0.2)
	bg.a = 0.85 if hovered else 0.65
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x, y, w, h), Color(0.5, 0.5, 0.5, 0.3), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + 10, y + 23), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
		Color(1, 1, 1, 0.95) if hovered else Color(0.8, 0.8, 0.8, 0.8))
