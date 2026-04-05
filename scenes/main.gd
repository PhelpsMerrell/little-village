extends Node2D
## Main scene controller. Orchestrates all game systems.
## Reds shoot enemies (ranged). Enemies touch-attack villagers.

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
const RED_HUNGER_INTERVAL := 60.0
const RED_STARVE_DPS := 2.0

var rooms: Array = []
var room_map: Dictionary = {}
var walls: Array = []
var villagers: Array = []
var enemies: Array = []
var collectables: Array = []
var fish_spots: Array = []
var homes: Array = []
var banks: Array = []
var fishing_huts: Array = []

var room_villagers: Dictionary = {}
var room_enemies: Dictionary = {}
var _hunger_timer: float = 0.0

@onready var _rooms_container: Node2D = $Rooms
@onready var _wall_container: Node2D = $Walls
@onready var _villager_container: Node2D = $Villagers
@onready var _enemy_container: Node2D = $Enemies
@onready var _collectables_container: Node2D = $Collectables
@onready var _fish_container: Node2D = $FishSpots
@onready var _homes_container: Node2D = $Homes
@onready var _banks_container: Node2D = $Banks
@onready var _huts_container: Node2D = $FishingHuts
@onready var _hud: Control = $UI/HUD

var _villager_scene: PackedScene = preload("res://scenes/villager.tscn")
var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
var _home_scene: PackedScene = preload("res://scenes/home.tscn")
var _placing_item: String = ""


func _ready() -> void:
	_collect_all()
	InfluenceManager.villager_shifted.connect(_on_villager_shifted)
	GameClock.phase_changed.connect(_on_phase_changed)
	_hud.buy_requested.connect(_on_buy_requested)


func _collect_all() -> void:
	_collect_rooms(); _collect_walls(); _collect_villagers(); _collect_enemies()
	collectables.clear()
	for c in _collectables_container.get_children(): collectables.append(c)
	fish_spots.clear()
	for f in _fish_container.get_children(): fish_spots.append(f)
	homes.clear()
	for h in _homes_container.get_children(): homes.append(h)
	banks.clear()
	for b in _banks_container.get_children(): banks.append(b)
	fishing_huts.clear()
	for h in _huts_container.get_children(): fishing_huts.append(h)

func _collect_rooms() -> void:
	rooms.clear(); room_map.clear()
	for child in _rooms_container.get_children():
		if child.has_method("get_rect"):
			rooms.append(child)
			room_map[child.room_id] = child
			room_villagers[child.room_id] = []
			room_enemies[child.room_id] = []

func _collect_walls() -> void:
	walls.clear()
	for w in _wall_container.get_children(): walls.append(w)

func _collect_villagers() -> void:
	villagers.clear()
	for v in _villager_container.get_children(): villagers.append(v)

func _collect_enemies() -> void:
	enemies.clear()
	for e in _enemy_container.get_children(): enemies.append(e)


# ── main loop ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_assign_entities_to_rooms()
	_update_obstacles()
	_update_brain_context()
	_process_stone_pickups()
	_process_fish_pickups()
	_process_deposits()
	_process_enemy_attacks(delta)
	_process_red_shooting()
	_process_red_hunger(delta)
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
	if _placing_item != "" and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_finalize_placement(get_global_mouse_position())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
			get_viewport().set_input_as_handled()

