extends RefCounted
## Procedural map generator.
## Grid-based room placement. Faction spawn clusters guaranteed symmetric.
## Accepts map_size ("small","medium","large","xl") and faction_count.
## Seed-deterministic for multiplayer sync.
##
## Neutral generation uses three passes:
##   Pass 1: island mask — grow an organic connected playable shape
##   Pass 2: footprint placement — place varied room shapes inside the mask
##   Pass 3: type assignment — assign gameplay roles by distance

const CELL := 675
const MAP_GAP := 8
const DOOR_SIZE := 120.0

# Grid dimensions: [cols, rows] by [faction_count_bucket][size_index]
# size_index: 0=small, 1=medium, 2=large, 3=xl
const SIZE_NAMES := ["small", "medium", "large", "xl"]
const GRID_CONFIG := {
	1: [[16, 12], [24, 16], [28, 20], [28, 20]],
	2: [[18, 14], [26, 18], [30, 22], [28, 22]],
	4: [[20, 16], [28, 20], [32, 24], [30, 22]],
	8: [[24, 18], [32, 22], [36, 26], [32, 24]],
}

# Room types
const RT_CORE     := "core"
const RT_STONE    := "stone_room"
const RT_RIVER    := "river_room"
const RT_QUARRY   := "quarry"
const RT_PASSAGE  := "passage"
const RT_COLORLESS_PASSAGE := "colorless_passage"
const RT_COLORLESS_CAMP    := "colorless_camp"
const RT_ENEMY_DEN         := "enemy_den"
const RT_CONTESTED         := "contested"
const RT_DIAMOND           := "diamond_cave"
const RT_PORTAL            := "portal"

# Room type colors
const ROOM_COLORS := {
	RT_CORE:              Color(0.18, 0.12, 0.12, 0.35),
	RT_STONE:             Color(0.18, 0.17, 0.08, 0.35),
	RT_RIVER:             Color(0.10, 0.13, 0.20, 0.35),
	RT_QUARRY:            Color(0.14, 0.16, 0.12, 0.35),
	RT_PASSAGE:           Color(0.14, 0.14, 0.14, 0.35),
	RT_COLORLESS_PASSAGE: Color(0.15, 0.14, 0.12, 0.35),
	RT_COLORLESS_CAMP:    Color(0.15, 0.14, 0.12, 0.35),
	RT_ENEMY_DEN:         Color(0.12, 0.08, 0.08, 0.35),
	RT_CONTESTED:         Color(0.10, 0.16, 0.20, 0.35),
	RT_DIAMOND:           Color(0.12, 0.18, 0.22, 0.35),
	RT_PORTAL:            Color(0.22, 0.08, 0.28, 0.35),
}

# Room type labels
const ROOM_LABELS := {
	RT_CORE:              "Home",
	RT_STONE:             "Stone Quarry",
	RT_RIVER:             "River",
	RT_QUARRY:            "Quarry",
	RT_PASSAGE:           "Passage",
	RT_COLORLESS_PASSAGE: "Wanderer's Path",
	RT_COLORLESS_CAMP:    "Wanderer Camp",
	RT_ENEMY_DEN:         "Enemy Den",
	RT_CONTESTED:         "Contested",
	RT_DIAMOND:           "Diamond Cave",
	RT_PORTAL:            "Portal",
}

# Cluster direction: which way does the chain extend from faction spawn
enum ClusterDir { RIGHT, LEFT, DOWN, UP }

# All allowed room footprints (cw, ch) — largest first for placement priority
const FOOTPRINTS := [
	[3, 2], [2, 3],
	[2, 2],
	[3, 1], [1, 3],
	[2, 1], [1, 2],
	[1, 1],
]

const LAYOUT_KEY_CORE_STANDARD := "__core_standard"
const LAYOUT_KEY_CORE_SURVIVAL := "__core_survival"
const ROOM_LAYOUT_PATHS := {
	RT_STONE: "res://scenes/room_layouts/stone_room_layout.tscn",
	RT_RIVER: "res://scenes/room_layouts/river_room_layout.tscn",
	RT_QUARRY: "res://scenes/room_layouts/quarry_layout.tscn",
	RT_ENEMY_DEN: "res://scenes/room_layouts/enemy_den_layout.tscn",
	RT_COLORLESS_PASSAGE: "res://scenes/room_layouts/colorless_passage_layout.tscn",
	RT_COLORLESS_CAMP: "res://scenes/room_layouts/colorless_camp_layout.tscn",
	RT_CONTESTED: "res://scenes/room_layouts/contested_layout.tscn",
	RT_DIAMOND: "res://scenes/room_layouts/diamond_cave_layout.tscn",
	RT_PORTAL: "res://scenes/room_layouts/portal_layout.tscn",
	LAYOUT_KEY_CORE_STANDARD: "res://scenes/room_layouts/core_standard_layout.tscn",
	LAYOUT_KEY_CORE_SURVIVAL: "res://scenes/room_layouts/core_survival_layout.tscn",
}

## Loaded room template cell patterns: Array of {cells: Array[Vector2i], name: String}
var _room_templates: Array = []
var _room_layout_scenes: Dictionary = {}


func _load_room_templates() -> void:
	## Load room template scenes from res://scenes/room_templates/ and extract cell patterns.
	_room_templates.clear()
	var template_paths: Array = [
		"res://scenes/room_templates/plus_shape.tscn",
		"res://scenes/room_templates/t_shape.tscn",
		"res://scenes/room_templates/l_shape.tscn",
		"res://scenes/room_templates/reverse_l_shape.tscn",
		"res://scenes/room_templates/big_square.tscn",
		"res://scenes/room_templates/horizontal_bar.tscn",
		"res://scenes/room_templates/vertical_bar.tscn",
		"res://scenes/room_templates/single_square.tscn",
	]
	for path in template_paths:
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		if scene == null:
			continue
		var inst = scene.instantiate()
		if inst == null or not inst.has_method("get_cells"):
			if inst:
				inst.free()
			continue
		var cells: Array = inst.get_cells()
		var tname: String = inst.name
		inst.free()
		if cells.size() > 0:
			_room_templates.append({"cells": cells, "name": tname})
	# Sort by cell count descending (largest templates placed first)
	_room_templates.sort_custom(func(a, b): return a["cells"].size() > b["cells"].size())


func _load_room_layouts() -> void:
	_room_layout_scenes.clear()
	for key in ROOM_LAYOUT_PATHS:
		var path: String = ROOM_LAYOUT_PATHS[key]
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		if scene != null:
			_room_layout_scenes[key] = scene


func _can_place_cells(anchor: Vector2i, cells: Array) -> bool:
	## True if all cells of this template are in the island mask and free.
	for offset in cells:
		var cell: Vector2i = anchor + Vector2i(offset)
		if not _island_mask.has(cell):
			return false
		if not _grid.has(cell):
			return false
		if _grid[cell] != -1:
			return false
	return true


func _mark_grid_cells(anchor: Vector2i, cells: Array, room_id: int) -> void:
	## Mark all cells of a template as belonging to room_id.
	for offset in cells:
		var cell: Vector2i = anchor + Vector2i(offset)
		if _grid.has(cell):
			_grid[cell] = room_id


func _cells_bounding_box(cells: Array) -> Dictionary:
	## Returns {min_offset: Vector2i, cw: int, ch: int} for a set of cell offsets.
	var min_c := Vector2i(999, 999)
	var max_c := Vector2i(-999, -999)
	for c in cells:
		min_c.x = mini(min_c.x, c.x)
		min_c.y = mini(min_c.y, c.y)
		max_c.x = maxi(max_c.x, c.x)
		max_c.y = maxi(max_c.y, c.y)
	return {"min_offset": min_c, "cw": max_c.x - min_c.x + 1, "ch": max_c.y - min_c.y + 1}


## Generated room definitions — parallel to old ROOM_DEFS format:
## [id, col, row, cells_w, cells_h, label, color]
var ROOM_DEFS: Array = []

## Generated faction starts — parallel to old FACTION_STARTS format:
## {home_room, bank_room (=stone_room id), river_room}
var FACTION_STARTS: Array = []

## Output: room_id -> room node
var room_map: Dictionary = {}

# Internal state
var _rng: RandomNumberGenerator
var _faction_count: int = 1
var _grid_cols: int = 6
var _grid_rows: int = 4
var _grid: Dictionary = {}           # Vector2i(col,row) -> room_id, -1=empty
var _island_mask: Dictionary = {}    # Vector2i -> true if cell is playable land
var _room_defs_map: Dictionary = {}  # room_id -> {id,col,row,cw,ch,label,color,type}
var _next_room_id: int = 0
var _faction_spawn_cells: Array = [] # Vector2i per faction
# Door restrictions: room_id -> Array[int] of allowed neighbor room_ids
var _door_restrictions: Dictionary = {}
var _river_room_ids: Array = []      # for main.gd river fish production
var _map_size_index: int = 1         # 0=small 1=medium 2=large 3=xl

## Portal pairs: room_id -> partner_room_id (bidirectional)
var portal_pairs: Dictionary = {}


var _faction_id_map: Array = []  ## maps faction array index -> actual faction ID

# ==============================================================================
# PUBLIC API
# ==============================================================================

