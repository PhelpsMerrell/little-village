extends Node2D
## Main scene controller. Orchestrates all game systems.

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

const RIVER_FISH_MAX := 4
const RIVER_FISH_INTERVAL := 1800.0
const COLORLESS_ATTRACT_RANGE := 350.0

var _river_room_ids: Array = []  ## populated after map generation

var _river_fish_timer: float = 0.0
var _dev_fog_off: bool = false

## War state: Set[faction_a][faction_b] = true when those factions have fought
var _war_state: Dictionary = {}  # faction_id -> Dictionary of {faction_id -> bool}

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

var _player: Node = null  ## PlayerController instance

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
var _options_menu: Control = null

var _player_controller_script: GDScript = preload("res://scenes/player_controller.gd")
var _map_generator_script: GDScript = preload("res://scenes/map_generator.gd")
var _map_gen = null  ## MapGenerator instance, kept alive after generate()

var map_seed: int = -1  ## -1 = random, >= 0 = deterministic
var faction_count: int = 1
var map_size: String = "medium"  ## lobby selection passed via FactionManager meta
var _next_net_id: int = 0
var _villager_name_counter: Dictionary = {}  ## color -> next number
var _tutorial_enemies_killed: int = 0  ## Track for tutorial phase skip-ahead


func _gen_villager_name(color_id: String) -> String:
	var n: int = _villager_name_counter.get(color_id, 0) + 1
	_villager_name_counter[color_id] = n
	return "%s-%d" % [color_id.capitalize(), n]


func _ready() -> void:
	_read_lobby_config()
	GameRNG.set_seed(map_seed)
	_generate_map()
	_collect_all()
	_init_camera()
	_init_player_controller()
	if not NetworkManager.is_authority():
		_init_client_puppets()
	NetworkManager.remote_command_received.connect(_on_remote_command)
	NetworkManager.building_placed_remote.connect(_on_building_placed_remote)
	# Starting resources per faction
	for fid in FactionManager.get_all_faction_ids():
		Economy.set_stone(fid, 5)
		Economy.set_fish(fid, 3)
	InfluenceManager.villager_shifted.connect(_on_villager_shifted)
	GameClock.phase_changed.connect(_on_phase_changed)
	NightEvents.connect_to_clock()
	NightEvents.night_event_started.connect(_on_night_event)
	NightEvents.night_event_ended.connect(_on_night_event_end)
	_hud.buy_requested.connect(_on_buy_requested)
	_hud.command_issued.connect(_on_hud_command)
	_hud.building_command_issued.connect(_on_hud_building_command)
	RoomOwnership.room_captured.connect(_on_room_captured)
	_init_options_menu()
	if TutorialManager.active:
		_dev_fog_off = true  # Fog off in tutorial for clarity
	if SaveManager.has_save():
		call_deferred("_try_load_save")


func _read_lobby_config() -> void:
	if FactionManager.has_meta("map_seed"):
		map_seed = FactionManager.get_meta("map_seed")
		FactionManager.remove_meta("map_seed")
	if FactionManager.has_meta("faction_count"):
		faction_count = FactionManager.get_meta("faction_count")
		FactionManager.remove_meta("faction_count")
	if FactionManager.has_meta("map_size"):
		map_size = FactionManager.get_meta("map_size")
		FactionManager.remove_meta("map_size")
	if FactionManager.has_meta("player_count"):
		FactionManager.remove_meta("player_count")
	if FactionManager.has_meta("peer_factions"):
		FactionManager.remove_meta("peer_factions")


func _init_player_controller() -> void:
	_player = Node.new()
	_player.set_script(_player_controller_script)
	_player.faction_id = FactionManager.local_faction_id
	add_child(_player)


func _init_options_menu() -> void:
	_options_menu = Control.new()
	_options_menu.set_script(preload("res://scenes/options_menu.gd"))
	_options_menu.name = "OptionsMenu"
	$UI.add_child(_options_menu)
	_options_menu.dev_command.connect(_on_dev_command)


func _try_load_save() -> void:
	SaveManager.load_game(self)
	_update_fog_and_camera()


# ==============================================================================
# MAP GENERATION (delegated to MapGenerator)
# ==============================================================================

func _generate_map() -> void:
	_map_gen = _map_generator_script.new()
	var containers := {
		"rooms": _rooms_container,
		"walls": _wall_container,
		"villagers": _villager_container,
		"enemies": _enemy_container,
		"collectables": _collectables_container,
		"fish": _fish_container,
		"homes": _homes_container,
		"banks": _banks_container,
		"huts": _huts_container,
	}
	var scenes := {
		"villager": _villager_scene,
		"enemy": _enemy_scene,
		"collectable": _collectable_scene,
		"fish": _fish_scene,
		"room": _room_scene,
		"wall": _wall_scene,
		"bank": preload("res://scenes/bank.tscn"),
		"hut": preload("res://scenes/fishing_hut.tscn"),
		"river": preload("res://scenes/obstacles/river_obstacle.tscn"),
	}
	if TutorialManager.active:
		_map_gen.generate_tutorial(containers, scenes)
	else:
		_map_gen.generate(containers, scenes, map_seed, faction_count, map_size,
				FactionManager.get_all_faction_ids())
	room_map = _map_gen.room_map
	_river_room_ids = _map_gen._river_room_ids.duplicate()

	# Register core rooms using actual faction IDs from the map
	for fi in _map_gen.FACTION_STARTS.size():
		var actual_fid: int = _map_gen._faction_id_map[fi]
		FactionManager.set_core_room(actual_fid, _map_gen.FACTION_STARTS[fi]["home_room"])


# ==============================================================================
# CAMERA + FOG
# ==============================================================================

func _init_camera() -> void:
	# Find home room for local faction
	var home_rid: int = 0
	var my_fid: int = FactionManager.local_faction_id
	var my_fi: int = _map_gen._faction_id_map.find(my_fid)
	if my_fi >= 0 and my_fi < _map_gen.FACTION_STARTS.size():
		home_rid = _map_gen.FACTION_STARTS[my_fi]["home_room"]
	var def: Array = _map_gen.find_room_def(home_rid)
	if not def.is_empty():
		var rpos: Vector2 = _map_gen.room_pixel_pos(def[1], def[2])
		var rsize: Vector2 = _map_gen.room_pixel_size(def[3], def[4])
		var center: Vector2 = rpos + rsize * 0.5
		_camera.position = center
		_camera.home_room_center = center
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
			continue
		if not FactionManager.is_local_faction(v.faction_id):
			continue
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
		if v.net_id < 0:
			v.net_id = _next_net_id
			_next_net_id += 1
		else:
			_next_net_id = maxi(_next_net_id, v.net_id + 1)
		if v.villager_name == "":
			v.villager_name = _gen_villager_name(str(v.color_type))
		if not v.resource_dropped.is_connected(_on_villager_dropped_resource):
			v.resource_dropped.connect(_on_villager_dropped_resource)


func _collect_enemies() -> void:
	enemies.clear()
	for e in _enemy_container.get_children():
		enemies.append(e)
		if e.net_id < 0:
			e.net_id = _next_net_id
			_next_net_id += 1
		else:
			_next_net_id = maxi(_next_net_id, e.net_id + 1)


# ==============================================================================
# MAIN LOOP
# ==============================================================================

