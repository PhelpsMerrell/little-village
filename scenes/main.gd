extends Node2D
## Main scene controller. Orchestrates all game systems.
## Click resource then click matching villager to assign waypoint.
## Event feed tracks all notable happenings.

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

## Waypoint: click resource first, then click a matching villager to assign
var _selected_resource: Node = null  # collectable or fish_spot
var _selected_resource_type: String = ""  # "stone" or "fish"

var room_villagers: Dictionary = {}
var room_enemies: Dictionary = {}

## Satiation uses per-villager timers now, no global _hunger_timer

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
@onready var _hud: Control = $UI/HUD

var _villager_scene: PackedScene = preload("res://scenes/villager.tscn")
var _enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
var _demon_scene: PackedScene = preload("res://scenes/demon.tscn")
var _zombie_scene: PackedScene = preload("res://scenes/zombie.tscn")
var _home_scene: PackedScene = preload("res://scenes/home.tscn")
var _church_scene: PackedScene = preload("res://scenes/church.tscn")
var _collectable_scene: PackedScene = preload("res://scenes/collectable.tscn")
var _fish_scene: PackedScene = preload("res://scenes/fish_spot.tscn")
var _placing_item: String = ""


func _ready() -> void:
	_collect_all()
	InfluenceManager.villager_shifted.connect(_on_villager_shifted)
	GameClock.phase_changed.connect(_on_phase_changed)
	NightEvents.connect_to_clock()
	NightEvents.night_event_started.connect(_on_night_event)
	NightEvents.night_event_ended.connect(_on_night_event_end)
	_hud.buy_requested.connect(_on_buy_requested)
	# Load save if continuing
	if SaveManager.has_save():
		# Defer so all nodes are ready
		call_deferred("_try_load_save")


func _try_load_save() -> void:
	SaveManager.load_game(self)


func _get_or_create_container(node_name: String) -> Node2D:
	var n = get_node_or_null(node_name)
	if n: return n
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
	for v in _villager_container.get_children():
		villagers.append(v)
		if not v.resource_dropped.is_connected(_on_villager_dropped_resource):
			v.resource_dropped.connect(_on_villager_dropped_resource)


func _collect_enemies() -> void:
	enemies.clear()
	for e in _enemy_container.get_children(): enemies.append(e)


# ==============================================================================
# MAIN LOOP
# ==============================================================================

