extends Control
## Full-screen HUD using scene nodes instead of _draw().
## Day/night bar, population, resources, shop, event feed,
## command menu, building menu, score overlay (Tab).

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

var _feed_expanded: bool = false
var _feed_scroll: int = 0

## Command menu state
var _cmd_menu_open: bool = false
var _pending_command: String = ""
const CMD_BUTTONS := [
	{"id": "move", "label": "Move", "color": Color(0.3, 0.8, 0.4), "requires": ""},
	{"id": "hold", "label": "Hold", "color": Color(1.0, 0.8, 0.2), "requires": ""},
	{"id": "house", "label": "House", "color": Color(0.7, 0.5, 0.3), "requires": ""},
	{"id": "attack", "label": "Attack [A]", "color": Color(0.85, 0.2, 0.2), "requires": "red"},
	{"id": "stun", "label": "Stun [S]", "color": Color(0.2, 0.4, 0.85), "requires": "blue"},
	{"id": "release", "label": "Release", "color": Color(0.6, 0.6, 0.6), "requires": ""},
]

const BUILDING_BUTTONS := [
	{"id": "evict", "label": "Evict All", "color": Color(0.8, 0.6, 0.3)},
	{"id": "sell", "label": "Sell", "color": Color(0.9, 0.3, 0.3)},
]

## Building menu state
var _building_menu_open: bool = false
var _building_can_sell: bool = false

## Selected villager info
var selected_villager_info: Array = []
var selected_building_info: Dictionary = {}

## Score data: [{faction_id, symbol, color, pop, stone, fish, rooms}]
var score_data: Array = []
var _score_open: bool = false

## UI refresh caching
var _last_cmd_menu_open: bool = false
var _last_building_menu_open: bool = false
var _last_building_can_sell: bool = false
var _last_selection_signature: String = ""
var _last_building_signature: String = ""

signal buy_requested(item_id: String)
signal command_issued(cmd_type: String)
signal building_command_issued(cmd_type: String)

# ── Node references ──────────────────────────────────────────────

# Day/Night Bar
@onready var _day_bg: ColorRect = $DayNightBar/DayBg
@onready var _night_bg: ColorRect = $DayNightBar/NightBg
@onready var _progress_line: ColorRect = $DayNightBar/ProgressLine
@onready var _day_label: Label = $DayNightBar/DayLabel
@onready var _night_label: Label = $DayNightBar/NightLabel
@onready var _time_label: Label = $DayNightBar/TimeLabel
@onready var _paused_label: Label = $DayNightBar/PausedLabel

# Population Panel
@onready var _pop_panel: Panel = $PopPanel
@onready var _faction_label: Label = $PopPanel/FactionLabel
@onready var _red_label: Label = $PopPanel/RedLabel
@onready var _yellow_label: Label = $PopPanel/YellowLabel
@onready var _blue_label: Label = $PopPanel/BlueLabel
@onready var _colorless_label: Label = $PopPanel/ColorlessLabel
@onready var _enemies_label: Label = $PopPanel/EnemiesLabel
@onready var _pop_label: Label = $PopPanel/PopLabel
@onready var _stone_label: Label = $PopPanel/StoneLabel
@onready var _fish_label: Label = $PopPanel/FishLabel

@onready var _pending_cmd_label: Label = $PendingCmdLabel

# Selection Panel
@onready var _selection_panel: Panel = $SelectionPanel
@onready var _selected_header: Label = $SelectionPanel/SelectedHeader
@onready var _type_counts: VBoxContainer = $SelectionPanel/TypeCounts
@onready var _villager_details: VBoxContainer = $SelectionPanel/VillagerDetails
@onready var _faction_bg: ColorRect = $SelectionPanel/FactionBg
@onready var _faction_symbol: Label = $SelectionPanel/FactionSymbol
@onready var _faction_title: Label = $SelectionPanel/FactionTitle
@onready var _faction_name_label: Label = $SelectionPanel/FactionName
@onready var _mixed_faction_label: Label = $SelectionPanel/MixedFactionLabel
@onready var _commands_container: VBoxContainer = $SelectionPanel/CommandsContainer