func _process(delta: float) -> void:
	# Client: apply snapshots and draw, skip simulation
	if not NetworkManager.is_authority():
		_client_process(delta)
		return

	if GameClock.is_paused:
		_update_hud()
		queue_redraw()
		return

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

	var wall_data: Array = []
	for w in walls:
		wall_data.append({"room_a": w.room_a_id, "room_b": w.room_b_id, "is_open": w.is_open})

	_process_red_door_breaking()
	if TutorialManager.active:
		var tut_state := {}
		var doors_open: Array = []
		for w in walls:
			if w.is_door:
				doors_open.append(w.is_open)
		tut_state["doors_open"] = doors_open
		tut_state["enemies_killed"] = _tutorial_enemies_killed
		TutorialManager.check_conditions(tut_state)
	InfluenceManager.process_influence(room_villagers, wall_data, delta)
	RoomOwnership.process_ownership(room_villagers, room_enemies, delta)
	_update_hud()
	if NetworkManager.should_broadcast(delta):
		_broadcast_snapshot()
	_sync_cursor(delta)
	queue_redraw()



func _unhandled_input(event: InputEvent) -> void:
	# Options menu eats all input when open
	if _options_menu and _options_menu.visible:
		return

	# Shift-hover selection mode: hovering over villagers auto-selects them
	if Input.is_key_pressed(KEY_SHIFT) and event is InputEventMouseMotion:
		var hover_pos: Vector2 = get_global_mouse_position()
		for v in villagers:
			if not is_instance_valid(v) or not v.visible:
				continue
			if v.faction_id != _player.faction_id:
				continue
			if v in _player.selected_villagers:
				continue
			if hover_pos.distance_to(v.global_position) < float(v.radius) + 10.0:
				_player.select_villager(v, true)
				_hud.set_command_menu_visible(true)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("quick_save"):
			SaveManager.save_game(self)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("deselect"):
			if TutorialManager.active:
				if not _player.has_selection() and _hud.get_pending_command() == "":
					TutorialManager.skip_tutorial()
					EventFeed.push("Tutorial skipped.", Color(0.7, 0.7, 0.5))
					get_viewport().set_input_as_handled()
					return
			if _hud.get_pending_command() != "":
				_hud.clear_pending_command()
				get_viewport().set_input_as_handled()
				return
			if _player.has_selection():
				_player.deselect_all()
				_hud.set_command_menu_visible(false)
				get_viewport().set_input_as_handled()
				return
			if _player.has_building_selection():
				_player.deselect_building()
				_hud.set_building_menu_visible(false)
				get_viewport().set_input_as_handled()
				return
			# Nothing selected — open options menu
			if _options_menu:
				_options_menu.open()
				get_viewport().set_input_as_handled()
				return
		elif event.is_action_pressed("toggle_fog_dev"):
			_dev_fog_off = not _dev_fog_off
			var label := "FOG OFF" if _dev_fog_off else "FOG ON"
			EventFeed.push("[DEV] %s" % label, Color(1, 1, 0))
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("dev_next_phase"):
			if NetworkManager.is_authority():
				GameClock.advance_phase()
				var phase_label := "DAY %d" % GameClock.day_count if GameClock.is_daytime else "NIGHT %d" % GameClock.day_count
				EventFeed.push("[DEV] Skipped to %s" % phase_label, Color(1, 1, 0))
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("cmd_hold") and _player.has_selection():
			_player.command_hold()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("cmd_house") and _player.has_selection():
			_player.command_enter_exit_house(homes, churches)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("cmd_release") and _player.has_selection():
			_player.command_release()
			_hud.set_command_menu_visible(false)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("cmd_move") and _player.has_selection():
			_hud._pending_command = "move"
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("cmd_break_door") and _player.has_selection():
			_hud._pending_command = "break_door"
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_A and _player.has_selection():
			_hud._pending_command = "attack"
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_S and _player.has_selection():
			_hud._pending_command = "stun"
			get_viewport().set_input_as_handled()
			return

	if not (event is InputEventMouseButton and event.pressed):
		return

	# Right-click: move command or cancel
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if _placing_item != "":
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
		if _player.has_resource_selection():
			_player.clear_resource_selection()
			get_viewport().set_input_as_handled()
			return
		if _player.has_selection():
			_player.command_move_to(get_global_mouse_position())
			get_viewport().set_input_as_handled()
			return
		return

	# Left-click only from here
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if _placing_item != "":
		_finalize_placement(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return

	var click_pos: Vector2 = get_global_mouse_position()

	# Pending move command from HUD menu
	if _hud.get_pending_command() == "move" and _player.has_selection():
		_player.command_move_to(click_pos)
		_hud.clear_pending_command()
		get_viewport().set_input_as_handled()
		return

	# Pending break_door command from HUD menu
	if _hud.get_pending_command() == "break_door" and _player.has_selection():
		var best_door: Node = null
		var best_d: float = 200.0  # max click distance to a door
		for w in walls:
			if not w.is_door or w.is_open:
				continue
			var d: float = click_pos.distance_to(w.get_midpoint())
			if d < best_d:
				best_d = d
				best_door = w
		if best_door:
			_player.command_break_door(best_door.get_midpoint())
		else:
			EventFeed.push("No closed door nearby.", Color(0.7, 0.5, 0.3))
		_hud.clear_pending_command()
		get_viewport().set_input_as_handled()
		return

	# Pending attack/stun: click on an enemy-faction villager
	if _hud.get_pending_command() in ["attack", "stun"] and _player.has_selection():
		var combat_cmd: String = _hud.get_pending_command()
		var target_v: Node = null
		var best_d: float = INF
		for v in villagers:
			if not is_instance_valid(v) or not v.visible:
				continue
			if v.faction_id == _player.faction_id or v.faction_id < 0:
				continue
			var d: float = click_pos.distance_to(v.global_position)
			if d < float(v.radius) + 10.0 and d < best_d:
				best_d = d
				target_v = v
		if target_v:
			if combat_cmd == "attack":
				_player.command_attack_target(target_v)
			else:
				_player.command_stun_target(target_v)
		else:
			EventFeed.push("No enemy villager at that location.", Color(0.7, 0.5, 0.3))
		_hud.clear_pending_command()
		get_viewport().set_input_as_handled()
		return

	if _player.has_resource_selection():
		var sel_res: Node = _player.get_selected_resource()
		var sel_type: String = _player.get_selected_resource_type()
		for v in villagers:
			if click_pos.distance_to(v.global_position) < float(v.radius) + 10.0:
				var matched: bool = false
				if sel_type == "stone" and str(v.color_type) == "yellow":
					matched = true
				elif sel_type == "fish" and str(v.color_type) == "blue":
					matched = true
				if matched and not v.is_carrying():
					v.waypoint_target_pos = sel_res.global_position
					v.has_waypoint = true
					EventFeed.push("Villager sent to gather.", Color(0.7, 0.8, 0.6))
					_player.clear_resource_selection()
					get_viewport().set_input_as_handled()
					return
		_player.clear_resource_selection()
		return

	for c in collectables:
		if not is_instance_valid(c) or c.collected:
			continue
		if click_pos.distance_to(c.global_position) < 20.0:
			_player.set_resource_selection(c, "stone")
			get_viewport().set_input_as_handled()
			return
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected:
			continue
		if click_pos.distance_to(f.global_position) < 20.0:
			_player.set_resource_selection(f, "fish")
			get_viewport().set_input_as_handled()
			return

	# Villager selection
	var shift_held: bool = Input.is_key_pressed(KEY_SHIFT)
	if _player.try_click_villager(click_pos, villagers, shift_held):
		_hud.set_command_menu_visible(true)
		return

	# Building selection (homes + churches + banks + fishing huts)
	var all_buildings: Array = []
	all_buildings.append_array(homes)
	all_buildings.append_array(churches)
	all_buildings.append_array(banks)
	all_buildings.append_array(fishing_huts)
	if _player.try_click_building(click_pos, all_buildings, Callable(self, "_room_id_at")):
		var b: Node = _player.selected_building
		var can_sell: bool = (b.placed_by_faction == FactionManager.local_faction_id)
		_hud.set_building_menu_visible(true, can_sell)
		return

	# Clicked empty ground — deselect
	if _player.has_selection():
		_player.deselect_all()
		_hud.set_command_menu_visible(false)
	if _player.has_building_selection():
		_player.deselect_building()
		_hud.set_building_menu_visible(false)



func _finalize_placement(pos: Vector2) -> void:
	# Client: send placement request to host
	if not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "build_place",
			"item_id": _placing_item,
			"px": pos.x,
			"py": pos.y,
		})
		_placing_item = ""
		return

	# Host: validate and place
	var rid: int = _room_id_at(pos)
	var owner_fid: int = RoomOwnership.get_room_owner(rid)
	if owner_fid != FactionManager.local_faction_id and faction_count > 1:
		EventFeed.push("Cannot build here — your faction doesn't own this room.", Color(0.9, 0.4, 0.3))
		_cancel_placement()
		return
	_place_building(_placing_item, pos)
	NetworkManager.broadcast_building_placed(_placing_item, pos)
	_placing_item = ""


