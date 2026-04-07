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

const RIVER_ROOM_ID := 6
const RIVER_FISH_MAX := 4
const RIVER_FISH_INTERVAL := 1800.0
const COLORLESS_ATTRACT_RANGE := 350.0

var _river_fish_timer: float = 0.0
var _dev_fog_off: bool = false

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

var map_seed: int = -1  ## -1 = random, >= 0 = deterministic
var faction_count: int = 1
var _next_net_id: int = 0


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
	# Starting resources
	Economy.stone = 5
	Economy.fish = 3
	InfluenceManager.villager_shifted.connect(_on_villager_shifted)
	GameClock.phase_changed.connect(_on_phase_changed)
	NightEvents.connect_to_clock()
	NightEvents.night_event_started.connect(_on_night_event)
	NightEvents.night_event_ended.connect(_on_night_event_end)
	_hud.buy_requested.connect(_on_buy_requested)
	_hud.command_issued.connect(_on_hud_command)
	_init_options_menu()
	if SaveManager.has_save():
		call_deferred("_try_load_save")


func _read_lobby_config() -> void:
	if FactionManager.has_meta("map_seed"):
		map_seed = FactionManager.get_meta("map_seed")
		FactionManager.remove_meta("map_seed")
	if FactionManager.has_meta("faction_count"):
		faction_count = FactionManager.get_meta("faction_count")
		FactionManager.remove_meta("faction_count")
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


func _try_load_save() -> void:
	SaveManager.load_game(self)
	_update_fog_and_camera()


# ==============================================================================
# MAP GENERATION (delegated to MapGenerator)
# ==============================================================================

func _generate_map() -> void:
	var gen = _map_generator_script.new()
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
	gen.generate(containers, scenes, map_seed, faction_count)
	room_map = gen.room_map


# ==============================================================================
# CAMERA + FOG
# ==============================================================================

func _init_camera() -> void:
	var MapGen: GDScript = _map_generator_script
	# Find home room for local faction
	var home_rid: int = 0
	var my_fid: int = FactionManager.local_faction_id
	if faction_count > 1 and my_fid < MapGen.FACTION_STARTS.size():
		home_rid = MapGen.FACTION_STARTS[my_fid]["home_room"]
	var def: Array = MapGen.find_room_def(home_rid)
	if not def.is_empty():
		var rpos: Vector2 = MapGen.room_pixel_pos(def[1], def[2])
		var rsize: Vector2 = MapGen.room_pixel_size(def[3], def[4])
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

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("quick_save"):
			SaveManager.save_game(self)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("deselect"):
			if _hud.get_pending_command() != "":
				_hud.clear_pending_command()
				get_viewport().set_input_as_handled()
				return
			if _player.has_selection():
				_player.deselect_all()
				_hud.set_command_menu_visible(false)
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

	# Clicked empty ground — deselect
	if _player.has_selection():
		_player.deselect_all()
		_hud.set_command_menu_visible(false)



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
	if _placing_item == "house":
		if NetworkManager.is_authority():
			Economy.stone += 5
	elif _placing_item == "church":
		if NetworkManager.is_authority():
			Economy.stone += 50
	_placing_item = ""


