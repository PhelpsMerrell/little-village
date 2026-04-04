extends Node2D
## Main scene controller. Rooms, walls, villagers, enemies, collectables, homes.

const ENEMY_DUPE_BASE := 0.2
const ENEMY_DUPE_MAX := 100.0
const ENEMY_DUPE_RANGE_MULT := 5.0  # dupe range = enemy radius × this
const TOUCH_DIST_BONUS := 4.0
const ENEMY_MERGE_COUNT := 4
const ENEMY_MERGE_DIST := 100.0
const BLUE_MERGE_COUNT := 3
const BLUE_MERGE_DIST := 120.0
const RED_LEVEL2_KILLS := 10
const RED_LEVEL3_KILLS := 30
const YELLOW_PAIR_DIST := 100.0
const HOME_SHELTER_DIST := 80.0

var rooms: Array = []
var room_map: Dictionary = {}
var walls: Array = []
var villagers: Array = []
var enemies: Array = []
var collectables: Array = []
var homes: Array = []

var room_villagers: Dictionary = {}
var room_enemies: Dictionary = {}

@onready var _rooms_container: Node2D = $Rooms
@onready var _wall_container: Node2D = $Walls
@onready var _villager_container: Node2D = $Villagers
@onready var _enemy_container: Node2D = $Enemies
@onready var _collectables_container: Node2D = $Collectables
@onready var _homes_container: Node2D = $Homes
@onready var _hud: Control = $UI/HUD

var _villager_scene: PackedScene = preload("res://scenes/villager.tscn")
var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
var _home_scene: PackedScene = preload("res://scenes/home.tscn")

var _placing_item: String = ""   # "" = not placing, "house" = placing house


func _ready() -> void:
	_collect_rooms()
	_collect_walls()
	_collect_villagers()
	_collect_enemies()
	_collect_collectables()
	_collect_homes()
	InfluenceManager.villager_shifted.connect(_on_villager_shifted)
	GameClock.phase_changed.connect(_on_phase_changed)
	_hud.buy_requested.connect(_on_buy_requested)


func _process(delta: float) -> void:
	_assign_entities_to_rooms()
	_update_obstacles()
	_process_collectables()
	_process_combat(delta)
	_process_enemy_duplication(delta)
	_process_enemy_merging()
	_process_red_leveling()
	_process_blue_merging()
	_process_yellow_leveling(delta)
	_process_home_sheltering()

	var wall_data: Array = []
	for w in walls:
		wall_data.append({"room_a": w.room_a_id, "room_b": w.room_b_id, "is_open": w.is_open})
	InfluenceManager.process_influence(room_villagers, wall_data, delta)

	_update_hud()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _placing_item != "":
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				_finalize_placement(get_global_mouse_position())
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_placement()
				get_viewport().set_input_as_handled()


func _draw() -> void:
	# Placement ghost
	if _placing_item == "house":
		var mpos: Vector2 = get_local_mouse_position()
		# Ghost house outline
		var hw := 40.0
		var hh := 40.0
		draw_rect(Rect2(mpos.x - hw * 0.8, mpos.y - hh * 0.3, hw * 1.6, hh * 1.3),
			Color(0.55, 0.4, 0.25, 0.4))
		var roof := PackedVector2Array([
			Vector2(mpos.x, mpos.y - hh),
			Vector2(mpos.x + hw, mpos.y - hh * 0.3),
			Vector2(mpos.x - hw, mpos.y - hh * 0.3),
		])
		draw_colored_polygon(roof, Color(0.6, 0.2, 0.15, 0.4))
		draw_string(ThemeDB.fallback_font, Vector2(mpos.x - 40, mpos.y + hh + 16),
			"Click to place  •  Right-click cancel",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.7, 0.7))


# ── placement ────────────────────────────────────────────────────────────────

func _finalize_placement(pos: Vector2) -> void:
	if _placing_item == "house":
		_place_home(pos)
	_placing_item = ""

func _cancel_placement() -> void:
	# Refund
	if _placing_item == "house":
		Economy.stone += 5
	_placing_item = ""


# ── discovery ────────────────────────────────────────────────────────────────

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
	for child in _wall_container.get_children():
		walls.append(child)

func _collect_villagers() -> void:
	villagers.clear()
	for child in _villager_container.get_children():
		villagers.append(child)

func _collect_enemies() -> void:
	enemies.clear()
	for child in _enemy_container.get_children():
		enemies.append(child)

func _collect_collectables() -> void:
	collectables.clear()
	for child in _collectables_container.get_children():
		collectables.append(child)

func _collect_homes() -> void:
	homes.clear()
	for child in _homes_container.get_children():
		homes.append(child)