func _draw() -> void:
	if _placing_item == "house":
		var mpos: Vector2 = get_local_mouse_position()
		draw_rect(Rect2(mpos.x - 32, mpos.y - 16, 64, 52), Color(0.55, 0.4, 0.25, 0.4))
		var roof := PackedVector2Array([Vector2(mpos.x, mpos.y - 40), Vector2(mpos.x + 40, mpos.y - 16), Vector2(mpos.x - 40, mpos.y - 16)])
		draw_colored_polygon(roof, Color(0.6, 0.2, 0.15, 0.4))
		draw_string(ThemeDB.fallback_font, Vector2(mpos.x - 40, mpos.y + 50),
			"Click to place  •  Right-click cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.7, 0.7))

func _finalize_placement(pos: Vector2) -> void:
	if _placing_item == "house":
		var h = _home_scene.instantiate()
		_homes_container.add_child(h)
		h.global_position = pos
		homes.append(h)
	_placing_item = ""

func _cancel_placement() -> void:
	if _placing_item == "house":
		Economy.stone += 5
	_placing_item = ""


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
		if e.is_dead: continue
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
			best_d = d; best_id = int(room.room_id)
	return best_id


# ── brain context ────────────────────────────────────────────────────────────

func _update_brain_context() -> void:
	for v in villagers:
		var rid: int = v.current_room_id
		v.brain_enemies = room_enemies.get(rid, [])
		v.brain_room_villagers = room_villagers.get(rid, [])
		v.has_deposit_in_room = false
		v.brain_has_resource = false

		match str(v.color_type):
			"yellow":
				# Find nearest uncollected stone in same room
				var best_d: float = INF
				for c in collectables:
					if not is_instance_valid(c) or c.collected: continue
					if _room_id_at(c.global_position) != rid: continue
					var d: float = v.global_position.distance_to(c.global_position)
					if d < best_d:
						best_d = d
						v.brain_nearest_resource_pos = c.global_position
						v.brain_has_resource = true
				# Bank in room?
				if str(v.carrying_resource) == "stone":
					for b in banks:
						if _room_id_at(b.global_position) == rid:
							v.deposit_position = b.global_position
							v.has_deposit_in_room = true
							break
			"blue":
				# Find nearest uncollected fish in same room
				var best_d: float = INF
				for f in fish_spots:
					if not is_instance_valid(f) or f.collected: continue
					if _room_id_at(f.global_position) != rid: continue
					var d: float = v.global_position.distance_to(f.global_position)
					if d < best_d:
						best_d = d
						v.brain_nearest_resource_pos = f.global_position
						v.brain_has_resource = true
				# Fishing hut in room?
				if str(v.carrying_resource) == "fish":
					for h in fishing_huts:
						if _room_id_at(h.global_position) == rid:
							v.deposit_position = h.global_position
							v.has_deposit_in_room = true
							break


# ── obstacles ────────────────────────────────────────────────────────────────

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


# ── resource pickups ─────────────────────────────────────────────────────────

func _process_stone_pickups() -> void:
	var to_remove: Array = []
	for c in collectables:
		if not is_instance_valid(c) or c.collected:
			to_remove.append(c); continue
		for v in villagers:
			if c.try_collect(v): break
	for c in to_remove:
		collectables.erase(c)

func _process_fish_pickups() -> void:
	var to_remove: Array = []
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected:
			to_remove.append(f); continue
		for v in villagers:
			if f.try_collect(v): break
	for f in to_remove:
		fish_spots.erase(f)


# ── deposits ─────────────────────────────────────────────────────────────────

func _process_deposits() -> void:
	for b in banks:
		for v in villagers:
			if str(v.carrying_resource) == "stone": b.try_deposit(v)
	for h in fishing_huts:
		for v in villagers:
			if str(v.carrying_resource) == "fish": h.try_deposit(v)


# ── red hunger ───────────────────────────────────────────────────────────────

func _process_red_hunger(delta: float) -> void:
	var reds: Array = []
	for v in villagers:
		if str(v.color_type) == "red": reds.append(v)
	if reds.is_empty(): return

	_hunger_timer += delta
	if _hunger_timer >= RED_HUNGER_INTERVAL:
		_hunger_timer -= RED_HUNGER_INTERVAL
		for v in reds:
			if Economy.fish > 0:
				Economy.fish -= 1; v.is_fed = true
			else:
				v.is_fed = false

	var starving: Array = []
	for v in reds:
		if not v.is_fed:
			v.health -= RED_STARVE_DPS * delta
			if v.health <= 0.0: starving.append(v)
	for v in starving:
		villagers.erase(v); v.queue_free()


# ── combat: enemy touch attacks (NOT red — reds shoot) ───────────────────────

func _process_enemy_attacks(_delta: float) -> void:
	var dead_villagers: Array = []
	for rid in room_enemies:
		for enemy in room_enemies[rid]:
			for v in room_villagers.get(rid, []):
				var dist: float = enemy.global_position.distance_to(v.global_position)
				var touch: float = float(enemy.radius) + float(v.radius) + TOUCH_DIST_BONUS
				if dist > touch: continue
				# Reds are immune to enemy touch — they fight back via shooting
				if str(v.color_type) == "red": continue
				var result: String = enemy.try_attack(v)
				if result == "kill" and v not in dead_villagers:
					dead_villagers.append(v)
	for v in dead_villagers:
		villagers.erase(v); v.queue_free()


# ── combat: red ranged shooting ──────────────────────────────────────────────

func _process_red_shooting() -> void:
	var dead_enemies: Array = []
	for v in villagers:
		if str(v.color_type) != "red": continue
		var target: Node = v.shoot_target_enemy
		if target == null: continue
		if not is_instance_valid(target) or target.is_dead: continue
		# Apply damage
		var killed: bool = target.take_red_hit(int(v.level))
		v.record_kill()
		v.shoot_target_enemy = null  # consumed
		if killed and target not in dead_enemies:
			dead_enemies.append(target)
	for e in dead_enemies:
		enemies.erase(e); e.die()


# ── enemy duplication / merging ──────────────────────────────────────────────

func _process_enemy_duplication(delta: float) -> void:
	for rid in room_enemies:
		var l1s: Array = []
		for e in room_enemies[rid]:
			if e.level == 1: l1s.append(e)
		for e in l1s:
			var dupe_range: float = e.radius * ENEMY_DUPE_RANGE_MULT
			var nearby: int = 0
			for other in l1s:
				if other != e and e.global_position.distance_to(other.global_position) < dupe_range:
					nearby += 1
			if nearby < 1:
				e.dupe_meter = maxf(0.0, e.dupe_meter - 5.0 * delta); continue
			var doublings: float = maxf(0.0, log(float(nearby + 1) / 2.0) / log(2.0))
			e.dupe_meter += ENEMY_DUPE_BASE * pow(0.9, doublings) * 10.0 * delta
		var spawned: bool = false
		for e in l1s:
			if e.dupe_meter >= ENEMY_DUPE_MAX and not spawned:
				e.dupe_meter = 0.0
				_spawn_enemy(e.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50)), 1)
				spawned = true

