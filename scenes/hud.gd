extends Control
## Full-screen HUD. Day/night bar, population, resources, shop, event feed,
## command menu, building menu, score overlay (Tab).

const BAR_HEIGHT := 48.0
const FEED_WIDTH := 340.0
const FEED_LINE_H := 32.0
const FEED_VISIBLE_COUNT := 5
const FEED_FADE_TIME := 8000

var pop_red: int = 0
var pop_yellow: int = 0
var pop_blue: int = 0
var pop_colorless: int = 0
var pop_enemies: int = 0
var pop_total: int = 0
var pop_max_effective: int = 50

var _shop_open: bool = false
var _shop_items: Array = []
var _hover_idx: int = -1

var _feed_expanded: bool = false
var _feed_scroll: int = 0
var _feed_hover: bool = false

## Command menu state
var _cmd_menu_open: bool = false
var _cmd_hover: String = ""
var _pending_command: String = ""
const CMD_BUTTONS := [
	{"id": "move", "label": "Move", "color": Color(0.3, 0.8, 0.4), "requires": ""},
	{"id": "hold", "label": "Hold", "color": Color(1.0, 0.8, 0.2), "requires": ""},
	{"id": "house", "label": "House", "color": Color(0.7, 0.5, 0.3), "requires": ""},
	{"id": "break_door", "label": "Break Door", "color": Color(0.9, 0.4, 0.2), "requires": "red"},
	{"id": "attack", "label": "Attack [A]", "color": Color(0.85, 0.2, 0.2), "requires": "red"},
	{"id": "stun", "label": "Stun [S]", "color": Color(0.2, 0.4, 0.85), "requires": "blue"},
	{"id": "release", "label": "Release", "color": Color(0.6, 0.6, 0.6), "requires": ""},
]

## Building menu state
var _building_menu_open: bool = false
var _building_can_sell: bool = false
const BUILDING_BUTTONS := [
	{"id": "evict", "label": "Evict All", "color": Color(0.8, 0.6, 0.3)},
	{"id": "sell", "label": "Sell", "color": Color(0.9, 0.3, 0.3)},
]

## Selected villager info
var selected_villager_info: Array = []
var selected_building_info: Dictionary = {}

## Score data: [{faction_id, symbol, color, pop, stone, fish, rooms}]
var score_data: Array = []
var _score_open: bool = false

signal buy_requested(item_id: String)
signal command_issued(cmd_type: String)
signal building_command_issued(cmd_type: String)


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
	if show:
		_building_menu_open = false
	if not show:
		_pending_command = ""


func set_building_menu_visible(show: bool, can_sell: bool = false) -> void:
	_building_menu_open = show
	_building_can_sell = can_sell
	if show:
		_cmd_menu_open = false
		_pending_command = ""


func get_pending_command() -> String:
	return _pending_command


func clear_pending_command() -> void:
	_pending_command = ""


func _get_filtered_commands() -> Array:
	## Returns only commands shared by ALL selected villager types.
	if selected_villager_info.is_empty():
		return []
	var types: Dictionary = {}
	for info in selected_villager_info:
		types[info.get("color_type", "")] = true
	var result: Array = []
	for btn in CMD_BUTTONS:
		var req: String = btn.get("requires", "")
		if req == "":
			result.append(btn)
		else:
			# Only include if ALL selected villagers match the required type
			if types.size() == 1 and types.has(req):
				result.append(btn)
	return result


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("toggle_shop"):
			_shop_open = not _shop_open
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB:
			_score_open = not _score_open
			get_viewport().set_input_as_handled()
			return

	var vp_size: Vector2 = get_viewport_rect().size

	# Command menu clicks
	if _cmd_menu_open and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var cmd_id: String = _get_cmd_at(event.position, vp_size)
		if cmd_id != "":
			if cmd_id == "move":
				_pending_command = "move"
			elif cmd_id == "break_door":
				_pending_command = "break_door"
			elif cmd_id == "attack":
				_pending_command = "attack"
			elif cmd_id == "stun":
				_pending_command = "stun"
			else:
				command_issued.emit(cmd_id)
			get_viewport().set_input_as_handled()
			return

	# Tutorial Reset button click
	if TutorialManager.active and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var reset_rect := _get_tutorial_reset_rect(vp_size)
		if reset_rect.has_point(event.position):
			_restart_tutorial()
			get_viewport().set_input_as_handled()
			return

	# Building menu clicks
	if _building_menu_open and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var bcmd_id: String = _get_building_cmd_at(event.position, vp_size)
		if bcmd_id != "":
			if bcmd_id == "sell" and not _building_can_sell:
				pass
			else:
				building_command_issued.emit(bcmd_id)
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
		_cmd_hover = ""
		if _cmd_menu_open:
			_cmd_hover = _get_cmd_at(event.position, vp_size)
		elif _building_menu_open:
			_cmd_hover = _get_building_cmd_at(event.position, vp_size)

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
	var filtered := _get_filtered_commands()
	var bx: float = vp_size.x - 150.0
	var by: float = vp_size.y - 222.0
	for i in filtered.size():
		var iy: float = by + i * 42.0
		if Rect2(bx, iy, 120, 36).has_point(pos):
			return filtered[i]["id"]
	return ""


