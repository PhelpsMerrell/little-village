extends Node
## Save/load system. Serializes full game state to user://savegame.json.
## Call SaveManager.save_game(main_node) and SaveManager.load_game(main_node).

const SAVE_PATH := "user://savegame.json"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game(main: Node) -> bool:
	if NetworkManager.is_online():
		EventFeed.push("Cannot save during multiplayer.", Color(0.9, 0.5, 0.3))
		return false
	var data: Dictionary = {
		"version": 1,
		"clock": GameClock.get_save_data(),
		"economy": {"stone": Economy.stone, "fish": Economy.fish},
		"walls": _save_walls(main),
		"villagers": _save_villagers(main),
		"enemies": _save_enemies(main),
		"collectables": _save_collectables(main),
		"fish_spots": _save_fish_spots(main),
		"buildings": _save_buildings(main),
		"fog_explored": FogOfWar.get_save_data(),
	}

	var json_str: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open %s for writing" % SAVE_PATH)
		return false
	file.store_string(json_str)
	file.close()
	EventFeed.push("Game saved.", Color(0.5, 0.8, 0.5))
	return true


func load_game(main: Node) -> bool:
	if NetworkManager.is_online():
		EventFeed.push("Cannot load during multiplayer.", Color(0.9, 0.5, 0.3))
		return false
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json_str: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		push_error("SaveManager: JSON parse error: %s" % json.get_error_message())
		return false

	var data: Dictionary = json.data
	if not data is Dictionary:
		return false

	# Restore clock
	GameClock.load_save_data(data.get("clock", {}))

	# Restore economy
	var econ: Dictionary = data.get("economy", {})
	Economy.stone = int(econ.get("stone", 0))
	Economy.fish = int(econ.get("fish", 0))

	# Restore walls
	_load_walls(main, data.get("walls", []))

	# Clear and restore dynamic entities
	_clear_dynamic_entities(main)
	_load_villagers(main, data.get("villagers", []))
	_load_enemies(main, data.get("enemies", []))
	_load_collectables(main, data.get("collectables", []))
	_load_fish_spots(main, data.get("fish_spots", []))
	_load_buildings(main, data.get("buildings", []))

	# Restore fog
	FogOfWar.load_save_data(data.get("fog_explored", []))

	# Re-collect everything
	main._collect_all()
	EventFeed.push("Game loaded.", Color(0.5, 0.8, 0.5))
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


# ==============================================================================
# SERIALIZATION HELPERS
# ==============================================================================

func _save_walls(main: Node) -> Array:
	var result: Array = []
	for w in main.walls:
		result.append({
			"room_a": w.room_a_id,
			"room_b": w.room_b_id,
			"is_open": w.is_open,
		})
	return result


func _save_villagers(main: Node) -> Array:
	var result: Array = []
	for v in main.villagers:
		result.append({
			"color_type": str(v.color_type),
			"level": int(v.level),
			"x": v.global_position.x,
			"y": v.global_position.y,
			"health": v.health,
			"max_health": v.max_health,
			"shift_meter": v.shift_meter,
			"kill_count": v.kill_count,
			"is_fed": v.is_fed,
			"satiation_timer": v._satiation_timer,
			"carrying_resource": str(v.carrying_resource),
			"faction_id": v.faction_id,
			"net_id": v.net_id,
		})
	return result


func _save_enemies(main: Node) -> Array:
	var result: Array = []
	for e in main.enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		result.append({
			"level": int(e.level),
			"x": e.global_position.x,
			"y": e.global_position.y,
			"health": e.health,
			"dupe_meter": e.dupe_meter,
			"net_id": e.net_id,
		})
	return result


func _save_collectables(main: Node) -> Array:
	var result: Array = []
	for c in main.collectables:
		if not is_instance_valid(c) or c.collected: continue
		result.append({"x": c.global_position.x, "y": c.global_position.y})
	return result


func _save_fish_spots(main: Node) -> Array:
	var result: Array = []
	for f in main.fish_spots:
		if not is_instance_valid(f) or f.collected: continue
		result.append({"x": f.global_position.x, "y": f.global_position.y})
	return result


func _save_buildings(main: Node) -> Array:
	var result: Array = []
	for h in main.homes:
		result.append({"type": "home", "x": h.global_position.x, "y": h.global_position.y})
	for ch in main.churches:
		result.append({"type": "church", "x": ch.global_position.x, "y": ch.global_position.y})
	return result