## Generate a deterministic 2-room tutorial map with pre-placed entities.
## Uses real gameplay systems — only the map layout is controlled.
func generate_tutorial(containers: Dictionary, scenes: Dictionary) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42
	_faction_count = 1
	_faction_id_map = [0]
	_grid_cols = 4
	_grid_rows = 2
	_map_size_index = 0
	_init_grid()
	_next_room_id = 0
	FACTION_STARTS.clear()
	_door_restrictions.clear()
	_river_room_ids.clear()

	# Room A: Tutorial Home (2x2, top-left) — learning room
	var room_a_id: int = _next_room_id
	_next_room_id += 1
	_mark_grid(Vector2i(0, 0), 2, 2, room_a_id)
	_mark_island_mask(Vector2i(0, 0), 2, 2)
	_room_defs_map[room_a_id] = {
		"id": room_a_id, "col": 0, "row": 0,
		"cw": 2, "ch": 2, "label": "Tutorial Home",
		"color": ROOM_COLORS[RT_CORE], "type": RT_CORE, "faction": 0,
	}

	# Room B: Challenge Room (2x1, right of A) — enemies + more resources
	var room_b_id: int = _next_room_id
	_next_room_id += 1
	_mark_grid(Vector2i(2, 0), 2, 1, room_b_id)
	_mark_island_mask(Vector2i(2, 0), 2, 1)
	_room_defs_map[room_b_id] = {
		"id": room_b_id, "col": 2, "row": 0,
		"cw": 2, "ch": 1, "label": "Challenge Room",
		"color": ROOM_COLORS[RT_PASSAGE], "type": RT_PASSAGE, "faction": -1,
	}

	TutorialManager.tutorial_room_b_id = room_b_id

	FACTION_STARTS.append({
		"home_room": room_a_id,
		"bank_room": room_a_id,
		"river_room": -1,
	})

	_build_room_defs_array()
	_generate_rooms(containers["rooms"], scenes["room"])

	# ── Wall with closed door between A and B ──
	var wall_scene: PackedScene = scenes["wall"]
	var wall_x: float = 2.0 * (CELL + MAP_GAP) - MAP_GAP / 2.0
	var wall_start := Vector2(wall_x, 0.0)
	var wall_end := Vector2(wall_x, 1.0 * (CELL + MAP_GAP) - MAP_GAP)
	var mid_y: float = (wall_start.y + wall_end.y) * 0.5
	var half_door: float = DOOR_SIZE * 0.5
	var door_start := Vector2(wall_x, mid_y - half_door)
	var door_end := Vector2(wall_x, mid_y + half_door)

	if wall_start.distance_to(door_start) > 20.0:
		var w1 = wall_scene.instantiate()
		w1.room_a_id = room_a_id; w1.room_b_id = room_b_id
		w1.start_pos = wall_start; w1.end_pos = door_start
		containers["walls"].add_child(w1)

	var door = wall_scene.instantiate()
	door.room_a_id = room_a_id; door.room_b_id = room_b_id
	door.start_pos = door_start; door.end_pos = door_end
	door.is_door = true; door.is_open = false
	containers["walls"].add_child(door)

	if door_end.distance_to(wall_end) > 20.0:
		var w2 = wall_scene.instantiate()
		w2.room_a_id = room_a_id; w2.room_b_id = room_b_id
		w2.start_pos = door_end; w2.end_pos = wall_end
		containers["walls"].add_child(w2)

	# ── Room A entities ──
	var a_pos: Vector2 = room_pixel_pos(0, 0)
	var a_size: Vector2 = room_pixel_size(2, 2)
	var a_center: Vector2 = a_pos + a_size * 0.5

	# Town Hall at center with magic orb inside
	if scenes.has("town_hall") and containers.has("town_halls"):
		var th = scenes["town_hall"].instantiate()
		containers["town_halls"].add_child(th)
		th.global_position = a_center
		th.placed_by_faction = 0
	var orb = scenes["villager"].instantiate()
	containers["villagers"].add_child(orb)
	orb.setup("magic_orb", a_center)
	orb.faction_id = 0

	# 3 red villagers (need extras: one for shift phase, one for duplication, one for door/combat)
	for i in 3:
		var v = scenes["villager"].instantiate()
		containers["villagers"].add_child(v)
		v.setup("red", Vector2(a_pos.x + 150 + i * 80, a_pos.y + 180))
		v.faction_id = 0
		v._satiation_timer = v.SATIATION_PER_LEVEL[1]
		v.is_fed = true

	# 1 yellow (for stone collection demo)
	var yv = scenes["villager"].instantiate()
	containers["villagers"].add_child(yv)
	yv.setup("yellow", Vector2(a_pos.x + a_size.x - 200, a_pos.y + 200))
	yv.faction_id = 0

	# 1 blue (for fish collection demo)
	var bv = scenes["villager"].instantiate()
	containers["villagers"].add_child(bv)
	bv.setup("blue", Vector2(a_pos.x + 200, a_pos.y + a_size.y - 250))
	bv.faction_id = 0

	# Bank (bottom-right of Room A)
	var bank = scenes["bank"].instantiate()
	containers["banks"].add_child(bank)
	bank.global_position = Vector2(a_pos.x + a_size.x - 150, a_pos.y + a_size.y - 150)
	bank.placed_by_faction = -2

	# Fishing hut (bottom-left of Room A — for blue fish delivery)
	var hut_a = scenes["hut"].instantiate()
	containers["huts"].add_child(hut_a)
	hut_a.global_position = Vector2(a_pos.x + 200, a_pos.y + a_size.y - 120)
	hut_a.placed_by_faction = -2

	# Home
	var home = preload("res://scenes/home.tscn").instantiate()
	containers["homes"].add_child(home)
	home.global_position = Vector2(a_pos.x + a_size.x * 0.5, a_pos.y + a_size.y - 120)
	home.placed_by_faction = -2

	# Stone collectables in Room A (clustered near bank for easy yellow pickup)
	for i in 6:
		var c = scenes["collectable"].instantiate()
		containers["collectables"].add_child(c)
		c.global_position = Vector2(
			_rng.randf_range(a_pos.x + a_size.x * 0.5, a_pos.x + a_size.x - 100),
			_rng.randf_range(a_pos.y + a_size.y * 0.3, a_pos.y + a_size.y - 200))

	# Fish spots in Room A (near the hut for easy blue pickup)
	for i in 4:
		var f = scenes["fish"].instantiate()
		containers["fish"].add_child(f)
		f.global_position = Vector2(
			_rng.randf_range(a_pos.x + 80, a_pos.x + 400),
			_rng.randf_range(a_pos.y + a_size.y * 0.4, a_pos.y + a_size.y - 180))

	# ── Room B entities (behind the door) ──
	var b_pos: Vector2 = room_pixel_pos(2, 0)
	var b_size: Vector2 = room_pixel_size(2, 1)
	var b_center: Vector2 = b_pos + b_size * 0.5

	# Enemies (3 — target for combat phase)
	for i in 3:
		var e = scenes["enemy"].instantiate()
		containers["enemies"].add_child(e)
		e.global_position = Vector2(
			_rng.randf_range(b_pos.x + 150, b_pos.x + b_size.x - 150),
			_rng.randf_range(b_pos.y + 150, b_pos.y + b_size.y - 150))

	# Extra stone + fish in Room B for post-tutorial exploration
	for i in 4:
		var c = scenes["collectable"].instantiate()
		containers["collectables"].add_child(c)
		c.global_position = Vector2(
			_rng.randf_range(b_pos.x + 80, b_pos.x + b_size.x - 80),
			_rng.randf_range(b_pos.y + 80, b_pos.y + b_size.y - 80))
	for i in 2:
		var f = scenes["fish"].instantiate()
		containers["fish"].add_child(f)
		f.global_position = Vector2(
			_rng.randf_range(b_pos.x + 80, b_pos.x + b_size.x - 80),
			_rng.randf_range(b_pos.y + 80, b_pos.y + b_size.y - 80))

	print("=== TUTORIAL MAP GENERATED ===")
	print("Room A (id=%d): %s size=%s" % [room_a_id, str(a_pos), str(a_size)])
	print("Room B (id=%d): %s size=%s" % [room_b_id, str(b_pos), str(b_size)])
	print("=============================")


