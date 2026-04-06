extends Node2D
## Main scene controller. Orchestrates all game systems.
## Procedurally generates rooms, walls, and entities from ROOM_DEFS data.

const ENEMY_DUPE_BASE := 0.2
const ENEMY_DUPE_MAX := 100.0
const ENEMY_DUPE_RANGE_MULT := 5.0
const TOUCH_DIST_BONUS := 4.0
const ENEMY_MERGE_COUNT := 4
const ENEMY_MERGE_DIST := 100.0
const BLUE_MERGE_COUNT := 3
const BLUE_MERGE_DIST := 120.0
const RED_LEVEL2_KILLS := 10
const RED_LEVEL3_KILLS := 30
const YELLOW_PAIR_DIST := 100.0
const HOME_SHELTER_DIST := 80.0
const CHURCH_INTAKE_RADIUS := 70.0
const RED_STARVE_DPS := 2.0
const DEMON_SPAWN_COUNT := 7
const ZOMBIE_SPAWN_COUNT := 5

# ==============================================================================
# MAP LAYOUT DATA — 12x8 grid, 9 distinct room sizes (Tetris-like variety)
# ==============================================================================
const CELL := 675
const MAP_GAP := 8

# [id, col, row, cells_w, cells_h, label, color]
const ROOM_DEFS := [
	[0,  0,  0, 2, 2, "Red Start",          Color(0.18, 0.12, 0.12, 0.35)],
	[1,  2,  0, 3, 2, "Yellow Plains",       Color(0.18, 0.17, 0.08, 0.35)],
	[2,  5,  0, 1, 2, "Narrow Pass",         Color(0.10, 0.16, 0.20, 0.35)],
	[3,  6,  0, 2, 2, "Enemy Den",           Color(0.12, 0.08, 0.08, 0.35)],
	[4,  8,  0, 2, 3, "Stone Field",         Color(0.14, 0.16, 0.12, 0.35)],
	[5,  10, 0, 2, 2, "Lookout",             Color(0.14, 0.14, 0.14, 0.35)],
	[6,  0,  2, 1, 3, "Blue Start",          Color(0.10, 0.13, 0.20, 0.35)],
	[7,  1,  2, 2, 2, "Gathering Hall",     Color(0.13, 0.13, 0.13, 0.35)],
	[8,  3,  2, 2, 1, "Short Corridor",      Color(0.14, 0.14, 0.14, 0.35)],
	[9,  3,  3, 2, 2, "Wanderer Camp",       Color(0.15, 0.14, 0.12, 0.35)],
	[10, 5,  2, 1, 3, "Tall Pass",           Color(0.10, 0.16, 0.20, 0.35)],
	[11, 6,  2, 2, 2, "Passage",             Color(0.14, 0.14, 0.14, 0.35)],
	[12, 8,  3, 2, 2, "Enemy Den",           Color(0.12, 0.08, 0.08, 0.35)],
	[13, 10, 2, 2, 3, "Flooded Quarry",      Color(0.10, 0.14, 0.16, 0.35)],
	[14, 0,  5, 1, 1, "Shallows",            Color(0.10, 0.15, 0.18, 0.35)],
	[15, 1,  4, 2, 2, "Stone Quarry",        Color(0.14, 0.16, 0.12, 0.35)],
	[16, 3,  5, 2, 2, "Walled Quarry",       Color(0.18, 0.14, 0.10, 0.35)],
	[17, 5,  5, 3, 2, "River Delta",         Color(0.08, 0.14, 0.20, 0.35)],
	[18, 8,  5, 2, 1, "Short Pass",          Color(0.14, 0.14, 0.14, 0.35)],
	[19, 8,  6, 4, 2, "Fortification",       Color(0.18, 0.14, 0.10, 0.35)],
	[20, 0,  6, 2, 2, "Enemy Den",           Color(0.12, 0.08, 0.08, 0.35)],
	[21, 2,  6, 1, 2, "Corridor",            Color(0.14, 0.14, 0.14, 0.35)],
	[22, 3,  7, 2, 1, "Wide Pass",           Color(0.13, 0.13, 0.13, 0.35)],
	[23, 5,  7, 3, 1, "Stone Mine",          Color(0.14, 0.16, 0.12, 0.35)],
	[24, 6,  4, 2, 1, "Wide Corridor",       Color(0.13, 0.13, 0.13, 0.35)],
	[25, 10, 5, 2, 1, "Overlook",            Color(0.14, 0.14, 0.14, 0.35)],
]

# River fish production
const RIVER_ROOM_ID := 6
const RIVER_FISH_MAX := 4
const RIVER_FISH_INTERVAL := 1800.0  # 1 fish per full day/night cycle
const COLORLESS_ATTRACT_RANGE := 350.0  # colorless path toward controlled villagers within this

var _river_fish_timer: float = 0.0
var _dev_fog_off: bool = false

# room_id -> array of spawn dicts
const SPAWN_RULES := {
	0:  [{"type": "villager", "color": "red", "count": 1, "fed": true}, {"type": "magic_orb", "count": 1}],
	1:  [{"type": "villager", "color": "yellow", "count": 1}, {"type": "bank", "count": 1}],
	3:  [{"type": "enemy", "count": 2}],
	4:  [{"type": "stone", "count": 15}],
	5:  [{"type": "stone", "count": 5}],
	6:  [{"type": "villager", "color": "blue", "count": 1}, {"type": "fishing_hut", "count": 1}, {"type": "river", "count": 1}, {"type": "fish", "count": 2}],
	9:  [{"type": "villager", "color": "colorless", "count": 4}],
	12: [{"type": "enemy", "count": 2}],
	13: [{"type": "stone", "count": 10}],
	15: [{"type": "stone", "count": 15}],
	17: [{"type": "fish", "count": 15}, {"type": "fishing_hut", "count": 1}],
	19: [{"type": "stone", "count": 8}],
	20: [{"type": "enemy", "count": 2}],
	23: [{"type": "stone", "count": 12}],
}

