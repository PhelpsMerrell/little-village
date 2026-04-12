extends Node
## AI Controller: manages one AI-controlled faction.
## Runs on the host, makes decisions each tick.
## Uses the same command functions as a human player would.

const THINK_INTERVAL := 1.5  ## seconds between AI decision cycles
const BUILD_INTERVAL := 8.0  ## seconds between build attempts
const ATTACK_INTERVAL := 3.0

var faction_id: int = -1
var _think_timer: float = 0.0
var _build_timer: float = 0.0
var _attack_timer: float = 0.0

## References set by main.gd
var main_ref: Node = null


func setup(fid: int, main: Node) -> void:
	faction_id = fid
	main_ref = main
	_think_timer = randf_range(0.5, THINK_INTERVAL)
	_build_timer = randf_range(2.0, BUILD_INTERVAL)
	_attack_timer = randf_range(1.0, ATTACK_INTERVAL)


func ai_process(delta: float) -> void:
	if main_ref == null:
		return
	if FactionManager.is_eliminated(faction_id):
		return

	_think_timer -= delta
	_build_timer -= delta
	_attack_timer -= delta

	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL + randf_range(-0.3, 0.3)
		_assign_idle_workers()

	if _build_timer <= 0.0:
		_build_timer = BUILD_INTERVAL + randf_range(-1.0, 1.0)
		_try_build()

	if _attack_timer <= 0.0:
		_attack_timer = ATTACK_INTERVAL + randf_range(-0.5, 0.5)
		_try_attack_enemies()


# ── Worker Assignment ────────────────────────────────────────────

func _get_my_villagers() -> Array:
	var result: Array = []
	for v in main_ref.villagers:
		if is_instance_valid(v) and v.visible and v.faction_id == faction_id:
			result.append(v)
	return result


func _get_idle_by_color(color: String) -> Array:
	var result: Array = []
	for v in _get_my_villagers():
		if str(v.color_type) != color:
			continue
		if v.command_mode != "none":
			continue
		if v.is_carrying():
			continue
		if v.has_waypoint:
			continue
		result.append(v)
	return result


func _assign_idle_workers() -> void:
	# Assign idle yellows to nearest uncollected stone/diamond
	var idle_yellows: Array = _get_idle_by_color("yellow")
	for v in idle_yellows:
		var best_res: Node = null
		var best_d: float = INF
		for c in main_ref.collectables:
			if not is_instance_valid(c) or c.collected:
				continue
			var d: float = v.global_position.distance_to(c.global_position)
			if d < best_d:
				best_d = d
				best_res = c
		if best_res and best_d < 2000.0:
			v.waypoint_target_pos = best_res.global_position
			v.has_waypoint = true

	# Assign idle blues to nearest uncollected fish
	var idle_blues: Array = _get_idle_by_color("blue")
	for v in idle_blues:
		var best_fish: Node = null
		var best_d: float = INF
		for f in main_ref.fish_spots:
			if not is_instance_valid(f) or f.collected:
				continue
			var d: float = v.global_position.distance_to(f.global_position)
			if d < best_d:
				best_d = d
				best_fish = f
		if best_fish and best_d < 2000.0:
			v.waypoint_target_pos = best_fish.global_position
			v.has_waypoint = true


# ── Building ─────────────────────────────────────────────────────