# ==============================================================================
# DESERIALIZATION HELPERS
# ==============================================================================

func _load_walls(main: Node, wall_data: Array) -> void:
	# Match walls by room_a/room_b pair
	for wd in wall_data:
		for w in main.walls:
			if w.room_a_id == int(wd["room_a"]) and w.room_b_id == int(wd["room_b"]):
				w.is_open = bool(wd["is_open"])
				w.queue_redraw()
				break


func _clear_dynamic_entities(main: Node) -> void:
	# Clear villagers
	for v in main.villagers:
		if is_instance_valid(v): v.queue_free()
	main.villagers.clear()

	# Clear enemies
	for e in main.enemies:
		if is_instance_valid(e): e.queue_free()
	main.enemies.clear()

	# Clear night enemies
	for ne in main.night_enemies:
		if is_instance_valid(ne): ne.queue_free()
	main.night_enemies.clear()

	# Clear collectables
	for c in main.collectables:
		if is_instance_valid(c): c.queue_free()
	main.collectables.clear()

	# Clear fish
	for f in main.fish_spots:
		if is_instance_valid(f): f.queue_free()
	main.fish_spots.clear()

	# Clear player-built buildings (not editor-placed ones)
	# We clear ALL homes/churches and rebuild from save
	for h in main.homes:
		if is_instance_valid(h): h.queue_free()
	main.homes.clear()
	for ch in main.churches:
		if is_instance_valid(ch): ch.queue_free()
	main.churches.clear()


func _load_villagers(main: Node, data: Array) -> void:
	var scene: PackedScene = preload("res://scenes/villager.tscn")
	for vd in data:
		var v = scene.instantiate()
		main.get_node("Villagers").add_child(v)
		v.setup(str(vd["color_type"]), Vector2(float(vd["x"]), float(vd["y"])), int(vd.get("level", 1)))
		v.health = float(vd.get("health", v.max_health))
		v.shift_meter = float(vd.get("shift_meter", 0.0))
		v.kill_count = int(vd.get("kill_count", 0))
		v.is_fed = bool(vd.get("is_fed", true))
		v._satiation_timer = float(vd.get("satiation_timer", 0.0))
		v.carrying_resource = str(vd.get("carrying_resource", ""))
		v.faction_id = int(vd.get("faction_id", 0))
		v.net_id = int(vd.get("net_id", -1))
		if not v.resource_dropped.is_connected(main._on_villager_dropped_resource):
			v.resource_dropped.connect(main._on_villager_dropped_resource)


func _load_enemies(main: Node, data: Array) -> void:
	var scene: PackedScene = preload("res://scenes/enemy.tscn")
	for ed in data:
		var e = scene.instantiate()
		main.get_node("Enemies").add_child(e)
		e.global_position = Vector2(float(ed["x"]), float(ed["y"]))
		e.set_level(int(ed.get("level", 1)))
		e.health = float(ed.get("health", e.max_health))
		e.dupe_meter = float(ed.get("dupe_meter", 0.0))
		e.net_id = int(ed.get("net_id", -1))


func _load_collectables(main: Node, data: Array) -> void:
	var scene: PackedScene = preload("res://scenes/collectable.tscn")
	for cd in data:
		var c = scene.instantiate()
		main.get_node("Collectables").add_child(c)
		c.global_position = Vector2(float(cd["x"]), float(cd["y"]))


func _load_fish_spots(main: Node, data: Array) -> void:
	var scene: PackedScene = preload("res://scenes/fish_spot.tscn")
	for fd in data:
		var f = scene.instantiate()
		main.get_node("FishSpots").add_child(f)
		f.global_position = Vector2(float(fd["x"]), float(fd["y"]))


func _load_buildings(main: Node, data: Array) -> void:
	var home_scene: PackedScene = preload("res://scenes/home.tscn")
	var church_scene: PackedScene = preload("res://scenes/church.tscn")
	var homes_container: Node = main.get_node("Homes")
	var churches_container: Node = main._get_or_create_container("Churches")

	for bd in data:
		match str(bd["type"]):
			"home":
				var h = home_scene.instantiate()
				homes_container.add_child(h)
				h.global_position = Vector2(float(bd["x"]), float(bd["y"]))
			"church":
				var c = church_scene.instantiate()
				churches_container.add_child(c)
				c.global_position = Vector2(float(bd["x"]), float(bd["y"]))