# Building Panel
@onready var _building_panel: Panel = $BuildingPanel
@onready var _building_icon: Control = $BuildingPanel/BuildingIcon
@onready var _building_type: Label = $BuildingPanel/BuildingType
@onready var _building_sheltered: Label = $BuildingPanel/BuildingSheltered
@onready var _building_owner: Label = $BuildingPanel/BuildingOwner
@onready var _evict_btn: Button = $BuildingPanel/EvictBtn
@onready var _sell_btn: Button = $BuildingPanel/SellBtn

# Score Overlay
@onready var _score_overlay: Panel = $ScoreOverlay
@onready var _score_rows: VBoxContainer = $ScoreOverlay/ScoreRows
@onready var _score_headers_box: HBoxContainer = $ScoreOverlay/ScoreHeaders

# Event Feed
@onready var _feed_panel: Panel = $FeedPanel
@onready var _feed_header: Label = $FeedPanel/FeedHeader
@onready var _feed_lines: VBoxContainer = $FeedPanel/FeedLines
@onready var _feed_scroll_hint: Label = $FeedPanel/FeedScrollHint

# Shop
@onready var _shop_panel: Panel = $ShopPanel
@onready var _shop_items_container: VBoxContainer = $ShopPanel/ShopItems

# Tutorial
@onready var _tutorial_overlay: Panel = $TutorialOverlay
@onready var _instruction_label: Label = $TutorialOverlay/InstructionLabel
@onready var _phase_label: Label = $TutorialOverlay/PhaseLabel
@onready var _reset_btn: Button = $ResetBtn


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_refresh_shop()
	Economy.currency_changed.connect(func(): _refresh_shop())

	# Style building action buttons
	_style_btn(_evict_btn, BUILDING_BUTTONS[0]["color"])
	_style_btn(_sell_btn, BUILDING_BUTTONS[1]["color"])
	_evict_btn.pressed.connect(func(): building_command_issued.emit("evict"))
	_sell_btn.pressed.connect(func(): building_command_issued.emit("sell"))

	# Tutorial reset
	_reset_btn.pressed.connect(_restart_tutorial)
	_style_btn(_reset_btn, Color(0.5, 0.15, 0.1))

	# Building icon custom draw
	_building_icon.draw.connect(_draw_building_icon)

	# Day/night bar proportions
	var day_frac: float = GameClock.DAY_DURATION / GameClock.CYCLE_DURATION
	_day_bg.anchor_right = day_frac
	_night_bg.anchor_left = day_frac
	_night_label.offset_left = 10.0  # relative offset after anchor

	# Feed click
	_feed_panel.gui_input.connect(_on_feed_input)

	# Score header labels
	for col_data in [["Faction", 120], ["Pop", 70], ["Stone", 80], ["Fish", 70], ["Rooms", 80], ["Score", 80]]:
		var lbl := Label.new()
		lbl.text = col_data[0]
		lbl.custom_minimum_size.x = col_data[1]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		_score_headers_box.add_child(lbl)

	# Position feed panel based on viewport
	_update_feed_position()
	_force_refresh_panels()


func _refresh_shop() -> void:
	_shop_items.clear()
	for id in Economy.get_shop_items():
		var item: Dictionary = Economy.get_shop_items()[id]
		_shop_items.append({"id": id, "name": item["name"], "cost": item["cost"], "desc": item["description"]})
	_rebuild_shop_items()


func set_command_menu_visible(show: bool) -> void:
	_cmd_menu_open = show
	if show:
		_building_menu_open = false
	if not show:
		_pending_command = ""
	_force_refresh_panels()


func set_building_menu_visible(show: bool, can_sell: bool = false) -> void:
	_building_menu_open = show
	_building_can_sell = can_sell
	if show:
		_cmd_menu_open = false
		_pending_command = ""
	_force_refresh_panels()


func get_pending_command() -> String:
	return _pending_command


func clear_pending_command() -> void:
	_pending_command = ""


func refresh_panels() -> void:
	_force_refresh_panels()