func _cancel_placement() -> void:
	var fid: int = FactionManager.local_faction_id
	if NetworkManager.is_authority():
		var cost: int = 0
		if Economy.get_shop_items().has(_placing_item):
			cost = int(Economy.get_shop_items()[_placing_item]["cost"])
		if cost > 0:
			Economy.add_stone(cost, fid)
	_placing_item = ""


func _place_building(item_id: String, pos: Vector2) -> void:
	## Shared building creation logic (host + client via remote).
	var fid: int = FactionManager.local_faction_id
	if item_id == "house":
		var h = _home_scene.instantiate()
		_homes_container.add_child(h)
		h.global_position = pos
		h.placed_by_faction = fid
		homes.append(h)
		EventFeed.push("Home built.", Color(0.7, 0.6, 0.4))
		TutorialManager.on_building_placed()
	elif item_id == "church":
		var c = _church_scene.instantiate()
		_churches_container.add_child(c)
		c.global_position = pos
		c.placed_by_faction = fid
		churches.append(c)
		EventFeed.push("Church built.", Color(0.5, 0.6, 0.85))
	elif item_id == "bank":
		var b = preload("res://scenes/bank.tscn").instantiate()
		_banks_container.add_child(b)
		b.global_position = pos
		b.placed_by_faction = fid
		banks.append(b)
		EventFeed.push("Bank built.", Color(0.85, 0.8, 0.5))
	elif item_id == "fishing_hut":
		var h = preload("res://scenes/fishing_hut.tscn").instantiate()
		_huts_container.add_child(h)
		h.global_position = pos
		h.placed_by_faction = fid
		fishing_huts.append(h)
		EventFeed.push("Fishing Hut built.", Color(0.6, 0.75, 0.9))


func _on_building_placed_remote(item_id: String, px: float, py: float) -> void:
	## Client receives building placement from host.
	_place_building(item_id, Vector2(px, py))


func _on_hud_command(cmd_type: String) -> void:
	match cmd_type:
		"hold":
			_player.command_hold()
		"house":
			_player.command_enter_exit_house(homes, churches)
		"release":
			_player.command_release()
			_hud.set_command_menu_visible(false)


func _on_hud_building_command(cmd_type: String) -> void:
	if not _player.has_building_selection():
		return
	var building: Node = _player.selected_building
	match cmd_type:
		"evict":
			building.evict_all()
			EventFeed.push("Villagers evicted from building.", Color(0.8, 0.6, 0.3))
		"sell":
			if building.placed_by_faction == -2:
				EventFeed.push("Cannot sell pre-placed buildings.", Color(0.9, 0.4, 0.3))
				return
			if building.placed_by_faction != FactionManager.local_faction_id:
				EventFeed.push("Cannot sell — not your building.", Color(0.9, 0.4, 0.3))
				return
			building.evict_all()
			var item_id: String = ""
			if building in homes: item_id = "house"
			elif building in churches: item_id = "church"
			elif building in banks: item_id = "bank"
			elif building in fishing_huts: item_id = "fishing_hut"
			var sell_val: int = Economy.get_sell_value(item_id)
			Economy.add_stone(sell_val, FactionManager.local_faction_id)
			if building in homes: homes.erase(building)
			if building in churches: churches.erase(building)
			if building in banks: banks.erase(building)
			if building in fishing_huts: fishing_huts.erase(building)
			_player.deselect_building()
			_hud.set_building_menu_visible(false)
			building.queue_free()
			EventFeed.push("Building sold for %d stone." % sell_val, Color(0.6, 0.7, 0.5))


func _on_dev_command(cmd: String) -> void:
	match cmd:
		"pause":
			var label := "PAUSED" if GameClock.is_paused else "UNPAUSED"
			EventFeed.push("[DEV] %s" % label, Color(1, 1, 0))
		"next_phase":
			var phase_label := "DAY %d" % GameClock.day_count if GameClock.is_daytime else "NIGHT %d" % GameClock.day_count
			EventFeed.push("[DEV] Skipped to %s" % phase_label, Color(1, 1, 0))
		"reset":
			SaveManager.delete_save()
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		"toggle_dev_mode":
			_dev_fog_off = not _dev_fog_off
			var label := "DEV MODE ON (fog disabled)" if _dev_fog_off else "DEV MODE OFF"
			EventFeed.push("[DEV] %s" % label, Color(1, 1, 0))


func _on_room_captured(room_id: int, new_owner: int, _old_owner: int) -> void:
	## Check if the captured room is a core room for any faction.
	if not NetworkManager.is_authority():
		return
	for fid in FactionManager.get_all_faction_ids():
		if FactionManager.is_eliminated(fid):
			continue
		if FactionManager.get_core_room(fid) != room_id:
			continue
		if new_owner == fid:
			continue  # Faction recaptured its own core (shouldn't happen, but safe)
		# Core room captured by another faction — eliminate
		_eliminate_faction(fid, new_owner)
		return


func _set_war_state(faction_a: int, faction_b: int, at_war: bool) -> void:
	if faction_a < 0 or faction_b < 0 or faction_a == faction_b:
		return
	if not _war_state.has(faction_a):
		_war_state[faction_a] = {}
	if not _war_state.has(faction_b):
		_war_state[faction_b] = {}
	var was_at_war: bool = _war_state[faction_a].get(faction_b, false)
	_war_state[faction_a][faction_b] = at_war
	_war_state[faction_b][faction_a] = at_war
	if at_war and not was_at_war:
		var sym_a: String = FactionManager.get_faction_symbol(faction_a)
		var sym_b: String = FactionManager.get_faction_symbol(faction_b)
		EventFeed.push("War declared: %s vs %s!" % [sym_a, sym_b], Color(0.9, 0.3, 0.2))


func _are_at_war(faction_a: int, faction_b: int) -> bool:
	return _war_state.get(faction_a, {}).get(faction_b, false)


func _eliminate_faction(eliminated_fid: int, captor_fid: int) -> void:
	FactionManager.eliminate_faction(eliminated_fid)
	var sym: String = FactionManager.get_faction_symbol(eliminated_fid)
	var captor_sym: String = FactionManager.get_faction_symbol(captor_fid)
	EventFeed.push("Faction %s has been ELIMINATED by %s!" % [sym, captor_sym], Color(0.9, 0.2, 0.2))

	# Convert all villagers belonging to eliminated faction
	for v in villagers:
		if not is_instance_valid(v):
			continue
		if v.faction_id == eliminated_fid:
			v.faction_id = captor_fid

	# Transfer all buildings placed by eliminated faction
	for b in homes + churches + banks + fishing_huts:
		if not is_instance_valid(b):
			continue
		if b.placed_by_faction == eliminated_fid:
			b.placed_by_faction = captor_fid

	# If local faction was eliminated, deselect everything
	if eliminated_fid == FactionManager.local_faction_id:
		_player.deselect_all()
		_hud.set_command_menu_visible(false)
		_hud.set_building_menu_visible(false)
		EventFeed.push("Your faction has been eliminated. You are now spectating.", Color(0.9, 0.5, 0.3))


