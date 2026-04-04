extends Node2D
## Main scene — 6-room grid with water (room 4) and breakable wall (room 5).

const ROOM_SIZE := Vector2(450.0, 450.0)
const ROOM_GAP := 8.0
const COLS := 3
const ROWS := 2
const ROOM_COUNT := 6

# Room 4 — water stripe (global coords, set in _ready)
var _water_rect := Rect2()
const WATER_LOCAL_X := 200.0
const WATER_WIDTH := 50.0

# Room 5 — breakable wall (global coords)
var _break_wall_rect := Rect2()
const BREAK_WALL_LOCAL_Y := 220.0
const BREAK_WALL_THICKNESS := 10.0
var breakable_wall_intact := true

var room_bounds: Array[Rect2] = []
var room_villagers: Dictionary = {}
var walls: Array = []
var villagers: Array = []

@onready var _villager_container: Node2D = $Villagers
@onready var _wall_container: Node2D = $Walls
@onready var _count_label: Label = $UI/CountLabel

var _villager_scene: PackedScene = preload("res://scenes/villager.tscn")


func _ready() -> void:
	_init_room_bounds()
	_init_obstacles()
	_collect_walls()
	_collect_villagers()
	InfluenceManager.villager_shifted.connect(_on_villager_shifted)


func _process(delta: float) -> void:
	_update_room_assignments()
	_check_breakable_wall()

	var wall_data: Array = []
	for w in walls:
		wall_data.append({"room_a": w.room_a_id, "room_b": w.room_b_id, "is_open": w.is_open})

	InfluenceManager.process_influence(room_villagers, wall_data, delta)
	queue_redraw()


# ── setup ────────────────────────────────────────────────────────────────────

func _init_room_bounds() -> void:
	# Layout:  Row0: [0] [1] [4]
	#          Row1: [2] [3] [5]
	var order := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 0), Vector2i(2, 1)]
	for idx in ROOM_COUNT:
		var col: int = order[idx].x
		var row: int = order[idx].y
		var origin := Vector2(col * (ROOM_SIZE.x + ROOM_GAP), row * (ROOM_SIZE.y + ROOM_GAP))
		room_bounds.append(Rect2(origin, ROOM_SIZE))
		room_villagers[idx] = []


func _init_obstacles() -> void:
	# Water stripe in room 4
	var r4 := room_bounds[4].position
	_water_rect = Rect2(r4.x + WATER_LOCAL_X, r4.y, WATER_WIDTH, ROOM_SIZE.y)
	# Breakable wall in room 5
	var r5 := room_bounds[5].position
	_break_wall_rect = Rect2(r5.x, r5.y + BREAK_WALL_LOCAL_Y, ROOM_SIZE.x, BREAK_WALL_THICKNESS)


func _collect_walls() -> void:
	for child in _wall_container.get_children():
		walls.append(child)


func _collect_villagers() -> void:
	for child in _villager_container.get_children():
		villagers.append(child)


# ── room assignment + obstacle injection ─────────────────────────────────────

func _update_room_assignments() -> void:
	for i in ROOM_COUNT:
		room_villagers[i] = []
	for v in villagers:
		var rid := _room_id_at(v.position)
		v.current_room_id = rid
		v.room_bounds = room_bounds[rid]
		v.blocked_rects = _get_blocked_rects(v.color_type, rid)
		room_villagers[rid].append(v)

	_update_count_label()


func _get_blocked_rects(color_id: String, rid: int) -> Array:
	var rects: Array = []
	# Water in room 4 — only blues can swim
	if rid == 4 and not ColorRegistry.has_ability(color_id, "swim"):
		rects.append(_water_rect)
	# Breakable wall in room 5 — blocks everyone except red (who breaks it)
	if rid == 5 and breakable_wall_intact:
		if not ColorRegistry.has_ability(color_id, "break_walls"):
			rects.append(_break_wall_rect)
	return rects


