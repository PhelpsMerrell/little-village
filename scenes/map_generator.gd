extends RefCounted
## Generates the map layout: rooms, walls, and entity spawns.
## Accepts a seed for deterministic generation (multiplayer sync).
## Data-driven: ROOM_DEFS and SPAWN_RULES define the world.

const CELL := 675
const MAP_GAP := 8
const DOOR_SIZE := 120.0  ## Width of door opening in pixels

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

## Faction starting positions (up to 4). Each gets a home room + bank room.
const FACTION_STARTS := [
	{"home_room": 0, "bank_room": 1},    # top-left corner
	{"home_room": 5, "bank_room": 4},    # top-right
	{"home_room": 20, "bank_room": 15},  # bottom-left
	{"home_room": 19, "bank_room": 13},  # bottom-right
]

## Output: populated by generate()
var room_map: Dictionary = {}

var _faction_override_rooms: Array = []
var _rng: RandomNumberGenerator
var _faction_count: int = 1


func generate(containers: Dictionary, scenes: Dictionary, map_seed: int = -1, faction_count: int = 1) -> void:
	_rng = RandomNumberGenerator.new()
	if map_seed >= 0:
		_rng.seed = map_seed
	else:
		_rng.randomize()
	_faction_count = faction_count
	_faction_override_rooms.clear()

	# Always override faction start rooms so SPAWN_RULES doesn't duplicate
	# villagers/buildings there — applies to solo (faction 0) too.
	for i in mini(maxi(_faction_count, 1), FACTION_STARTS.size()):
		_faction_override_rooms.append(FACTION_STARTS[i]["home_room"])
		_faction_override_rooms.append(FACTION_STARTS[i]["bank_room"])

	_generate_rooms(containers["rooms"], scenes["room"])
	_generate_walls(containers["walls"], scenes["wall"])
	_generate_entities(containers, scenes)
	_generate_faction_starts(containers, scenes)


static func room_pixel_pos(col: int, row: int) -> Vector2:
	return Vector2(col * (CELL + MAP_GAP), row * (CELL + MAP_GAP))


static func room_pixel_size(cw: int, ch: int) -> Vector2:
	return Vector2(cw * CELL + (cw - 1) * MAP_GAP, ch * CELL + (ch - 1) * MAP_GAP)


static func find_room_def(rid: int) -> Array:
	for def in ROOM_DEFS:
		if def[0] == rid:
			return def
	return []


func _rand_in_room(rpos: Vector2, rsize: Vector2, margin: float) -> Vector2:
	return Vector2(
		_rng.randf_range(rpos.x + margin, rpos.x + rsize.x - margin),
		_rng.randf_range(rpos.y + margin, rpos.y + rsize.y - margin))


func _generate_rooms(container: Node2D, room_scene: PackedScene) -> void:
	for def in ROOM_DEFS:
		var r = room_scene.instantiate()
		r.room_id = def[0]
		r.room_size = room_pixel_size(def[3], def[4])
		r.room_label = def[5]
		r.room_color = def[6]
		r.position = room_pixel_pos(def[1], def[2])
		container.add_child(r)
		room_map[def[0]] = r


func _generate_walls(container: Node2D, wall_scene: PackedScene) -> void:
	var grid: Dictionary = {}
	for def in ROOM_DEFS:
		var rid: int = def[0]
		for dx in def[3]:
			for dy in def[4]:
				grid[Vector2i(def[1] + dx, def[2] + dy)] = rid

	var wall_pairs: Dictionary = {}
	for cell in grid:
		var rid_a: int = grid[cell]
		var right := Vector2i(cell.x + 1, cell.y)
		if grid.has(right) and grid[right] != rid_a:
			var rid_b: int = grid[right]
			var key: String = "%d_%d" % [mini(rid_a, rid_b), maxi(rid_a, rid_b)]
			if not wall_pairs.has(key):
				wall_pairs[key] = {"a": mini(rid_a, rid_b), "b": maxi(rid_a, rid_b), "cells": [], "orient": "v"}
			wall_pairs[key]["cells"].append(cell)
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
			cells.sort_custom(func(a, b): return a.y < b.y)
			var col: int = cells[0].x
			var min_row: int = cells[0].y
			var max_row: int = cells[cells.size() - 1].y
			var x: float = (col + 1) * (CELL + MAP_GAP) - MAP_GAP / 2.0
			start_pos = Vector2(x, min_row * (CELL + MAP_GAP))
			end_pos = Vector2(x, (max_row + 1) * (CELL + MAP_GAP) - MAP_GAP)
		else:
			cells.sort_custom(func(a, b): return a.x < b.x)
			var row: int = cells[0].y
			var min_col: int = cells[0].x
			var max_col: int = cells[cells.size() - 1].x
			var y: float = (row + 1) * (CELL + MAP_GAP) - MAP_GAP / 2.0
			start_pos = Vector2(min_col * (CELL + MAP_GAP), y)
			end_pos = Vector2((max_col + 1) * (CELL + MAP_GAP) - MAP_GAP, y)
		var wall_length := start_pos.distance_to(end_pos)
		var dir := (end_pos - start_pos).normalized()
		var mid := (start_pos + end_pos) * 0.5
		var half_door := DOOR_SIZE * 0.5

		# Door gap in the center
		var door_start := mid - dir * half_door
		var door_end := mid + dir * half_door

		# Left/top wall segment
		if start_pos.distance_to(door_start) > 20.0:
			var w1 = wall_scene.instantiate()
			w1.room_a_id = wp["a"]
			w1.room_b_id = wp["b"]
			w1.start_pos = start_pos
			w1.end_pos = door_start
			container.add_child(w1)

		# Door segment (always open, ensures influence connectivity)
		var door = wall_scene.instantiate()
		door.room_a_id = wp["a"]
		door.room_b_id = wp["b"]
		door.start_pos = door_start
		door.end_pos = door_end
		door.is_open = false
		door.is_door = true
		container.add_child(door)

		# Right/bottom wall segment
		if door_end.distance_to(end_pos) > 20.0:
			var w2 = wall_scene.instantiate()
			w2.room_a_id = wp["a"]
			w2.room_b_id = wp["b"]
			w2.start_pos = door_end
			w2.end_pos = end_pos
			container.add_child(w2)