var rooms: Array = []
var room_map: Dictionary = {}
var walls: Array = []
var villagers: Array = []
var enemies: Array = []
var night_enemies: Array = []
var collectables: Array = []
var fish_spots: Array = []
var homes: Array = []
var banks: Array = []
var fishing_huts: Array = []
var churches: Array = []

var _selected_resource: Node = null
var _selected_resource_type: String = ""

var room_villagers: Dictionary = {}
var room_enemies: Dictionary = {}

@onready var _rooms_container: Node2D = $Rooms
@onready var _wall_container: Node2D = $Walls
@onready var _villager_container: Node2D = $Villagers
@onready var _enemy_container: Node2D = $Enemies
@onready var _collectables_container: Node2D = $Collectables
@onready var _fish_container: Node2D = $FishSpots
@onready var _homes_container: Node2D = $Homes
@onready var _banks_container: Node2D = $Banks
@onready var _huts_container: Node2D = $FishingHuts
@onready var _churches_container: Node2D = _get_or_create_container("Churches")
@onready var _fog_overlay: Node2D = $FogOverlay
@onready var _camera: Camera2D = $Camera
@onready var _hud: Control = $UI/HUD

var _villager_scene: PackedScene = preload("res://scenes/villager.tscn")
var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
var _demon_scene: PackedScene = preload("res://scenes/demon.tscn")
var _zombie_scene: PackedScene = preload("res://scenes/zombie.tscn")
var _home_scene: PackedScene = preload("res://scenes/home.tscn")
var _church_scene: PackedScene = preload("res://scenes/church.tscn")
var _collectable_scene: PackedScene = preload("res://scenes/collectable.tscn")
var _fish_scene: PackedScene = preload("res://scenes/fish_spot.tscn")
var _room_scene: PackedScene = preload("res://scenes/room.tscn")
var _wall_scene: PackedScene = preload("res://scenes/wall_segment.tscn")
var _placing_item: String = ""


func _ready() -> void:
	_generate_map()
	_collect_all()
	_init_camera()
	# Starting resources
	Economy.stone = 5
	Economy.fish = 3
	InfluenceManager.villager_shifted.connect(_on_villager_shifted)
	GameClock.phase_changed.connect(_on_phase_changed)
	NightEvents.connect_to_clock()
	NightEvents.night_event_started.connect(_on_night_event)
	NightEvents.night_event_ended.connect(_on_night_event_end)
	_hud.buy_requested.connect(_on_buy_requested)
	if SaveManager.has_save():
		call_deferred("_try_load_save")


func _try_load_save() -> void:
	SaveManager.load_game(self)
	_update_fog_and_camera()


# ==============================================================================
# MAP GENERATION
# ==============================================================================

func _room_pixel_pos(col: int, row: int) -> Vector2:
	return Vector2(col * (CELL + MAP_GAP), row * (CELL + MAP_GAP))


func _room_pixel_size(cw: int, ch: int) -> Vector2:
	return Vector2(cw * CELL + (cw - 1) * MAP_GAP, ch * CELL + (ch - 1) * MAP_GAP)


func _generate_map() -> void:
	_generate_rooms()
	_generate_walls()
	_generate_entities()


func _generate_rooms() -> void:
	for def in ROOM_DEFS:
		var r = _room_scene.instantiate()
		r.room_id = def[0]
		r.room_size = _room_pixel_size(def[3], def[4])
		r.room_label = def[5]
		r.room_color = def[6]
		r.position = _room_pixel_pos(def[1], def[2])
		_rooms_container.add_child(r)
		# Populate room_map early so _generate_entities can reference rooms
		room_map[def[0]] = r


func _generate_walls() -> void:
	# Build occupancy: map each grid cell to room_id
	var grid: Dictionary = {}  # Vector2i(col, row) -> room_id
	for def in ROOM_DEFS:
		var rid: int = def[0]
		for dx in def[3]:
			for dy in def[4]:
				grid[Vector2i(def[1] + dx, def[2] + dy)] = rid

	# Find adjacent room pairs and compute shared wall edges
	var wall_pairs: Dictionary = {}  # "a_b" -> {pos, start, end, orientation}
	for cell in grid:
		var rid_a: int = grid[cell]
		# Check right neighbor
		var right := Vector2i(cell.x + 1, cell.y)
		if grid.has(right) and grid[right] != rid_a:
			var rid_b: int = grid[right]
			var key: String = "%d_%d" % [mini(rid_a, rid_b), maxi(rid_a, rid_b)]
			if not wall_pairs.has(key):
				wall_pairs[key] = {"a": mini(rid_a, rid_b), "b": maxi(rid_a, rid_b), "cells": [], "orient": "v"}
			wall_pairs[key]["cells"].append(cell)
		# Check bottom neighbor
		var below := Vector2i(cell.x, cell.y + 1)
		if grid.has(below) and grid[below] != rid_a:
			var rid_b: int = grid[below]
			var key: String = "%d_%d" % [mini(rid_a, rid_b), maxi(rid_a, rid_b)]
			if not wall_pairs.has(key):
				wall_pairs[key] = {"a": mini(rid_a, rid_b), "b": maxi(rid_a, rid_b), "cells": [], "orient": "h"}
			wall_pairs[key]["cells"].append(cell)

	for key in wall_pairs:
		var wp: Dictionary = wall_pairs[key]
		var cells: Array = wp["cells"]
		var start_pos: Vector2
		var end_pos: Vector2

		if wp["orient"] == "v":
			# Vertical wall: right edge of left room
			cells.sort_custom(func(a, b): return a.y < b.y)
			var col: int = cells[0].x
			var min_row: int = cells[0].y
			var max_row: int = cells[cells.size() - 1].y
			var x: float = (col + 1) * (CELL + MAP_GAP) - MAP_GAP / 2.0
			start_pos = Vector2(x, min_row * (CELL + MAP_GAP))
			end_pos = Vector2(x, (max_row + 1) * (CELL + MAP_GAP) - MAP_GAP)
		else:
			# Horizontal wall: bottom edge of top room
			cells.sort_custom(func(a, b): return a.x < b.x)
			var row: int = cells[0].y
			var min_col: int = cells[0].x
			var max_col: int = cells[cells.size() - 1].x
			var y: float = (row + 1) * (CELL + MAP_GAP) - MAP_GAP / 2.0
			start_pos = Vector2(min_col * (CELL + MAP_GAP), y)
			end_pos = Vector2((max_col + 1) * (CELL + MAP_GAP) - MAP_GAP, y)

		var w = _wall_scene.instantiate()
		w.room_a_id = wp["a"]
		w.room_b_id = wp["b"]
		w.start_pos = start_pos
		w.end_pos = end_pos
		_wall_container.add_child(w)