## Generate a 2-room sandbox map for free play.
## Room A: big open room with villagers, orb in safe corner.
## Room B: obstacle-filled room with enemies.
func generate_sandbox(containers: Dictionary, scenes: Dictionary) -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 99
	_faction_count = 1
	_faction_id_map = [0]
	_grid_cols = 5
	_grid_rows = 3
	_map_size_index = 0
	_init_grid()
	_next_room_id = 0
	FACTION_STARTS.clear()
	_door_restrictions.clear()
	_river_room_ids.clear()

	# Room A: Big open playground (3x2)
	var room_a_id: int = _next_room_id
	_next_room_id += 1
	_mark_grid(Vector2i(0, 0), 3, 2, room_a_id)
	_mark_island_mask(Vector2i(0, 0), 3, 2)
	_room_defs_map[room_a_id] = {
		"id": room_a_id, "col": 0, "row": 0,
		"cw": 3, "ch": 2, "label": "Sandbox",
		"color": Color(0.14, 0.14, 0.18, 0.35), "type": RT_CORE, "faction": 0,
	}

	# Room B: Enemy arena with obstacles (2x2)
	var room_b_id: int = _next_room_id
	_next_room_id += 1
	_mark_grid(Vector2i(3, 0), 2, 2, room_b_id)
	_mark_island_mask(Vector2i(3, 0), 2, 2)
	_room_defs_map[room_b_id] = {
		"id": room_b_id, "col": 3, "row": 0,
		"cw": 2, "ch": 2, "label": "Enemy Arena",
		"color": Color(0.18, 0.1, 0.1, 0.35), "type": RT_ENEMY_DEN, "faction": -1,
	}

	FACTION_STARTS.append({
		"home_room": room_a_id,
		"bank_room": room_a_id,
		"river_room": -1,
	})

	_build_room_defs_array()
	_generate_rooms(containers["rooms"], scenes["room"])

	# ── Wall with door between A and B ──
	var wall_scene: PackedScene = scenes["wall"]
	var wall_x: float = 3.0 * (CELL + MAP_GAP) - MAP_GAP / 2.0
	var wall_start := Vector2(wall_x, 0.0)
	var wall_end := Vector2(wall_x, 2.0 * (CELL + MAP_GAP) - MAP_GAP)
	var mid_y: float = (wall_start.y + wall_end.y) * 0.5
	var half_door: float = DOOR_SIZE * 0.5
	var door_start := Vector2(wall_x, mid_y - half_door)
	var door_end := Vector2(wall_x, mid_y + half_door)

	if wall_start.distance_to(door_start) > 20.0:
		var w1 = wall_scene.instantiate()
		w1.room_a_id = room_a_id; w1.room_b_id = room_b_id
		w1.start_pos = wall_start; w1.end_pos = door_start
		containers["walls"].add_child(w1)

	var door = wall_scene.instantiate()
	door.room_a_id = room_a_id; door.room_b_id = room_b_id
	door.start_pos = door_start; door.end_pos = door_end
	door.is_door = true; door.is_open = false
	containers["walls"].add_child(door)

	if door_end.distance_to(wall_end) > 20.0:
		var w2 = wall_scene.instantiate()
		w2.room_a_id = room_a_id; w2.room_b_id = room_b_id
		w2.start_pos = door_end; w2.end_pos = wall_end
		containers["walls"].add_child(w2)

	# ── Room A entities ──
	var a_pos: Vector2 = room_pixel_pos(0, 0)
	var a_size: Vector2 = room_pixel_size(3, 2)

	# Town Hall with magic orb inside — safe top-left corner
	var orb_pos := Vector2(a_pos.x + 120, a_pos.y + 120)
	if scenes.has("town_hall") and containers.has("town_halls"):
		var th = scenes["town_hall"].instantiate()
		containers["town_halls"].add_child(th)
		th.global_position = orb_pos
		th.placed_by_faction = 0
	var orb = scenes["villager"].instantiate()
	containers["villagers"].add_child(orb)
	orb.setup("magic_orb", orb_pos)
	orb.faction_id = 0

	# Red villager — top-right area
	var rv = scenes["villager"].instantiate()
	containers["villagers"].add_child(rv)
	rv.setup("red", Vector2(a_pos.x + a_size.x - 200, a_pos.y + 200))
	rv.faction_id = 0
	rv._satiation_timer = rv.SATIATION_PER_LEVEL[1]
	rv.is_fed = true

	# Yellow villagers — center-left and center-right
	for i in 2:
		var yv = scenes["villager"].instantiate()
		containers["villagers"].add_child(yv)
		yv.setup("yellow", Vector2(a_pos.x + 300 + i * 500, a_pos.y + a_size.y * 0.5))
		yv.faction_id = 0

	# Blue villagers — bottom-left and bottom-right
	for i in 2:
		var bv = scenes["villager"].instantiate()
		containers["villagers"].add_child(bv)
		bv.setup("blue", Vector2(a_pos.x + 250 + i * 600, a_pos.y + a_size.y - 250))
		bv.faction_id = 0

	# Bank + fishing hut + home for resource play
	var bank = scenes["bank"].instantiate()
	containers["banks"].add_child(bank)
	bank.global_position = Vector2(a_pos.x + a_size.x * 0.5, a_pos.y + a_size.y - 150)
	bank.placed_by_faction = -2

	var hut = scenes["hut"].instantiate()
	containers["huts"].add_child(hut)
	hut.global_position = Vector2(a_pos.x + 200, a_pos.y + a_size.y - 150)
	hut.placed_by_faction = -2

	var home = preload("res://scenes/home.tscn").instantiate()
	containers["homes"].add_child(home)
	home.global_position = Vector2(a_pos.x + a_size.x - 200, a_pos.y + a_size.y - 150)
	home.placed_by_faction = -2

	# Some stone and fish in Room A
	for i in 8:
		var c = scenes["collectable"].instantiate()
		containers["collectables"].add_child(c)
		c.global_position = _rand_in_room(a_pos, a_size, 100.0)
	for i in 5:
		var f = scenes["fish"].instantiate()
		containers["fish"].add_child(f)
		f.global_position = _rand_in_room(a_pos, a_size, 100.0)

	# ── Room B entities — enemies + internal walls ──
	var b_pos: Vector2 = room_pixel_pos(3, 0)
	var b_size: Vector2 = room_pixel_size(2, 2)
	var b_center: Vector2 = b_pos + b_size * 0.5

	# Internal obstacle walls (breakable) — create maze-like layout
	var obs_scene: PackedScene = preload("res://scenes/obstacles/breakable_wall_obstacle.tscn")
	var room_b_node = room_map.get(room_b_id)
	if room_b_node:
		# Horizontal wall across top third
		var obs1 = obs_scene.instantiate()
		obs1.wall_size = Vector2(b_size.x * 0.6, 14)
		room_b_node.add_child(obs1)
		obs1.position = Vector2(50, b_size.y * 0.3)

		# Horizontal wall across bottom third (offset from right)
		var obs2 = obs_scene.instantiate()
		obs2.wall_size = Vector2(b_size.x * 0.6, 14)
		room_b_node.add_child(obs2)
		obs2.position = Vector2(b_size.x * 0.4 - 50, b_size.y * 0.65)

		# Short vertical wall in center
		var obs3 = obs_scene.instantiate()
		obs3.wall_size = Vector2(14, b_size.y * 0.25)
		room_b_node.add_child(obs3)
		obs3.position = Vector2(b_size.x * 0.5, b_size.y * 0.35)

	# 5 enemies scattered in Room B
	for i in 5:
		var e = scenes["enemy"].instantiate()
		containers["enemies"].add_child(e)
		e.global_position = Vector2(
			_rng.randf_range(b_pos.x + 150, b_pos.x + b_size.x - 150),
			_rng.randf_range(b_pos.y + 150, b_pos.y + b_size.y - 150))

	# Extra stone in Room B
	for i in 6:
		var c = scenes["collectable"].instantiate()
		containers["collectables"].add_child(c)
		c.global_position = _rand_in_room(b_pos, b_size, 100.0)

	print("=== SANDBOX MAP GENERATED ===")
	print("Room A (id=%d): %s size=%s" % [room_a_id, str(a_pos), str(a_size)])
	print("Room B (id=%d): %s size=%s" % [room_b_id, str(b_pos), str(b_size)])
	print("=============================")


func generate(containers: Dictionary, scenes: Dictionary, map_seed: int = -1,
		faction_count: int = 1, map_size: String = "medium",
		faction_id_map: Array = []) -> void:
	_rng = RandomNumberGenerator.new()
	if map_seed >= 0:
		_rng.seed = map_seed
	else:
		_rng.randomize()
	_faction_count = clampi(faction_count, 1, 8)

	# Build faction ID map: index -> actual faction ID
	if faction_id_map.is_empty():
		_faction_id_map = range(_faction_count)
	else:
		_faction_id_map = faction_id_map.duplicate()

	_setup_grid_size(map_size)
	_init_grid()
	_load_room_templates()
	_load_room_layouts()
	_place_faction_clusters()
	_connect_faction_clusters()   ## Ensures single connected landmass
	_fill_neutral_rooms()
	_assign_portal_pair()
	_build_room_defs_array()
	_generate_rooms(containers["rooms"], scenes["room"])
	# Walls/doors omitted in main game — open map layout.
	# Tutorial and sandbox modes generate walls in their own methods.
	_generate_entities(containers, scenes)
	_generate_faction_starts(containers, scenes)
	_print_debug_summary()


static func room_pixel_pos(col: int, row: int) -> Vector2:
	return Vector2(col * (CELL + MAP_GAP), row * (CELL + MAP_GAP))


static func room_pixel_size(cw: int, ch: int) -> Vector2:
	return Vector2(cw * CELL + (cw - 1) * MAP_GAP, ch * CELL + (ch - 1) * MAP_GAP)


func find_room_def(rid: int) -> Array:
	for def in ROOM_DEFS:
		if def[0] == rid:
			return def
	return []


# ==============================================================================
# GRID SETUP
# ==============================================================================

func _setup_grid_size(map_size: String) -> void:
	var si: int = SIZE_NAMES.find(map_size)
	if si < 0:
		si = 1
	_map_size_index = si
	var bucket: int = 1
	if _faction_count >= 5: bucket = 8
	elif _faction_count >= 3: bucket = 4
	elif _faction_count >= 2: bucket = 2
	var dims: Array = GRID_CONFIG[bucket][si]
	_grid_cols = dims[0]
	_grid_rows = dims[1]


func _init_grid() -> void:
	_grid.clear()
	_island_mask.clear()
	for c in _grid_cols:
		for r in _grid_rows:
			_grid[Vector2i(c, r)] = -1


# ==============================================================================
# FACTION CLUSTER PLACEMENT
# ==============================================================================

func _place_faction_clusters() -> void:
	_faction_spawn_cells.clear()
	FACTION_STARTS.clear()
	_door_restrictions.clear()
	_river_room_ids.clear()
	portal_pairs.clear()
	_next_room_id = 0

	var perimeter: Array = _get_perimeter_cells()
	var spawn_cells: Array = _spread_on_perimeter(perimeter, _faction_count)

	for fi in spawn_cells.size():
		var sc: Vector2i = spawn_cells[fi]
		_faction_spawn_cells.append(sc)
		var dir: ClusterDir = _cluster_direction(sc)
		_place_cluster(fi, sc, dir)