func _generate_entities(containers: Dictionary, scenes: Dictionary) -> void:
	for rid in SPAWN_RULES:
		var room_def: Array = find_room_def(rid)
		if room_def.is_empty():
			continue
		var rpos: Vector2 = room_pixel_pos(room_def[1], room_def[2])
		var rsize: Vector2 = room_pixel_size(room_def[3], room_def[4])
		var center: Vector2 = rpos + rsize * 0.5
		var rules: Array = SPAWN_RULES[rid]

		for rule in rules:
			var rtype: String = str(rule["type"])
			var count: int = int(rule.get("count", 1))

			# Skip villager/building spawns in faction start rooms (solo and multi).
			if rid in _faction_override_rooms:
				if rtype in ["villager", "magic_orb", "bank", "fishing_hut"]:
					continue

			match rtype:
				"villager":
					for i in count:
						var v = scenes["villager"].instantiate()
						containers["villagers"].add_child(v)
						v.setup(str(rule["color"]), center + Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-40, 40)))
						if rule.get("fed", false):
							v._satiation_timer = v.SATIATION_PER_LEVEL[1]
							v.is_fed = true
						# Faction assignment
						if str(rule["color"]) == "colorless" and _faction_count > 1:
							v.faction_id = -1  # unowned, recruitable
						else:
							v.faction_id = 0
				"magic_orb":
					var orb = scenes["villager"].instantiate()
					containers["villagers"].add_child(orb)
					orb.setup("magic_orb", center)
				"enemy":
					for i in count:
						var e = scenes["enemy"].instantiate()
						containers["enemies"].add_child(e)
						e.global_position = _rand_in_room(rpos, rsize, 100.0)
				"stone":
					for i in count:
						var c = scenes["collectable"].instantiate()
						containers["collectables"].add_child(c)
						c.global_position = _rand_in_room(rpos, rsize, 60.0)
				"fish":
					for i in count:
						var f = scenes["fish"].instantiate()
						containers["fish"].add_child(f)
						f.global_position = _rand_in_room(rpos, rsize, 60.0)
				"bank":
					var b = scenes["bank"].instantiate()
					containers["banks"].add_child(b)
					b.global_position = Vector2(center.x, rpos.y + 200)
				"fishing_hut":
					var h = scenes["hut"].instantiate()
					containers["huts"].add_child(h)
					h.global_position = Vector2(rpos.x + rsize.x - 200, center.y)
				"river":
					var river = scenes["river"].instantiate()
					var room_node = room_map.get(rid)
					if room_node:
						room_node.add_child(river)
						river.position = Vector2(50, 50)


func _generate_faction_starts(containers: Dictionary, scenes: Dictionary) -> void:
	## Spawn balanced starting units per faction. Each color is placed in a
	## separate corner of the home room, spaced beyond influence range (~540px)
	## so no shifting occurs until the player deliberately drags them together.
	for fi in mini(_faction_count, FACTION_STARTS.size()):
		var start: Dictionary = FACTION_STARTS[fi]
		var home_def: Array = find_room_def(start["home_room"])
		var bank_def: Array = find_room_def(start["bank_room"])
		if home_def.is_empty():
			continue

		var hpos: Vector2 = room_pixel_pos(home_def[1], home_def[2])
		var hsize: Vector2 = room_pixel_size(home_def[3], home_def[4])
		var margin: float = 150.0

		# Corner positions — well beyond 540px influence range of each other
		var corners: Array[Vector2] = [
			Vector2(hpos.x + margin, hpos.y + margin),                    # top-left: red
			Vector2(hpos.x + hsize.x - margin, hpos.y + margin),         # top-right: yellow
			Vector2(hpos.x + margin, hpos.y + hsize.y - margin),         # bottom-left: blue
		]
		var color_defs: Array = [
			{"color": "red", "fed": true},
			{"color": "yellow", "fed": false},
			{"color": "blue", "fed": false},
		]

		for ci in color_defs.size():
			var v = scenes["villager"].instantiate()
			containers["villagers"].add_child(v)
			v.setup(str(color_defs[ci]["color"]), corners[ci] + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-30, 30)))
			v.faction_id = fi
			if color_defs[ci]["fed"]:
				v._satiation_timer = v.SATIATION_PER_LEVEL[1]
				v.is_fed = true

		# Magic orb in center
		var hcenter: Vector2 = hpos + hsize * 0.5
		var orb = scenes["villager"].instantiate()
		containers["villagers"].add_child(orb)
		orb.setup("magic_orb", hcenter)
		orb.faction_id = fi

		# Bank in bank room
		if not bank_def.is_empty():
			var bpos: Vector2 = room_pixel_pos(bank_def[1], bank_def[2])
			var bsize: Vector2 = room_pixel_size(bank_def[3], bank_def[4])
			var bcenter: Vector2 = bpos + bsize * 0.5
			var bank = scenes["bank"].instantiate()
			containers["banks"].add_child(bank)
			bank.global_position = Vector2(bcenter.x, bpos.y + 200)

		# Fishing hut in home room
		var hut = scenes["hut"].instantiate()
		containers["huts"].add_child(hut)
		hut.global_position = Vector2(hpos.x + hsize.x - 200, hcenter.y)