func _generate_entities() -> void:
	for rid in SPAWN_RULES:
		var room_def: Array = _find_room_def(rid)
		if room_def.is_empty():
			continue
		var rpos: Vector2 = _room_pixel_pos(room_def[1], room_def[2])
		var rsize: Vector2 = _room_pixel_size(room_def[3], room_def[4])
		var center: Vector2 = rpos + rsize * 0.5
		var rules: Array = SPAWN_RULES[rid]

		for rule in rules:
			var count: int = int(rule.get("count", 1))
			match str(rule["type"]):
				"villager":
					for i in count:
						var v = _villager_scene.instantiate()
						_villager_container.add_child(v)
						v.setup(str(rule["color"]), center + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
						v.resource_dropped.connect(_on_villager_dropped_resource)
						if rule.get("fed", false):
							v._satiation_timer = v.SATIATION_PER_LEVEL[1]  # fed for 1 day
							v.is_fed = true
				"magic_orb":
					var orb = _villager_scene.instantiate()
					_villager_container.add_child(orb)
					orb.setup("magic_orb", center)
					orb.resource_dropped.connect(_on_villager_dropped_resource)
				"enemy":
					for i in count:
						var e = _enemy_scene.instantiate()
						_enemy_container.add_child(e)
						e.global_position = _rand_in_room(rpos, rsize, 100.0)
				"stone":
					for i in count:
						var c = _collectable_scene.instantiate()
						_collectables_container.add_child(c)
						c.global_position = _rand_in_room(rpos, rsize, 60.0)
				"fish":
					for i in count:
						var f = _fish_scene.instantiate()
						_fish_container.add_child(f)
						f.global_position = _rand_in_room(rpos, rsize, 60.0)
				"bank":
					var b_scene: PackedScene = preload("res://scenes/bank.tscn")
					var b = b_scene.instantiate()
					_banks_container.add_child(b)
					b.global_position = Vector2(center.x, rpos.y + 200)
				"fishing_hut":
					var h_scene: PackedScene = preload("res://scenes/fishing_hut.tscn")
					var h = h_scene.instantiate()
					_huts_container.add_child(h)
					h.global_position = Vector2(rpos.x + rsize.x - 200, center.y)
				"river":
					var r_scene: PackedScene = preload("res://scenes/obstacles/river_obstacle.tscn")
					var river = r_scene.instantiate()
					var room_node = room_map.get(rid)
					if room_node:
						room_node.add_child(river)
						river.position = Vector2(50, 50)


func _find_room_def(rid: int) -> Array:
	for def in ROOM_DEFS:
		if def[0] == rid:
			return def
	return []


func _rand_in_room(rpos: Vector2, rsize: Vector2, margin: float) -> Vector2:
	return Vector2(
		randf_range(rpos.x + margin, rpos.x + rsize.x - margin),
		randf_range(rpos.y + margin, rpos.y + rsize.y - margin))


# ==============================================================================
# CAMERA + FOG
# ==============================================================================

func _init_camera() -> void:
	# Center camera on starting room
	var def: Array = _find_room_def(0)
	if not def.is_empty():
		var rpos: Vector2 = _room_pixel_pos(def[1], def[2])
		var rsize: Vector2 = _room_pixel_size(def[3], def[4])
		_camera.position = rpos + rsize * 0.5
	_camera.zoom = Vector2(0.8, 0.8)
	_update_fog_and_camera()


func _compute_map_bounds() -> Rect2:
	if rooms.is_empty():
		return Rect2()
	var bounds: Rect2 = rooms[0].get_rect()
	for i in range(1, rooms.size()):
		bounds = bounds.merge(rooms[i].get_rect())
	return bounds


func _compute_explored_bounds() -> Rect2:
	var found := false
	var bounds := Rect2()
	for room in rooms:
		if FogOfWar.is_explored(room.room_id):
			if not found:
				bounds = room.get_rect()
				found = true
			else:
				bounds = bounds.merge(room.get_rect())
	return bounds


func _update_fog_and_camera() -> void:
	# Update which rooms are active (have a controlled villager right now)
	# Colorless villagers do NOT give visibility
	FogOfWar.clear_active()
	for v in villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		if str(v.color_type) == "colorless":
			continue  # colorless don't reveal rooms
		FogOfWar.mark_active(v.current_room_id)

	# Hide entities in non-active rooms (resources + enemies invisible without villager)
	_update_entity_visibility()

	# Update camera bounds
	var mb: Rect2 = _compute_map_bounds()
	var eb: Rect2
	if _dev_fog_off:
		eb = mb  # full map visible when dev fog is off
	else:
		eb = _compute_explored_bounds()
	_camera.update_bounds(mb, eb)

	# Redraw fog overlay
	_fog_overlay.queue_redraw()


func _update_entity_visibility() -> void:
	# When dev fog is off, everything is visible
	if _dev_fog_off:
		for c in collectables:
			if is_instance_valid(c): c.visible = true
		for f in fish_spots:
			if is_instance_valid(f): f.visible = true
		for e in enemies:
			if is_instance_valid(e): e.visible = true
		for ne in night_enemies:
			if is_instance_valid(ne): ne.visible = true
		return
	# Resources: only visible in active rooms
	for c in collectables:
		if not is_instance_valid(c) or c.collected:
			continue
		c.visible = FogOfWar.is_active(_room_id_at(c.global_position))
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected:
			continue
		f.visible = FogOfWar.is_active(_room_id_at(f.global_position))
	# Enemies: only visible in active rooms
	for e in enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		e.visible = FogOfWar.is_active(e.current_room_id)
	for ne in night_enemies:
		if not is_instance_valid(ne) or ne.is_dead:
			continue
		ne.visible = FogOfWar.is_active(ne.current_room_id)


func _get_or_create_container(node_name: String) -> Node2D:
	var n = get_node_or_null(node_name)
	if n:
		return n
	n = Node2D.new()
	n.name = node_name
	add_child(n)
	return n


func _collect_all() -> void:
	_collect_rooms()
	_collect_walls()
	_collect_villagers()
	_collect_enemies()

	collectables.clear()
	for c in _collectables_container.get_children():
		collectables.append(c)

	fish_spots.clear()
	for f in _fish_container.get_children():
		fish_spots.append(f)

	homes.clear()
	for h in _homes_container.get_children():
		homes.append(h)

	banks.clear()
	for b in _banks_container.get_children():
		banks.append(b)

	fishing_huts.clear()
	for h in _huts_container.get_children():
		fishing_huts.append(h)

	churches.clear()
	for c in _churches_container.get_children():
		churches.append(c)


func _collect_rooms() -> void:
	rooms.clear()
	room_map.clear()
	for child in _rooms_container.get_children():
		if child.has_method("get_rect"):
			rooms.append(child)
			room_map[child.room_id] = child
			room_villagers[child.room_id] = []
			room_enemies[child.room_id] = []


func _collect_walls() -> void:
	walls.clear()
	for w in _wall_container.get_children():
		walls.append(w)


func _collect_villagers() -> void:
	villagers.clear()
	for v in _villager_container.get_children():
		villagers.append(v)
		if not v.resource_dropped.is_connected(_on_villager_dropped_resource):
			v.resource_dropped.connect(_on_villager_dropped_resource)


func _collect_enemies() -> void:
	enemies.clear()
	for e in _enemy_container.get_children():
		enemies.append(e)


# ==============================================================================
# MAIN LOOP
# ==============================================================================

func _process(delta: float) -> void:
	EventFeed.check_time_events()
	_assign_entities_to_rooms()
	_update_fog_and_camera()
	_update_obstacles()
	_update_brain_context()
	_process_stone_pickups()
	_process_fish_pickups()
	_process_deposits()
	_process_enemy_attacks(delta)
	_process_night_enemy_attacks(delta)
	_process_red_shooting()
	_process_red_hunger(delta)
	_process_church_healing(delta)
	_process_church_intake()
	_process_building_influence(delta)
	_process_enemy_duplication(delta)
	_process_enemy_merging()
	_process_red_leveling()
	_process_blue_merging()
	_process_yellow_leveling(delta)
	_process_home_sheltering()
	_process_river_fish(delta)
	_clean_selected_resource()

	var wall_data: Array = []
	for w in walls:
		wall_data.append({"room_a": w.room_a_id, "room_b": w.room_b_id, "is_open": w.is_open})

	InfluenceManager.process_influence(room_villagers, wall_data, delta)
	_update_hud()
	queue_redraw()


func _clean_selected_resource() -> void:
	if _selected_resource != null:
		if not is_instance_valid(_selected_resource) or _selected_resource.collected:
			_selected_resource = null
			_selected_resource_type = ""


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			SaveManager.save_game(self)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_ESCAPE:
			SaveManager.save_game(self)
			get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_0:
			_dev_fog_off = not _dev_fog_off
			var label := "FOG OFF" if _dev_fog_off else "FOG ON"
			EventFeed.push("[DEV] %s" % label, Color(1, 1, 0))
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	if _placing_item != "":
		_finalize_placement(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _placing_item != "":
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
		if _selected_resource != null:
			_selected_resource = null
			_selected_resource_type = ""
			get_viewport().set_input_as_handled()
			return

	var click_pos: Vector2 = get_global_mouse_position()

	if _selected_resource != null:
		for v in villagers:
			if click_pos.distance_to(v.global_position) < float(v.radius) + 10.0:
				var matched: bool = false
				if _selected_resource_type == "stone" and str(v.color_type) == "yellow":
					matched = true
				elif _selected_resource_type == "fish" and str(v.color_type) == "blue":
					matched = true
				if matched and not v.is_carrying():
					v.waypoint_target_pos = _selected_resource.global_position
					v.has_waypoint = true
					EventFeed.push("Villager sent to gather.", Color(0.7, 0.8, 0.6))
					_selected_resource = null
					_selected_resource_type = ""
					get_viewport().set_input_as_handled()
					return
		_selected_resource = null
		_selected_resource_type = ""
		return

	for c in collectables:
		if not is_instance_valid(c) or c.collected:
			continue
		if click_pos.distance_to(c.global_position) < 20.0:
			_selected_resource = c
			_selected_resource_type = "stone"
			get_viewport().set_input_as_handled()
			return
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected:
			continue
		if click_pos.distance_to(f.global_position) < 20.0:
			_selected_resource = f
			_selected_resource_type = "fish"
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	if _placing_item != "":
		var m: Vector2 = get_local_mouse_position()
		if _placing_item == "house":
			draw_rect(Rect2(m.x - 32, m.y - 16, 64, 52), Color(0.55, 0.4, 0.25, 0.4))
			draw_colored_polygon(PackedVector2Array([
				Vector2(m.x, m.y - 40), Vector2(m.x + 40, m.y - 16), Vector2(m.x - 40, m.y - 16)]),
				Color(0.6, 0.2, 0.15, 0.4))
		elif _placing_item == "church":
			draw_rect(Rect2(m.x - 42, m.y - 18, 84, 54), Color(0.35, 0.38, 0.5, 0.4))
			draw_colored_polygon(PackedVector2Array([
				Vector2(m.x, m.y - 50), Vector2(m.x + 14, m.y - 18), Vector2(m.x - 14, m.y - 18)]),
				Color(0.3, 0.35, 0.55, 0.4))
		draw_string(ThemeDB.fallback_font, Vector2(m.x - 40, m.y + 50),
			"Click to place  |  Right-click cancel",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.7, 0.7))

	if _selected_resource != null and is_instance_valid(_selected_resource):
		var sp: Vector2 = _selected_resource.global_position
		var pulse: float = 0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.4
		var sel_color: Color = Color(0.94, 0.84, 0.12, pulse) if _selected_resource_type == "stone" else Color(0.2, 0.4, 0.9, pulse)
		draw_arc(sp, 22.0, 0.0, TAU, 24, sel_color, 2.5, true)
		var hint_color: String = "yellow" if _selected_resource_type == "stone" else "blue"
		draw_string(ThemeDB.fallback_font, Vector2(sp.x - 40, sp.y - 24),
			"Click a %s villager" % hint_color,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.9, 0.9, 0.8, pulse))