func _get_selection_signature() -> String:
	return var_to_str(selected_villager_info)


func _get_building_signature() -> String:
	return "%s|%s" % [var_to_str(selected_building_info), str(_building_can_sell)]


func _force_refresh_panels() -> void:
	_last_cmd_menu_open = not _cmd_menu_open
	_last_building_menu_open = not _building_menu_open
	_last_building_can_sell = not _building_can_sell
	_last_selection_signature = ""
	_last_building_signature = ""
	_maybe_refresh_panels()


func _maybe_refresh_panels() -> void:
	var selection_sig := _get_selection_signature()
	var building_sig := _get_building_signature()

	var menu_state_changed := (
		_cmd_menu_open != _last_cmd_menu_open
		or _building_menu_open != _last_building_menu_open
		or _building_can_sell != _last_building_can_sell
	)

	var selection_changed := selection_sig != _last_selection_signature
	var building_changed := building_sig != _last_building_signature

	_selection_panel.visible = _cmd_menu_open
	_building_panel.visible = _building_menu_open

	if _cmd_menu_open and (menu_state_changed or selection_changed):
		_update_selection_panel()

	if _building_menu_open and (menu_state_changed or building_changed):
		_update_building_panel()

	_last_cmd_menu_open = _cmd_menu_open
	_last_building_menu_open = _building_menu_open
	_last_building_can_sell = _building_can_sell
	_last_selection_signature = selection_sig
	_last_building_signature = building_sig


func _get_filtered_commands() -> Array:
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
			# Show command if ANY selected unit has the required color
			if types.has(req):
				result.append(btn)
	return result


func _process(_delta: float) -> void:
	_update_day_night_bar()
	_update_population_panel()
	_update_pending_command()
	_maybe_refresh_panels()
	_update_feed()
	_update_tutorial()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("toggle_shop"):
			_shop_open = not _shop_open
			_shop_panel.visible = _shop_open
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB:
			_score_open = not _score_open
			_update_score()
			get_viewport().set_input_as_handled()
			return


# ── Day/Night Bar Updates ────────────────────────────────────────

func _update_day_night_bar() -> void:
	var bar_w: float = $DayNightBar.size.x
	var progress: float = GameClock.get_cycle_progress()
	_progress_line.offset_left = progress * bar_w - 2.0
	_progress_line.offset_right = progress * bar_w + 2.0
	_time_label.text = GameClock.get_time_string()

	_paused_label.visible = GameClock.is_paused
	if GameClock.is_paused:
		var alpha: float = 0.8 + sin(Time.get_ticks_msec() * 0.003) * 0.2
		_paused_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, alpha))

	# Position night label after day region
	var day_frac: float = GameClock.DAY_DURATION / GameClock.CYCLE_DURATION
	_night_label.offset_left = day_frac * bar_w + 10.0
	_night_label.offset_right = _night_label.offset_left + 100.0


# ── Population Panel Updates ─────────────────────────────────────

func _update_population_panel() -> void:
	var fid: int = FactionManager.local_faction_id
	var sym: String = FactionManager.get_faction_symbol(fid)
	var fc: Color = FactionManager.get_faction_color(fid)
	_faction_label.text = "Faction %s" % sym
	_faction_label.add_theme_color_override("font_color", fc)

	_red_label.text = "● Red: %d" % pop_red
	_yellow_label.text = "● Yellow: %d" % pop_yellow
	_blue_label.text = "● Blue: %d" % pop_blue
	_colorless_label.text = "● Colorless: %d" % pop_colorless
	_enemies_label.text = "Enemies: %d" % pop_enemies
	_pop_label.text = "Pop: %d / %d" % [pop_total, pop_max_effective]

	var my_stone: int = Economy.get_stone(fid)
	var my_fish: int = Economy.get_fish(fid)
	var my_diamonds: int = Economy.get_diamonds(fid)
	_stone_label.text = "Stone: %d" % my_stone
	_fish_label.text = "Fish: %d  |  Diamonds: %d" % [my_fish, my_diamonds]


