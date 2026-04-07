extends Control
## In-game options menu for key remapping. Drawn as overlay.
## Toggle with Escape from main scene (when no selection active).

var _hover_idx: int = -1
var _rebinding_idx: int = -1  ## if >= 0, waiting for key press
var _actions: Array = []


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

	# Rebinding mode: capture next key press
	if _rebinding_idx >= 0 and event is InputEventKey and event.pressed:
		var action: String = _actions[_rebinding_idx]["action"]
		InputConfig.set_binding(action, event.keycode)
		InputConfig.save_config()
		_rebinding_idx = -1
		_refresh()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_hover_idx = _get_row_at(event.position)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var vp: Vector2 = get_viewport_rect().size
		var cx: float = vp.x * 0.5

		# Reset button
		if Rect2(cx - 80, vp.y * 0.5 + _actions.size() * 44.0 + 20, 160, 40).has_point(event.position):
			InputConfig.reset_defaults()
			_refresh()
			get_viewport().set_input_as_handled()
			return

		# Close button
		if Rect2(cx - 80, vp.y * 0.5 + _actions.size() * 44.0 + 70, 160, 40).has_point(event.position):
			close()
			get_viewport().set_input_as_handled()
			return

		# Key binding click
		if _hover_idx >= 0 and _hover_idx < _actions.size():
			_rebinding_idx = _hover_idx
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _get_row_at(pos: Vector2) -> int:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	var start_y: float = vp.y * 0.5 - _actions.size() * 22.0
	for i in _actions.size():
		var ry: float = start_y + i * 44.0
		if Rect2(cx + 60, ry, 160, 38).has_point(pos):
			return i
	return -1


func _draw() -> void:
	if not visible:
		return
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5

	# Dimmed background
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.7))

	draw_string(ThemeDB.fallback_font, Vector2(cx - 80, 80),
		"OPTIONS", HORIZONTAL_ALIGNMENT_CENTER, -1, 32, Color(0.9, 0.85, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 120, 120),
		"Click a key binding to remap it", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.55, 0.55, 0.6))

	var start_y: float = vp.y * 0.5 - _actions.size() * 22.0
	for i in _actions.size():
		var a: Dictionary = _actions[i]
		var ry: float = start_y + i * 44.0
		var hovered: bool = (_hover_idx == i)
		var rebinding: bool = (_rebinding_idx == i)

		# Label
		draw_string(ThemeDB.fallback_font, Vector2(cx - 200, ry + 26),
			a["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.8, 0.8))

		# Key button
		var bg: Color
		if rebinding:
			bg = Color(0.4, 0.25, 0.1, 0.9)
		elif hovered:
			bg = Color(0.2, 0.25, 0.3, 0.9)
		else:
			bg = Color(0.12, 0.14, 0.18, 0.8)
		draw_rect(Rect2(cx + 60, ry, 160, 38), bg)
		draw_rect(Rect2(cx + 60, ry, 160, 38), Color(0.4, 0.4, 0.4, 0.4), false, 1.0)

		var key_text: String = "Press a key..." if rebinding else a["key"]
		var key_col: Color = Color(1, 0.8, 0.3) if rebinding else Color(0.9, 0.9, 0.85)
		draw_string(ThemeDB.fallback_font, Vector2(cx + 80, ry + 26),
			key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, key_col)

	# Reset button
	var reset_y: float = start_y + _actions.size() * 44.0 + 20
	var reset_hover: bool = Rect2(cx - 80, reset_y, 160, 40).has_point(get_viewport().get_mouse_position())
	draw_rect(Rect2(cx - 80, reset_y, 160, 40), Color(0.3, 0.15, 0.15, 0.8) if reset_hover else Color(0.18, 0.1, 0.1, 0.7))
	draw_rect(Rect2(cx - 80, reset_y, 160, 40), Color(0.5, 0.3, 0.3, 0.4), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 55, reset_y + 28),
		"Reset Defaults", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.9, 0.6, 0.6) if reset_hover else Color(0.6, 0.4, 0.4))

	# Close button
	var close_y: float = reset_y + 50
	var close_hover: bool = Rect2(cx - 80, close_y, 160, 40).has_point(get_viewport().get_mouse_position())
	draw_rect(Rect2(cx - 80, close_y, 160, 40), Color(0.15, 0.2, 0.15, 0.8) if close_hover else Color(0.1, 0.12, 0.1, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 25, close_y + 28),
		"Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(0.7, 0.9, 0.7) if close_hover else Color(0.5, 0.6, 0.5))