func _get_perimeter_cells() -> Array:
	var cells: Array = []
	for c in _grid_cols:
		cells.append(Vector2i(c, 0))
	for r in range(1, _grid_rows):
		cells.append(Vector2i(_grid_cols - 1, r))
	for c in range(_grid_cols - 2, -1, -1):
		cells.append(Vector2i(c, _grid_rows - 1))
	for r in range(_grid_rows - 2, 0, -1):
		cells.append(Vector2i(0, r))
	return cells


func _spread_on_perimeter(perimeter: Array, count: int) -> Array:
	if count <= 0:
		return []
	var result: Array = []
	var step: float = float(perimeter.size()) / float(count)
	for i in count:
		var idx: int = int(round(i * step)) % perimeter.size()
		result.append(perimeter[idx])
	return result


func _cluster_direction(spawn_cell: Vector2i) -> ClusterDir:
	var cx: float = float(_grid_cols - 1) * 0.5
	var cy: float = float(_grid_rows - 1) * 0.5
	var dx: float = float(spawn_cell.x) - cx
	var dy: float = float(spawn_cell.y) - cy
	if spawn_cell.y == 0: return ClusterDir.DOWN
	if spawn_cell.y == _grid_rows - 1: return ClusterDir.UP
	if spawn_cell.x == 0: return ClusterDir.RIGHT
	if spawn_cell.x == _grid_cols - 1: return ClusterDir.LEFT
	if abs(dx) >= abs(dy):
		return ClusterDir.LEFT if dx > 0.0 else ClusterDir.RIGHT
	else:
		return ClusterDir.UP if dy > 0.0 else ClusterDir.DOWN


func _place_cluster(faction_idx: int, spawn_cell: Vector2i, dir: ClusterDir) -> void:
	# --- CORE (2×2) ---
	var core_id: int = _next_room_id
	_next_room_id += 1
	var core_cell: Vector2i = spawn_cell
	core_cell.x = clampi(core_cell.x, 0, _grid_cols - 2)
	core_cell.y = clampi(core_cell.y, 0, _grid_rows - 2)
	_mark_grid(core_cell, 2, 2, core_id)
	_mark_island_mask(core_cell, 2, 2)
	_room_defs_map[core_id] = {
		"id": core_id, "col": core_cell.x, "row": core_cell.y,
		"cw": 2, "ch": 2, "label": ROOM_LABELS[RT_CORE],
		"color": ROOM_COLORS[RT_CORE], "type": RT_CORE, "faction": faction_idx,
	}

	# --- STONE ROOM (1×2 or 2×1) ---
	var stone_id: int = _next_room_id
	_next_room_id += 1
	var stone_cell: Vector2i
	var stone_cw: int = 1
	var stone_ch: int = 2
	match dir:
		ClusterDir.RIGHT:
			stone_cell = Vector2i(core_cell.x + 2, core_cell.y)
			stone_cw = 1; stone_ch = 2
		ClusterDir.LEFT:
			stone_cell = Vector2i(core_cell.x - 1, core_cell.y)
			stone_cw = 1; stone_ch = 2
		ClusterDir.DOWN:
			stone_cell = Vector2i(core_cell.x, core_cell.y + 2)
			stone_cw = 2; stone_ch = 1
		ClusterDir.UP:
			stone_cell = Vector2i(core_cell.x, core_cell.y - 1)
			stone_cw = 2; stone_ch = 1
	stone_cell.x = clampi(stone_cell.x, 0, _grid_cols - stone_cw)
	stone_cell.y = clampi(stone_cell.y, 0, _grid_rows - stone_ch)
	_mark_grid(stone_cell, stone_cw, stone_ch, stone_id)
	_mark_island_mask(stone_cell, stone_cw, stone_ch)
	_room_defs_map[stone_id] = {
		"id": stone_id, "col": stone_cell.x, "row": stone_cell.y,
		"cw": stone_cw, "ch": stone_ch, "label": ROOM_LABELS[RT_STONE],
		"color": ROOM_COLORS[RT_STONE], "type": RT_STONE, "faction": faction_idx,
	}

	# --- RIVER ROOM (1×1) ---
	var river_id: int = _next_room_id
	_next_room_id += 1
	var river_cell: Vector2i
	match dir:
		ClusterDir.RIGHT:  river_cell = Vector2i(stone_cell.x + 1, stone_cell.y)
		ClusterDir.LEFT:   river_cell = Vector2i(stone_cell.x - 1, stone_cell.y)
		ClusterDir.DOWN:   river_cell = Vector2i(stone_cell.x, stone_cell.y + 1)
		ClusterDir.UP:     river_cell = Vector2i(stone_cell.x, stone_cell.y - 1)
	river_cell.x = clampi(river_cell.x, 0, _grid_cols - 1)
	river_cell.y = clampi(river_cell.y, 0, _grid_rows - 1)
	if _grid.has(river_cell) and _grid[river_cell] != -1:
		for off in _perpendicular_offsets(dir):
			var candidate: Vector2i = stone_cell + off
			candidate.x = clampi(candidate.x, 0, _grid_cols - 1)
			candidate.y = clampi(candidate.y, 0, _grid_rows - 1)
			if _grid.has(candidate) and _grid[candidate] == -1:
				river_cell = candidate
				break
	_mark_grid(river_cell, 1, 1, river_id)
	_mark_island_mask(river_cell, 1, 1)
	_room_defs_map[river_id] = {
		"id": river_id, "col": river_cell.x, "row": river_cell.y,
		"cw": 1, "ch": 1, "label": ROOM_LABELS[RT_RIVER],
		"color": ROOM_COLORS[RT_RIVER], "type": RT_RIVER, "faction": faction_idx,
	}
	_river_room_ids.append(river_id)

	_door_restrictions[core_id] = [stone_id]
	_door_restrictions[stone_id] = [core_id, river_id]

	FACTION_STARTS.append({
		"home_room": core_id,
		"bank_room": stone_id,
		"river_room": river_id,
	})


# ==============================================================================
# FACTION CLUSTER CONNECTIVITY
# ==============================================================================

func _connect_faction_clusters() -> void:
	## Carve L-shaped Manhattan paths between consecutive faction spawn cells,
	## guaranteeing all factions are on a single connected landmass.
	if _faction_spawn_cells.size() <= 1:
		return
	for i in _faction_spawn_cells.size():
		var from: Vector2i = _faction_spawn_cells[i]
		var to: Vector2i = _faction_spawn_cells[(i + 1) % _faction_spawn_cells.size()]
		_carve_path(from, to)


func _carve_path(from: Vector2i, to: Vector2i) -> void:
	## Carve an L-shaped Manhattan path between two cells, marking them into _island_mask.
	var mid_x: int = _rng.randi_range(mini(from.x, to.x), maxi(from.x, to.x))
	var cur: Vector2i = from
	# Walk horizontally to mid_x
	while cur.x != mid_x:
		cur.x += 1 if mid_x > cur.x else -1
		_ensure_mask(cur)
	# Walk vertically to target row
	while cur.y != to.y:
		cur.y += 1 if to.y > cur.y else -1
		_ensure_mask(cur)
	# Walk horizontally to target col
	while cur.x != to.x:
		cur.x += 1 if to.x > cur.x else -1
		_ensure_mask(cur)


func _ensure_mask(cell: Vector2i) -> void:
	if _grid.has(cell) and not _island_mask.has(cell):
		_island_mask[cell] = true


func _perpendicular_offsets(dir: ClusterDir) -> Array:
	match dir:
		ClusterDir.RIGHT, ClusterDir.LEFT:
			return [Vector2i(0, 1), Vector2i(0, -1)]
		_:
			return [Vector2i(1, 0), Vector2i(-1, 0)]


func _mark_grid(top_left: Vector2i, cw: int, ch: int, room_id: int) -> void:
	for dc in cw:
		for dr in ch:
			var cell := Vector2i(top_left.x + dc, top_left.y + dr)
			if _grid.has(cell):
				_grid[cell] = room_id


func _mark_island_mask(top_left: Vector2i, cw: int, ch: int) -> void:
	for dc in cw:
		for dr in ch:
			_island_mask[Vector2i(top_left.x + dc, top_left.y + dr)] = true


# ==============================================================================
# NEUTRAL ROOM FILLING — three-pass island generation
# ==============================================================================

func _fill_neutral_rooms() -> void:
	# Pass 1: grow island mask from faction cells
	_grow_island_mask()
	# Pass 2: place varied footprints inside mask
	_place_footprints()
	# Pass 3: assign room types to placed rooms
	_assign_room_types()


# ------------------------------------------------------------------------------
# Pass 1: Island mask growth
# ------------------------------------------------------------------------------