func _update_pending_command() -> void:
	_pending_cmd_label.visible = _pending_command != ""
	if _pending_command != "":
		_pending_cmd_label.text = "Click target for: %s" % _pending_command.to_upper()


# ── Panel Visibility & Content ───────────────────────────────────

func _update_selection_panel() -> void:
	var total: int = selected_villager_info.size()
	_selected_header.text = "SELECTED (%d)" % total

	# Type counts
	_clear_container(_type_counts)
	var type_counts: Dictionary = {}
	for info in selected_villager_info:
		var ct: String = info.get("color_type", "unknown")
		type_counts[ct] = type_counts.get(ct, 0) + 1
	for ct in type_counts:
		var def: Dictionary = ColorRegistry.get_def(ct)
		var col: Color = def.get("display_color", Color.WHITE)
		var lbl := Label.new()
		lbl.text = "● %s: %d" % [ct.capitalize(), type_counts[ct]]
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", col.lightened(0.3))
		_type_counts.add_child(lbl)

	# Villager details (small selections)
	_clear_container(_villager_details)
	if total == 1:
		# Single villager: show name prominently + color/level/hp
		var info: Dictionary = selected_villager_info[0]
		var col: Color = info.get("display_color", Color.WHITE)
		var hp: int = int(info.get("health", 0))
		var max_hp: int = int(info.get("max_health", 1))
		var name_lbl := Label.new()
		name_lbl.text = str(info.get("name", ""))
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		_villager_details.add_child(name_lbl)
		var stat_lbl := Label.new()
		stat_lbl.text = "%s  HP:%d/%d" % [str(info.get("color_type", "")).capitalize(), hp, max_hp]
		stat_lbl.add_theme_font_size_override("font_size", 12)
		stat_lbl.add_theme_color_override("font_color", col.lightened(0.3))
		_villager_details.add_child(stat_lbl)
	elif total <= 4:
		for info in selected_villager_info:
			var col: Color = info.get("display_color", Color.WHITE)
			var hp: int = int(info.get("health", 0))
			var max_hp: int = int(info.get("max_health", 1))
			var lbl := Label.new()
			lbl.text = "%s  HP:%d/%d" % [str(info.get("name", "")), hp, max_hp]
			lbl.add_theme_font_size_override("font_size", 12)
			lbl.add_theme_color_override("font_color", col.lightened(0.3))
			_villager_details.add_child(lbl)

	# Faction identity
	var faction_ids: Dictionary = {}
	for info in selected_villager_info:
		faction_ids[info.get("faction_id", -1)] = true

	var single_faction: bool = faction_ids.size() == 1 and not selected_villager_info.is_empty()
	_faction_bg.visible = single_faction
	_faction_symbol.visible = single_faction
	_faction_title.visible = single_faction
	_faction_name_label.visible = single_faction
	_mixed_faction_label.visible = not single_faction

	if single_faction:
		var fc: Color = selected_villager_info[0].get("faction_color", Color(0.5, 0.5, 0.5))
		var fsym: String = selected_villager_info[0].get("faction_symbol", "?")
		var fid: int = faction_ids.keys()[0]
		var fname: String = FactionManager.get_faction_name(fid) if fid >= 0 else "Unknown"
		_faction_bg.color = Color(fc.r, fc.g, fc.b, 0.14)
		_faction_symbol.text = fsym
		_faction_symbol.add_theme_color_override("font_color", fc)
		_faction_title.add_theme_color_override("font_color", Color(fc.r, fc.g, fc.b, 0.6))
		_faction_name_label.text = fname
		_faction_name_label.add_theme_color_override("font_color", fc)

	# Command buttons
	_rebuild_command_buttons()


func _rebuild_command_buttons() -> void:
	_clear_container(_commands_container)
	var filtered := _get_filtered_commands()
	for btn_data in filtered:
		var btn := Button.new()
		btn.text = btn_data["label"]
		btn.custom_minimum_size = Vector2(120, 36)
		_style_btn(btn, btn_data["color"])
		var cmd_id: String = btn_data["id"]
		btn.pressed.connect(func():
			if cmd_id in ["move", "attack", "stun", "house"]:
				_pending_command = cmd_id
			else:
				command_issued.emit(cmd_id)
		)
		_commands_container.add_child(btn)