# ==============================================================================
# NETWORK COMMAND APPLICATION
# ==============================================================================

func _find_villager_by_net_id(nid: int) -> Node:
	for v in villagers:
		if is_instance_valid(v) and v.net_id == nid:
			return v
	return null


func _apply_net_command(cmd: Dictionary) -> void:
	## Apply a command received from the lockstep system.
	var cmd_type: String = cmd.get("type", "")
	var net_ids: Array = cmd.get("net_ids", [])

	match cmd_type:
		"move_to":
			var target: Vector2 = Vector2(cmd.get("tx", 0.0), cmd.get("ty", 0.0))
			var i: int = 0
			for nid in net_ids:
				var v: Node = _find_villager_by_net_id(int(nid))
				if v:
					var offset := Vector2(GameRNG.randf_range(-20, 20), GameRNG.randf_range(-20, 20))
					v.command_move_to(target + offset)
				i += 1
		"hold":
			for nid in net_ids:
				var v: Node = _find_villager_by_net_id(int(nid))
				if v:
					if v.command_mode == "hold":
						v.command_release()
					else:
						v.command_hold()
		"release":
			for nid in net_ids:
				var v: Node = _find_villager_by_net_id(int(nid))
				if v:
					v.command_release()
		"enter_exit_house":
			# Gather villager refs from net_ids
			var cmd_villagers: Array = []
			for nid in net_ids:
				var v: Node = _find_villager_by_net_id(int(nid))
				if v:
					cmd_villagers.append(v)
			_apply_house_command(cmd_villagers)
		"break_door":
			var target: Vector2 = Vector2(cmd.get("tx", 0.0), cmd.get("ty", 0.0))
			for nid in net_ids:
				var v: Node = _find_villager_by_net_id(int(nid))
				if v and str(v.color_type) == "red":
					v.command_move_to(target)
					v.break_door_target = target
		"build_place":
			var item_id: String = cmd.get("item_id", "")
			var bpos := Vector2(float(cmd.get("px", 0.0)), float(cmd.get("py", 0.0)))
			var sender_faction: int = NetworkManager.get_faction_for_peer(int(cmd.get("peer_id", 0)))
			var brid: int = _room_id_at(bpos)
			var bowner: int = RoomOwnership.get_room_owner(brid)
			if bowner != sender_faction and faction_count > 1:
				return
			if not Economy.purchase(item_id):
				return
			_place_building(item_id, bpos)
			NetworkManager.broadcast_building_placed(item_id, bpos)

		"drag_start":
			var nid: int = int(cmd.get("net_id", -1))
			var v: Node = _find_villager_by_net_id(nid)
			if v:
				v._dragging = true
				v.z_index = 10
				v._drop_carried_resource()
		"drag_move":
			var nid: int = int(cmd.get("net_id", -1))
			var v: Node = _find_villager_by_net_id(nid)
			if v:
				v.global_position = Vector2(float(cmd.get("px", 0.0)), float(cmd.get("py", 0.0)))
		"drag_end":
			var nid: int = int(cmd.get("net_id", -1))
			var v: Node = _find_villager_by_net_id(nid)
			if v:
				v.global_position = Vector2(float(cmd.get("px", 0.0)), float(cmd.get("py", 0.0)))
				v._dragging = false
				v.z_index = 0
				v._arrived = true
				v._idle_timer = GameRNG.randf_range(0.5, 1.5)

		"attack":
			var target: Node = _find_villager_by_net_id(int(cmd.get("target_net_id", -1)))
			if target:
				for nid in net_ids:
					var v: Node = _find_villager_by_net_id(int(nid))
					if v and str(v.color_type) == "red":
						v.command_attack(target)

		"stun":
			var target: Node = _find_villager_by_net_id(int(cmd.get("target_net_id", -1)))
			if target:
				for nid in net_ids:
					var v: Node = _find_villager_by_net_id(int(nid))
					if v and str(v.color_type) == "blue":
						v.command_stun(target)

func _apply_house_command(cmd_villagers: Array) -> void:
	## Shared logic for house enter/exit used by both local and network paths.
	var released_any := false
	for building in homes + churches:
		var to_release: Array = []
		for v in building.sheltered:
			if is_instance_valid(v) and v in cmd_villagers:
				to_release.append(v)
		for v in to_release:
			building.sheltered.erase(v)
			v.visible = true
			v.set_process(true)
			v.global_position = building.global_position + Vector2(GameRNG.randf_range(-60, 60), GameRNG.randf_range(40, 80))
			released_any = true
	if released_any:
		TutorialManager.on_release()
		return
	for v in cmd_villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		var best_building: Node = null
		var best_bd: float = INF
		for b in homes + churches:
			if b.is_full():
				continue
			var d: float = v.global_position.distance_to(b.global_position)
			if d < best_bd:
				best_bd = d
				best_building = b
		if best_building:
			best_building.shelter_villager(v)
			TutorialManager.on_shelter()



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
		if TutorialManager.active and v.faction_id >= 0:
			TutorialManager.on_villager_entered_room(rid)

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
	# Build wall data once per frame for villager collision
	var wall_info: Array = []
	var doorway_info: Array = []  # [{mid: Vector2, room_a: int, room_b: int}]
	for w in walls:
		wall_info.append({"start": w.start_pos, "end": w.end_pos, "is_open": w.is_open})
		if w.is_door or w.is_open:
			doorway_info.append({"mid": (w.start_pos + w.end_pos) * 0.5, "room_a": w.room_a_id, "room_b": w.room_b_id})

	for v in villagers:
		var rid: int = v.current_room_id
		v.brain_enemies = room_enemies.get(rid, [])
		v.brain_room_villagers = room_villagers.get(rid, [])
		v.brain_walls = wall_info
		v.brain_doorways = doorway_info
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


func _process_red_door_breaking() -> void:
	## Reds automatically break closed doors when within awareness range.
	## Also handles break_door_target from player command.
	for v in villagers:
		if str(v.color_type) != "red":
			continue
		if not v.visible:
			continue
		for w in walls:
			if not w.is_door or w.is_open:
				continue
			var mid: Vector2 = w.get_midpoint()
			var dist: float = v.global_position.distance_to(mid)
			if dist < w.BREAK_RADIUS + float(v.radius):
				w.break_door()
				EventFeed.push("A red villager broke open a door!", Color(0.9, 0.5, 0.3))
				TutorialManager.on_door_broken()
				# Clear break_door_target if this was the target
				if v.break_door_target != Vector2.ZERO and v.break_door_target.distance_to(mid) < 80.0:
					v.break_door_target = Vector2.ZERO
					v.command_release()


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
				if b.try_deposit(v):
					TutorialManager.on_deposit("stone")
	for h in fishing_huts:
		for v in villagers:
			if str(v.carrying_resource) == "fish":
				if h.try_deposit(v):
					TutorialManager.on_fish_delivered()
	


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
			var fid: int = v.faction_id if v.faction_id >= 0 else 0
			if Economy.get_fish(fid) > 0:
				Economy.set_fish(fid, Economy.get_fish(fid) - 1)
				v.is_fed = true
				v._satiation_timer = v.SATIATION_PER_LEVEL[clampi(v.level, 1, 3)]
				# Red L3: each fish extends lifespan
				if v.level == 3:
					v.extend_l3_lifespan()
			else:
				v.is_fed = false
				v.health -= RED_STARVE_DPS * delta
				if v.health <= 0.0:
					starving.append(v)
	for v in starving:
		var dead_fid: int = v.faction_id
		villagers.erase(v)
		v.start_death_animation()
		EventFeed.push("A red villager starved to death.", Color(0.85, 0.3, 0.25))
		_check_survival_color_recovery("red", dead_fid)


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
		var dead_color: String = str(v.color_type)
		var dead_fid: int = v.faction_id
		villagers.erase(v)
		EventFeed.push("A %s villager was killed by an enemy." % dead_color, Color(0.8, 0.25, 0.2))
		v.queue_free()
		_check_survival_color_recovery(dead_color, dead_fid)


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
		var dead_color: String = str(v.color_type)
		var dead_fid: int = v.faction_id
		villagers.erase(v)
		EventFeed.push("A villager was lost in the night.", Color(0.6, 0.3, 0.5))
		v.queue_free()
		_check_survival_color_recovery(dead_color, dead_fid)
	for pos in to_convert:
		_spawn_night_enemy("zombie", pos)
	for ne in dead_ne:
		night_enemies.erase(ne)
		ne.die()