func _finalize_placement(pos: Vector2) -> void:
	if _placing_item == "house":
		var h = _home_scene.instantiate()
		_homes_container.add_child(h)
		h.global_position = pos
		homes.append(h)
		EventFeed.push("Home built.", Color(0.7, 0.6, 0.4))
	elif _placing_item == "church":
		var c = _church_scene.instantiate()
		_churches_container.add_child(c)
		c.global_position = pos
		churches.append(c)
		EventFeed.push("Church built.", Color(0.5, 0.6, 0.85))
	_placing_item = ""


func _cancel_placement() -> void:
	if _placing_item == "house":
		Economy.stone += 5
	elif _placing_item == "church":
		Economy.stone += 50
	_placing_item = ""


# ==============================================================================
# ROOM ASSIGNMENT
# ==============================================================================

func _assign_entities_to_rooms() -> void:
	for rid in room_villagers:
		room_villagers[rid] = []
		room_enemies[rid] = []

	for v in villagers:
		var rid: int = _room_id_at(v.global_position)
		v.current_room_id = rid
		if room_map.has(rid):
			v.room_bounds = room_map[rid].get_rect()
		room_villagers[rid].append(v)

	var all_enemies: Array = enemies.duplicate()
	all_enemies.append_array(night_enemies)
	for e in all_enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var rid: int = _room_id_at(e.global_position)
		e.current_room_id = rid
		if room_map.has(rid):
			e.room_bounds = room_map[rid].get_rect()
		room_enemies[rid].append(e)