func _process(delta: float) -> void:
	EventFeed.check_time_events()
	_assign_entities_to_rooms()
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
	# Save/load keybinds
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

	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return

	# Placement mode takes priority
	if _placing_item != "":
		_finalize_placement(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	# Cancel placement on right-click handled separately
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _placing_item != "":
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
		# Right click also cancels resource selection
		if _selected_resource != null:
			_selected_resource = null
			_selected_resource_type = ""
			get_viewport().set_input_as_handled()
			return

	var click_pos: Vector2 = get_global_mouse_position()

	# If we have a resource selected, try to assign it to a clicked villager
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
		# Clicked somewhere that wasn't a valid villager -- deselect
		_selected_resource = null
		_selected_resource_type = ""
		return

	# No resource selected -- try to select one
	for c in collectables:
		if not is_instance_valid(c) or c.collected: continue
		if click_pos.distance_to(c.global_position) < 20.0:
			_selected_resource = c
			_selected_resource_type = "stone"
			get_viewport().set_input_as_handled()
			return
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected: continue
		if click_pos.distance_to(f.global_position) < 20.0:
			_selected_resource = f
			_selected_resource_type = "fish"
			get_viewport().set_input_as_handled()
			return


func _draw() -> void:
	# Placement preview
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

	# Selected resource indicator
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
		_homes_container.add_child(h); h.global_position = pos; homes.append(h)
		EventFeed.push("Home built.", Color(0.7, 0.6, 0.4))
	elif _placing_item == "church":
		var c = _church_scene.instantiate()
		_churches_container.add_child(c); c.global_position = pos; churches.append(c)
		EventFeed.push("Church built.", Color(0.5, 0.6, 0.85))
	_placing_item = ""


func _cancel_placement() -> void:
	if _placing_item == "house": Economy.stone += 5
	elif _placing_item == "church": Economy.stone += 50
	_placing_item = ""


# ==============================================================================
# ROOM ASSIGNMENT
# ==============================================================================

func _assign_entities_to_rooms() -> void:
	for rid in room_villagers:
		room_villagers[rid] = []; room_enemies[rid] = []

	for v in villagers:
		var rid: int = _room_id_at(v.global_position)
		v.current_room_id = rid
		if room_map.has(rid): v.room_bounds = room_map[rid].get_rect()
		room_villagers[rid].append(v)

	var all_enemies: Array = enemies.duplicate()
	all_enemies.append_array(night_enemies)
	for e in all_enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		var rid: int = _room_id_at(e.global_position)
		e.current_room_id = rid
		if room_map.has(rid): e.room_bounds = room_map[rid].get_rect()
		room_enemies[rid].append(e)


func _room_id_at(pos: Vector2) -> int:
	for room in rooms:
		if room.get_rect().has_point(pos): return int(room.room_id)
	var best_id: int = 0; var best_d: float = INF
	for room in rooms:
		var d: float = pos.distance_squared_to(room.get_rect().get_center())
		if d < best_d: best_d = d; best_id = int(room.room_id)
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
		# Don't clear waypoint here -- it persists until villager reaches it
		v.brain_has_church = false

		match str(v.color_type):
			"yellow":
				var best_d: float = INF
				for c in collectables:
					if not is_instance_valid(c) or c.collected: continue
					if _room_id_at(c.global_position) != rid: continue
					var d: float = v.global_position.distance_to(c.global_position)
					if d < best_d:
						best_d = d
						v.brain_nearest_resource_pos = c.global_position
						v.brain_has_resource = true
				if str(v.carrying_resource) == "stone":
					# Check same-room first, then any bank
					for b in banks:
						if _room_id_at(b.global_position) == rid:
							v.deposit_position = b.global_position
							v.has_deposit_in_room = true; break
					if not v.has_deposit_in_room and banks.size() > 0:
						# Set nearest bank as cross-room target
						var bd: float = INF
						for b in banks:
							var d2: float = v.global_position.distance_to(b.global_position)
							if d2 < bd: bd = d2; v.deposit_position = b.global_position

			"blue":
				for ch in churches:
					if ch.is_full(): continue
					v.brain_church_pos = ch.global_position
					v.brain_has_church = true; break

				var best_d: float = INF
				for f in fish_spots:
					if not is_instance_valid(f) or f.collected: continue
					if _room_id_at(f.global_position) != rid: continue
					var d: float = v.global_position.distance_to(f.global_position)
					if d < best_d:
						best_d = d
						v.brain_nearest_resource_pos = f.global_position
						v.brain_has_resource = true
				if str(v.carrying_resource) == "fish":
					for h in fishing_huts:
						if _room_id_at(h.global_position) == rid:
							v.deposit_position = h.global_position
							v.has_deposit_in_room = true; break
					if not v.has_deposit_in_room and fishing_huts.size() > 0:
						var hd: float = INF
						for h in fishing_huts:
							var d2: float = v.global_position.distance_to(h.global_position)
							if d2 < hd: hd = d2; v.deposit_position = h.global_position

	# Clear waypoints for villagers that arrived or are now carrying
	for v in villagers:
		if v.has_waypoint:
			if v.is_carrying() or v.global_position.distance_to(v.waypoint_target_pos) < float(v.radius) + 20.0:
				v.has_waypoint = false

	for ne in night_enemies:
		if not is_instance_valid(ne) or ne.is_dead: continue
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
		if not is_instance_valid(c) or c.collected: rm.append(c); continue
		for v in villagers:
			if c.try_collect(v): break
	for c in rm: collectables.erase(c)


func _process_fish_pickups() -> void:
	var rm: Array = []
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected: rm.append(f); continue
		for v in villagers:
			if f.try_collect(v): break
	for f in rm: fish_spots.erase(f)


func _process_deposits() -> void:
	for b in banks:
		for v in villagers:
			if str(v.carrying_resource) == "stone": b.try_deposit(v)
	for h in fishing_huts:
		for v in villagers:
			if str(v.carrying_resource) == "fish": h.try_deposit(v)


# ==============================================================================
# CHURCH
# ==============================================================================

func _process_church_healing(delta: float) -> void:
	for ch in churches: ch.heal_tick(delta)


func _process_church_intake() -> void:
	if not GameClock.is_daytime: return
	for ch in churches:
		if ch.is_full(): continue
		for v in villagers:
			if not v.visible: continue
			if str(v.color_type) != "blue": continue
			if v.health >= v.max_health: continue
			if v.global_position.distance_to(ch.global_position) < CHURCH_INTAKE_RADIUS:
				ch.shelter_villager(v)


# ==============================================================================
# INFLUENCE INSIDE BUILDINGS
# ==============================================================================

func _process_building_influence(delta: float) -> void:
	var building_groups: Array = []
	for h in homes:
		if h.get_sheltered_count() > 1: building_groups.append(h.sheltered)
	for ch in churches:
		if ch.get_sheltered_count() > 1: building_groups.append(ch.sheltered)
	for group in building_groups:
		var valid: Array = []
		for v in group:
			if is_instance_valid(v): valid.append(v)
		if valid.size() < 2: continue
		InfluenceManager.process_building_group(valid, delta)


# ==============================================================================
# HUNGER
# ==============================================================================

func _process_red_hunger(delta: float) -> void:
	var starving: Array = []
	for v in villagers:
		if str(v.color_type) != "red": continue
		if v._satiation_timer > 0.0:
			v._satiation_timer -= delta
			v.is_fed = true
		else:
			# Try to eat a fish
			if Economy.fish > 0:
				Economy.fish -= 1
				v.is_fed = true
				# L1=1 day, L2=2 days, L3=3 days
				v._satiation_timer = v.SATIATION_PER_LEVEL[clampi(v.level, 1, 3)]
			else:
				v.is_fed = false
				v.health -= RED_STARVE_DPS * delta
				if v.health <= 0.0: starving.append(v)
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
			if enemy_type != null and enemy_type != "": continue
			for v in room_villagers.get(rid, []):
				var dist: float = enemy.global_position.distance_to(v.global_position)
				if dist > float(enemy.radius) + float(v.radius) + TOUCH_DIST_BONUS: continue
				if str(v.color_type) == "red": continue
				var result: String = enemy.try_attack(v)
				if result == "kill" and v not in dead: dead.append(v)
	for v in dead:
		villagers.erase(v)
		EventFeed.push("A %s villager was killed by an enemy." % str(v.color_type), Color(0.8, 0.25, 0.2))
		v.queue_free()


func _process_night_enemy_attacks(_delta: float) -> void:
	var dead_v: Array = []
	var dead_ne: Array = []
	var to_convert: Array = []

	for ne in night_enemies:
		if not is_instance_valid(ne) or ne.is_dead: continue
		for v in room_villagers.get(ne.current_room_id, []):
			var dist: float = ne.global_position.distance_to(v.global_position)
			if dist > float(ne.radius) + float(v.radius) + TOUCH_DIST_BONUS: continue
			var result: String = ne.try_attack(v)
			if result == "kill" and v not in dead_v:
				dead_v.append(v)
			elif result == "convert" and v not in dead_v:
				to_convert.append(v.global_position); dead_v.append(v)

	for v in dead_v:
		villagers.erase(v)
		EventFeed.push("A villager was lost in the night.", Color(0.6, 0.3, 0.5))
		v.queue_free()
	for pos in to_convert: _spawn_night_enemy("zombie", pos)
	for ne in dead_ne: night_enemies.erase(ne); ne.die()


func _process_red_shooting() -> void:
	var dead: Array = []
	for v in villagers:
		if str(v.color_type) != "red": continue
		var target: Node = v.shoot_target_enemy
		if target == null or not is_instance_valid(target) or target.is_dead: continue
		var killed: bool = target.take_red_hit(int(v.level))
		v.record_kill(); v.shoot_target_enemy = null
		if killed and target not in dead: dead.append(target)
	for e in dead:
		if e in enemies: enemies.erase(e)
		if e in night_enemies: night_enemies.erase(e)
		e.die()


# ==============================================================================
# NIGHT EVENTS
# ==============================================================================

func _on_phase_changed(is_daytime: bool) -> void:
	if is_daytime:
		for h in homes: h.release_all()
		for ch in churches: ch.release_all()
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
		if str(v.color_type) == "red" and int(v.level) == 3: continue
		var best_building: Node = null; var best_d: float = INF
		for h in homes:
			if h.is_full(): continue
			var d: float = v.global_position.distance_to(h.global_position)
			if d < best_d: best_d = d; best_building = h
		for ch in churches:
			if ch.is_full(): continue
			var d: float = v.global_position.distance_to(ch.global_position)
			if d < best_d: best_d = d; best_building = ch
		if best_building: best_building.shelter_villager(v)


func _spawn_night_wave(enemy_type: String, count: int) -> void:
	var occupied_rids: Array = []
	for rid in room_villagers:
		if room_villagers[rid].size() > 0: occupied_rids.append(rid)
	if occupied_rids.is_empty(): occupied_rids = room_map.keys()
	for i in count:
		var rid: int = occupied_rids[randi() % occupied_rids.size()]
		var room = room_map.get(rid)
		if not room: continue
		var rect: Rect2 = room.get_rect()
		var pos := Vector2(
			randf_range(rect.position.x + 100, rect.end.x - 100),
			randf_range(rect.position.y + 100, rect.end.y - 100))
		_spawn_night_enemy(enemy_type, pos)


func _spawn_night_enemy(enemy_type: String, pos: Vector2) -> void:
	var scene: PackedScene
	match enemy_type:
		"demon": scene = _demon_scene
		"zombie": scene = _zombie_scene
		_: return
	var e = scene.instantiate()
	_enemy_container.add_child(e); e.global_position = pos
	night_enemies.append(e)


func _despawn_night_enemies() -> void:
	for ne in night_enemies:
		if is_instance_valid(ne): ne.queue_free()
	night_enemies.clear()


func _process_home_sheltering() -> void:
	if not GameClock.is_daytime:
		for h in homes:
			if h.is_full(): continue
			for v in villagers:
				if not v.visible: continue
				if str(v.color_type) == "red" and int(v.level) == 3: continue
				if v.global_position.distance_to(h.global_position) < HOME_SHELTER_DIST:
					h.shelter_villager(v)
		for ch in churches:
			if ch.is_full(): continue
			for v in villagers:
				if not v.visible: continue
				if str(v.color_type) == "red" and int(v.level) == 3: continue
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
			if enemy_type != null and enemy_type != "": continue
			if e.level == 1: l1s.append(e)
		for e in l1s:
			var dr: float = e.radius * ENEMY_DUPE_RANGE_MULT
			var nearby: int = 0
			for other in l1s:
				if other != e and e.global_position.distance_to(other.global_position) < dr: nearby += 1
			if nearby < 1: e.dupe_meter = maxf(0.0, e.dupe_meter - 5.0 * delta); continue
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
			if enemy_type != null and enemy_type != "": continue
			if e.level < 3:
				if not by_lv.has(e.level): by_lv[e.level] = []
				by_lv[e.level].append(e)
		for lv in by_lv:
			if by_lv[lv].size() < ENEMY_MERGE_COUNT: continue
			var cluster := _find_cluster(by_lv[lv], ENEMY_MERGE_DIST, ENEMY_MERGE_COUNT)
			if cluster.size() >= ENEMY_MERGE_COUNT:
				cluster[0].set_level(lv + 1)
				for i in range(1, ENEMY_MERGE_COUNT):
					enemies.erase(cluster[i]); cluster[i].die()
				EventFeed.push("Enemies have merged into a stronger form!", Color(0.9, 0.3, 0.2))


func _spawn_enemy(pos: Vector2, p_level: int = 1) -> void:
	var e = _enemy_scene.instantiate()
	_enemy_container.add_child(e); e.global_position = pos
	e.set_level(p_level); enemies.append(e)


# ==============================================================================
# VILLAGER LEVELING
# ==============================================================================

func _process_red_leveling() -> void:
	for v in villagers:
		if v.color_type != "red": continue
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
				if not by_lv.has(v.level): by_lv[v.level] = []
				by_lv[v.level].append(v)
		for lv in by_lv:
			if by_lv[lv].size() < BLUE_MERGE_COUNT: continue
			var merged := _find_cluster(by_lv[lv], BLUE_MERGE_DIST, BLUE_MERGE_COUNT)
			if merged.size() == BLUE_MERGE_COUNT:
				merged[0].set_level(lv + 1)
				for i in range(1, BLUE_MERGE_COUNT):
					villagers.erase(merged[i]); merged[i].queue_free()
				EventFeed.push("Blues merged to Level %d!" % (lv + 1), Color(0.3, 0.5, 0.9))


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
					yellows[i].leveling_partner = yellows[j]; yellows[j].leveling_partner = yellows[i]
					yellows[i].leveling_meter += delta; yellows[j].leveling_meter += delta
					if yellows[i].leveling_meter >= yellows[i].YELLOW_LEVEL_TIME:
						yellows[i].set_level(yellows[i].level + 1); yellows[i].leveling_meter = 0.0
						yellows[j].set_level(yellows[j].level + 1); yellows[j].leveling_meter = 0.0
						EventFeed.push("Yellows paired to Level %d!" % (yellows[i].level), Color(0.94, 0.84, 0.2))
					paired[i] = true; paired[j] = true; break
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
				if cluster.size() >= count: return cluster
	return []


func _on_buy_requested(item_id: String) -> void:
	if Economy.purchase(item_id): _placing_item = item_id


func _on_villager_shifted(villager, old_color, new_color, spawn_count) -> void:
	villager.set_color_type(str(new_color))
	var color_names: Dictionary = {"red": "the red", "yellow": "the yellow", "blue": "the blue", "colorless": "the colorless"}
	var name: String = color_names.get(str(new_color), str(new_color))
	EventFeed.push("A villager joined %s." % name, ColorRegistry.get_def(str(new_color)).get("display_color", Color.WHITE))
	for i in range(int(spawn_count) - 1):
		_spawn_villager(str(new_color),
			villager.global_position + Vector2(randf_range(-50, 50), randf_range(-50, 50)))


func _spawn_villager(color_id: String, pos: Vector2) -> void:
	var v = _villager_scene.instantiate()
	_villager_container.add_child(v); v.setup(color_id, pos)
	v.resource_dropped.connect(_on_villager_dropped_resource)
	villagers.append(v)


func _update_hud() -> void:
	if not _hud: return
	var counts: Dictionary = {}
	for v in villagers: counts[v.color_type] = counts.get(v.color_type, 0) + 1
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
			_collectables_container.add_child(c); c.global_position = pos; collectables.append(c)
		"fish":
			var f = _fish_scene.instantiate()
			_fish_container.add_child(f); f.global_position = pos; fish_spots.append(f)