func _process_red_shooting() -> void:
	var dead_enemies: Array = []
	var dead_villagers: Array = []
	for v in villagers:
		if str(v.color_type) != "red":
			continue
		var target: Node = v.shoot_target_enemy
		if target == null or not is_instance_valid(target):
			continue
		# PvP: target is a villager (has faction_id)
		if target.get("faction_id") != null:
			if target.faction_id == v.faction_id:
				continue  ## Never shoot own faction
			var dmg: float = 10.0 * float(v.level)
			target.health -= dmg
			v.record_kill() if target.health <= 0.0 else null
			if target.health <= 0.0 and target not in dead_villagers:
				dead_villagers.append(target)
			# Mark factions at war
			_set_war_state(v.faction_id, target.faction_id, true)
		else:
			# PvE: target is an enemy
			if target.get("is_dead") and target.is_dead:
				continue
			var killed: bool = target.take_red_hit(int(v.level))
			v.record_kill()
			v.shoot_target_enemy = null
			if killed and target not in dead_enemies:
				dead_enemies.append(target)
				_tutorial_enemies_killed += 1
				TutorialManager.on_enemy_killed()
	for e in dead_enemies:
		if e in enemies:
			enemies.erase(e)
		if e in night_enemies:
			night_enemies.erase(e)
		e.die()
	for v in dead_villagers:
		var dead_color: String = str(v.color_type)
		var dead_fid: int = v.faction_id
		villagers.erase(v)
		EventFeed.push("A %s villager was killed in combat." % dead_color, Color(0.9, 0.3, 0.3))
		v.start_death_animation()
		_check_survival_color_recovery(dead_color, dead_fid)


# ==============================================================================
# NIGHT EVENTS
# ==============================================================================

func _on_phase_changed(is_daytime: bool) -> void:
	if not NetworkManager.is_authority():
		return
	if is_daytime:
		# Dawn: blue L3 villagers that slept in a church get lifespan extended
		for ch in churches:
			for v in ch.sheltered:
				if not is_instance_valid(v):
					continue
				if str(v.color_type) == "blue" and v.level == 3:
					v.extend_l3_lifespan()
					EventFeed.push("A blue L3 villager rested and lives on.", Color(0.3, 0.5, 0.9))
		# Tutorial: check if any red villager survived the night fed
		for v in villagers:
			if str(v.color_type) == "red" and v.is_fed:
				TutorialManager.on_red_day_survived()
				break
		for h in homes:
			h.release_all()
		for ch in churches:
			ch.release_all()
		_despawn_night_enemies()
	else:
		_auto_shelter_villagers()


func _on_night_event(event_id: String) -> void:
	if not NetworkManager.is_authority():
		return
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
		var rid: int = occupied_rids[GameRNG.randi() % occupied_rids.size()]
		var room = room_map.get(rid)
		if not room:
			continue
		var rect: Rect2 = room.get_rect()
		var pos := Vector2(
			GameRNG.randf_range(rect.position.x + 100, rect.end.x - 100),
			GameRNG.randf_range(rect.position.y + 100, rect.end.y - 100))
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
	e.net_id = _next_net_id
	_next_net_id += 1
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
				_spawn_enemy(e.global_position + Vector2(GameRNG.randf_range(-50, 50), GameRNG.randf_range(-50, 50)), 1)
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
	e.net_id = _next_net_id
	_next_net_id += 1
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
				TutorialManager.on_blue_merge()


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
	if not NetworkManager.is_authority():
		# Client: send build request to host
		NetworkManager.send_command({
			"type": "buy_request",
			"item_id": item_id,
		})
		_placing_item = item_id  # start local placement preview
		return
	if Economy.purchase(item_id):
		_placing_item = item_id


func _get_dupe_chance(faction_id: int) -> float:
	## Returns 0.0-1.0 duplication probability based on faction pop vs effective max_pop.
	## 100% until 15% of max, linear decline to 0% at 100% of max.
	var faction_rooms: int = 0
	for rid in RoomOwnership.ownership:
		if RoomOwnership.ownership[rid] == faction_id:
			faction_rooms += 1
	var total_rooms: int = rooms.size()
	var claimable: int = maxi(1, total_rooms - FactionManager.get_all_faction_ids().size())
	var max_p: int = FactionManager.get_effective_max_pop(faction_id, faction_rooms, claimable)
	if max_p <= 0:
		return 1.0
	var current: int = 0
	for v in villagers:
		if is_instance_valid(v) and v.visible and v.faction_id == faction_id:
			if str(v.color_type) != "magic_orb":
				current += 1
	var ratio: float = float(current) / float(max_p)
	if ratio <= 0.15:
		return 1.0
	if ratio >= 1.0:
		return 0.0
	return clampf(1.0 - (ratio - 0.15) / 0.85, 0.0, 1.0)


func _on_villager_shifted(villager, old_color, new_color, spawn_count, faction_override) -> void:
	if not NetworkManager.is_authority():
		return
	if not is_instance_valid(villager):
		return

	villager.set_color_type(str(new_color))

	# For colorless shifting: use faction_override from the dominant influencer
	if str(old_color) == "colorless" and faction_override >= 0:
		villager.faction_id = faction_override
	elif villager.faction_id < 0:
		# Other unowned villagers: inherit from nearest same-color villager
		var best_fid: int = -1
		var best_d: float = INF
		for other in villagers:
			if not is_instance_valid(other) or other == villager:
				continue
			if str(other.color_type) == str(new_color) and other.faction_id >= 0:
				var d: float = villager.global_position.distance_to(other.global_position)
				if d < best_d:
					best_d = d
					best_fid = other.faction_id
		if best_fid >= 0:
			villager.faction_id = best_fid
	# Non-colorless cross-faction shifts: color changes, faction stays (no faction change needed)

	var color_names: Dictionary = {"red": "the red", "yellow": "the yellow", "blue": "the blue", "colorless": "the colorless"}
	var cname: String = color_names.get(str(new_color), str(new_color))
	EventFeed.push("A villager joined %s." % cname, ColorRegistry.get_def(str(new_color)).get("display_color", Color.WHITE))
	# Tutorial hook
	TutorialManager.on_shift(str(old_color), str(new_color), int(spawn_count))

	# Data-driven extra spawns with population-based probability scaling
	var dupe_chance: float = 1.0 if TutorialManager.active else _get_dupe_chance(villager.faction_id)
	for i in range(int(spawn_count) - 1):
		if GameRNG.randf() > dupe_chance:
			continue  # Pop cap reduces duplication
		_spawn_villager(
			str(new_color),
			villager.global_position + Vector2(GameRNG.randf_range(-50, 50), GameRNG.randf_range(-50, 50)),
			villager.faction_id
		)