func _room_id_at(pos: Vector2) -> int:
	for room in rooms:
		if room.get_rect().has_point(pos):
			return int(room.room_id)
	var best_id: int = 0
	var best_d: float = INF
	for room in rooms:
		var d: float = pos.distance_squared_to(room.get_rect().get_center())
		if d < best_d:
			best_d = d
			best_id = int(room.room_id)
	return best_id


# ==============================================================================
# BRAIN CONTEXT
# ==============================================================================

func _update_brain_context() -> void:
	for v in villagers:
		var rid: int = v.current_room_id
		v.brain_enemies = room_enemies.get(rid, [])
		v.brain_room_villagers = room_villagers.get(rid, [])
		v.has_deposit_in_room = false
		v.brain_has_resource = false
		v.brain_has_church = false
		v.has_attract_target = false

		match str(v.color_type):
			"yellow":
				var best_d: float = INF
				for c in collectables:
					if not is_instance_valid(c) or c.collected:
						continue
					if _room_id_at(c.global_position) != rid:
						continue
					var d: float = v.global_position.distance_to(c.global_position)
					if d < best_d:
						best_d = d
						v.brain_nearest_resource_pos = c.global_position
						v.brain_has_resource = true
				if str(v.carrying_resource) == "stone":
					for b in banks:
						if _room_id_at(b.global_position) == rid:
							v.deposit_position = b.global_position
							v.has_deposit_in_room = true
							break
					if not v.has_deposit_in_room and banks.size() > 0:
						var bd: float = INF
						for b in banks:
							var d2: float = v.global_position.distance_to(b.global_position)
							if d2 < bd:
								bd = d2
								v.deposit_position = b.global_position
			"blue":
				for ch in churches:
					if ch.is_full():
						continue
					v.brain_church_pos = ch.global_position
					v.brain_has_church = true
					break
				var best_d: float = INF
				for f in fish_spots:
					if not is_instance_valid(f) or f.collected:
						continue
					if _room_id_at(f.global_position) != rid:
						continue
					var d: float = v.global_position.distance_to(f.global_position)
					if d < best_d:
						best_d = d
						v.brain_nearest_resource_pos = f.global_position
						v.brain_has_resource = true
				if str(v.carrying_resource) == "fish":
					for h in fishing_huts:
						if _room_id_at(h.global_position) == rid:
							v.deposit_position = h.global_position
							v.has_deposit_in_room = true
							break
					if not v.has_deposit_in_room and fishing_huts.size() > 0:
						var hd: float = INF
						for h in fishing_huts:
							var d2: float = v.global_position.distance_to(h.global_position)
							if d2 < hd:
								hd = d2
								v.deposit_position = h.global_position

	for v in villagers:
		if v.has_waypoint:
			if v.is_carrying() or v.global_position.distance_to(v.waypoint_target_pos) < float(v.radius) + 20.0:
				v.has_waypoint = false

	# Colorless attraction: find nearest controlled villager within range
	for v in villagers:
		if str(v.color_type) != "colorless":
			continue
		var best_d: float = COLORLESS_ATTRACT_RANGE
		for other in villagers:
			if not is_instance_valid(other) or other == v:
				continue
			if str(other.color_type) == "colorless":
				continue
			var d: float = v.global_position.distance_to(other.global_position)
			if d < best_d:
				best_d = d
				v.colorless_attract_pos = other.global_position
				v.has_attract_target = true

	for ne in night_enemies:
		if not is_instance_valid(ne) or ne.is_dead:
			continue
		ne.brain_villagers = room_villagers.get(ne.current_room_id, [])


# ==============================================================================
# OBSTACLES + RESOURCES + DEPOSITS
# ==============================================================================