func _process_enemy_merging() -> void:
	for rid in room_enemies:
		var by_level: Dictionary = {1: [], 2: []}
		for e in room_enemies[rid]:
			if e.level < 3:
				if not by_level.has(e.level): by_level[e.level] = []
				by_level[e.level].append(e)
		for lv in by_level:
			var group: Array = by_level[lv]
			if group.size() < ENEMY_MERGE_COUNT: continue
			var cluster := _find_cluster(group, ENEMY_MERGE_DIST, ENEMY_MERGE_COUNT)
			if cluster.size() >= ENEMY_MERGE_COUNT:
				cluster[0].set_level(lv + 1)
				for i in range(1, ENEMY_MERGE_COUNT):
					enemies.erase(cluster[i]); cluster[i].die()

func _spawn_enemy(pos: Vector2, p_level: int = 1) -> void:
	var e = _enemy_scene.instantiate()
	_enemy_container.add_child(e)
	e.global_position = pos; e.set_level(p_level)
	enemies.append(e)


# ── homes ────────────────────────────────────────────────────────────────────

func _process_home_sheltering() -> void:
	if not GameClock.is_daytime:
		for h in homes:
			if h.is_full(): continue
			for v in villagers:
				if v.visible and v.global_position.distance_to(h.global_position) < HOME_SHELTER_DIST:
					h.shelter_villager(v)

func _on_phase_changed(is_daytime: bool) -> void:
	if is_daytime:
		for h in homes: h.release_all()

