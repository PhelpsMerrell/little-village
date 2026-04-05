extends Node
## Processes color influence each physics frame.
## Range-based: influence within ~7.5× radius, stronger when closer.
## Level-aware: influencer level must be >= target level to affect them.
## Sets influence_attractor on targets so they drift toward influencers.

const SHIFT_MAX := 100.0
const BASE_SHIFT_SPEED := 18.0
const DECAY_MULTIPLIER := 1.3
const INFLUENCE_RANGE_MULT := 7.5
const MIN_PROXIMITY_FACTOR := 0.15

signal villager_shifted(villager: Node, old_color: String, new_color: String, spawn_count: int)


func process_influence(room_villagers: Dictionary, wall_data: Array, delta: float) -> void:
	var groups := _find_connected_groups(room_villagers.keys(), wall_data)
	for rid in room_villagers:
		for v in room_villagers[rid]:
			v.is_being_influenced = false
			v.influence_attractor = Vector2.ZERO
	for group in groups:
		var all_v: Array = []
		for room_id in group:
			all_v.append_array(room_villagers.get(room_id, []))
		_process_group(all_v, delta)


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


func _proximity_factor(src_pos: Vector2, tgt_pos: Vector2, src_radius: float) -> float:
	var dist: float = src_pos.distance_to(tgt_pos)
	var max_range: float = src_radius * INFLUENCE_RANGE_MULT
	if dist >= max_range:
		return 0.0
	return lerpf(1.0, MIN_PROXIMITY_FACTOR, dist / max_range)


## Level gate: influencer must be >= target level to affect them.
## Exception: yellow L3 is always influenceable.
func _level_multiplier(src_level: int, target: Node) -> float:
	var tgt_level: int = target.level
	# Yellow L3 exception: always influenceable
	if target.color_type == "yellow" and tgt_level == 3:
		return 1.0
	# L3 targets are immune to all influence
	if tgt_level == 3:
		return 0.0
	# Source must be at least target's level
	if src_level < tgt_level:
		return 0.0
	# L2 targets get reduced influence even from L2+ sources
	if tgt_level == 2:
		return 0.2
	return 1.0


func _process_group(villagers: Array, delta: float) -> void:
	var negations: Array[String] = []
	for v in villagers:
		var vdef: Dictionary = ColorRegistry.get_def(v.color_type)
		negations.append_array(vdef.get("negates_influences", []))

	var inf_rate: Dictionary = {}
	var attractor_sum: Dictionary = {}
	var attractor_weight: Dictionary = {}
	for v in villagers:
		inf_rate[v] = 0.0
		attractor_sum[v] = Vector2.ZERO
		attractor_weight[v] = 0.0

	var by_color: Dictionary = {}
	for v in villagers:
		if not by_color.has(v.color_type):
			by_color[v.color_type] = []
		by_color[v.color_type].append(v)

	for src_color in by_color:
		var src_def: Dictionary = ColorRegistry.get_def(src_color)
		var src_list: Array = by_color[src_color]
		var targets_colors: Array = src_def.get("influence_targets", [])
		var delivery: String = src_def.get("influence_delivery", "standard")
		var base_rate: float = src_def.get("influence_rate", 1.0)
		var stack_bonus: float = src_def.get("stacking_bonus", 0.1)
		var src_radius: float = float(src_def.get("radius", 22))

		# Pre-filter targets by color and negation (NOT by level — level is per-source)
		var color_valid_targets: Array = []
		for v in villagers:
			if v.color_type in targets_colors:
				var v_def: Dictionary = ColorRegistry.get_def(v.color_type)
				var shift_key: String = v.color_type + "->" + v_def.get("shifts_to", "")
				if shift_key not in negations:
					color_valid_targets.append(v)
		if color_valid_targets.is_empty():
			continue

		if delivery == "single_target":
			var claimed: Dictionary = {}
			for src in src_list:
				var src_lv: int = src.level
				for t in color_valid_targets:
					if claimed.has(t):
						continue
					var lv_mult: float = _level_multiplier(src_lv, t)
					if lv_mult <= 0.0:
						continue
					var prox: float = _proximity_factor(src.global_position, t.global_position, src_radius)
					if prox <= 0.0:
						continue
					inf_rate[t] += base_rate * prox * lv_mult
					attractor_sum[t] += src.global_position * prox
					attractor_weight[t] += prox
					claimed[t] = true
					break
		else:
			for t in color_valid_targets:
				var total_for_target: float = 0.0
				var in_range_count: int = 0
				for src in src_list:
					var lv_mult: float = _level_multiplier(src.level, t)
					if lv_mult <= 0.0:
						continue
					var prox: float = _proximity_factor(src.global_position, t.global_position, src_radius)
					if prox > 0.0:
						total_for_target += base_rate * prox * lv_mult
						in_range_count += 1
						attractor_sum[t] += src.global_position * prox
						attractor_weight[t] += prox
				if in_range_count > 1:
					total_for_target += stack_bonus * (in_range_count - 1)
				inf_rate[t] += total_for_target

	var shift_queue: Array = []
	for v in villagers:
		var rate: float = inf_rate.get(v, 0.0)
		var vdef: Dictionary = ColorRegistry.get_def(v.color_type)
		if vdef.get("shifts_to", "").is_empty():
			v.shift_meter = 0.0
			continue
		if rate > 0.0:
			v.shift_meter += rate * BASE_SHIFT_SPEED * delta
			var w: float = attractor_weight.get(v, 0.0)
			if w > 0.0:
				v.is_being_influenced = true
				v.influence_attractor = attractor_sum[v] / w
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
