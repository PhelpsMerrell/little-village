extends Control
## Full-screen HUD. Day/night bar, population, resources (stone + fish), buy menu.

const BAR_HEIGHT := 28.0

var pop_red: int = 0
var pop_yellow: int = 0
var pop_blue: int = 0
var pop_colorless: int = 0
var pop_enemies: int = 0
var pop_total: int = 0

var _shop_open: bool = false
var _shop_items: Array = []
var _hover_idx: int = -1

signal buy_requested(item_id: String)


func _ready() -> void:
	_refresh_shop()
	Economy.currency_changed.connect(func(): _refresh_shop())

func _refresh_shop() -> void:
	_shop_items.clear()
	for id in Economy.get_shop_items():
		var item: Dictionary = Economy.get_shop_items()[id]
		_shop_items.append({"id": id, "name": item["name"], "cost": item["cost"], "desc": item["description"]})

func _process(_delta: float) -> void:
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B:
			_shop_open = not _shop_open
			get_viewport().set_input_as_handled()
			return
	if not _shop_open:
		return
	var vp_size: Vector2 = get_viewport_rect().size
	var shop_x: float = vp_size.x - 260.0
	var shop_y: float = 60.0
	if event is InputEventMouseMotion:
		_hover_idx = -1
		for i in _shop_items.size():
			var iy: float = shop_y + 30 + i * 50.0
			if Rect2(shop_x, iy, 240, 45).has_point(event.position):
				_hover_idx = i
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _hover_idx >= 0 and _hover_idx < _shop_items.size():
			var item_id: String = _shop_items[_hover_idx]["id"]
			if Economy.can_afford(item_id):
				buy_requested.emit(item_id)
			get_viewport().set_input_as_handled()


func _draw() -> void:
	var vp_size: Vector2 = get_viewport_rect().size

	# Day/Night bar
	draw_rect(Rect2(0, 0, vp_size.x, BAR_HEIGHT), Color(0.08, 0.08, 0.1, 0.85))
	var day_frac: float = GameClock.DAY_DURATION / GameClock.CYCLE_DURATION
	var day_w: float = vp_size.x * day_frac
	draw_rect(Rect2(0, 0, day_w, BAR_HEIGHT), Color(0.35, 0.32, 0.15, 0.4))
	draw_rect(Rect2(day_w, 0, vp_size.x - day_w, BAR_HEIGHT), Color(0.08, 0.08, 0.2, 0.4))
	draw_rect(Rect2(GameClock.get_cycle_progress() * vp_size.x - 2, 0, 4, BAR_HEIGHT), Color(1, 1, 1, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(8, 18), "DAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.85, 0.4, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(day_w + 8, 18), "NIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.8, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(vp_size.x * 0.5 - 80, 18), GameClock.get_time_string(), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0.85, 0.85, 0.85))

	# Population panel
	var panel_y: float = vp_size.y - 130
	draw_rect(Rect2(0, panel_y, 340, 130), Color(0.06, 0.06, 0.08, 0.8))
	draw_rect(Rect2(0, panel_y, 340, 130), Color(0.3, 0.3, 0.3, 0.3), false, 1.0)

	var ty: float = panel_y + 18.0
	_draw_pop_line(12, ty, "Red", pop_red, Color(0.9, 0.22, 0.2)); ty += 16.0
	_draw_pop_line(12, ty, "Yellow", pop_yellow, Color(0.94, 0.84, 0.12)); ty += 16.0
	_draw_pop_line(12, ty, "Blue", pop_blue, Color(0.2, 0.4, 0.9)); ty += 16.0
	_draw_pop_line(12, ty, "Colorless", pop_colorless, Color(0.7, 0.7, 0.7))

	# Right column: enemies + resources
	draw_string(ThemeDB.fallback_font, Vector2(200, panel_y + 34), "Enemies: %d" % pop_enemies,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.2, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(200, panel_y + 54), "Total: %d" % pop_total,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.65, 0.65))

	# Resources
	draw_circle(Vector2(210, panel_y + 76), 6.0, Color(0.5, 0.52, 0.48))
	draw_string(ThemeDB.fallback_font, Vector2(220, panel_y + 80),
		"Stone: %d" % Economy.stone, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.65, 0.55))
	draw_circle(Vector2(210, panel_y + 96), 6.0, Color(0.3, 0.55, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(220, panel_y + 100),
		"Fish: %d" % Economy.fish, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.65, 0.8))

	# Controls hint
	var hint := "WASD: Pan | Q/E: Zoom | F11: Fullscreen | B: Shop"
	draw_string(ThemeDB.fallback_font, Vector2(vp_size.x - 450, vp_size.y - 12), hint,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color(0.45, 0.45, 0.45, 0.6))

	if _shop_open:
		_draw_shop(vp_size)


func _draw_shop(vp_size: Vector2) -> void:
	var sx: float = vp_size.x - 260.0
	var sy: float = 60.0
	var sw: float = 240.0
	var sh: float = 40.0 + _shop_items.size() * 50.0
	draw_rect(Rect2(sx, sy, sw, sh), Color(0.06, 0.06, 0.08, 0.9))
	draw_rect(Rect2(sx, sy, sw, sh), Color(0.4, 0.4, 0.4, 0.4), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(sx + 10, sy + 20), "SHOP (B to close)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.85, 0.85))
	for i in _shop_items.size():
		var item: Dictionary = _shop_items[i]
		var iy: float = sy + 30 + i * 50.0
		var can: bool = Economy.stone >= int(item["cost"])
		var hovered: bool = (i == _hover_idx)
		var bg_color := Color(0.25, 0.35, 0.2, 0.8) if (hovered and can) else (Color(0.2, 0.25, 0.18, 0.6) if can else Color(0.15, 0.12, 0.12, 0.4))
		draw_rect(Rect2(sx + 5, iy, sw - 10, 45), bg_color)
		draw_rect(Rect2(sx + 5, iy, sw - 10, 45), Color(0.4, 0.4, 0.4, 0.3), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(sx + 12, iy + 18), str(item["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.9, 0.85) if can else Color(0.5, 0.5, 0.5))
		draw_string(ThemeDB.fallback_font, Vector2(sx + 12, iy + 36),
			"%s — Cost: %d stone" % [str(item["desc"]), int(item["cost"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.55))


func _draw_pop_line(x: float, y: float, label: String, count: int, col: Color) -> void:
	draw_circle(Vector2(x + 6, y - 4), 5.0, col)
	draw_string(ThemeDB.fallback_font, Vector2(x + 16, y), "%s: %d" % [label, count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.8, 0.8))