# ── room assignment ──────────────────────────────────────────────────────────

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

	for e in enemies:
		if e.is_dead:
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


# ── obstacles ────────────────────────────────────────────────────────────────

func _update_obstacles() -> void:
	var checked_rooms: Dictionary = {}
	for v in villagers:
		var room = room_map.get(v.current_room_id)
		if room:
			v.blocked_rects = room.get_blocked_rects_for(v.color_type)
			if not checked_rooms.has(v.current_room_id):
				checked_rooms[v.current_room_id] = true
				for child in room.get_children():
					if child.has_method("check_break"):
						child.check_break(room_villagers.get(v.current_room_id, []))


# ── collectables ─────────────────────────────────────────────────────────────

func _process_collectables() -> void:
	var to_remove: Array = []
	for c in collectables:
		if not is_instance_valid(c) or c.collected:
			to_remove.append(c)
			continue
		for v in villagers:
			if c.try_collect(v):
				break
	for c in to_remove:
		collectables.erase(c)


# ── combat ───────────────────────────────────────────────────────────────────

func _process_combat(_delta: float) -> void:
	var dead_villagers: Array = []
	var dead_enemies: Array = []

	for rid in room_enemies:
		for enemy in room_enemies[rid]:
			for v in room_villagers.get(rid, []):
				var dist: float = enemy.global_position.distance_to(v.global_position)
				var touch: float = float(enemy.radius) + float(v.radius) + TOUCH_DIST_BONUS
				if dist > touch:
					continue
				if ColorRegistry.has_ability(str(v.color_type), "damage"):
					var killed: bool = enemy.take_red_hit(int(v.level))
					v.record_kill()
					if killed and enemy not in dead_enemies:
						dead_enemies.append(enemy)
					continue
				var result: String = enemy.try_attack(v)
				if result == "kill" and v not in dead_villagers:
					dead_villagers.append(v)

	for v in dead_villagers:
		_remove_villager(v)
	for e in dead_enemies:
		_remove_enemy(e)


func _remove_villager(v: Node) -> void:
	villagers.erase(v)
	v.queue_free()

func _remove_enemy(e: Node) -> void:
	enemies.erase(e)
	e.die()


# ── enemy duplication (L1 only, range-based, diminishing) ────────────────────

func _process_enemy_duplication(delta: float) -> void:
	for rid in room_enemies:
		var l1_enemies: Array = []
		for e in room_enemies[rid]:
			if e.level == 1:
				l1_enemies.append(e)

		# For each L1 enemy, count nearby L1 neighbors within dupe range
		for e in l1_enemies:
			var dupe_range: float = e.radius * ENEMY_DUPE_RANGE_MULT
			var nearby: int = 0
			for other in l1_enemies:
				if other == e:
					continue
				var d: float = e.global_position.distance_to(other.global_position)
				if d < dupe_range:
					nearby += 1

			if nearby < 1:
				e.dupe_meter = maxf(0.0, e.dupe_meter - 5.0 * delta)
				continue

			# Diminishing returns based on total nearby
			var doublings: float = log(float(nearby + 1) / 2.0) / log(2.0)
			doublings = maxf(doublings, 0.0)
			var rate: float = ENEMY_DUPE_BASE * pow(0.9, doublings)
			e.dupe_meter += rate * 10.0 * delta

		# Spawn from first enemy to hit max
		var spawned: bool = false
		for e in l1_enemies:
			if e.dupe_meter >= ENEMY_DUPE_MAX and not spawned:
				e.dupe_meter = 0.0
				_spawn_enemy(e.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50)), 1)
				spawned = true


# ── enemy merging ────────────────────────────────────────────────────────────

func _process_enemy_merging() -> void:
	for rid in room_enemies:
		var by_level: Dictionary = {1: [], 2: []}
		for e in room_enemies[rid]:
			if e.level < 3:
				var lv: int = e.level
				if not by_level.has(lv):
					by_level[lv] = []
				by_level[lv].append(e)

		for lv in by_level:
			var group: Array = by_level[lv]
			if group.size() < ENEMY_MERGE_COUNT:
				continue
			var cluster := _find_enemy_cluster(group)
			if cluster.size() >= ENEMY_MERGE_COUNT:
				var survivor = cluster[0]
				survivor.set_level(lv + 1)
				for i in range(1, ENEMY_MERGE_COUNT):
					_remove_enemy(cluster[i])