func _update_building_panel() -> void:
	if selected_building_info.is_empty():
		return
	var btype: String = selected_building_info.get("type", "Building")
	var occ: int = selected_building_info.get("occupied", 0)
	var cap: int = selected_building_info.get("capacity", 4)
	var fc: Color = selected_building_info.get("faction_color", Color(0.5, 0.5, 0.5))
	var fsym: String = selected_building_info.get("faction_symbol", "?")

	_building_type.text = btype
	_building_sheltered.text = "Sheltered: %d / %d" % [occ, cap]
	_building_owner.text = "Owner: %s" % fsym
	_building_owner.add_theme_color_override("font_color", fc)
	_building_icon.queue_redraw()

	# Sell button state
	var sell_item_id: String = ""
	if btype == "Home":
		sell_item_id = "house"
	elif btype == "Church":
		sell_item_id = "church"
	elif btype == "Bank":
		sell_item_id = "bank"
	elif btype == "Fishing Hut":
		sell_item_id = "fishing_hut"

	var sell_val: int = Economy.get_sell_value(sell_item_id)
	var is_preplaced: bool = (selected_building_info.get("faction_id", -1) == -2)
	var disabled: bool = not _building_can_sell or is_preplaced

	_sell_btn.disabled = disabled
	if is_preplaced:
		_sell_btn.text = "Pre-placed"
	elif not _building_can_sell:
		_sell_btn.text = "Conquered"
	else:
		_sell_btn.text = "Sell ($%d)" % sell_val


func _draw_building_icon() -> void:
	if selected_building_info.is_empty():
		return
	var btype: String = selected_building_info.get("type", "")
	var cx: float = _building_icon.size.x * 0.5
	var cy: float = _building_icon.size.y * 0.5

	if btype == "Home":
		_building_icon.draw_rect(Rect2(cx - 26, cy - 8, 52, 32), Color(0.55, 0.4, 0.25, 0.8))
		_building_icon.draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy - 36), Vector2(cx + 32, cy - 8), Vector2(cx - 32, cy - 8)
		]), Color(0.6, 0.2, 0.15, 0.8))
	elif btype == "Church":
		_building_icon.draw_rect(Rect2(cx - 20, cy - 8, 40, 32), Color(0.35, 0.38, 0.5, 0.8))
		_building_icon.draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy - 40), Vector2(cx + 13, cy - 8), Vector2(cx - 13, cy - 8)
		]), Color(0.3, 0.35, 0.55, 0.8))
	elif btype == "Bank":
		_building_icon.draw_rect(Rect2(cx - 26, cy - 14, 52, 30), Color(0.4, 0.38, 0.32, 0.8))
		_building_icon.draw_circle(Vector2(cx, cy), 10.0, Color(0.5, 0.52, 0.48, 0.8))
	elif btype == "Fishing Hut":
		_building_icon.draw_rect(Rect2(cx - 26, cy - 10, 52, 26), Color(0.3, 0.25, 0.2, 0.8))
		_building_icon.draw_colored_polygon(PackedVector2Array([
			Vector2(cx, cy - 36), Vector2(cx + 30, cy - 10), Vector2(cx - 30, cy - 10)
		]), Color(0.25, 0.35, 0.5, 0.8))


# ── Score Overlay ────────────────────────────────────────────────