func _update_obstacles() -> void:
	var checked: Dictionary = {}
	for v in villagers:
		var room = room_map.get(v.current_room_id)
		if room:
			v.blocked_rects = room.get_blocked_rects_for(v.color_type)
			if not checked.has(v.current_room_id):
				checked[v.current_room_id] = true
				for child in room.get_children():
					if child.has_method("check_break"):
						child.check_break(room_villagers.get(v.current_room_id, []))


func _process_stone_pickups() -> void:
	var rm: Array = []
	for c in collectables:
		if not is_instance_valid(c) or c.collected:
			rm.append(c)
			continue
		for v in villagers:
			if c.try_collect(v):
				break
	for c in rm:
		collectables.erase(c)


func _process_fish_pickups() -> void:
	var rm: Array = []
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected:
			rm.append(f)
			continue
		for v in villagers:
			if f.try_collect(v):
				break
	for f in rm:
		fish_spots.erase(f)


func _process_deposits() -> void:
	for b in banks:
		for v in villagers:
			if str(v.carrying_resource) == "stone":
				b.try_deposit(v)
	for h in fishing_huts:
		for v in villagers:
			if str(v.carrying_resource) == "fish":
				h.try_deposit(v)


# ==============================================================================
# CHURCH
# ==============================================================================

func _process_church_healing(delta: float) -> void:
	for ch in churches:
		ch.heal_tick(delta)


func _process_church_intake() -> void:
	if not GameClock.is_daytime:
		return
	for ch in churches:
		if ch.is_full():
			continue
		for v in villagers:
			if not v.visible:
				continue
			if str(v.color_type) != "blue":
				continue
			if v.health >= v.max_health:
				continue
			if v.global_position.distance_to(ch.global_position) < CHURCH_INTAKE_RADIUS:
				ch.shelter_villager(v)


func _process_building_influence(delta: float) -> void:
	var building_groups: Array = []
	for h in homes:
		if h.get_sheltered_count() > 1:
			building_groups.append(h.sheltered)
	for ch in churches:
		if ch.get_sheltered_count() > 1:
			building_groups.append(ch.sheltered)
	for group in building_groups:
		var valid: Array = []
		for v in group:
			if is_instance_valid(v):
				valid.append(v)
		if valid.size() < 2:
			continue
		InfluenceManager.process_building_group(valid, delta)


# ==============================================================================
# HUNGER
# ==============================================================================

func _process_red_hunger(delta: float) -> void:
	var starving: Array = []
	for v in villagers:
		if str(v.color_type) != "red":
			continue
		if v._satiation_timer > 0.0:
			v._satiation_timer -= delta
			v.is_fed = true
		else:
			if Economy.fish > 0:
				Economy.fish -= 1
				v.is_fed = true
				v._satiation_timer = v.SATIATION_PER_LEVEL[clampi(v.level, 1, 3)]
			else:
				v.is_fed = false
				v.health -= RED_STARVE_DPS * delta
				if v.health <= 0.0:
					starving.append(v)
	for v in starving:
		villagers.erase(v)
		v.start_death_animation()
		EventFeed.push("A red villager starved to death.", Color(0.85, 0.3, 0.25))


# ==============================================================================
# COMBAT
# ==============================================================================

func _process_enemy_attacks(_delta: float) -> void:
	var dead: Array = []
	for rid in room_enemies:
		for enemy in room_enemies[rid]:
			var enemy_type = enemy.get("enemy_type")
			if enemy_type != null and enemy_type != "":
				continue
			for v in room_villagers.get(rid, []):
				var dist: float = enemy.global_position.distance_to(v.global_position)
				if dist > float(enemy.radius) + float(v.radius) + TOUCH_DIST_BONUS:
					continue
				if str(v.color_type) == "red":
					continue
				var result: String = enemy.try_attack(v)
				if result == "kill" and v not in dead:
					dead.append(v)
	for v in dead:
		villagers.erase(v)
		EventFeed.push("A %s villager was killed by an enemy." % str(v.color_type), Color(0.8, 0.25, 0.2))
		v.queue_free()


func _process_night_enemy_attacks(_delta: float) -> void:
	var dead_v: Array = []
	var dead_ne: Array = []
	var to_convert: Array = []

	for ne in night_enemies:
		if not is_instance_valid(ne) or ne.is_dead:
			continue
		for v in room_villagers.get(ne.current_room_id, []):
			var dist: float = ne.global_position.distance_to(v.global_position)
			if dist > float(ne.radius) + float(v.radius) + TOUCH_DIST_BONUS:
				continue
			var result: String = ne.try_attack(v)
			if result == "kill" and v not in dead_v:
				dead_v.append(v)
			elif result == "convert" and v not in dead_v:
				to_convert.append(v.global_position)
				dead_v.append(v)

	for v in dead_v:
		villagers.erase(v)
		EventFeed.push("A villager was lost in the night.", Color(0.6, 0.3, 0.5))
		v.queue_free()
	for pos in to_convert:
		_spawn_night_enemy("zombie", pos)
	for ne in dead_ne:
		night_enemies.erase(ne)
		ne.die()


func _process_red_shooting() -> void:
	var dead: Array = []
	for v in villagers:
		if str(v.color_type) != "red":
			continue
		var target: Node = v.shoot_target_enemy
		if target == null or not is_instance_valid(target) or target.is_dead:
			continue
		var killed: bool = target.take_red_hit(int(v.level))
		v.record_kill()
		v.shoot_target_enemy = null
		if killed and target not in dead:
			dead.append(target)
	for e in dead:
		if e in enemies:
			enemies.erase(e)
		if e in night_enemies:
			night_enemies.erase(e)
		e.die()


# ==============================================================================
# NIGHT EVENTS
# ==============================================================================

func _on_phase_changed(is_daytime: bool) -> void:
	if is_daytime:
		for h in homes:
			h.release_all()
		for ch in churches:
			ch.release_all()
		_despawn_night_enemies()
	else:
		_auto_shelter_villagers()