func _place_building(item_id: String, pos: Vector2) -> void:
	## Shared building creation logic (host + client via remote).
	if item_id == "house":
		var h = _home_scene.instantiate()
		_homes_container.add_child(h)
		h.global_position = pos
		homes.append(h)
		EventFeed.push("Home built.", Color(0.7, 0.6, 0.4))
	elif item_id == "church":
		var c = _church_scene.instantiate()
		_churches_container.add_child(c)
		c.global_position = pos
		churches.append(c)
		EventFeed.push("Church built.", Color(0.5, 0.6, 0.85))


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
		"wall_toggle":
			var wa: int = int(cmd.get("room_a", -1))
			var wb: int = int(cmd.get("room_b", -1))
			var wsx: float = float(cmd.get("sx", 0.0))
			var wsy: float = float(cmd.get("sy", 0.0))
			for w in walls:
				if w.room_a_id == wa and w.room_b_id == wb and not w.is_door:
					if absf(w.start_pos.x - wsx) < 1.0 and absf(w.start_pos.y - wsy) < 1.0:
						w.is_open = not w.is_open
						w.queue_redraw()
						break
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
	# Build wall data once per frame for villager collision
	var wall_info: Array = []
	for w in walls:
		wall_info.append({"start": w.start_pos, "end": w.end_pos, "is_open": w.is_open})

	for v in villagers:
		var rid: int = v.current_room_id
		v.brain_enemies = room_enemies.get(rid, [])
		v.brain_room_villagers = room_villagers.get(rid, [])
		v.brain_walls = wall_info
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
	if not NetworkManager.is_authority():
		return
	if is_daytime:
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


func _on_villager_shifted(villager, old_color, new_color, spawn_count) -> void:
	if not NetworkManager.is_authority():
		return
	if not is_instance_valid(villager):
		return

	villager.set_color_type(str(new_color))

	# Inherit faction from nearest same-color villager, or stay unowned
	if villager.faction_id < 0:
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

	var color_names: Dictionary = {"red": "the red", "yellow": "the yellow", "blue": "the blue", "colorless": "the colorless"}
	var cname: String = color_names.get(str(new_color), str(new_color))
	EventFeed.push("A villager joined %s." % cname, ColorRegistry.get_def(str(new_color)).get("display_color", Color.WHITE))

	# Data-driven extra spawns (e.g. red->yellow produces 2 total: the shifted one + 1 extra)
	for i in range(int(spawn_count) - 1):
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

	# Count existing fish in the river room
	var fish_in_river: int = 0
	for f in fish_spots:
		if not is_instance_valid(f) or f.collected:
			continue
		if _room_id_at(f.global_position) == RIVER_ROOM_ID:
			fish_in_river += 1
	if fish_in_river >= RIVER_FISH_MAX:
		return

	var MapGen: GDScript = _map_generator_script
	var room_def: Array = MapGen.find_room_def(RIVER_ROOM_ID)
	if room_def.is_empty():
		return
	var rpos: Vector2 = MapGen.room_pixel_pos(room_def[1], room_def[2])
	var rsize: Vector2 = MapGen.room_pixel_size(room_def[3], room_def[4])
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

	# Economy
	snap["eco"] = [Economy.stone, Economy.fish]

	# Clock
	snap["clk"] = [1 if GameClock.is_daytime else 0]

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

	# Economy
	var eco: Array = snap.get("eco", [])
	if eco.size() >= 2:
		Economy.stone = int(eco[0])
		Economy.fish = int(eco[1])

	# Clock
	var clk: Array = snap.get("clk", [])
	if clk.size() >= 1:
		GameClock.is_daytime = (int(clk[0]) == 1)

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
# CURSOR SYNC & FACTION VISUALS
# ==============================================================================

func _sync_cursor(delta: float) -> void:
	if not NetworkManager.is_online():
		return
	if NetworkManager.should_send_cursor(delta):
		var world_pos: Vector2 = get_global_mouse_position()
		NetworkManager.send_cursor(world_pos, FactionManager.local_faction_id)


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

	# Faction markers at villager centroids
	_draw_faction_markers()


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


const FACTION_GLYPHS := ["P1", "P2", "P3", "P4"]

func _draw_faction_markers() -> void:
	## Draw a faction glyph at the centroid of each faction's villagers.
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
		var glyph: String = FACTION_GLYPHS[fid] if fid < FACTION_GLYPHS.size() else "P?"
		var bg_color := Color(0.0, 0.0, 0.0, 0.45)
		draw_rect(Rect2(centroid.x - 14, centroid.y - 30, 28, 18), bg_color)
		draw_string(ThemeDB.fallback_font, Vector2(centroid.x - 10, centroid.y - 16),
			glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, fc)