func _get_building_cmd_at(pos: Vector2, vp_size: Vector2) -> String:
	var panel_w: float = 380.0
	var panel_h: float = 200.0
	var px: float = vp_size.x - panel_w - 10.0
	var py: float = vp_size.y - panel_h - 10.0
	var cmd_x: float = px + panel_w - 140.0
	for i in BUILDING_BUTTONS.size():
		var iy: float = py + 28.0 + i * 50.0
		if Rect2(cmd_x, iy, 120, 40).has_point(pos):
			return BUILDING_BUTTONS[i]["id"]
	return ""


func _draw() -> void:
	var vp_size: Vector2 = get_viewport_rect().size

	# ── Tutorial overlay ────────────────────────────────────────
	if TutorialManager.active:
		_draw_tutorial_overlay(vp_size)

	# ── Day/Night bar ────────────────────────────────────────────
	draw_rect(Rect2(0, 0, vp_size.x, BAR_HEIGHT), Color(0.08, 0.08, 0.1, 0.85))
	var day_frac: float = GameClock.DAY_DURATION / GameClock.CYCLE_DURATION
	var day_w: float = vp_size.x * day_frac
	draw_rect(Rect2(0, 0, day_w, BAR_HEIGHT), Color(0.35, 0.32, 0.15, 0.4))
	draw_rect(Rect2(day_w, 0, vp_size.x - day_w, BAR_HEIGHT), Color(0.08, 0.08, 0.2, 0.4))
	draw_rect(Rect2(GameClock.get_cycle_progress() * vp_size.x - 2, 0, 4, BAR_HEIGHT), Color(1, 1, 1, 0.9))
	draw_string(ThemeDB.fallback_font, Vector2(10, 30), "DAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.85, 0.4, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(day_w + 10, 30), "NIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.5, 0.5, 0.8, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(vp_size.x * 0.5 - 80, 32), GameClock.get_time_string(), HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color(0.85, 0.85, 0.85))

	if GameClock.is_paused:
		draw_string(ThemeDB.fallback_font, Vector2(vp_size.x * 0.5 - 40, 60),
			"PAUSED", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(1.0, 0.8, 0.2, 0.8 + sin(Time.get_ticks_msec() * 0.003) * 0.2))

	# ── Population panel (bottom-left) ───────────────────────────
	var panel_y: float = vp_size.y - 220
	draw_rect(Rect2(0, panel_y, 420, 220), Color(0.06, 0.06, 0.08, 0.8))
	draw_rect(Rect2(0, panel_y, 420, 220), Color(0.3, 0.3, 0.3, 0.3), false, 1.0)

	var fid: int = FactionManager.local_faction_id
	var sym: String = FactionManager.get_faction_symbol(fid)
	var fc: Color = FactionManager.get_faction_color(fid)
	draw_string(ThemeDB.fallback_font, Vector2(16, panel_y + 24), "Faction %s" % sym,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, fc)

	var ty: float = panel_y + 48.0
	_draw_pop_line(16, ty, "Red", pop_red, Color(0.9, 0.22, 0.2)); ty += 24.0
	_draw_pop_line(16, ty, "Yellow", pop_yellow, Color(0.94, 0.84, 0.12)); ty += 24.0
	_draw_pop_line(16, ty, "Blue", pop_blue, Color(0.2, 0.4, 0.9)); ty += 24.0
	_draw_pop_line(16, ty, "Colorless", pop_colorless, Color(0.7, 0.7, 0.7))

	draw_string(ThemeDB.fallback_font, Vector2(250, panel_y + 56), "Enemies: %d" % pop_enemies,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.2, 0.2))
	draw_string(ThemeDB.fallback_font, Vector2(250, panel_y + 80), "Pop: %d / %d" % [pop_total, pop_max_effective],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.65, 0.65, 0.65))

	# Per-faction resources
	var my_stone: int = Economy.get_stone(fid)
	var my_fish: int = Economy.get_fish(fid)
	draw_circle(Vector2(260, panel_y + 116), 8.0, Color(0.5, 0.52, 0.48))
	draw_string(ThemeDB.fallback_font, Vector2(275, panel_y + 122),
		"Stone: %d" % my_stone, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.65, 0.55))
	draw_circle(Vector2(260, panel_y + 144), 8.0, Color(0.3, 0.55, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(275, panel_y + 150),
		"Fish: %d" % my_fish, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.4, 0.65, 0.8))

	draw_string(ThemeDB.fallback_font, Vector2(16, panel_y + 186),
		"Shift: Hover-select  |  Tab: Scoreboard", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.4, 0.45))

	# Pending command
	if _pending_command != "":
		draw_string(ThemeDB.fallback_font, Vector2(16, panel_y - 10),
			"Click target for: %s" % _pending_command.to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.3, 0.9))

	# ── Selection panel: villager info (left) + commands (right) ──
	if _cmd_menu_open:
		_draw_selection_panel(vp_size)

	# ── Building menu ────────────────────────────────────────────
	if _building_menu_open:
		_draw_building_menu(vp_size)

	# ── Score overlay (Tab) ──────────────────────────────────────
	if _score_open:
		_draw_score(vp_size)

	# ── Event feed ───────────────────────────────────────────────
	_draw_feed(vp_size)

	# ── Shop ─────────────────────────────────────────────────────
	if _shop_open:
		_draw_shop(vp_size)