func _find_enemy_cluster(group: Array) -> Array:
	for i in group.size():
		var cluster: Array = [group[i]]
		for j in group.size():
			if i == j:
				continue
			var d: float = group[i].global_position.distance_to(group[j].global_position)
			if d < ENEMY_MERGE_DIST:
				cluster.append(group[j])
				if cluster.size() >= ENEMY_MERGE_COUNT:
					return cluster
	return []

func _spawn_enemy(pos: Vector2, p_level: int = 1) -> void:
	var e = _enemy_scene.instantiate()
	_enemy_container.add_child(e)
	e.global_position = pos
	e.set_level(p_level)
	enemies.append(e)


# ── homes / sheltering ──────────────────────────────────────────────────────

func _process_home_sheltering() -> void:
	if not GameClock.is_daytime:
		for h in homes:
			if h.is_full():
				continue
			for v in villagers:
				if not v.visible:
					continue
				var dist: float = v.global_position.distance_to(h.global_position)
				if dist < HOME_SHELTER_DIST:
					h.shelter_villager(v)


func _on_phase_changed(is_daytime: bool) -> void:
	if is_daytime:
		for h in homes:
			h.release_all()


func _on_buy_requested(item_id: String) -> void:
	if Economy.purchase(item_id):
		_placing_item = item_id


func _place_home(pos: Vector2) -> void:
	var h = _home_scene.instantiate()
	_homes_container.add_child(h)
	h.global_position = pos
	homes.append(h)


# ── villager leveling ────────────────────────────────────────────────────────

func _process_red_leveling() -> void:
	for v in villagers:
		if v.color_type != "red":
			continue
		if v.level == 1 and v.kill_count >= RED_LEVEL2_KILLS:
			v.set_level(2)
		elif v.level == 2 and v.kill_count >= RED_LEVEL3_KILLS:
			v.set_level(3)

func _process_blue_merging() -> void:
	for rid in room_villagers:
		var blues_by_level: Dictionary = {1: [], 2: []}
		for v in room_villagers[rid]:
			if v.color_type == "blue" and v.level < 3:
				var lv: int = v.level
				if not blues_by_level.has(lv):
					blues_by_level[lv] = []
				blues_by_level[lv].append(v)

		for lv in blues_by_level:
			var blues: Array = blues_by_level[lv]
			if blues.size() < BLUE_MERGE_COUNT:
				continue
			var merged := _find_blue_cluster(blues)
			if merged.size() == BLUE_MERGE_COUNT:
				var survivor = merged[0]
				survivor.set_level(lv + 1)
				for i in range(1, BLUE_MERGE_COUNT):
					_remove_villager(merged[i])

func _find_blue_cluster(blues: Array) -> Array:
	for i in blues.size():
		var cluster: Array = [blues[i]]
		for j in blues.size():
			if i == j:
				continue
			var d: float = blues[i].global_position.distance_to(blues[j].global_position)
			if d < BLUE_MERGE_DIST:
				cluster.append(blues[j])
				if cluster.size() >= BLUE_MERGE_COUNT:
					return cluster
	return []

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
			var yi = yellows[i]
			for j in range(i + 1, yellows.size()):
				if paired.has(j):
					continue
				var yj = yellows[j]
				if yi.level != yj.level:
					continue
				var d: float = yi.global_position.distance_to(yj.global_position)
				if d < YELLOW_PAIR_DIST:
					yi.leveling_partner = yj
					yj.leveling_partner = yi
					yi.leveling_meter += delta
					yj.leveling_meter += delta
					if yi.leveling_meter >= yi.YELLOW_LEVEL_TIME:
						yi.set_level(yi.level + 1)
						yi.leveling_meter = 0.0
						yj.set_level(yj.level + 1)
						yj.leveling_meter = 0.0
					paired[i] = true
					paired[j] = true
					break

		for k in yellows.size():
			if not paired.has(k):
				yellows[k].leveling_meter = maxf(0.0, yellows[k].leveling_meter - delta * 0.5)
				yellows[k].leveling_partner = null


# ── shift handling ───────────────────────────────────────────────────────────

func _on_villager_shifted(villager, _old_color, new_color, spawn_count) -> void:
	villager.set_color_type(str(new_color))
	for i in range(int(spawn_count) - 1):
		var offset := Vector2(randf_range(-50, 50), randf_range(-50, 50))
		_spawn_villager(str(new_color), villager.global_position + offset)

func _spawn_villager(color_id: String, pos: Vector2) -> void:
	var v = _villager_scene.instantiate()
	_villager_container.add_child(v)
	v.setup(color_id, pos)
	villagers.append(v)


# ── HUD ──────────────────────────────────────────────────────────────────────

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
	_hud.pop_enemies = enemies.size()
	_hud.pop_total = villagers.size()