func _grow_island_mask() -> void:
	## Grow an organic island from faction cells using a seeded random walk.
	## Fill ratio scales with map size: small ~50%, medium ~65%, large ~75%, xl ~85%.

	var total_cells: int = _grid_cols * _grid_rows

	# Fill ratio by map size index (stored during _setup_grid_size)
	const FILL_MIN := [0.45, 0.58, 0.70, 0.80]
	const FILL_MAX := [0.56, 0.68, 0.80, 0.90]
	var fill_min: float = FILL_MIN[_map_size_index]
	var fill_max: float = FILL_MAX[_map_size_index]

	var faction_cells: int = _island_mask.size()
	var target_fill_ratio: float = _rng.randf_range(fill_min, fill_max)
	var target_total: int = int(float(total_cells) * target_fill_ratio)
	var target_neutral: int = maxi(0, target_total - faction_cells)

	# Start frontier from all faction-occupied cells
	var frontier: Array = []
	for cell in _island_mask:
		for off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb: Vector2i = cell + off
			if _grid.has(nb) and not _island_mask.has(nb):
				if nb not in frontier:
					frontier.append(nb)

	_rng_shuffle(frontier)

	var placed: int = 0
	var iterations: int = 0
	var max_iter: int = total_cells * 4

	while placed < target_neutral and frontier.size() > 0 and iterations < max_iter:
		iterations += 1

		# Bias: pick from a random position in the frontier, but prefer
		# cells adjacent to more island cells (organic growth)
		var pick_idx: int = _weighted_frontier_pick(frontier)
		var cell: Vector2i = frontier[pick_idx]
		frontier.remove_at(pick_idx)

		if _island_mask.has(cell):
			continue

		# Anti-rectangle: reject if this cell would complete a 4×4 or larger
		# fully-filled rectangle — adds irregularity to edges
		if _would_over_rectangularize(cell):
			# Still might add it at reduced probability
			if _rng.randf() > 0.25:
				continue

		_island_mask[cell] = true
		placed += 1

		# Add this cell's unmasked neighbors to frontier
		for off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb: Vector2i = cell + off
			if _grid.has(nb) and not _island_mask.has(nb) and nb not in frontier:
				frontier.append(nb)

	# Carve notches for extra irregularity (remove isolated peninsula tips)
	_carve_notches()


func _weighted_frontier_pick(frontier: Array) -> int:
	## Pick a frontier cell, biasing toward cells with more island neighbors.
	## Uses reservoir-style weighted selection for O(n) performance.
	var best_idx: int = 0
	var best_weight: float = -1.0
	for i in frontier.size():
		var cell: Vector2i = frontier[i]
		var island_neighbors: int = 0
		for off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			if _island_mask.has(cell + off):
				island_neighbors += 1
		# Weight = island neighbor count + small random jitter
		var w: float = float(island_neighbors) + _rng.randf() * 0.8
		if w > best_weight:
			best_weight = w
			best_idx = i
	return best_idx


func _would_over_rectangularize(cell: Vector2i) -> bool:
	## Returns true if adding this cell would create a 4×4 or larger fully-filled
	## rectangular block — used to discourage overly boxy shapes.
	## Check if the cell is surrounded on all four cardinal sides AND diagonals
	## by island cells (i.e., would be deeply interior).
	var all_8_filled: bool = true
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nb := Vector2i(cell.x + dx, cell.y + dy)
			if not _island_mask.has(nb):
				all_8_filled = false
				break
		if not all_8_filled:
			break
	return all_8_filled


func _carve_notches() -> void:
	## Remove cells that are peninsula tips (only 1 island neighbor) at the
	## edge of the grid, with some probability. Creates organic coastline.
	var to_remove: Array = []
	for cell in _island_mask:
		# Skip faction cells
		if _grid.has(cell) and _grid[cell] >= 0:
			continue
		var island_neighbors: int = 0
		for off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			if _island_mask.has(cell + off):
				island_neighbors += 1
		# Isolated peninsula tip — remove with high probability
		if island_neighbors <= 1 and _rng.randf() < 0.7:
			to_remove.append(cell)
		# Corner peninsula (2 neighbors but on grid edge) — remove sometimes
		elif island_neighbors == 2:
			var on_edge: bool = (cell.x == 0 or cell.x == _grid_cols - 1 or
								 cell.y == 0 or cell.y == _grid_rows - 1)
			if on_edge and _rng.randf() < 0.4:
				to_remove.append(cell)

	for cell in to_remove:
		_island_mask.erase(cell)

	# Connectivity repair: re-add any removed cell that would disconnect the island
	for cell in to_remove:
		if not _is_island_connected():
			_island_mask[cell] = true


func _is_island_connected() -> bool:
	## BFS from first faction cell — returns true if all island mask cells reachable.
	if _island_mask.is_empty():
		return true
	var start: Vector2i = _island_mask.keys()[0]
	var visited: Dictionary = {}
	var queue: Array = [start]
	visited[start] = true
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		for off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nb: Vector2i = cur + off
			if _island_mask.has(nb) and not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	return visited.size() == _island_mask.size()


# ------------------------------------------------------------------------------
# Pass 2: Footprint placement
# ------------------------------------------------------------------------------

func _place_footprints() -> void:
	## Place varied room footprints inside island mask.
	## Uses loaded room templates when available, falls back to FOOTPRINTS.
	## Largest templates placed first. Remaining cells become 1×1 rooms.

	if _room_templates.size() > 0:
		_place_footprints_from_templates()
	else:
		_place_footprints_rectangular()

	# 1×1 cleanup: any remaining free mask cell becomes a 1×1 room
	for cell in _get_free_mask_cells():
		var rid: int = _next_room_id
		_next_room_id += 1
		_grid[cell] = rid
		_room_defs_map[rid] = {
			"id": rid, "col": cell.x, "row": cell.y,
			"cw": 1, "ch": 1, "label": "Room",
			"color": Color(0.14, 0.14, 0.14, 0.35), "type": RT_PASSAGE, "faction": -1,
		}


func _place_footprints_from_templates() -> void:
	## Place rooms using loaded scene-based templates (supports non-rectangular shapes).
	for tmpl in _room_templates:
		var cells: Array = tmpl["cells"]
		if cells.size() <= 1:
			continue  # Skip single-cell templates (handled by 1×1 cleanup)

		var candidates: Array = _get_free_mask_cells()
		_rng_shuffle(candidates)

		for anchor in candidates:
			if not _can_place_cells(anchor, cells):
				continue
			var rid: int = _next_room_id
			_next_room_id += 1
			_mark_grid_cells(anchor, cells, rid)
			var bbox: Dictionary = _cells_bounding_box(cells)
			_room_defs_map[rid] = {
				"id": rid, "col": anchor.x + bbox["min_offset"].x,
				"row": anchor.y + bbox["min_offset"].y,
				"cw": bbox["cw"], "ch": bbox["ch"], "label": "Room",
				"color": Color(0.14, 0.14, 0.14, 0.35), "type": RT_PASSAGE, "faction": -1,
			}


func _place_footprints_rectangular() -> void:
	## Fallback: place rooms using hardcoded rectangular FOOTPRINTS.
	for fp in FOOTPRINTS:
		var cw: int = fp[0]
		var ch: int = fp[1]
		if cw == 1 and ch == 1:
			break

		var candidates: Array = _get_free_mask_cells()
		_rng_shuffle(candidates)

		for anchor in candidates:
			if not _can_place_footprint(anchor, cw, ch):
				continue
			var rid: int = _next_room_id
			_next_room_id += 1
			_mark_grid(anchor, cw, ch, rid)
			_room_defs_map[rid] = {
				"id": rid, "col": anchor.x, "row": anchor.y,
				"cw": cw, "ch": ch, "label": "Room",
				"color": Color(0.14, 0.14, 0.14, 0.35), "type": RT_PASSAGE, "faction": -1,
			}


func _get_free_mask_cells() -> Array:
	## Returns all island mask cells not yet occupied by a room.
	var result: Array = []
	for cell in _island_mask:
		if _grid.has(cell) and _grid[cell] == -1:
			result.append(cell)
	return result


func _can_place_footprint(anchor: Vector2i, cw: int, ch: int) -> bool:
	## True if all cells of this footprint are in the island mask and free.
	for dc in cw:
		for dr in ch:
			var cell := Vector2i(anchor.x + dc, anchor.y + dr)
			if not _island_mask.has(cell):
				return false
			if not _grid.has(cell):
				return false
			if _grid[cell] != -1:
				return false
	return true


# ------------------------------------------------------------------------------
# Pass 3: Room type assignment
# ------------------------------------------------------------------------------

func _assign_room_types() -> void:
	## Assign gameplay types to all neutral rooms based on distance from
	## nearest faction spawn.

	# Build distance map for placed neutral rooms
	var neutral_rooms: Array = []
	var faction_room_ids: Dictionary = {}
	for fs in FACTION_STARTS:
		faction_room_ids[fs["home_room"]] = true
		faction_room_ids[fs["bank_room"]] = true
		faction_room_ids[fs["river_room"]] = true

	for rid in _room_defs_map:
		if faction_room_ids.has(rid):
			continue
		neutral_rooms.append(rid)

	# Compute distance per neutral room (min manhattan distance from any faction spawn cell)
	var dist_map: Dictionary = {}
	for rid in neutral_rooms:
		var rd: Dictionary = _room_defs_map[rid]
		var room_center := Vector2i(rd["col"] + rd["cw"] / 2, rd["row"] + rd["ch"] / 2)
		var min_d: int = 999
		for sc in _faction_spawn_cells:
			var d: int = absi(room_center.x - sc.x) + absi(room_center.y - sc.y)
			if d < min_d:
				min_d = d
		dist_map[rid] = min_d

	# Targets
	var total_neutral: int = neutral_rooms.size()
	var target_rivers: int = maxi(1, total_neutral / 6)
	var target_quarries: int = maxi(1, total_neutral / 4)
	var target_enemies: int = maxi(1, total_neutral / 8)
	var target_diamonds: int = maxi(1, total_neutral / 10)
	var rivers_placed: int = 0
	var quarries_placed: int = 0
	var enemies_placed: int = 0
	var diamonds_placed: int = 0

	# Sort by distance
	neutral_rooms.sort_custom(func(a, b): return dist_map[a] < dist_map[b])

	for rid in neutral_rooms:
		var rd: Dictionary = _room_defs_map[rid]
		var d: int = dist_map[rid]
		var room_type: String = _choose_room_type(
			d, rd["cw"], rd["ch"],
			rivers_placed, target_rivers,
			quarries_placed, target_quarries,
			enemies_placed, target_enemies,
			diamonds_placed, target_diamonds)

		match room_type:
			RT_RIVER:     rivers_placed += 1
			RT_QUARRY:    quarries_placed += 1
			RT_ENEMY_DEN: enemies_placed += 1
			RT_DIAMOND:   diamonds_placed += 1

		rd["type"] = room_type
		rd["label"] = ROOM_LABELS.get(room_type, "Room")
		rd["color"] = ROOM_COLORS.get(room_type, Color(0.14, 0.14, 0.14, 0.35))

		if room_type == RT_RIVER:
			_river_room_ids.append(rid)