func _try_build() -> void:
	# Priority: home > bank > fishing_hut > church
	var my_rooms: Array = []
	for rid in RoomOwnership.ownership:
		if RoomOwnership.ownership[rid] == faction_id:
			my_rooms.append(rid)
	if my_rooms.is_empty():
		return

	# Count existing buildings
	var home_count: int = 0
	var bank_count: int = 0
	var hut_count: int = 0
	var church_count: int = 0
	for h in main_ref.homes:
		if is_instance_valid(h) and h.placed_by_faction == faction_id:
			home_count += 1
	for b in main_ref.banks:
		if is_instance_valid(b) and (b.placed_by_faction == faction_id or b.placed_by_faction == -2):
			bank_count += 1
	for h in main_ref.fishing_huts:
		if is_instance_valid(h) and (h.placed_by_faction == faction_id or h.placed_by_faction == -2):
			hut_count += 1
	for c in main_ref.churches:
		if is_instance_valid(c) and c.placed_by_faction == faction_id:
			church_count += 1

	var item_to_build: String = ""
	if home_count < 2:
		item_to_build = "house"
	elif bank_count < 1:
		item_to_build = "bank"
	elif hut_count < 1:
		item_to_build = "fishing_hut"
	elif home_count < 4:
		item_to_build = "house"
	elif church_count < 1:
		item_to_build = "church"
	elif bank_count < 2:
		item_to_build = "bank"
	else:
		item_to_build = "house"

	if not Economy.can_afford(item_to_build, faction_id):
		return

	# Pick a random owned room to build in
	var rid: int = my_rooms[randi() % my_rooms.size()]
	var room = main_ref.room_map.get(rid)
	if not room:
		return
	var rect: Rect2 = room.get_rect()
	var pos := Vector2(
		randf_range(rect.position.x + 100, rect.end.x - 100),
		randf_range(rect.position.y + 100, rect.end.y - 100))

	if Economy.purchase(item_to_build, faction_id):
		_place_building(item_to_build, pos)


func _place_building(item_id: String, pos: Vector2) -> void:
	var home_scene: PackedScene = preload("res://scenes/home.tscn")
	var church_scene: PackedScene = preload("res://scenes/church.tscn")
	var bank_scene: PackedScene = preload("res://scenes/bank.tscn")
	var hut_scene: PackedScene = preload("res://scenes/fishing_hut.tscn")

	match item_id:
		"house":
			var h = home_scene.instantiate()
			main_ref.get_node("Homes").add_child(h)
			h.global_position = pos
			h.placed_by_faction = faction_id
			main_ref.homes.append(h)
		"church":
			var c = church_scene.instantiate()
			main_ref._get_or_create_container("Churches").add_child(c)
			c.global_position = pos
			c.placed_by_faction = faction_id
			main_ref.churches.append(c)
		"bank":
			var b = bank_scene.instantiate()
			main_ref.get_node("Banks").add_child(b)
			b.global_position = pos
			b.placed_by_faction = faction_id
			main_ref.banks.append(b)
		"fishing_hut":
			var h = hut_scene.instantiate()
			main_ref.get_node("FishingHuts").add_child(h)
			h.global_position = pos
			h.placed_by_faction = faction_id
			main_ref.fishing_huts.append(h)


# ── Combat ───────────────────────────────────────────────────────

func _try_attack_enemies() -> void:
	var reds: Array = []
	for v in _get_my_villagers():
		if str(v.color_type) == "red" and v.command_mode == "none":
			reds.append(v)
	if reds.is_empty():
		return

	# Find nearest enemy to any idle red
	for r in reds:
		var best_enemy: Node = null
		var best_d: float = 500.0
		# Check map enemies
		for e in main_ref.enemies:
			if not is_instance_valid(e) or e.is_dead:
				continue
			var d: float = r.global_position.distance_to(e.global_position)
			if d < best_d:
				best_d = d
				best_enemy = e
		# Check night enemies
		for ne in main_ref.night_enemies:
			if not is_instance_valid(ne) or ne.is_dead:
				continue
			var d: float = r.global_position.distance_to(ne.global_position)
			if d < best_d:
				best_d = d
				best_enemy = ne
		# Check enemy-faction villagers
		for v in main_ref.villagers:
			if not is_instance_valid(v) or not v.visible:
				continue
			if v.faction_id == faction_id or v.faction_id < 0:
				continue
			# Only attack if we're at war or they're in our territory
			var v_rid: int = v.current_room_id
			var room_owner: int = RoomOwnership.ownership.get(v_rid, -1)
			if room_owner == faction_id or main_ref._are_at_war(faction_id, v.faction_id):
				var d: float = r.global_position.distance_to(v.global_position)
				if d < best_d:
					best_d = d
					best_enemy = v

		if best_enemy:
			r.command_attack(best_enemy)
			break  # one attack order per cycle