func _on_night_event(event_id: String) -> void:
	match event_id:
		"demon_hunt":
			_spawn_night_wave("demon", DEMON_SPAWN_COUNT)
			EventFeed.push("Demons emerge from the shadows!", Color(0.7, 0.2, 0.5))
		"zombie_plague":
			_spawn_night_wave("zombie", ZOMBIE_SPAWN_COUNT)
			EventFeed.push("The dead begin to stir...", Color(0.3, 0.7, 0.3))
		"quiet_night":
			EventFeed.push("A peaceful night.", Color(0.5, 0.55, 0.65))


func _on_night_event_end(_event_id: String) -> void:
	pass


func _auto_shelter_villagers() -> void:
	for v in villagers:
		if str(v.color_type) == "red" and int(v.level) == 3:
			continue
		var best_building: Node = null
		var best_d: float = INF
		for h in homes:
			if h.is_full():
				continue
			var d: float = v.global_position.distance_to(h.global_position)
			if d < best_d:
				best_d = d
				best_building = h
		for ch in churches:
			if ch.is_full():
				continue
			var d: float = v.global_position.distance_to(ch.global_position)
			if d < best_d:
				best_d = d
				best_building = ch
		if best_building:
			best_building.shelter_villager(v)


func _spawn_night_wave(enemy_type: String, count: int) -> void:
	var occupied_rids: Array = []
	for rid in room_villagers:
		if room_villagers[rid].size() > 0:
			occupied_rids.append(rid)
	if occupied_rids.is_empty():
		occupied_rids = room_map.keys()
	for i in count:
		var rid: int = occupied_rids[randi() % occupied_rids.size()]
		var room = room_map.get(rid)
		if not room:
			continue
		var rect: Rect2 = room.get_rect()
		var pos := Vector2(
			randf_range(rect.position.x + 100, rect.end.x - 100),
			randf_range(rect.position.y + 100, rect.end.y - 100))
		_spawn_night_enemy(enemy_type, pos)


func _spawn_night_enemy(enemy_type: String, pos: Vector2) -> void:
	var scene: PackedScene
	match enemy_type:
		"demon":
			scene = _demon_scene
		"zombie":
			scene = _zombie_scene
		_:
			return
	var e = scene.instantiate()
	_enemy_container.add_child(e)
	e.global_position = pos
	night_enemies.append(e)


func _despawn_night_enemies() -> void:
	for ne in night_enemies:
		if is_instance_valid(ne):
			ne.queue_free()
	night_enemies.clear()


func _process_home_sheltering() -> void:
	if not GameClock.is_daytime:
		for h in homes:
			if h.is_full():
				continue
			for v in villagers:
				if not v.visible:
					continue
				if str(v.color_type) == "red" and int(v.level) == 3:
					continue
				if v.global_position.distance_to(h.global_position) < HOME_SHELTER_DIST:
					h.shelter_villager(v)
		for ch in churches:
			if ch.is_full():
				continue
			for v in villagers:
				if not v.visible:
					continue
				if str(v.color_type) == "red" and int(v.level) == 3:
					continue
				if v.global_position.distance_to(ch.global_position) < CHURCH_INTAKE_RADIUS:
					ch.shelter_villager(v)


# ==============================================================================
# ENEMY DUPLICATION / MERGING
# ==============================================================================

func _process_enemy_duplication(delta: float) -> void:
	for rid in room_enemies:
		var l1s: Array = []
		for e in room_enemies[rid]:
			var enemy_type = e.get("enemy_type")
			if enemy_type != null and enemy_type != "":
				continue
			if e.level == 1:
				l1s.append(e)
		for e in l1s:
			var dr: float = e.radius * ENEMY_DUPE_RANGE_MULT
			var nearby: int = 0
			for other in l1s:
				if other != e and e.global_position.distance_to(other.global_position) < dr:
					nearby += 1
			if nearby < 1:
				e.dupe_meter = maxf(0.0, e.dupe_meter - 5.0 * delta)
				continue
			e.dupe_meter += ENEMY_DUPE_BASE * pow(0.9, maxf(0.0, log(float(nearby + 1) / 2.0) / log(2.0))) * 10.0 * delta
		var spawned: bool = false
		for e in l1s:
			if e.dupe_meter >= ENEMY_DUPE_MAX and not spawned:
				e.dupe_meter = 0.0
				_spawn_enemy(e.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50)), 1)
				EventFeed.push("Enemy approaches!", Color(0.8, 0.3, 0.3))
				spawned = true


func _process_enemy_merging() -> void:
	for rid in room_enemies:
		var by_lv: Dictionary = {1: [], 2: []}
		for e in room_enemies[rid]:
			var enemy_type = e.get("enemy_type")
			if enemy_type != null and enemy_type != "":
				continue
			if e.level < 3:
				if not by_lv.has(e.level):
					by_lv[e.level] = []
				by_lv[e.level].append(e)
		for lv in by_lv:
			if by_lv[lv].size() < ENEMY_MERGE_COUNT:
				continue
			var cluster := _find_cluster(by_lv[lv], ENEMY_MERGE_DIST, ENEMY_MERGE_COUNT)
			if cluster.size() >= ENEMY_MERGE_COUNT:
				cluster[0].set_level(lv + 1)
				for i in range(1, ENEMY_MERGE_COUNT):
					enemies.erase(cluster[i])
					cluster[i].die()
				EventFeed.push("Enemies have merged into a stronger form!", Color(0.9, 0.3, 0.2))


func _spawn_enemy(pos: Vector2, p_level: int = 1) -> void:
	var e = _enemy_scene.instantiate()
	_enemy_container.add_child(e)
	e.global_position = pos
	e.set_level(p_level)
	enemies.append(e)


# ==============================================================================
# VILLAGER LEVELING
# ==============================================================================

func _process_red_leveling() -> void:
	for v in villagers:
		if v.color_type != "red":
			continue
		if v.level == 1 and v.kill_count >= RED_LEVEL2_KILLS:
			v.set_level(2)
			EventFeed.push("A red villager reached Level 2!", Color(0.9, 0.4, 0.3))
		elif v.level == 2 and v.kill_count >= RED_LEVEL3_KILLS:
			v.set_level(3)
			EventFeed.push("A red villager reached Level 3!", Color(1.0, 0.5, 0.3))