func _spawn_villager(color_id: String, pos: Vector2, p_faction_id: int = 0) -> void:
	var v = _villager_scene.instantiate()
	_villager_container.add_child(v)
	v.setup(color_id, pos)
	v.faction_id = p_faction_id
	v.net_id = _next_net_id
	_next_net_id += 1
	v.villager_name = _gen_villager_name(color_id)
	v.resource_dropped.connect(_on_villager_dropped_resource)
	villagers.append(v)


func _update_hud() -> void:
	if not _hud:
		return
	var my_fid: int = FactionManager.local_faction_id

	# Count population for local faction only
	var counts: Dictionary = {}
	var faction_pop: Dictionary = {}  # fid -> total count
	for v in villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		if str(v.color_type) == "magic_orb":
			continue
		if v.faction_id == my_fid:
			counts[v.color_type] = counts.get(v.color_type, 0) + 1
		if v.faction_id >= 0:
			faction_pop[v.faction_id] = faction_pop.get(v.faction_id, 0) + 1
	_hud.pop_red = counts.get("red", 0)
	_hud.pop_yellow = counts.get("yellow", 0)
	_hud.pop_blue = counts.get("blue", 0)
	_hud.pop_colorless = counts.get("colorless", 0)
	_hud.pop_enemies = enemies.size() + night_enemies.size()
	_hud.pop_total = faction_pop.get(my_fid, 0)
	# Tutorial population hook
	TutorialManager.on_population_update(_hud.pop_total)

	# Populate selected villager info
	_hud.selected_villager_info.clear()
	if _player.has_selection():
		for v in _player.selected_villagers:
			if not is_instance_valid(v):
				continue
			var def: Dictionary = ColorRegistry.get_def(str(v.color_type))
			_hud.selected_villager_info.append({
				"name": v.villager_name if v.villager_name != "" else str(v.color_type).capitalize(),
				"health": v.health,
				"max_health": v.max_health,
				"shift": v.shift_meter,
				"color_type": str(v.color_type),
				"display_color": def.get("display_color", Color.WHITE),
			})

	# Populate selected building info
	_hud.selected_building_info.clear()
	if _player.has_building_selection():
		var b: Node = _player.selected_building
		var b_type: String = "Home"
		if b in churches: b_type = "Church"
		elif b in banks: b_type = "Bank"
		elif b in fishing_huts: b_type = "Fishing Hut"
		var b_cap: int = b.get_capacity() if b.has_method("get_capacity") else 0
		var b_occ: int = b.get_sheltered_count() if b.has_method("get_sheltered_count") else 0
		var b_fid: int = b.placed_by_faction if b.get("placed_by_faction") != null else -1
		_hud.selected_building_info = {
			"type": b_type,
			"capacity": b_cap,
			"occupied": b_occ,
			"faction_id": b_fid,
			"faction_symbol": FactionManager.get_faction_symbol(b_fid) if b_fid >= 0 else ("⚙" if b_fid == -2 else "?"),
			"faction_color": FactionManager.get_faction_color(b_fid) if b_fid >= 0 else Color(0.5, 0.5, 0.5),
		}

	# Count rooms owned per faction
	var faction_rooms: Dictionary = {}
	for rid in RoomOwnership.ownership:
		var owner_fid: int = RoomOwnership.ownership[rid]
		if owner_fid >= 0:
			faction_rooms[owner_fid] = faction_rooms.get(owner_fid, 0) + 1

	# Territory-based effective max pop for local faction
	var all_fids: Array = FactionManager.get_all_faction_ids()
	var total_rooms: int = rooms.size()
	var claimable_rooms: int = maxi(1, total_rooms - all_fids.size())

	# Build score data
	_hud.score_data.clear()
	for fid in all_fids:
		_hud.score_data.append({
			"faction_id": fid,
			"symbol": FactionManager.get_faction_symbol(fid),
			"name": FactionManager.get_faction_name(fid),
			"color": FactionManager.get_faction_color(fid),
			"pop": faction_pop.get(fid, 0),
			"stone": Economy.get_stone(fid),
			"fish": Economy.get_fish(fid),
			"rooms": faction_rooms.get(fid, 0),
			"score": faction_rooms.get(fid, 0) * 100,
			"eliminated": FactionManager.is_eliminated(fid),
		})

	# Update effective max pop display for local faction
	_hud.pop_max_effective = FactionManager.get_effective_max_pop(
		my_fid, faction_rooms.get(my_fid, 0), claimable_rooms)


func _on_villager_dropped_resource(villager: Node2D, resource_type: String) -> void:
	var pos: Vector2 = villager.global_position + Vector2(GameRNG.randf_range(-20, 20), GameRNG.randf_range(-20, 20))
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

	if _river_room_ids.is_empty():
		return

	for river_rid in _river_room_ids:
		# Count existing fish in this river room
		var fish_count: int = 0
		for f in fish_spots:
			if not is_instance_valid(f) or f.collected:
				continue
			if _room_id_at(f.global_position) == river_rid:
				fish_count += 1
		if fish_count >= RIVER_FISH_MAX:
			continue

		var room_def: Array = _map_gen.find_room_def(river_rid)
		if room_def.is_empty():
			continue
		var rpos: Vector2 = _map_gen.room_pixel_pos(room_def[1], room_def[2])
		var rsize: Vector2 = _map_gen.room_pixel_size(room_def[3], room_def[4])
		var f = _fish_scene.instantiate()
		_fish_container.add_child(f)
		f.global_position = Vector2(
			GameRNG.randf_range(rpos.x + 60.0, rpos.x + rsize.x - 60.0),
			GameRNG.randf_range(rpos.y + 60.0, rpos.y + rsize.y - 60.0))
		fish_spots.append(f)
		EventFeed.push("A fish appeared in the river.", Color(0.3, 0.55, 0.75))


# ==============================================================================
# HOST-AUTHORITATIVE NETWORKING
# ==============================================================================

const COLOR_TO_IDX := {"red": 0, "yellow": 1, "blue": 2, "colorless": 3, "magic_orb": 4}
const IDX_TO_COLOR := ["red", "yellow", "blue", "colorless", "magic_orb"]
const CARRY_TO_IDX := {"": 0, "stone": 1, "fish": 2}
const IDX_TO_CARRY := ["", "stone", "fish"]
const CMD_TO_IDX := {"none": 0, "move_to": 1, "hold": 2}
const IDX_TO_CMD := ["none", "move_to", "hold"]


func _init_client_puppets() -> void:
	## Mark all map-generated entities as puppets (client only).
	for v in villagers:
		v.is_puppet = true
	for e in enemies:
		e.is_puppet = true


func _on_remote_command(cmd: Dictionary) -> void:
	## Host receives a command from a client (or from local in solo).
	_apply_net_command(cmd)


func _client_process(delta: float) -> void:
	## Client-only frame: apply latest snapshot, interpolate, update visuals.
	var snap := NetworkManager.consume_snapshot()
	if not snap.is_empty():
		_apply_snapshot(snap)

	_assign_entities_to_rooms()
	_update_fog_and_camera()
	_update_hud()
	_sync_cursor(delta)
	queue_redraw()


