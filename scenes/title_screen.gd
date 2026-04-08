extends Control
## Title screen. New Game or Continue.

var _hover: String = ""


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _get_button_at(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var btn: String = _get_button_at(event.position)
		if btn == "new":
			get_tree().change_scene_to_file("res://scenes/lobby.tscn")
		elif btn == "tutorial":
			_start_tutorial()
		elif btn == "continue":
			get_tree().change_scene_to_file("res://scenes/main.tscn")


func _start_tutorial() -> void:
	## Configure a minimal solo game and activate the tutorial before loading main.
	FactionManager.clear()
	FactionManager.register_faction(0, "$", Color(0.2, 0.6, 0.9))
	FactionManager.local_faction_id = 0
	FactionManager.max_population = 40
	FactionManager.set_meta("map_seed", 42)        ## Fixed seed so tutorial map is consistent
	FactionManager.set_meta("faction_count", 1)
	FactionManager.set_meta("map_size", "small")
	FactionManager.set_meta("player_count", 1)
	SaveManager.delete_save()
	TutorialManager.start_tutorial()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _get_button_at(pos: Vector2) -> String:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.5
	var bw: float = 280.0
	var bh: float = 50.0

	if Rect2(cx - bw * 0.5, cy - 10, bw, bh).has_point(pos):
		return "new"
	if Rect2(cx - bw * 0.5, cy + 60, bw, bh).has_point(pos):
		return "tutorial"
	if SaveManager.has_save() and Rect2(cx - bw * 0.5, cy + 130, bw, bh).has_point(pos):
		return "continue"
	return ""


func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	var cy: float = vp.y * 0.5

	# Background
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.06, 0.06, 0.1))

	# Title
	draw_string(ThemeDB.fallback_font, Vector2(cx - 120, cy - 100),
		"Little Village", HORIZONTAL_ALIGNMENT_CENTER, -1, 36, Color(0.9, 0.85, 0.6))

	# Moon decoration
	var moon_y: float = cy - 180
	draw_circle(Vector2(cx, moon_y), 30, Color(0.85, 0.82, 0.6, 0.3))
	draw_arc(Vector2(cx, moon_y), 30, 0.0, TAU, 32, Color(0.9, 0.85, 0.5, 0.5), 2.0)

	# New Game button
	var bw: float = 280.0
	var bh: float = 50.0
	var new_rect := Rect2(cx - bw * 0.5, cy - 10, bw, bh)
	var new_hovered: bool = (_hover == "new")
	draw_rect(new_rect, Color(0.18, 0.22, 0.15, 0.9) if new_hovered else Color(0.12, 0.14, 0.1, 0.8))
	draw_rect(new_rect, Color(0.4, 0.5, 0.3, 0.6), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 40, cy + 22),
		"New Game", HORIZONTAL_ALIGNMENT_CENTER, -1, 18,
		Color(0.9, 0.9, 0.8) if new_hovered else Color(0.7, 0.7, 0.6))

	# Tutorial button
	var tut_rect := Rect2(cx - bw * 0.5, cy + 60, bw, bh)
	var tut_hovered: bool = (_hover == "tutorial")
	draw_rect(tut_rect, Color(0.18, 0.18, 0.12, 0.9) if tut_hovered else Color(0.12, 0.12, 0.08, 0.8))
	draw_rect(tut_rect, Color(0.55, 0.5, 0.25, 0.6), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 36, cy + 92),
		"Tutorial", HORIZONTAL_ALIGNMENT_CENTER, -1, 18,
		Color(0.95, 0.9, 0.65) if tut_hovered else Color(0.72, 0.68, 0.45))

	# Continue button (only if save exists)
	if SaveManager.has_save():
		var cont_rect := Rect2(cx - bw * 0.5, cy + 130, bw, bh)
		var cont_hovered: bool = (_hover == "continue")
		draw_rect(cont_rect, Color(0.15, 0.18, 0.22, 0.9) if cont_hovered else Color(0.1, 0.12, 0.15, 0.8))
		draw_rect(cont_rect, Color(0.3, 0.4, 0.5, 0.6), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(cx - 36, cy + 162),
			"Continue", HORIZONTAL_ALIGNMENT_CENTER, -1, 18,
			Color(0.85, 0.9, 0.95) if cont_hovered else Color(0.6, 0.65, 0.7))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(cx - 50, cy + 162),
			"No save found", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0.4, 0.4, 0.4))

	# Version
	draw_string(ThemeDB.fallback_font, Vector2(cx - 30, vp.y - 20),
		"v0.1", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.3, 0.3, 0.3))