func _update_score() -> void:
	_score_overlay.visible = _score_open
	if not _score_open:
		return
	_clear_container(_score_rows)
	_score_overlay.offset_bottom = 100.0 + 60.0 + score_data.size() * 50.0

	for sd in score_data:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 44
		var row_col: Color = sd.get("color", Color.WHITE)
		var is_local: bool = (sd.get("faction_id", -1) == FactionManager.local_faction_id)
		var is_elim: bool = sd.get("eliminated", false)

		var sym_label := Label.new()
		sym_label.text = str(sd.get("symbol", "?"))
		sym_label.add_theme_font_size_override("font_size", 28)
		sym_label.add_theme_color_override("font_color", row_col)
		sym_label.custom_minimum_size.x = 40
		row.add_child(sym_label)

		var name_label := Label.new()
		name_label.text = str(sd.get("name", ""))
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(0.4, 0.35, 0.35) if is_elim else Color(0.75, 0.75, 0.75))
		name_label.custom_minimum_size.x = 80
		row.add_child(name_label)

		if is_elim:
			var elim_label := Label.new()
			elim_label.text = "ELIMINATED"
			elim_label.add_theme_font_size_override("font_size", 16)
			elim_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.3))
			row.add_child(elim_label)
		else:
			for col_data in [
				[str(sd.get("pop", 0)), 70, Color(0.8, 0.8, 0.8)],
				[str(sd.get("stone", 0)), 80, Color(0.6, 0.65, 0.55)],
				[str(sd.get("fish", 0)), 70, Color(0.4, 0.65, 0.8)],
				[str(sd.get("rooms", 0)), 80, Color(0.7, 0.7, 0.5)],
				[str(sd.get("score", 0)), 80, Color(0.85, 0.75, 0.4)],
			]:
				var val_label := Label.new()
				val_label.text = col_data[0]
				val_label.add_theme_font_size_override("font_size", 20)
				val_label.add_theme_color_override("font_color", col_data[2])
				val_label.custom_minimum_size.x = col_data[1]
				row.add_child(val_label)

		_score_rows.add_child(row)


# ── Event Feed ───────────────────────────────────────────────────

func _update_feed_position() -> void:
	_feed_panel.anchors_preset = 0
	_feed_panel.anchor_left = 1.0
	_feed_panel.anchor_right = 1.0
	_feed_panel.anchor_top = 0.3
	_feed_panel.anchor_bottom = 0.3
	_feed_panel.offset_left = -356.0
	_feed_panel.offset_right = -16.0
	_feed_panel.offset_top = 0.0


func _update_feed() -> void:
	var msgs: Array = EventFeed.messages
	var now: int = Time.get_ticks_msec()

	_feed_header.text = "Events (click to %s)" % ("collapse" if _feed_expanded else "expand")

	var current_sb = _feed_panel.get_theme_stylebox("panel")
	if current_sb is StyleBoxFlat:
		var feed_sb := current_sb.duplicate() as StyleBoxFlat
		if feed_sb:
			feed_sb.bg_color.a = 0.7 if _feed_expanded else 0.45
			_feed_panel.add_theme_stylebox_override("panel", feed_sb)

	var visible_count: int = FEED_VISIBLE_COUNT if not _feed_expanded else mini(20, msgs.size())
	var feed_h: float = maxf(visible_count * FEED_LINE_H + 40.0, 80.0)
	_feed_panel.offset_bottom = feed_h

	_clear_container(_feed_lines)

	if msgs.is_empty():
		var empty := Label.new()
		empty.text = "No events yet..."
		empty.add_theme_font_size_override("font_size", 20)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		_feed_lines.add_child(empty)
		_feed_scroll_hint.visible = false
		return

	var start_idx: int
	if _feed_expanded:
		start_idx = maxi(0, msgs.size() - visible_count - _feed_scroll)
	else:
		start_idx = maxi(0, msgs.size() - visible_count)
	var end_idx: int = mini(start_idx + visible_count, msgs.size())

	for i in range(start_idx, end_idx):
		var msg: Dictionary = msgs[i]
		var age: int = now - int(msg["time"])
		var alpha: float = 1.0
		if not _feed_expanded and age > FEED_FADE_TIME:
			alpha = maxf(0.15, 1.0 - float(age - FEED_FADE_TIME) / 4000.0)
		var col: Color = msg["color"]
		col.a = alpha
		var lbl := Label.new()
		lbl.text = str(msg["text"])
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", col)
		lbl.clip_text = true
		lbl.custom_minimum_size.x = 320
		_feed_lines.add_child(lbl)

	_feed_scroll_hint.visible = _feed_expanded and msgs.size() > visible_count


