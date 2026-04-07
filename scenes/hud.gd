extends Control
## Full-screen HUD. Day/night bar, population, resources, shop, event feed, command menu.

const BAR_HEIGHT := 48.0
const FEED_WIDTH := 340.0
const FEED_LINE_H := 32.0
const FEED_VISIBLE_COUNT := 5
const FEED_FADE_TIME := 8000
const F := 2  ## font scale multiplier

var pop_red: int = 0
var pop_yellow: int = 0
var pop_blue: int = 0
var pop_colorless: int = 0
var pop_enemies: int = 0
var pop_total: int = 0

var _shop_open: bool = false
var _shop_items: Array = []
var _hover_idx: int = -1

var _feed_expanded: bool = false
var _feed_scroll: int = 0
var _feed_hover: bool = false

## Command menu state
var _cmd_menu_open: bool = false
var _cmd_hover: String = ""
var _pending_command: String = ""  ## "move", "hold", "house", "release" — waiting for click
const CMD_BUTTONS := [
	{"id": "move", "label": "Move", "color": Color(0.3, 0.8, 0.4)},
	{"id": "hold", "label": "Hold", "color": Color(1.0, 0.8, 0.2)},
	{"id": "house", "label": "House", "color": Color(0.7, 0.5, 0.3)},
	{"id": "release", "label": "Release", "color": Color(0.6, 0.6, 0.6)},
]

signal buy_requested(item_id: String)
signal command_issued(cmd_type: String)


func _ready() -> void:
	_refresh_shop()
	Economy.currency_changed.connect(func(): _refresh_shop())


func _refresh_shop() -> void:
	_shop_items.clear()
	for id in Economy.get_shop_items():
		var item: Dictionary = Economy.get_shop_items()[id]
		_shop_items.append({"id": id, "name": item["name"], "cost": item["cost"], "desc": item["description"]})


func set_command_menu_visible(show: bool) -> void:
	_cmd_menu_open = show
	if not show:
		_pending_command = ""


func get_pending_command() -> String:
	return _pending_command


func clear_pending_command() -> void:
	_pending_command = ""


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("toggle_shop"):
			_shop_open = not _shop_open
			get_viewport().set_input_as_handled()
			return

	var vp_size: Vector2 = get_viewport_rect().size

	# Command menu clicks
	if _cmd_menu_open and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cmd_id: String = _get_cmd_at(event.position, vp_size)
		if cmd_id != "":
			if cmd_id == "move":
				_pending_command = "move"
			elif cmd_id == "hold":
				command_issued.emit("hold")
			elif cmd_id == "house":
				command_issued.emit("house")
			elif cmd_id == "release":
				command_issued.emit("release")
			get_viewport().set_input_as_handled()
			return

	# Feed click
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var feed_rect := _get_feed_rect(vp_size)
		if feed_rect.has_point(event.position):
			_feed_expanded = not _feed_expanded
			_feed_scroll = 0
			get_viewport().set_input_as_handled()
			return

	# Feed scroll
	if _feed_expanded and event is InputEventMouseButton:
		var feed_rect := _get_feed_rect(vp_size)
		if feed_rect.has_point(event.position):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				_feed_scroll = mini(_feed_scroll + 1, maxi(0, EventFeed.messages.size() - FEED_VISIBLE_COUNT))
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				_feed_scroll = maxi(0, _feed_scroll - 1)
				get_viewport().set_input_as_handled()

	# Feed + cmd hover
	if event is InputEventMouseMotion:
		var feed_rect := _get_feed_rect(vp_size)
		_feed_hover = feed_rect.has_point(event.position)
		_cmd_hover = _get_cmd_at(event.position, vp_size) if _cmd_menu_open else ""

	if not _shop_open:
		return

	var shop_x: float = vp_size.x - 320.0
	var shop_y: float = 80.0
	if event is InputEventMouseMotion:
		_hover_idx = -1
		for i in _shop_items.size():
			var iy: float = shop_y + 50 + i * 70.0
			if Rect2(shop_x, iy, 300, 60).has_point(event.position):
				_hover_idx = i
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _hover_idx >= 0 and _hover_idx < _shop_items.size():
			var item_id: String = _shop_items[_hover_idx]["id"]
			if Economy.can_afford(item_id):
				buy_requested.emit(item_id)
			get_viewport().set_input_as_handled()