func _draw_selection_panel(vp_size: Vector2) -> void:
	## Villager info on left, commands on right, faction identity at bottom.
	var filtered := _get_filtered_commands()
	var panel_w: float = 380.0
	var panel_h: float = 280.0
	var px: float = vp_size.x - panel_w - 10.0
	var py: float = vp_size.y - panel_h - 10.0

	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.06, 0.06, 0.08, 0.88))
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.4, 0.4, 0.4, 0.3), false, 1.0)

	var info_x: float = px + 10.0
	var total: int = selected_villager_info.size()

	# ── Header ──────────────────────────────────────────────────
	draw_string(ThemeDB.fallback_font, Vector2(info_x, py + 18), "SELECTED (%d)" % total,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.65))

	# ── Per-type counts ──────────────────────────────────────────
	var type_counts: Dictionary = {}
	for info in selected_villager_info:
		var ct: String = info.get("color_type", "unknown")
		type_counts[ct] = type_counts.get(ct, 0) + 1
	var ty: float = py + 30.0
	for ct in type_counts:
		var def: Dictionary = ColorRegistry.get_def(ct)
		var col: Color = def.get("display_color", Color.WHITE)
		draw_circle(Vector2(info_x + 8, ty + 6), 6.0, col)
		draw_string(ThemeDB.fallback_font, Vector2(info_x + 20, ty + 12),
			"%s: %d" % [ct.capitalize(), type_counts[ct]],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.85))
		ty += 24.0

	# ── Individual villager details (small selections) ───────────
	if total <= 4:
		ty += 2.0
		for info in selected_villager_info:
			if ty > py + panel_h - 72.0:  # leave room for faction block
				break
			var col: Color = info.get("display_color", Color.WHITE)
			var hp: int = int(info.get("health", 0))
			var max_hp: int = int(info.get("max_health", 1))
			draw_string(ThemeDB.fallback_font, Vector2(info_x + 4, ty + 12),
				"%s  HP:%d/%d" % [str(info.get("name", "")), hp, max_hp],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.lightened(0.3))
			ty += 20.0

	# ── Faction identity block — bottom of panel ─────────────────
	var faction_ids: Dictionary = {}
	for info in selected_villager_info:
		faction_ids[info.get("faction_id", -1)] = true

	var faction_block_y: float = py + panel_h - 62.0
	draw_line(Vector2(px + 8, faction_block_y - 4), Vector2(px + panel_w * 0.55 - 8, faction_block_y - 4),
		Color(0.3, 0.3, 0.35, 0.6), 1.0)

	if faction_ids.size() == 1 and not selected_villager_info.is_empty():
		var fc: Color = selected_villager_info[0].get("faction_color", Color(0.5, 0.5, 0.5))
		var fsym: String = selected_villager_info[0].get("faction_symbol", "?")
		var fid: int = faction_ids.keys()[0]
		var fname: String = FactionManager.get_faction_name(fid) if fid >= 0 else "Unknown"
		# Tinted background strip
		draw_rect(Rect2(px, faction_block_y, panel_w * 0.57, 62), Color(fc.r, fc.g, fc.b, 0.14))
		# Large symbol
		draw_string(ThemeDB.fallback_font, Vector2(info_x, faction_block_y + 48),
			fsym, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, fc)
		# Faction name beside symbol
		draw_string(ThemeDB.fallback_font, Vector2(info_x + 46, faction_block_y + 24),
			"FACTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(fc.r, fc.g, fc.b, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(info_x + 46, faction_block_y + 46),
			fname, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, fc)
	else:
		# Mixed factions
		draw_string(ThemeDB.fallback_font, Vector2(info_x, faction_block_y + 40),
			"Mixed Factions", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.5, 0.3))

	# ── Commands (right column) ───────────────────────────────────
	var cmd_x: float = px + panel_w - 140.0
	draw_string(ThemeDB.fallback_font, Vector2(cmd_x, py + 18), "COMMANDS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.65))
	for i in filtered.size():
		var btn: Dictionary = filtered[i]
		var iy: float = py + 28.0 + i * 42.0
		var hovered: bool = (_cmd_hover == btn["id"])
		var bg: Color = btn["color"].darkened(0.2 if not hovered else 0.0)
		bg.a = 0.8 if hovered else 0.5
		draw_rect(Rect2(cmd_x, iy, 120, 36), bg)
		draw_rect(Rect2(cmd_x, iy, 120, 36), Color(0.5, 0.5, 0.5, 0.4), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(cmd_x + 10, iy + 24), btn["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.95) if hovered else Color(0.9, 0.9, 0.9, 0.8))


func _draw_building_menu(vp_size: Vector2) -> void:
	var panel_w: float = 380.0
	var panel_h: float = 200.0
	var px: float = vp_size.x - panel_w - 10.0
	var py: float = vp_size.y - panel_h - 10.0

	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.06, 0.06, 0.08, 0.88))
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.4, 0.4, 0.4, 0.3), false, 1.0)

	# Left side: building info
	var info_x: float = px + 10.0
	draw_string(ThemeDB.fallback_font, Vector2(info_x, py + 18), "BUILDING",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.65))

	if not selected_building_info.is_empty():
		var btype: String = selected_building_info.get("type", "Building")
		var occ: int = selected_building_info.get("occupied", 0)
		var cap: int = selected_building_info.get("capacity", 4)
		var fc: Color = selected_building_info.get("faction_color", Color(0.5, 0.5, 0.5))
		var fsym: String = selected_building_info.get("faction_symbol", "?")

		# Mini building icon
		var icon_cx: float = info_x + 48.0
		var icon_cy: float = py + 88.0
		if btype == "Home":
			draw_rect(Rect2(icon_cx - 26, icon_cy - 8, 52, 32), Color(0.55, 0.4, 0.25, 0.8))
			draw_colored_polygon(PackedVector2Array([
				Vector2(icon_cx, icon_cy - 36),
				Vector2(icon_cx + 32, icon_cy - 8),
				Vector2(icon_cx - 32, icon_cy - 8)]),
				Color(0.6, 0.2, 0.15, 0.8))
		elif btype == "Church":
			draw_rect(Rect2(icon_cx - 20, icon_cy - 8, 40, 32), Color(0.35, 0.38, 0.5, 0.8))
			draw_colored_polygon(PackedVector2Array([
				Vector2(icon_cx, icon_cy - 40),
				Vector2(icon_cx + 13, icon_cy - 8),
				Vector2(icon_cx - 13, icon_cy - 8)]),
				Color(0.3, 0.35, 0.55, 0.8))
		elif btype == "Bank":
			draw_rect(Rect2(icon_cx - 26, icon_cy - 14, 52, 30), Color(0.4, 0.38, 0.32, 0.8))
			draw_circle(Vector2(icon_cx, icon_cy), 10.0, Color(0.5, 0.52, 0.48, 0.8))
		elif btype == "Fishing Hut":
			draw_rect(Rect2(icon_cx - 26, icon_cy - 10, 52, 26), Color(0.3, 0.25, 0.2, 0.8))
			draw_colored_polygon(PackedVector2Array([
				Vector2(icon_cx, icon_cy - 36),
				Vector2(icon_cx + 30, icon_cy - 10),
				Vector2(icon_cx - 30, icon_cy - 10)]),
				Color(0.25, 0.35, 0.5, 0.8))

		draw_string(ThemeDB.fallback_font, Vector2(info_x, py + 116), btype,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.85, 0.85))
		draw_string(ThemeDB.fallback_font, Vector2(info_x, py + 142),
			"Sheltered: %d / %d" % [occ, cap],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.65, 0.65, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(info_x, py + 165),
			"Owner: %s" % fsym,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, fc)

	# Right side: action buttons
	var cmd_x: float = px + panel_w - 140.0
	draw_string(ThemeDB.fallback_font, Vector2(cmd_x, py + 18), "ACTIONS",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.6, 0.65))

	# Compute dynamic sell value
	var sell_item_id: String = ""
	var btype_for_sell: String = selected_building_info.get("type", "")
	if btype_for_sell == "Home": sell_item_id = "house"
	elif btype_for_sell == "Church": sell_item_id = "church"
	elif btype_for_sell == "Bank": sell_item_id = "bank"
	elif btype_for_sell == "Fishing Hut": sell_item_id = "fishing_hut"
	var sell_val: int = Economy.get_sell_value(sell_item_id)
	var is_preplaced: bool = (selected_building_info.get("faction_id", -1) == -2)

	for i in BUILDING_BUTTONS.size():
		var btn: Dictionary = BUILDING_BUTTONS[i]
		var iy: float = py + 28.0 + i * 50.0
		var hovered: bool = (_cmd_hover == btn["id"])
		var is_sell: bool = (btn["id"] == "sell")
		var disabled: bool = is_sell and (not _building_can_sell or is_preplaced)
		var bg: Color
		if disabled: bg = Color(0.2, 0.2, 0.2, 0.3)
		else:
			bg = btn["color"].darkened(0.2 if not hovered else 0.0)
			bg.a = 0.8 if hovered else 0.5
		draw_rect(Rect2(cmd_x, iy, 120, 40), bg)
		draw_rect(Rect2(cmd_x, iy, 120, 40), Color(0.5, 0.5, 0.5, 0.4), false, 1.0)
		var label_text: String
		if is_sell:
			if is_preplaced: label_text = "Pre-placed"
			elif disabled: label_text = "Conquered"
			else: label_text = "Sell ($%d)" % sell_val
		else:
			label_text = btn["label"]
		var text_col: Color = Color(0.4, 0.4, 0.4) if disabled else (Color(1, 1, 1, 0.95) if hovered else Color(0.9, 0.9, 0.9, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(cmd_x + 10, iy + 27), label_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, text_col)


func _draw_score(vp_size: Vector2) -> void:
	var sw: float = 580.0
	var sh: float = 60.0 + score_data.size() * 50.0
	var sx: float = (vp_size.x - sw) * 0.5
	var sy: float = 100.0

	draw_rect(Rect2(sx, sy, sw, sh), Color(0.04, 0.04, 0.06, 0.92))
	draw_rect(Rect2(sx, sy, sw, sh), Color(0.5, 0.5, 0.5, 0.3), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(sx + 20, sy + 28),
		"SCOREBOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.85, 0.6))
	draw_string(ThemeDB.fallback_font, Vector2(sx + sw - 120, sy + 28),
		"Tab to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.45, 0.5))

	# Headers
	var hy: float = sy + 48.0
	draw_string(ThemeDB.fallback_font, Vector2(sx + 20, hy), "Faction", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.55))
	draw_string(ThemeDB.fallback_font, Vector2(sx + 140, hy), "Pop", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.55))
	draw_string(ThemeDB.fallback_font, Vector2(sx + 210, hy), "Stone", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.55))
	draw_string(ThemeDB.fallback_font, Vector2(sx + 290, hy), "Fish", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.55))
	draw_string(ThemeDB.fallback_font, Vector2(sx + 360, hy), "Rooms", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.55))
	draw_string(ThemeDB.fallback_font, Vector2(sx + 440, hy), "Score", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.5, 0.55))

	for i in score_data.size():
		var sd: Dictionary = score_data[i]
		var ry: float = sy + 68.0 + i * 50.0
		var row_col: Color = sd.get("color", Color.WHITE)
		var is_local: bool = (sd.get("faction_id", -1) == FactionManager.local_faction_id)
		var is_elim: bool = sd.get("eliminated", false)
		if is_local:
			draw_rect(Rect2(sx + 5, ry - 16, sw - 10, 44), Color(row_col.r, row_col.g, row_col.b, 0.12))
		if is_elim:
			draw_rect(Rect2(sx + 5, ry - 16, sw - 10, 44), Color(0.3, 0.1, 0.1, 0.3))

		var name_col: Color = Color(0.4, 0.35, 0.35) if is_elim else Color(0.75, 0.75, 0.75)
		draw_string(ThemeDB.fallback_font, Vector2(sx + 20, ry + 10),
			str(sd.get("symbol", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, row_col)
		draw_string(ThemeDB.fallback_font, Vector2(sx + 60, ry + 6),
			str(sd.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, name_col)

		if is_elim:
			draw_string(ThemeDB.fallback_font, Vector2(sx + 140, ry + 6),
				"ELIMINATED", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.3, 0.3))
		else:
			draw_string(ThemeDB.fallback_font, Vector2(sx + 140, ry + 6),
				str(sd.get("pop", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.8, 0.8))
			draw_string(ThemeDB.fallback_font, Vector2(sx + 210, ry + 6),
				str(sd.get("stone", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.65, 0.55))
			draw_string(ThemeDB.fallback_font, Vector2(sx + 290, ry + 6),
				str(sd.get("fish", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.4, 0.65, 0.8))
			draw_string(ThemeDB.fallback_font, Vector2(sx + 360, ry + 6),
				str(sd.get("rooms", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.7, 0.5))
			draw_string(ThemeDB.fallback_font, Vector2(sx + 440, ry + 6),
				str(sd.get("score", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.75, 0.4))


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
		draw_string(ThemeDB.fallback_font, Vector2(rect.position.x + 8, rect.end.y - 6),
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
		var can: bool = Economy.can_afford(item["id"])
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
	draw_circle(Vector2(x + 8, y - 4), 6.0, col)
	draw_string(ThemeDB.fallback_font, Vector2(x + 20, y), "%s: %d" % [label, count],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.8, 0.8, 0.8))


func _draw_tutorial_overlay(vp_size: Vector2) -> void:
	var instruction: String = TutorialManager.get_current_instruction()
	if instruction.is_empty():
		return
	var box_w: float = 600.0
	var box_h: float = 62.0
	var box_x: float = (vp_size.x - box_w) * 0.5
	var box_y: float = BAR_HEIGHT + 8.0
	# Pending advance = green flash
	var bg_col := Color(0.0, 0.15, 0.0, 0.82) if TutorialManager._pending_advance else Color(0.0, 0.0, 0.0, 0.78)
	draw_rect(Rect2(box_x, box_y, box_w, box_h), bg_col)
	var border_col := Color(0.4, 0.9, 0.4, 0.7) if TutorialManager._pending_advance else Color(0.9, 0.85, 0.4, 0.6)
	draw_rect(Rect2(box_x, box_y, box_w, box_h), border_col, false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(box_x + 14, box_y + 24),
		instruction, HORIZONTAL_ALIGNMENT_LEFT, int(box_w - 28), 16, Color(0.95, 0.9, 0.7))
	var phase_max: int = TutorialManager.PHASE_INSTRUCTIONS.size() - 1
	draw_string(ThemeDB.fallback_font, Vector2(box_x + 14, box_y + 50),
		"Phase %d / %d  |  Press Escape to open menu (Quit to Main Menu available there)" % [TutorialManager.current_phase, phase_max],
		HORIZONTAL_ALIGNMENT_LEFT, int(box_w - 28), 12, Color(0.5, 0.5, 0.5))
	# Reset button
	var reset_rect := _get_tutorial_reset_rect(vp_size)
	draw_rect(reset_rect, Color(0.5, 0.15, 0.1, 0.85))
	draw_rect(reset_rect, Color(0.9, 0.4, 0.3, 0.7), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(reset_rect.position.x + 16, reset_rect.position.y + 30),
		"RESET TUTORIAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.9, 0.8))


func _get_tutorial_reset_rect(vp_size: Vector2) -> Rect2:
	return Rect2(vp_size.x - 200, BAR_HEIGHT + 14, 170, 44)


func _restart_tutorial() -> void:
	TutorialManager.start_tutorial()
	call_deferred("_deferred_restart")


func _deferred_restart() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