func _broadcast_snapshot() -> void:
	## Host builds and broadcasts current state to all clients.
	var snap: Dictionary = {}

	# Villagers
	var v_data: Array = []
	for v in villagers:
		if not is_instance_valid(v):
			continue
		v_data.append([
			v.net_id,
			snappedi(int(v.global_position.x * 10.0), 1),
			snappedi(int(v.global_position.y * 10.0), 1),
			int(v.health),
			int(v.max_health),
			COLOR_TO_IDX.get(v.color_type, 0),
			v.level,
			CARRY_TO_IDX.get(v.carrying_resource, 0),
			1 if v.visible else 0,
			CMD_TO_IDX.get(v.command_mode, 0),
			v.faction_id,
			int(v.shift_meter),
			1 if v.is_fed else 0,
		])
	snap["v"] = v_data

	# Enemies
	var e_data: Array = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		e_data.append([
			e.net_id,
			snappedi(int(e.global_position.x * 10.0), 1),
			snappedi(int(e.global_position.y * 10.0), 1),
			int(e.health),
			int(e.max_health),
			e.level,
			1 if e.is_dead else 0,
		])
	snap["e"] = e_data

	# Night enemies
	var ne_data: Array = []
	for ne in night_enemies:
		if not is_instance_valid(ne):
			continue
		ne_data.append([
			ne.net_id,
			snappedi(int(ne.global_position.x * 10.0), 1),
			snappedi(int(ne.global_position.y * 10.0), 1),
			int(ne.health),
			1 if ne.is_dead else 0,
		])
	snap["ne"] = ne_data

	# Collectables (only collected state)
	var c_data: Array = []
	for i in collectables.size():
		var c = collectables[i]
		if is_instance_valid(c) and c.collected:
			c_data.append(i)
	snap["cc"] = c_data

	# Fish spots (only collected state)
	var f_data: Array = []
	for i in fish_spots.size():
		var fs = fish_spots[i]
		if is_instance_valid(fs) and fs.collected:
			f_data.append(i)
	snap["fc"] = f_data

	# Economy — per-faction
	var eco_data: Dictionary = {}
	for fid in FactionManager.get_all_faction_ids():
		eco_data[fid] = [Economy.get_stone(fid), Economy.get_fish(fid)]
	snap["eco"] = eco_data

	# Clock — full state for sync
	snap["clk"] = [GameClock.elapsed, GameClock.day_count, 1 if GameClock.is_paused else 0]

	# Dev state
	snap["dev"] = [1 if _dev_fog_off else 0]

	# Room ownership
	snap["own"] = RoomOwnership.ownership.duplicate()

	# Wall states (index-matched with walls array)
	var w_data: Array = []
	for w in walls:
		w_data.append(1 if w.is_open else 0)
	snap["ws"] = w_data

	NetworkManager.broadcast_snapshot(snap)


func _apply_snapshot(snap: Dictionary) -> void:
	## Client applies a state snapshot from host.
	var v_lookup: Dictionary = {}  # net_id → villager node
	for v in villagers:
		if is_instance_valid(v):
			v_lookup[v.net_id] = v

	var seen_v_ids: Dictionary = {}
	for vd in snap.get("v", []):
		var nid: int = int(vd[0])
		seen_v_ids[nid] = true
		var v = v_lookup.get(nid)
		if v == null:
			# New villager spawned on host — create puppet
			v = _villager_scene.instantiate()
			_villager_container.add_child(v)
			v.net_id = nid
			v.is_puppet = true
			villagers.append(v)
			v_lookup[nid] = v

		v.interp_target = Vector2(float(vd[1]) / 10.0, float(vd[2]) / 10.0)
		# Don't override position if this client is dragging this villager
		if not v._client_dragging:
			if v.global_position.distance_to(v.interp_target) > 500.0:
				v.global_position = v.interp_target
		v.health = float(vd[3])
		v.max_health = float(vd[4])
		var new_color: String = IDX_TO_COLOR[int(vd[5])] if int(vd[5]) < IDX_TO_COLOR.size() else "red"
		if v.color_type != new_color:
			v.set_color_type(new_color)
			v.health = float(vd[3])  # re-set after color change resets health
			v.max_health = float(vd[4])
		var new_level: int = int(vd[6])
		if v.level != new_level:
			v.set_level(new_level)
			v.health = float(vd[3])
			v.max_health = float(vd[4])
		v.carrying_resource = IDX_TO_CARRY[int(vd[7])] if int(vd[7]) < IDX_TO_CARRY.size() else ""
		v.visible = (int(vd[8]) == 1)
		v.command_mode = IDX_TO_CMD[int(vd[9])] if int(vd[9]) < IDX_TO_CMD.size() else "none"
		v.faction_id = int(vd[10])
		v.shift_meter = float(vd[11])
		v.is_fed = (int(vd[12]) == 1)

	# Remove villagers no longer in snapshot (died on host)
	var to_remove_v: Array = []
	for v in villagers:
		if is_instance_valid(v) and not seen_v_ids.has(v.net_id):
			to_remove_v.append(v)
	for v in to_remove_v:
		villagers.erase(v)
		v.queue_free()

	# Enemies
	var e_lookup: Dictionary = {}
	for e in enemies:
		if is_instance_valid(e):
			e_lookup[e.net_id] = e

	var seen_e_ids: Dictionary = {}
	for ed in snap.get("e", []):
		var nid: int = int(ed[0])
		seen_e_ids[nid] = true
		var e = e_lookup.get(nid)
		if e == null:
			e = _enemy_scene.instantiate()
			_enemy_container.add_child(e)
			e.net_id = nid
			e.is_puppet = true
			enemies.append(e)
			e_lookup[nid] = e
		e.interp_target = Vector2(float(ed[1]) / 10.0, float(ed[2]) / 10.0)
		if e.global_position.distance_to(e.interp_target) > 500.0:
			e.global_position = e.interp_target
		e.health = float(ed[3])
		e.max_health = float(ed[4])
		var new_lv: int = int(ed[5])
		if e.level != new_lv:
			e.set_level(new_lv)
			e.health = float(ed[3])
			e.max_health = float(ed[4])
		e.is_dead = (int(ed[6]) == 1)
		e.visible = not e.is_dead

	var to_remove_e: Array = []
	for e in enemies:
		if is_instance_valid(e) and not seen_e_ids.has(e.net_id):
			to_remove_e.append(e)
	for e in to_remove_e:
		enemies.erase(e)
		e.queue_free()

	# Night enemies — handle spawn/despawn from host
	var ne_lookup: Dictionary = {}
	for ne in night_enemies:
		if is_instance_valid(ne):
			ne_lookup[ne.net_id] = ne

	var seen_ne_ids: Dictionary = {}
	for ned in snap.get("ne", []):
		var nid: int = int(ned[0])
		seen_ne_ids[nid] = true
		var ne = ne_lookup.get(nid)
		if ne == null:
			# Spawn night enemy puppet
			ne = _demon_scene.instantiate()  # default; visual only
			_enemy_container.add_child(ne)
			ne.net_id = nid
			ne.is_puppet = true
			night_enemies.append(ne)
			ne_lookup[nid] = ne
		ne.interp_target = Vector2(float(ned[1]) / 10.0, float(ned[2]) / 10.0)
		if ne.global_position.distance_to(ne.interp_target) > 500.0:
			ne.global_position = ne.interp_target
		ne.health = float(ned[3])
		ne.is_dead = (int(ned[4]) == 1)
		ne.visible = not ne.is_dead

	var to_remove_ne: Array = []
	for ne in night_enemies:
		if is_instance_valid(ne) and not seen_ne_ids.has(ne.net_id):
			to_remove_ne.append(ne)
	for ne in to_remove_ne:
		night_enemies.erase(ne)
		ne.queue_free()

	# Collectables — mark collected on client
	for ci in snap.get("cc", []):
		if int(ci) < collectables.size():
			var c = collectables[int(ci)]
			if is_instance_valid(c) and not c.collected:
				c.collected = true
				c.visible = false

	# Fish spots — mark collected on client
	for fi in snap.get("fc", []):
		if int(fi) < fish_spots.size():
			var fs = fish_spots[int(fi)]
			if is_instance_valid(fs) and not fs.collected:
				fs.collected = true
				fs.visible = false

	# Economy — per-faction
	var eco: Dictionary = snap.get("eco", {})
	for fid_key in eco:
		var fid: int = int(fid_key)
		var vals: Array = eco[fid_key]
		if vals.size() >= 2:
			Economy.set_stone(fid, int(vals[0]))
			Economy.set_fish(fid, int(vals[1]))

	# Clock — full state sync
	var clk: Array = snap.get("clk", [])
	if clk.size() >= 3:
		GameClock.elapsed = float(clk[0])
		GameClock.day_count = int(clk[1])
		GameClock.is_paused = (int(clk[2]) == 1)
		GameClock.is_daytime = GameClock.elapsed < GameClock.DAY_DURATION

	# Dev state
	var dev: Array = snap.get("dev", [])
	if dev.size() >= 1:
		_dev_fog_off = (int(dev[0]) == 1)

	# Room ownership
	var own: Dictionary = snap.get("own", {})
	for rid in own:
		RoomOwnership.ownership[int(rid)] = int(own[rid])

	# Wall states
	var ws: Array = snap.get("ws", [])
	for i in mini(ws.size(), walls.size()):
		var should_open: bool = (int(ws[i]) == 1)
		if walls[i].is_open != should_open:
			walls[i].is_open = should_open
			walls[i].queue_redraw()