func _get_feed_rect(vp_size: Vector2) -> Rect2:
	var line_count: int = FEED_VISIBLE_COUNT if not _feed_expanded else mini(20, EventFeed.messages.size())
	var h: float = maxf(line_count * FEED_LINE_H + 40.0, 80.0)
	var x: float = vp_size.x - FEED_WIDTH - 16.0
	var y: float = vp_size.y * 0.3
	return Rect2(x, y, FEED_WIDTH, h)


func _get_cmd_at(pos: Vector2, vp_size: Vector2) -> String:
	var bx: float = vp_size.x - 220.0
	var by: float = vp_size.y - 260.0
	for i in CMD_BUTTONS.size():
		var iy: float = by + i * 48.0
		if Rect2(bx, iy, 200, 42).has_point(pos):
			return CMD_BUTTONS[i]["id"]
	return ""


func _draw() -> void:
	var vp_size: Vector2 = get_viewport_rect().size

	# ── Day/Night bar ────────────────────────────────────────────────────
	draw_rect(Rect2(0, 0, vp_size.x, BAR_HEIGHT), Color(0.08, 0.08, 0.1, 0.85))
	var day_frac: float = GameClock.DAY_DURATION / GameClock.CYCLE_DURATION
	var day_w: float = vp_size.x * day_frac
	draw_rect(Rect2(0, 0, day_w, BAR_HEIGHT), Color(0.35, 0.32, 0.15, 0.4))
	draw_rect(Rect2(day_w, 0, vp_size.x - day_w, BAR_HEIGHT), Color(0.08, 0.08, 0.2, 0.4))
	draw_rect(Rect2(GameClock.get_cycle_progress() * vp_size.x - 2, 0, 4, BAR_HEIGHT), Color(1, 1, 1, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(10, 30), "DAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.85, 0.4, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(day_w + 10, 30), "NIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.5, 0.5, 0.8, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(vp_size.x * 0.5 - 80, 32), GameClock.get_time_string(), HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color(0.85, 0.85, 0.85))

	# ── Population panel (bottom-left) ───────────────────────────────────
	var panel_y: float = vp_size.y - 220
	draw_rect(Rect2(0, panel_y, 420, 220), Color(0.06, 0.06, 0.08, 0.8))
	draw_rect(Rect2(0, panel_y, 420, 220), Color(0.3, 0.3, 0.3, 0.3), false, 1.0)

	var ty: float = panel_y + 30.0
	_draw_pop_line(16, ty, "Red", pop_red, Color(0.9, 0.22, 0.2)); ty += 28.0
	_draw_pop_line(16, ty, "Yellow", pop_yellow, Color(0.94, 0.84, 0.12)); ty += 28.0
	_draw_pop_line(16, ty, "Blue", pop_blue, Color(0.2, 0.4, 0.9)); ty += 28.0
	_draw_pop_line(16, ty, "Colorless", pop_colorless, Color(0.7, 0.7, 0.7))

	draw_string(ThemeDB.fallback_font, Vector2(250, panel_y + 46), "Enemies: %d" % pop_enemies,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.2, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(250, panel_y + 76), "Total: %d" % pop_total,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.65, 0.65, 0.65))

	draw_circle(Vector2(260, panel_y + 116), 8.0, Color(0.5, 0.52, 0.48))
	draw_string(ThemeDB.fallback_font, Vector2(275, panel_y + 122),
		"Stone: %d" % Economy.stone, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.6, 0.65, 0.55))
	draw_circle(Vector2(260, panel_y + 148), 8.0, Color(0.3, 0.55, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(275, panel_y + 154),
		"Fish: %d" % Economy.fish, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.4, 0.65, 0.8))

	# Pending command indicator
	if _pending_command != "":
		draw_string(ThemeDB.fallback_font, Vector2(16, panel_y - 10),
			"Click target for: %s" % _pending_command.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.3, 0.9))

	# ── Command menu (bottom-right, when selection active) ───────────────
	if _cmd_menu_open:
		_draw_cmd_menu(vp_size)

	# ── Event feed ───────────────────────────────────────────────────────
	_draw_feed(vp_size)

	# ── Shop ─────────────────────────────────────────────────────────────
	if _shop_open:
		_draw_shop(vp_size)