func _choose_room_type(dist: int, cw: int, ch: int,
		rivers_placed: int, target_rivers: int,
		quarries_placed: int, target_quarries: int,
		enemies_placed: int, target_enemies: int,
		diamonds_placed: int = 0, target_diamonds: int = 1) -> String:

	var area: int = cw * ch

	if dist <= 2:
		return RT_PASSAGE

	if dist <= 4:
		var roll: float = _rng.randf()
		if rivers_placed < target_rivers and roll < 0.2:
			return RT_RIVER
		if quarries_placed < target_quarries and roll < 0.45:
			return RT_QUARRY
		if area >= 3 and roll < 0.55:
			return RT_COLORLESS_PASSAGE
		return RT_PASSAGE

	# Far zone
	var roll: float = _rng.randf()
	if diamonds_placed < target_diamonds and roll < 0.12:
		return RT_DIAMOND
	if rivers_placed < target_rivers and roll < 0.25:
		return RT_RIVER
	if enemies_placed < target_enemies and roll < 0.4:
		return RT_ENEMY_DEN
	if quarries_placed < target_quarries and roll < 0.45:
		return RT_QUARRY
	if area >= 2 and roll < 0.58:
		return RT_COLORLESS_CAMP
	if roll < 0.72:
		return RT_CONTESTED
	return RT_PASSAGE


# ------------------------------------------------------------------------------
# Portal pair assignment
# ------------------------------------------------------------------------------

func _assign_portal_pair() -> void:
	## Pick two far-apart neutral rooms and retype them as portal pairs.
	var faction_room_ids: Dictionary = {}
	for fs in FACTION_STARTS:
		faction_room_ids[fs["home_room"]] = true
		faction_room_ids[fs["bank_room"]] = true
		faction_room_ids[fs["river_room"]] = true

	var candidates: Array = []
	for rid in _room_defs_map:
		if faction_room_ids.has(rid):
			continue
		var rd: Dictionary = _room_defs_map[rid]
		var rtype: String = rd["type"]
		if rtype == RT_RIVER or rtype == RT_DIAMOND:
			continue
		candidates.append(rid)

	if candidates.size() < 2:
		return

	# Find the pair with maximum Manhattan distance between room centers
	var best_a: int = -1
	var best_b: int = -1
	var best_dist: int = -1
	for i in candidates.size():
		var ra: Dictionary = _room_defs_map[candidates[i]]
		var ca := Vector2i(ra["col"] + ra["cw"] / 2, ra["row"] + ra["ch"] / 2)
		for j in range(i + 1, candidates.size()):
			var rb: Dictionary = _room_defs_map[candidates[j]]
			var cb := Vector2i(rb["col"] + rb["cw"] / 2, rb["row"] + rb["ch"] / 2)
			var d: int = absi(ca.x - cb.x) + absi(ca.y - cb.y)
			if d > best_dist:
				best_dist = d
				best_a = candidates[i]
				best_b = candidates[j]

	if best_a < 0 or best_b < 0:
		return

	for rid in [best_a, best_b]:
		var rd: Dictionary = _room_defs_map[rid]
		rd["type"] = RT_PORTAL
		rd["label"] = ROOM_LABELS[RT_PORTAL]
		rd["color"] = ROOM_COLORS[RT_PORTAL]

	portal_pairs[best_a] = best_b
	portal_pairs[best_b] = best_a
	print("Portal pair: room %d <-> room %d (distance %d)" % [best_a, best_b, best_dist])


# ==============================================================================
# BUILD ROOM_DEFS ARRAY
# ==============================================================================

func _build_room_defs_array() -> void:
	ROOM_DEFS.clear()
	for rid in _room_defs_map:
		var rd: Dictionary = _room_defs_map[rid]
		ROOM_DEFS.append([
			rd["id"], rd["col"], rd["row"], rd["cw"], rd["ch"],
			rd["label"], rd["color"],
		])


# ==============================================================================
# ROOM INSTANTIATION
# ==============================================================================

func _generate_rooms(container: Node2D, room_scene: PackedScene) -> void:
	room_map.clear()
	for rid in _room_defs_map:
		var rd: Dictionary = _room_defs_map[rid]
		var r = room_scene.instantiate()
		r.room_id = rid
		r.room_size = room_pixel_size(rd["cw"], rd["ch"])
		r.room_label = rd["label"]
		r.room_color = rd["color"]
		r.position = room_pixel_pos(rd["col"], rd["row"])
		container.add_child(r)
		room_map[rid] = r


# ==============================================================================
# WALL GENERATION
# ==============================================================================

func _generate_walls(container: Node2D, wall_scene: PackedScene) -> void:
	var cell_to_room: Dictionary = {}
	for rid in _room_defs_map:
		var rd: Dictionary = _room_defs_map[rid]
		for dc in rd["cw"]:
			for dr in rd["ch"]:
				cell_to_room[Vector2i(rd["col"] + dc, rd["row"] + dr)] = rid

	var wall_pairs: Dictionary = {}
	for cell in cell_to_room:
		var rid_a: int = cell_to_room[cell]
		for neighbor_offset in [Vector2i(1, 0), Vector2i(0, 1)]:
			var neighbor: Vector2i = cell + neighbor_offset
			if not cell_to_room.has(neighbor):
				continue
			var rid_b: int = cell_to_room[neighbor]
			if rid_b == rid_a:
				continue
			var key: String = "%d_%d" % [mini(rid_a, rid_b), maxi(rid_a, rid_b)]
			if not wall_pairs.has(key):
				var is_h: bool = (neighbor_offset.y == 1)
				wall_pairs[key] = {
					"a": mini(rid_a, rid_b), "b": maxi(rid_a, rid_b),
					"cells": [], "orient": "h" if is_h else "v",
				}
			wall_pairs[key]["cells"].append(cell)

	for key in wall_pairs:
		var wp: Dictionary = wall_pairs[key]
		var door_allowed: bool = _is_door_allowed(wp["a"], wp["b"])
		var cells: Array = wp["cells"]
		var start_pos: Vector2
		var end_pos: Vector2

		if wp["orient"] == "v":
			cells.sort_custom(func(a, b): return a.y < b.y)
			var col: int = cells[0].x
			var x: float = (col + 1) * (CELL + MAP_GAP) - MAP_GAP / 2.0
			start_pos = Vector2(x, cells[0].y * (CELL + MAP_GAP))
			end_pos = Vector2(x, (cells[cells.size()-1].y + 1) * (CELL + MAP_GAP) - MAP_GAP)
		else:
			cells.sort_custom(func(a, b): return a.x < b.x)
			var row: int = cells[0].y
			var y: float = (row + 1) * (CELL + MAP_GAP) - MAP_GAP / 2.0
			start_pos = Vector2(cells[0].x * (CELL + MAP_GAP), y)
			end_pos = Vector2((cells[cells.size()-1].x + 1) * (CELL + MAP_GAP) - MAP_GAP, y)

		if door_allowed:
			_spawn_wall_with_door(container, wall_scene, wp, start_pos, end_pos)
		else:
			_spawn_solid_wall(container, wall_scene, wp, start_pos, end_pos)


func _is_door_allowed(rid_a: int, rid_b: int) -> bool:
	if _door_restrictions.has(rid_a) and rid_b not in _door_restrictions[rid_a]:
		return false
	if _door_restrictions.has(rid_b) and rid_a not in _door_restrictions[rid_b]:
		return false
	return true


func _spawn_solid_wall(container: Node2D, wall_scene: PackedScene,
		wp: Dictionary, start_pos: Vector2, end_pos: Vector2) -> void:
	var w = wall_scene.instantiate()
	w.room_a_id = wp["a"]; w.room_b_id = wp["b"]
	w.start_pos = start_pos; w.end_pos = end_pos
	w.is_door = false; w.is_open = false
	container.add_child(w)


func _spawn_wall_with_door(container: Node2D, wall_scene: PackedScene,
		wp: Dictionary, start_pos: Vector2, end_pos: Vector2) -> void:
	var dir := (end_pos - start_pos).normalized()
	var mid := (start_pos + end_pos) * 0.5
	var half_door := DOOR_SIZE * 0.5
	var door_start := mid - dir * half_door
	var door_end := mid + dir * half_door

	if start_pos.distance_to(door_start) > 20.0:
		var w1 = wall_scene.instantiate()
		w1.room_a_id = wp["a"]; w1.room_b_id = wp["b"]
		w1.start_pos = start_pos; w1.end_pos = door_start
		container.add_child(w1)

	var door = wall_scene.instantiate()
	door.room_a_id = wp["a"]; door.room_b_id = wp["b"]
	door.start_pos = door_start; door.end_pos = door_end
	door.is_open = false; door.is_door = true
	container.add_child(door)

	if door_end.distance_to(end_pos) > 20.0:
		var w2 = wall_scene.instantiate()
		w2.room_a_id = wp["a"]; w2.room_b_id = wp["b"]
		w2.start_pos = door_end; w2.end_pos = end_pos
		container.add_child(w2)