func _on_feed_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_feed_expanded = not _feed_expanded
		_feed_scroll = 0
		get_viewport().set_input_as_handled()
	elif _feed_expanded and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_feed_scroll = mini(_feed_scroll + 1, maxi(0, EventFeed.messages.size() - FEED_VISIBLE_COUNT))
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_feed_scroll = maxi(0, _feed_scroll - 1)
			get_viewport().set_input_as_handled()


# ── Shop ─────────────────────────────────────────────────────────

func _rebuild_shop_items() -> void:
	_clear_container(_shop_items_container)
	for item in _shop_items:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(290, 60)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var item_id: String = item["id"]
		var can: bool = Economy.can_afford(item_id)
		btn.text = "%s\n%s  |  %d stone" % [str(item["name"]), str(item["desc"]), int(item["cost"])]

		var bg_col: Color = Color(0.2, 0.25, 0.18, 0.6) if can else Color(0.15, 0.12, 0.12, 0.4)
		var hover_col: Color = Color(0.25, 0.35, 0.2, 0.8) if can else bg_col
		_style_btn_colors(btn, bg_col, hover_col)
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.85) if can else Color(0.5, 0.5, 0.5))

		btn.pressed.connect(func():
			if Economy.can_afford(item_id):
				buy_requested.emit(item_id)
		)
		_shop_items_container.add_child(btn)


# ── Tutorial Overlay ─────────────────────────────────────────────

func _update_tutorial() -> void:
	var active: bool = TutorialManager.active
	_tutorial_overlay.visible = active
	_reset_btn.visible = active
	if not active:
		return

	var instruction: String = TutorialManager.get_current_instruction()
	_instruction_label.text = instruction

	var phase_max: int = TutorialManager.PHASE_INSTRUCTIONS.size() - 1
	_phase_label.text = "Phase %d / %d  |  Press Escape to open menu (Quit to Main Menu available there)" % [TutorialManager.current_phase, phase_max]

	var current_sb = _tutorial_overlay.get_theme_stylebox("panel")
	if current_sb is StyleBoxFlat:
		var tut_sb := current_sb.duplicate() as StyleBoxFlat
		if tut_sb:
			if TutorialManager._pending_advance:
				tut_sb.bg_color = Color(0.0, 0.15, 0.0, 0.82)
				tut_sb.border_color = Color(0.4, 0.9, 0.4, 0.7)
			else:
				tut_sb.bg_color = Color(0.0, 0.0, 0.0, 0.78)
				tut_sb.border_color = Color(0.9, 0.85, 0.4, 0.6)
			_tutorial_overlay.add_theme_stylebox_override("panel", tut_sb)


func _restart_tutorial() -> void:
	TutorialManager.start_tutorial()
	call_deferred("_deferred_restart")


func _deferred_restart() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ── Helpers ──────────────────────────────────────────────────────

func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _style_btn(btn: Button, col: Color) -> void:
	_style_btn_colors(btn, col.darkened(0.2), col)


func _style_btn_colors(btn: Button, bg_normal: Color, bg_hover: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(bg_normal.r, bg_normal.g, bg_normal.b, maxf(bg_normal.a, 0.5))
	normal.border_color = Color(0.5, 0.5, 0.5, 0.4)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(4)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(bg_hover.r, bg_hover.g, bg_hover.b, maxf(bg_hover.a, 0.8))
	hover.border_color = Color(0.5, 0.5, 0.5, 0.4)
	hover.set_border_width_all(1)
	hover.set_content_margin_all(4)

	var pressed := hover.duplicate()

	var disabled_sb := StyleBoxFlat.new()
	disabled_sb.bg_color = Color(0.2, 0.2, 0.2, 0.3)
	disabled_sb.border_color = Color(0.3, 0.3, 0.3, 0.3)
	disabled_sb.set_border_width_all(1)
	disabled_sb.set_content_margin_all(4)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled_sb)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.95))
	btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4))
	btn.add_theme_font_size_override("font_size", 18)