# ==============================================================================
# SURVIVAL MODE — COLOR RECOVERY
# ==============================================================================

func _check_survival_color_recovery(dead_color: String, dead_faction_id: int) -> void:
	## In survival mode, if a color has 0 remaining villagers for a faction,
	## convert the nearest valid villager from another color (count > 1) to the missing color.
	if FactionManager.game_mode != "survival":
		return
	if dead_faction_id < 0:
		return
	if dead_color not in ["red", "yellow", "blue"]:
		return

	# Count remaining of this color
	var remaining: int = 0
	for v in villagers:
		if is_instance_valid(v) and v.visible and str(v.color_type) == dead_color and v.faction_id == dead_faction_id:
			remaining += 1
	if remaining > 0:
		return  # Still have some, no recovery needed

	# Count all colors for this faction
	var color_counts: Dictionary = {}  # color -> count
	for v in villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		if v.faction_id != dead_faction_id:
			continue
		var ct: String = str(v.color_type)
		if ct in ["red", "yellow", "blue"]:
			color_counts[ct] = color_counts.get(ct, 0) + 1

	# Find a donor color with count > 1
	var best_v: Node = null
	var best_d: float = INF
	# We need a dead villager position — use the faction's core room center as fallback
	var ref_pos: Vector2 = Vector2.ZERO
	var core_rid: int = FactionManager.get_core_room(dead_faction_id)
	if room_map.has(core_rid):
		ref_pos = room_map[core_rid].get_rect().get_center()

	for v in villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		if v.faction_id != dead_faction_id:
			continue
		var ct: String = str(v.color_type)
		if ct == dead_color or ct not in ["red", "yellow", "blue"]:
			continue
		if color_counts.get(ct, 0) <= 1:
			continue  # Can't take from a color with only 1
		var d: float = v.global_position.distance_to(ref_pos) if ref_pos != Vector2.ZERO else 0.0
		if d < best_d:
			best_d = d
			best_v = v

	if best_v:
		var old_ct: String = str(best_v.color_type)
		best_v.set_color_type(dead_color)
		if dead_color == "red":
			best_v._satiation_timer = best_v.SATIATION_PER_LEVEL[1]
			best_v.is_fed = true
		EventFeed.push("A %s villager became %s to preserve color access!" % [old_ct, dead_color], Color(0.9, 0.7, 0.3))


# ==============================================================================
# CURSOR SYNC & FACTION VISUALS
# ==============================================================================

func _sync_cursor(delta: float) -> void:
	if not NetworkManager.is_online():
		return
	if NetworkManager.should_send_cursor(delta):
		var world_pos: Vector2 = get_global_mouse_position()
		NetworkManager.send_cursor(world_pos, FactionManager.local_faction_id)


func _draw() -> void:
	# Selection mode indicator
	if Input.is_key_pressed(KEY_SHIFT):
		var m: Vector2 = get_local_mouse_position()
		draw_arc(m, 20.0, 0.0, TAU, 16, Color(0.3, 0.9, 1.0, 0.5), 2.0, true)

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
		elif _placing_item == "bank":
			draw_rect(Rect2(m.x - 50, m.y - 30, 100, 60), Color(0.4, 0.38, 0.32, 0.4))
			draw_circle(m, 12.0, Color(0.5, 0.52, 0.48, 0.4))
		elif _placing_item == "fishing_hut":
			draw_rect(Rect2(m.x - 55, m.y - 25, 110, 55), Color(0.3, 0.25, 0.2, 0.4))
			draw_colored_polygon(PackedVector2Array([
				Vector2(m.x, m.y - 50), Vector2(m.x + 60, m.y - 25), Vector2(m.x - 60, m.y - 25)]),
				Color(0.25, 0.35, 0.5, 0.4))
		draw_string(ThemeDB.fallback_font, Vector2(m.x - 40, m.y + 50),
			"Click to place  |  Right-click cancel",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.7, 0.7))

	# Resource selection highlight
	if _player.has_resource_selection():
		var sp: Vector2 = _player.get_selected_resource().global_position
		var pulse: float = 0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.4
		var sel_color: Color = Color(0.94, 0.84, 0.12, pulse) if _player.get_selected_resource_type() == "stone" else Color(0.2, 0.4, 0.9, pulse)
		draw_arc(sp, 22.0, 0.0, TAU, 24, sel_color, 2.5, true)
		var hint_color: String = "yellow" if _player.get_selected_resource_type() == "stone" else "blue"
		draw_string(ThemeDB.fallback_font, Vector2(sp.x - 40, sp.y - 24),
			"Click a %s villager" % hint_color,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.9, 0.9, 0.8, pulse))

	# Remote cursors
	_draw_remote_cursors()


func _draw_remote_cursors() -> void:
	var my_peer := NetworkManager.get_my_peer_id()
	for pid in NetworkManager.remote_cursors:
		if int(pid) == my_peer:
			continue
		var data: Dictionary = NetworkManager.remote_cursors[pid]
		var pos: Vector2 = data["pos"]
		var fid: int = int(data["faction_id"])
		var fc: Color = FactionManager.get_faction_color(fid)
		# Crosshair cursor
		draw_line(pos + Vector2(-12, 0), pos + Vector2(12, 0), fc, 2.0)
		draw_line(pos + Vector2(0, -12), pos + Vector2(0, 12), fc, 2.0)
		draw_arc(pos, 8.0, 0.0, TAU, 16, fc, 1.5, true)
		# Label
		var label: String = FactionManager.get_faction_name(fid)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-16, -16), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, fc)


func _draw_faction_markers() -> void:
	## Draw a faction symbol at the centroid of each faction's villagers.
	var faction_positions: Dictionary = {}  # fid -> [positions]
	for v in villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		if v.faction_id < 0:
			continue
		if str(v.color_type) == "magic_orb":
			continue
		if not faction_positions.has(v.faction_id):
			faction_positions[v.faction_id] = []
		faction_positions[v.faction_id].append(v.global_position)

	for fid in faction_positions:
		var positions: Array = faction_positions[fid]
		if positions.is_empty():
			continue
		var centroid := Vector2.ZERO
		for p in positions:
			centroid += p
		centroid /= float(positions.size())
		var fc: Color = FactionManager.get_faction_color(fid)
		var glyph: String = FactionManager.get_faction_symbol(fid)
		var bg_color := Color(0.0, 0.0, 0.0, 0.45)
		draw_rect(Rect2(centroid.x - 14, centroid.y - 30, 28, 18), bg_color)
		draw_string(ThemeDB.fallback_font, Vector2(centroid.x - 10, centroid.y - 16),
			glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, fc)