func _check_breakable_wall() -> void:
	if not breakable_wall_intact:
		return
	# Any red villager in room 5 touching the wall line breaks it
	var wall_y := _break_wall_rect.position.y + BREAK_WALL_THICKNESS * 0.5
	for v in room_villagers.get(5, []):
		if ColorRegistry.has_ability(v.color_type, "break_walls"):
			if absf(v.position.y - wall_y) < v.radius + BREAK_WALL_THICKNESS:
				breakable_wall_intact = false
				return


func _update_count_label() -> void:
	var counts: Dictionary = {}
	for v in villagers:
		counts[v.color_type] = counts.get(v.color_type, 0) + 1
	if _count_label:
		_count_label.text = "R:%d  Y:%d  B:%d  C:%d  Total:%d" % [
			counts.get("red", 0), counts.get("yellow", 0),
			counts.get("blue", 0), counts.get("colorless", 0),
			villagers.size()]


func _room_id_at(pos: Vector2) -> int:
	for i in room_bounds.size():
		if room_bounds[i].has_point(pos):
			return i
	var best := 0
	var best_d := INF
	for i in room_bounds.size():
		var d := pos.distance_squared_to(room_bounds[i].get_center())
		if d < best_d:
			best_d = d
			best = i
	return best


# ── shift handling ───────────────────────────────────────────────────────────

func _on_villager_shifted(villager, old_color, new_color, spawn_count) -> void:
	villager.set_color_type(str(new_color))
	for i in range(int(spawn_count) - 1):
		var offset := Vector2(randf_range(-40, 40), randf_range(-40, 40))
		_spawn_villager(str(new_color), villager.position + offset)


func _spawn_villager(color_id: String, pos: Vector2) -> void:
	var v := _villager_scene.instantiate()
	_villager_container.add_child(v)
	v.setup(color_id, pos)
	villagers.append(v)


# ── drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var labels := ["Room 1", "Room 2", "Room 3", "Room 4", "Room 5 (water)", "Room 6 (wall)"]
	for i in ROOM_COUNT:
		var pos := room_bounds[i].position + Vector2(8, 18)
		draw_string(ThemeDB.fallback_font, pos, labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.45, 0.45, 0.45, 0.6))

	# Outer border
	var total := Vector2(COLS * ROOM_SIZE.x + (COLS - 1) * ROOM_GAP,
						  ROWS * ROOM_SIZE.y + (ROWS - 1) * ROOM_GAP)
	draw_rect(Rect2(Vector2(-1, -1), total + Vector2(2, 2)), Color(0.3, 0.3, 0.3), false, 2.0)

	# ── Water stripe in room 4 ──
	draw_rect(_water_rect, Color(0.15, 0.35, 0.6, 0.45))
	# Wavy lines for texture
	var wy := _water_rect.position.y
	while wy < _water_rect.end.y:
		var wave_x := _water_rect.position.x + sin(wy * 0.08) * 6.0
		draw_line(Vector2(wave_x + 8, wy), Vector2(wave_x + WATER_WIDTH - 8, wy),
			Color(0.3, 0.55, 0.85, 0.25), 1.0)
		wy += 14.0

	# ── Breakable wall in room 5 ──
	if breakable_wall_intact:
		draw_rect(_break_wall_rect, Color(0.45, 0.3, 0.15))
		# Crack lines for style
		var cx := _break_wall_rect.position.x
		var cy := _break_wall_rect.position.y + BREAK_WALL_THICKNESS * 0.5
		while cx < _break_wall_rect.end.x:
			draw_line(Vector2(cx, cy - 3), Vector2(cx + 8, cy + 3),
				Color(0.3, 0.2, 0.1, 0.6), 1.0)
			cx += 25.0
	else:
		# Rubble hint
		var r5c := _break_wall_rect.get_center()
		draw_string(ThemeDB.fallback_font, Vector2(r5c.x - 30, r5c.y + 4),
			"[broken]", HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
			Color(0.5, 0.35, 0.2, 0.5))