func _draw_cmd_menu(vp_size: Vector2) -> void:
	var bx: float = vp_size.x - 220.0
	var by: float = vp_size.y - 260.0
	draw_rect(Rect2(bx - 10, by - 30, 220, 230), Color(0.06, 0.06, 0.08, 0.85))
	draw_rect(Rect2(bx - 10, by - 30, 220, 230), Color(0.4, 0.4, 0.4, 0.3), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(bx, by - 8), "COMMANDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.7, 0.7))
	for i in CMD_BUTTONS.size():
		var btn: Dictionary = CMD_BUTTONS[i]
		var iy: float = by + i * 48.0
		var hovered: bool = (_cmd_hover == btn["id"])
		var bg: Color = btn["color"].darkened(0.2 if not hovered else 0.0)
		bg.a = 0.8 if hovered else 0.5
		draw_rect(Rect2(bx, iy, 200, 42), bg)
		draw_rect(Rect2(bx, iy, 200, 42), Color(0.5, 0.5, 0.5, 0.4), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(bx + 16, iy + 28), btn["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95) if hovered else Color(0.9, 0.9, 0.9, 0.8))


func _draw_feed(vp_size: Vector2) -> void:
	var rect := _get_feed_rect(vp_size)
	var now: int = Time.get_ticks_msec()

	var bg_alpha: float = 0.7 if (_feed_expanded or _feed_hover) else 0.45
	draw_rect(rect, Color(0.05, 0.05, 0.08, bg_alpha))
	draw_rect(rect, Color(0.35, 0.35, 0.4, 0.25), false, 1.0)

	var header_text: String = "Events (click to %s)" % ("collapse" if _feed_expanded else "expand")
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 8, rect.position.y + 22),
		header_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.55, 0.6))

	var msgs: Array = EventFeed.messages
	if msgs.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 10, rect.position.y + 52),
			"No events yet...", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.4, 0.4, 0.4))
		return

	var visible_count: int = FEED_VISIBLE_COUNT if not _feed_expanded else mini(20, msgs.size())
	var start_idx: int
	if _feed_expanded:
		start_idx = maxi(0, msgs.size() - visible_count - _feed_scroll)
	else:
		start_idx = maxi(0, msgs.size() - visible_count)
	var end_idx: int = mini(start_idx + visible_count, msgs.size())

	var y_offset: float = rect.position.y + 32.0
	for i in range(start_idx, end_idx):
		var msg: Dictionary = msgs[i]
		var age: int = now - int(msg["time"])
		var alpha: float = 1.0
		if not _feed_expanded and age > FEED_FADE_TIME:
			alpha = maxf(0.15, 1.0 - float(age - FEED_FADE_TIME) / 4000.0)
		var col: Color = msg["color"]
		col.a = alpha
		y_offset += FEED_LINE_H
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 10, y_offset),
			str(msg["text"]), HORIZONTAL_ALIGNMENT_LEFT, int(FEED_WIDTH - 20), 20, col)

	if _feed_expanded and msgs.size() > visible_count:
		draw_string(ThemeDB.fallback_font,
			Vector2(rect.position.x + 8, rect.end.y - 6),
			"Scroll for more...", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.45, 0.45, 0.5))


func _draw_shop(vp_size: Vector2) -> void:
	var sx: float = vp_size.x - 320.0
	var sy: float = 80.0
	var sw: float = 300.0
	var sh: float = 60.0 + _shop_items.size() * 70.0
	draw_rect(Rect2(sx, sy, sw, sh), Color(0.06, 0.06, 0.08, 0.9))
	draw_rect(Rect2(sx, sy, sw, sh), Color(0.4, 0.4, 0.4, 0.4), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(sx + 14, sy + 34), "SHOP (B to close)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.85, 0.85))
	for i in _shop_items.size():
		var item: Dictionary = _shop_items[i]
		var iy: float = sy + 50 + i * 70.0
		var can: bool = Economy.stone >= int(item["cost"])
		var hovered: bool = (i == _hover_idx)
		var bg_color := Color(0.25, 0.35, 0.2, 0.8) if (hovered and can) else (Color(0.2, 0.25, 0.18, 0.6) if can else Color(0.15, 0.12, 0.12, 0.4))
		draw_rect(Rect2(sx + 5, iy, sw - 10, 60), bg_color)
		draw_rect(Rect2(sx + 5, iy, sw - 10, 60), Color(0.4, 0.4, 0.4, 0.3), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(sx + 16, iy + 28), str(item["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.9, 0.9, 0.85) if can else Color(0.5, 0.5, 0.5))
		var cost_str: String = "%s  |  %d stone" % [str(item["desc"]), int(item["cost"])]
		draw_string(ThemeDB.fallback_font, Vector2(sx + 16, iy + 50),
			cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.6, 0.55))


func _draw_pop_line(x: float, y: float, label: String, count: int, col: Color) -> void:
	draw_circle(Vector2(x + 8, y - 4), 7.0, col)
	draw_string(ThemeDB.fallback_font, Vector2(x + 22, y), "%s: %d" % [label, count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.8, 0.8, 0.8))
