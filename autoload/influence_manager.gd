extends Node
## Processes color influence each physics frame.
## Rooms connected by open walls share influence.

const SHIFT_MAX := 100.0
const BASE_SHIFT_SPEED := 10.0   # 100 / 10 seconds
const DECAY_MULTIPLIER := 1.3

signal villager_shifted(villager: Node, old_color: String, new_color: String, spawn_count: int)


## Main entry point — called by main.gd every frame.
func process_influence(room_villagers: Dictionary, wall_data: Array, delta: float) -> void:
	var groups := _find_connected_groups(room_villagers.keys(), wall_data)
	for group in groups:
		var all_v: Array = []
		for room_id in group:
			all_v.append_array(room_villagers.get(room_id, []))
		_process_group(all_v, delta)


# ── Connected-component search ──────────────────────────────────────────────

func _find_connected_groups(room_ids: Array, wall_data: Array) -> Array[Array]:
	var adj: Dictionary = {}
	for rid in room_ids:
		adj[rid] = []
	for w in wall_data:
		if w["is_open"]:
			adj[w["room_a"]].append(w["room_b"])
			adj[w["room_b"]].append(w["room_a"])

	var visited: Dictionary = {}
	var groups: Array[Array] = []
	for rid in room_ids:
		if visited.has(rid):
			continue
		var component: Array = []
		var stack: Array = [rid]
		while stack.size() > 0:
			var cur = stack.pop_back()
			if visited.has(cur):
				continue
			visited[cur] = true
			component.append(cur)
			for nb in adj.get(cur, []):
				if not visited.has(nb):
					stack.append(nb)
		groups.append(component)
	return groups


# ── Per-group influence logic ────────────────────────────────────────────────

func _process_group(villagers: Array, delta: float) -> void:
	# Collect active negations across the whole group
	var negations: Array[String] = []
	for v in villagers:
		var vdef: Dictionary = ColorRegistry.get_def(v.color_type)
		negations.append_array(vdef.get("negates_influences", []))

	# Map: villager → accumulated influence rate
	var inf_rate: Dictionary = {}
	for v in villagers:
		inf_rate[v] = 0.0

	# Group influencers by color
	var by_color: Dictionary = {}
	for v in villagers:
		if not by_color.has(v.color_type):
			by_color[v.color_type] = []
		by_color[v.color_type].append(v)

	# Calculate influence from each color type
	for src_color in by_color:
		var src_def: Dictionary = ColorRegistry.get_def(src_color)
		var src_list: Array = by_color[src_color]
		var targets_colors: Array = src_def.get("influence_targets", [])
		var delivery: String = src_def.get("influence_delivery", "standard")
		var base_rate: float = src_def.get("influence_rate", 1.0)
		var stack_bonus: float = src_def.get("stacking_bonus", 0.1)

		# Gather valid targets (villagers whose color is in targets_colors)
		var valid_targets: Array = []
		for v in villagers:
			if v.color_type in targets_colors:
				var v_def: Dictionary = ColorRegistry.get_def(v.color_type)
				var shift_key: String = v.color_type + "->" + v_def.get("shifts_to", "")
				if shift_key not in negations:
					valid_targets.append(v)
		if valid_targets.is_empty():
			continue

		if delivery == "single_target":
			# Each influencer picks exactly one unique target
			var claimed: Dictionary = {}
			for _inf in src_list:
				for t in valid_targets:
					if not claimed.has(t):
						inf_rate[t] += base_rate
						claimed[t] = true
						break
		else:
			# Standard: all stack, all targets receive
			var count: int = src_list.size()
			var total: float = base_rate + stack_bonus * (count - 1)
			for t in valid_targets:
				inf_rate[t] += total

	# Apply influence or decay
	# Collect shift events to fire AFTER iteration (avoids mutation during loop)
	var shift_queue: Array = []
	for v in villagers:
		var rate: float = inf_rate.get(v, 0.0)
		var vdef: Dictionary = ColorRegistry.get_def(v.color_type)
		if vdef.get("shifts_to", "").is_empty():
			v.shift_meter = 0.0
			continue
		if rate > 0.0:
			v.shift_meter += rate * BASE_SHIFT_SPEED * delta
			if v.shift_meter >= SHIFT_MAX:
				shift_queue.append(v)
		else:
			_apply_decay(v, delta)

	for v in shift_queue:
		_trigger_shift(v)


func _apply_decay(v: Node, delta: float) -> void:
	if v.shift_meter > 0.0:
		v.shift_meter -= DECAY_MULTIPLIER * BASE_SHIFT_SPEED * delta
		v.shift_meter = maxf(v.shift_meter, 0.0)


func _trigger_shift(v: Node) -> void:
	var old_color: String = str(v.color_type)
	var def: Dictionary = ColorRegistry.get_def(old_color)
	var new_color: String = def.get("shifts_to", "")
	var spawn_count: int = def.get("on_shift_spawn_count", 1)
	if new_color.is_empty():
		v.shift_meter = 0.0
		return
	v.shift_meter = 0.0
	villager_shifted.emit(v, old_color, new_color, spawn_count)