func _on_buy_requested(item_id: String) -> void:
	if Economy.purchase(item_id): _placing_item = item_id


# ── villager leveling ────────────────────────────────────────────────────────

func _process_red_leveling() -> void:
	for v in villagers:
		if v.color_type != "red": continue
		if v.level == 1 and v.kill_count >= RED_LEVEL2_KILLS: v.set_level(2)
		elif v.level == 2 and v.kill_count >= RED_LEVEL3_KILLS: v.set_level(3)

func _process_blue_merging() -> void:
	for rid in room_villagers:
		var by_lv: Dictionary = {1: [], 2: []}
		for v in room_villagers[rid]:
			if v.color_type == "blue" and v.level < 3:
				if not by_lv.has(v.level): by_lv[v.level] = []
				by_lv[v.level].append(v)
		for lv in by_lv:
			if by_lv[lv].size() < BLUE_MERGE_COUNT: continue
			var merged := _find_cluster(by_lv[lv], BLUE_MERGE_DIST, BLUE_MERGE_COUNT)
			if merged.size() == BLUE_MERGE_COUNT:
				merged[0].set_level(lv + 1)
				for i in range(1, BLUE_MERGE_COUNT):
					villagers.erase(merged[i]); merged[i].queue_free()

func _process_yellow_leveling(delta: float) -> void:
	for rid in room_villagers:
		var yellows: Array = []
		for v in room_villagers[rid]:
			if v.color_type == "yellow" and v.level < 3: yellows.append(v)
		var paired: Dictionary = {}
		for i in yellows.size():
			if paired.has(i): continue
			for j in range(i + 1, yellows.size()):
				if paired.has(j) or yellows[i].level != yellows[j].level: continue
				if yellows[i].global_position.distance_to(yellows[j].global_position) < YELLOW_PAIR_DIST:
					yellows[i].leveling_partner = yellows[j]
					yellows[j].leveling_partner = yellows[i]
					yellows[i].leveling_meter += delta
					yellows[j].leveling_meter += delta
					if yellows[i].leveling_meter >= yellows[i].YELLOW_LEVEL_TIME:
						yellows[i].set_level(yellows[i].level + 1); yellows[i].leveling_meter = 0.0
						yellows[j].set_level(yellows[j].level + 1); yellows[j].leveling_meter = 0.0
					paired[i] = true; paired[j] = true; break
		for k in yellows.size():
			if not paired.has(k):
				yellows[k].leveling_meter = maxf(0.0, yellows[k].leveling_meter - delta * 0.5)
				yellows[k].leveling_partner = null


# ── utility ──────────────────────────────────────────────────────────────────

func _find_cluster(group: Array, max_dist: float, count: int) -> Array:
	for i in group.size():
		var cluster: Array = [group[i]]
		for j in group.size():
			if i != j and group[i].global_position.distance_to(group[j].global_position) < max_dist:
				cluster.append(group[j])
				if cluster.size() >= count: return cluster
	return []


# ── shift handling ───────────────────────────────────────────────────────────

func _on_villager_shifted(villager, _old_color, new_color, spawn_count) -> void:
	villager.set_color_type(str(new_color))
	for i in range(int(spawn_count) - 1):
		_spawn_villager(str(new_color), villager.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50)))

func _spawn_villager(color_id: String, pos: Vector2) -> void:
	var v = _villager_scene.instantiate()
	_villager_container.add_child(v)
	v.setup(color_id, pos)
	villagers.append(v)


# ── HUD ──────────────────────────────────────────────────────────────────────

func _update_hud() -> void:
	if not _hud: return
	var counts: Dictionary = {}
	for v in villagers:
		counts[v.color_type] = counts.get(v.color_type, 0) + 1
	_hud.pop_red = counts.get("red", 0)
	_hud.pop_yellow = counts.get("yellow", 0)
	_hud.pop_blue = counts.get("blue", 0)
	_hud.pop_colorless = counts.get("colorless", 0)
	_hud.pop_enemies = enemies.size()
	_hud.pop_total = villagers.size()