func _spawn_layout_contents(layout_key: String, room_id: int, room_pos: Vector2, room_size: Vector2,
		containers: Dictionary, scenes: Dictionary, faction_id: int = -1) -> bool:
	var layout_scene: PackedScene = _room_layout_scenes.get(layout_key, null)
	if layout_scene == null:
		return false
	var layout = layout_scene.instantiate()
	if layout == null or not layout.has_method("get_spawn_markers") or not layout.has_method("get_room_position_for_marker"):
		if layout != null:
			layout.free()
		return false

	var room_node = room_map.get(room_id, null)
	for marker in layout.get_spawn_markers():
		var spawn_kind: String = str(marker.get("spawn_kind"))
		var spawn_pos: Vector2 = layout.get_room_position_for_marker(marker, room_pos, room_size)
		match spawn_kind:
			"stone":
				_spawn_resource_at_position(containers, scenes, spawn_pos, "stone")
			"fish":
				_spawn_fish_at_position(containers, scenes, spawn_pos)
			"diamond":
				_spawn_resource_at_position(containers, scenes, spawn_pos, "diamond")
			"enemy":
				_spawn_enemy_at_position(containers, scenes, spawn_pos)
			"colorless":
				_spawn_colorless_at_position(containers, scenes, spawn_pos)
			"bank":
				var bank = scenes["bank"].instantiate()
				containers["banks"].add_child(bank)
				bank.global_position = spawn_pos
				bank.placed_by_faction = -2
			"fishing_hut":
				var hut = scenes["hut"].instantiate()
				containers["huts"].add_child(hut)
				hut.global_position = spawn_pos
				hut.placed_by_faction = -2
			"town_hall":
				if faction_id >= 0 and scenes.has("town_hall") and containers.has("town_halls"):
					var th = scenes["town_hall"].instantiate()
					containers["town_halls"].add_child(th)
					th.global_position = spawn_pos
					th.placed_by_faction = faction_id
			"portal":
				if scenes.has("portal"):
					var p = scenes["portal"].instantiate()
					containers["portals"].add_child(p)
					p.global_position = spawn_pos
					p.room_id = room_id
					p.partner_room_id = portal_pairs.get(room_id, -1)
			"river":
				if room_node != null and scenes.has("river"):
					var river = scenes["river"].instantiate()
					room_node.add_child(river)
					river.position = spawn_pos - room_node.global_position
			"red", "yellow", "blue":
				if faction_id >= 0:
					var v = scenes["villager"].instantiate()
					containers["villagers"].add_child(v)
					v.setup(spawn_kind, spawn_pos)
					v.faction_id = faction_id
					if spawn_kind == "red":
						v._satiation_timer = v.SATIATION_PER_LEVEL[1]
						v.is_fed = true
			"magic_orb":
				if faction_id >= 0:
					var orb = scenes["villager"].instantiate()
					containers["villagers"].add_child(orb)
					orb.setup("magic_orb", spawn_pos)
					orb.faction_id = faction_id

	layout.free()
	return true


func _spawn_resource_at_position(containers: Dictionary, scenes: Dictionary, pos: Vector2, resource_type: String = "stone") -> void:
	var c = scenes["collectable"].instantiate()
	containers["collectables"].add_child(c)
	c.global_position = pos
	c.resource_type = resource_type


func _spawn_fish_at_position(containers: Dictionary, scenes: Dictionary, pos: Vector2) -> void:
	var f = scenes["fish"].instantiate()
	containers["fish"].add_child(f)
	f.global_position = pos


func _spawn_enemy_at_position(containers: Dictionary, scenes: Dictionary, pos: Vector2) -> void:
	var e = scenes["enemy"].instantiate()
	containers["enemies"].add_child(e)
	e.global_position = pos


func _spawn_colorless_at_position(containers: Dictionary, scenes: Dictionary, pos: Vector2) -> void:
	var v = scenes["villager"].instantiate()
	containers["villagers"].add_child(v)
	v.setup("colorless", pos)
	v.faction_id = -1


# ==============================================================================
# ENTITY GENERATION — neutral rooms
# ==============================================================================

func _generate_entities(containers: Dictionary, scenes: Dictionary) -> void:
	var faction_room_ids: Array = []
	for fi in FACTION_STARTS:
		faction_room_ids.append(fi["home_room"])
		faction_room_ids.append(fi["bank_room"])
		faction_room_ids.append(fi["river_room"])

	for rid in _room_defs_map:
		if rid in faction_room_ids:
			continue
		var rd: Dictionary = _room_defs_map[rid]
		var rtype: String = rd["type"]
		var rpos: Vector2 = room_pixel_pos(rd["col"], rd["row"])
		var rsize: Vector2 = room_pixel_size(rd["cw"], rd["ch"])
		var center: Vector2 = rpos + rsize * 0.5

		match rtype:
			RT_QUARRY:
				if not _spawn_layout_contents(RT_QUARRY, rid, rpos, rsize, containers, scenes):
					for i in _rng.randi_range(8, 15):
						_spawn_stone(containers, scenes, rpos, rsize)

			RT_RIVER:
				if not _spawn_layout_contents(RT_RIVER, rid, rpos, rsize, containers, scenes):
					var hut = scenes["hut"].instantiate()
					containers["huts"].add_child(hut)
					hut.global_position = Vector2(center.x, rpos.y + 200)
					hut.placed_by_faction = -2
					for i in _rng.randi_range(2, 4):
						_spawn_fish(containers, scenes, rpos, rsize)
					var room_node = room_map.get(rid)
					if room_node and scenes.has("river"):
						var river = scenes["river"].instantiate()
						room_node.add_child(river)
						river.position = Vector2(50, 50)

			RT_ENEMY_DEN:
				if not _spawn_layout_contents(RT_ENEMY_DEN, rid, rpos, rsize, containers, scenes):
					for i in _rng.randi_range(2, 3):
						var e = scenes["enemy"].instantiate()
						containers["enemies"].add_child(e)
						e.global_position = _rand_in_room(rpos, rsize, 100.0)

			RT_COLORLESS_PASSAGE:
				if not _spawn_layout_contents(RT_COLORLESS_PASSAGE, rid, rpos, rsize, containers, scenes):
					for i in _rng.randi_range(1, 3):
						_spawn_colorless(containers, scenes, center)

			RT_COLORLESS_CAMP:
				if not _spawn_layout_contents(RT_COLORLESS_CAMP, rid, rpos, rsize, containers, scenes):
					for i in _rng.randi_range(6, 10):
						_spawn_colorless(containers, scenes, center)

			RT_CONTESTED:
				if not _spawn_layout_contents(RT_CONTESTED, rid, rpos, rsize, containers, scenes):
					for i in _rng.randi_range(1, 2):
						var e = scenes["enemy"].instantiate()
						containers["enemies"].add_child(e)
						e.global_position = _rand_in_room(rpos, rsize, 100.0)
					for i in _rng.randi_range(4, 8):
						_spawn_stone(containers, scenes, rpos, rsize)

			RT_DIAMOND:
				if not _spawn_layout_contents(RT_DIAMOND, rid, rpos, rsize, containers, scenes):
					# Diamond cave: guarded by enemies, contains diamonds
					for i in _rng.randi_range(1, 3):
						var e = scenes["enemy"].instantiate()
						containers["enemies"].add_child(e)
						e.global_position = _rand_in_room(rpos, rsize, 100.0)
					for i in _rng.randi_range(4, 8):
						_spawn_diamond(containers, scenes, rpos, rsize)

			RT_PORTAL:
				if not _spawn_layout_contents(RT_PORTAL, rid, rpos, rsize, containers, scenes):
					# Portal visual entity — spawned at room center
					if scenes.has("portal"):
						var p = scenes["portal"].instantiate()
						containers["portals"].add_child(p)
						p.global_position = center
						p.room_id = rid
						p.partner_room_id = portal_pairs.get(rid, -1)

			RT_STONE:
				if not _spawn_layout_contents(RT_STONE, rid, rpos, rsize, containers, scenes):
					var bank = scenes["bank"].instantiate()
					containers["banks"].add_child(bank)
					bank.global_position = Vector2(center.x, rpos.y + 200)
					bank.placed_by_faction = -2
					for i in _rng.randi_range(8, 15):
						_spawn_stone(containers, scenes, rpos, rsize)


func _spawn_stone(containers: Dictionary, scenes: Dictionary, rpos: Vector2, rsize: Vector2) -> void:
	var c = scenes["collectable"].instantiate()
	containers["collectables"].add_child(c)
	c.global_position = _rand_in_room(rpos, rsize, 60.0)


func _spawn_fish(containers: Dictionary, scenes: Dictionary, rpos: Vector2, rsize: Vector2) -> void:
	var f = scenes["fish"].instantiate()
	containers["fish"].add_child(f)
	f.global_position = _rand_in_room(rpos, rsize, 60.0)


func _spawn_diamond(containers: Dictionary, scenes: Dictionary, rpos: Vector2, rsize: Vector2) -> void:
	var c = scenes["collectable"].instantiate()
	containers["collectables"].add_child(c)
	c.resource_type = "diamond"
	c.global_position = _rand_in_room(rpos, rsize, 60.0)


func _spawn_colorless(containers: Dictionary, scenes: Dictionary, center: Vector2) -> void:
	var v = scenes["villager"].instantiate()
	containers["villagers"].add_child(v)
	v.setup("colorless", center + Vector2(_rng.randf_range(-80, 80), _rng.randf_range(-80, 80)))
	v.faction_id = -1