func _process_blue_merging() -> void:
	for rid in room_villagers:
		var by_lv: Dictionary = {1: [], 2: []}
		for v in room_villagers[rid]:
			if v.color_type == "blue" and v.level < 3:
				if not by_lv.has(v.level):
					by_lv[v.level] = []
				by_lv[v.level].append(v)
		for lv in by_lv:
			if by_lv[lv].size() < BLUE_MERGE_COUNT:
				continue
			var merged := _find_cluster(by_lv[lv], BLUE_MERGE_DIST, BLUE_MERGE_COUNT)
			if merged.size() == BLUE_MERGE_COUNT:
				merged[0].set_level(lv + 1)
				for i in range(1, BLUE_MERGE_COUNT):
					villagers.erase(merged[i])
					merged[i].queue_free()
				EventFeed.push("Blues merged to Level %d!" % (lv + 1), Color(0.3, 0.5, 0.9))


func _process_yellow_leveling(delta: float) -> void:
	for rid in room_villagers:
		var yellows: Array = []
		for v in room_villagers[rid]:
			if v.color_type == "yellow" and v.level < 3:
				yellows.append(v)
		var paired: Dictionary = {}
		for i in yellows.size():
			if paired.has(i):
				continue
			for j in range(i + 1, yellows.size()):
				if paired.has(j) or yellows[i].level != yellows[j].level:
					continue
				if yellows[i].global_position.distance_to(yellows[j].global_position) < YELLOW_PAIR_DIST:
					yellows[i].leveling_partner = yellows[j]
					yellows[j].leveling_partner = yellows[i]
					yellows[i].leveling_meter += delta
					yellows[j].leveling_meter += delta
					if yellows[i].leveling_meter >= yellows[i].YELLOW_LEVEL_TIME:
						yellows[i].set_level(yellows[i].level + 1)
						yellows[i].leveling_meter = 0.0
						yellows[j].set_level(yellows[j].level + 1)
						yellows[j].leveling_meter = 0.0
						EventFeed.push("Yellows paired to Level %d!" % (yellows[i].level), Color(0.94, 0.84, 0.2))
					paired[i] = true
					paired[j] = true
					break
		for k in yellows.size():
			if not paired.has(k):
				yellows[k].leveling_meter = maxf(0.0, yellows[k].leveling_meter - delta * 0.5)
				yellows[k].leveling_partner = null


func _find_cluster(group: Array, max_dist: float, count: int) -> Array:
	for i in group.size():
		var cluster: Array = [group[i]]
		for j in group.size():
			if i != j and group[i].global_position.distance_to(group[j].global_position) < max_dist:
				cluster.append(group[j])
				if cluster.size() >= count:
					return cluster
	return []


func _on_buy_requested(item_id: String) -> void:
	if Economy.purchase(item_id):
		_placing_item = item_id


func _on_villager_shifted(villager, old_color, new_color, spawn_count) -> void:
	villager.set_color_type(str(new_color))
	var color_names: Dictionary = {"red": "the red", "yellow": "the yellow", "blue": "the blue", "colorless": "the colorless"}
	var cname: String = color_names.get(str(new_color), str(new_color))
	EventFeed.push("A villager joined %s." % cname, ColorRegistry.get_def(str(new_color)).get("display_color", Color.WHITE))
	for i in range(int(spawn_count) - 1):
		_spawn_villager(str(new_color),
			villager.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50)))


func _spawn_villager(color_id: String, pos: Vector2) -> void:
	var v = _villager_scene.instantiate()
	_villager_container.add_child(v)
	v.setup(color_id, pos)
	v.resource_dropped.connect(_on_villager_dropped_resource)
	villagers.append(v)


func _update_hud() -> void:
	if not _hud:
		return
	var counts: Dictionary = {}
	for v in villagers:
		counts[v.color_type] = counts.get(v.color_type, 0) + 1
	_hud.pop_red = counts.get("red", 0)
	_hud.pop_yellow = counts.get("yellow", 0)
	_hud.pop_blue = counts.get("blue", 0)
	_hud.pop_colorless = counts.get("colorless", 0)
	_hud.pop_enemies = enemies.size() + night_enemies.size()
	_hud.pop_total = villagers.size()


func _on_villager_dropped_resource(villager: Node2D, resource_type: String) -> void:
	var pos: Vector2 = villager.global_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	match resource_type:
		"stone":
			var c = _collectable_scene.instantiate()
			_collectables_container.add_child(c)
			c.global_position = pos
			collectables.append(c)
		"fish":
			var f = _fish_scene.instantiate()
			_fish_container.add_child(f)
			f.global_position = pos
			fish_spots.append(f)


# ==============================================================================
# RIVER FISH PRODUCTION
# ==============================================================================

func _process_river_fish(delta: float) -> void:
	_river_fish_timer += delta
	if _river_fish_timer < RIVER_FISH_INTERVAL:
		return
	_river_fish_timer -= RIVER_FISH_INTERVAL

	# Count existing fish in the river room
	var fish_in_river: int = 0
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected:
			continue
		if _room_id_at(f.global_position) == RIVER_ROOM_ID:
			fish_in_river += 1
	if fish_in_river >= RIVER_FISH_MAX:
		return

	# Spawn a fish in the river room
	var room_def: Array = _find_room_def(RIVER_ROOM_ID)
	if room_def.is_empty():
		return
	var rpos: Vector2 = _room_pixel_pos(room_def[1], room_def[2])
	var rsize: Vector2 = _room_pixel_size(room_def[3], room_def[4])
	var f = _fish_scene.instantiate()
	_fish_container.add_child(f)
	f.global_position = _rand_in_room(rpos, rsize, 60.0)
	fish_spots.append(f)
	EventFeed.push("A fish appeared in the river.", Color(0.3, 0.55, 0.75))