# ==============================================================================
# FACTION STARTS — spawn balanced starting units per faction
# ==============================================================================

func _generate_faction_starts(containers: Dictionary, scenes: Dictionary) -> void:
	var is_survival: bool = (FactionManager.game_mode == "survival")
	for fi in FACTION_STARTS.size():
		var start: Dictionary = FACTION_STARTS[fi]
		var core_id: int = start["home_room"]
		var stone_id: int = start["bank_room"]
		var river_id: int = start["river_room"]

		var core_rd: Dictionary = _room_defs_map.get(core_id, {})
		var stone_rd: Dictionary = _room_defs_map.get(stone_id, {})
		var river_rd: Dictionary = _room_defs_map.get(river_id, {})

		if core_rd.is_empty():
			continue

		var hpos: Vector2 = room_pixel_pos(core_rd["col"], core_rd["row"])
		var hsize: Vector2 = room_pixel_size(core_rd["cw"], core_rd["ch"])
		var hcenter: Vector2 = hpos + hsize * 0.5
		var margin: float = 150.0

		var core_layout_key: String = LAYOUT_KEY_CORE_SURVIVAL if is_survival else LAYOUT_KEY_CORE_STANDARD
		if not _spawn_layout_contents(core_layout_key, core_id, hpos, hsize, containers, scenes, _faction_id_map[fi]):
			var color_defs: Array
			var orb_pos: Vector2 = hcenter
			if is_survival:
				# Survival: 5 villagers (2R, 2Y, 1B), no orb
				color_defs = [
					{"color": "red",    "fed": true,  "pos": Vector2(hpos.x + margin, hpos.y + margin)},
					{"color": "red",    "fed": true,  "pos": Vector2(hpos.x + margin + 60, hpos.y + margin + 40)},
					{"color": "yellow", "fed": false, "pos": Vector2(hpos.x + hsize.x - margin, hpos.y + margin)},
					{"color": "yellow", "fed": false, "pos": Vector2(hpos.x + hsize.x - margin - 60, hpos.y + margin + 40)},
					{"color": "blue",   "fed": false, "pos": Vector2(hpos.x + margin, hpos.y + hsize.y - margin)},
				]
			else:
				# Standard: 3 villagers + orb — red closest to door, orb furthest
				var spawn_dir: ClusterDir = _cluster_direction(_faction_spawn_cells[fi])
				var door_edge: Vector2
				match spawn_dir:
					ClusterDir.RIGHT: door_edge = Vector2(hpos.x + hsize.x, hpos.y + hsize.y * 0.5)
					ClusterDir.LEFT:  door_edge = Vector2(hpos.x, hpos.y + hsize.y * 0.5)
					ClusterDir.DOWN:  door_edge = Vector2(hpos.x + hsize.x * 0.5, hpos.y + hsize.y)
					_:                door_edge = Vector2(hpos.x + hsize.x * 0.5, hpos.y)
				var corners := [
					Vector2(hpos.x + margin, hpos.y + margin),
					Vector2(hpos.x + hsize.x - margin, hpos.y + margin),
					Vector2(hpos.x + margin, hpos.y + hsize.y - margin),
					Vector2(hpos.x + hsize.x - margin, hpos.y + hsize.y - margin),
				]
				corners.sort_custom(func(a, b): return a.distance_to(door_edge) < b.distance_to(door_edge))
				orb_pos = corners[3]
				color_defs = [
					{"color": "red",    "fed": true,  "pos": corners[0]},
					{"color": "yellow", "fed": false, "pos": corners[1]},
					{"color": "blue",   "fed": false, "pos": corners[2]},
				]
			for cd in color_defs:
				var v = scenes["villager"].instantiate()
				containers["villagers"].add_child(v)
				v.setup(str(cd["color"]), cd["pos"] + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30)))
				v.faction_id = _faction_id_map[fi]
				if cd["fed"]:
					v._satiation_timer = v.SATIATION_PER_LEVEL[1]
					v.is_fed = true

			if not is_survival:
				# Place Town Hall at orb position — orb starts inside
				if scenes.has("town_hall") and containers.has("town_halls"):
					var th = scenes["town_hall"].instantiate()
					containers["town_halls"].add_child(th)
					th.global_position = orb_pos
					th.placed_by_faction = _faction_id_map[fi]
				var orb = scenes["villager"].instantiate()
				containers["villagers"].add_child(orb)
				orb.setup("magic_orb", orb_pos)
				orb.faction_id = _faction_id_map[fi]

		if not stone_rd.is_empty():
			var spos: Vector2 = room_pixel_pos(stone_rd["col"], stone_rd["row"])
			var ssize: Vector2 = room_pixel_size(stone_rd["cw"], stone_rd["ch"])
			var scenter: Vector2 = spos + ssize * 0.5
			if not _spawn_layout_contents(RT_STONE, stone_id, spos, ssize, containers, scenes, _faction_id_map[fi]):
				var bank = scenes["bank"].instantiate()
				containers["banks"].add_child(bank)
				bank.global_position = Vector2(scenter.x, spos.y + 200)
				bank.placed_by_faction = -2
				for i in _rng.randi_range(8, 12):
					_spawn_stone(containers, scenes, spos, ssize)

		if not river_rd.is_empty():
			var rpos: Vector2 = room_pixel_pos(river_rd["col"], river_rd["row"])
			var rsize: Vector2 = room_pixel_size(river_rd["cw"], river_rd["ch"])
			var rcenter: Vector2 = rpos + rsize * 0.5
			if not _spawn_layout_contents(RT_RIVER, river_id, rpos, rsize, containers, scenes, _faction_id_map[fi]):
				var hut = scenes["hut"].instantiate()
				containers["huts"].add_child(hut)
				hut.global_position = rcenter
				hut.placed_by_faction = -2
				for i in _rng.randi_range(1, 3):
					_spawn_fish(containers, scenes, rpos, rsize)
				var room_node = room_map.get(river_id)
				if room_node and scenes.has("river"):
					var river_ob = scenes["river"].instantiate()
					room_node.add_child(river_ob)
					river_ob.position = Vector2(50, 50)


# ==============================================================================
# HELPERS
# ==============================================================================

func _rand_in_room(rpos: Vector2, rsize: Vector2, margin: float) -> Vector2:
	return Vector2(
		_rng.randf_range(rpos.x + margin, rpos.x + rsize.x - margin),
		_rng.randf_range(rpos.y + margin, rpos.y + rsize.y - margin))


func _rng_shuffle(arr: Array) -> void:
	## Fisher-Yates shuffle using seeded RNG.
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ==============================================================================
# DEBUG SUMMARY
# ==============================================================================

func _print_debug_summary() -> void:
	var total_cells: int = _grid_cols * _grid_rows
	var occupied: int = _island_mask.size()
	var empty: int = total_cells - occupied
	var total_rooms: int = _room_defs_map.size()

	# Bounding box of placed rooms
	var min_col: int = _grid_cols; var max_col: int = 0
	var min_row: int = _grid_rows; var max_row: int = 0
	for rid in _room_defs_map:
		var rd: Dictionary = _room_defs_map[rid]
		min_col = mini(min_col, rd["col"])
		max_col = maxi(max_col, rd["col"] + rd["cw"] - 1)
		min_row = mini(min_row, rd["row"])
		max_row = maxi(max_row, rd["row"] + rd["ch"] - 1)

	# Footprint size counts
	var fp_counts: Dictionary = {}
	for rid in _room_defs_map:
		var rd: Dictionary = _room_defs_map[rid]
		var key: String = "%dx%d" % [rd["cw"], rd["ch"]]
		fp_counts[key] = fp_counts.get(key, 0) + 1

	# Room type counts
	var type_counts: Dictionary = {}
	for rid in _room_defs_map:
		var t: String = _room_defs_map[rid]["type"]
		type_counts[t] = type_counts.get(t, 0) + 1

	print("=== MAP GEN DEBUG ===")
	print("Grid: %dx%d (%d total cells)" % [_grid_cols, _grid_rows, total_cells])
	print("Occupied cells: %d (%.0f%%)  |  Empty: %d (%.0f%%)" % [
		occupied, 100.0*occupied/total_cells, empty, 100.0*empty/total_cells])
	print("Playable rooms: %d  |  Bbox: cols %d-%d, rows %d-%d" % [
		total_rooms, min_col, max_col, min_row, max_row])
	print("Footprints: %s" % str(fp_counts))
	print("Room types: %s" % str(type_counts))
	print("Connectivity: %s" % ("PASS" if _is_island_connected() else "FAIL"))

	# ASCII occupancy grid
	var lines: Array = []
	for r in _grid_rows:
		var line: String = ""
		for c in _grid_cols:
			var cell := Vector2i(c, r)
			if _grid.has(cell) and _grid[cell] >= 0:
				var rd: Dictionary = _room_defs_map.get(_grid[cell], {})
				match rd.get("type", ""):
					RT_CORE:     line += "C"
					RT_STONE:    line += "S"
					RT_RIVER:    line += "R"
					RT_QUARRY:   line += "Q"
					RT_ENEMY_DEN: line += "E"
					RT_DIAMOND: line += "D"
					RT_PORTAL: line += "P"
					RT_COLORLESS_CAMP: line += "W"
					RT_COLORLESS_PASSAGE: line += "w"
					RT_CONTESTED: line += "X"
					_:           line += "."
			else:
				line += "~"
		lines.append(line)
	print("Layout (C=Core S=Stone R=River Q=Quarry E=Enemy D=Diamond P=Portal W=WandererCamp w=path X=Contested .=Passage ~=Water):")
	for line in lines:
		print("  " + line)
	print("=====================")
