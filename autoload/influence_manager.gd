extends Node
## Processes color influence each physics frame.
## Range-based: influence within ~15× radius, stronger when closer.
## Level-aware: influencer level must be >= target level.
## 3-second grace period before shift meter starts decaying.

const SHIFT_MAX := 100.0
const BASE_SHIFT_SPEED := 18.0
const DECAY_MULTIPLIER := 1.3
const INFLUENCE_RANGE_MULT := 15.0   # Red=420px, Yellow=330px, Blue=540px
const MIN_PROXIMITY_FACTOR := 0.15
const DECAY_GRACE_PERIOD := 3.0      # seconds before decay starts

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
		if visited.has(rid): continue
		var component: Array = []
		var stack: Array = [rid]
		while stack.size() > 0:
			var cur = stack.pop_back()
			if visited.has(cur): continue
			visited[cur] = true
			component.append(cur)
			for nb in adj.get(cur, []):
				if not visited.has(nb): stack.append(nb)
		groups.append(component)
	return groups


func _proximity_factor(src_pos: Vector2, tgt_pos: Vector2, src_radius: float) -> float:
	var dist: float = src_pos.distance_to(tgt_pos)
	var max_range: float = src_radius * INFLUENCE_RANGE_MULT
	if dist >= max_range: return 0.0
	return lerpf(1.0, MIN_PROXIMITY_FACTOR, dist / max_range)


func _level_multiplier(src_level: int, target: Node) -> float:
	var tgt_level: int = target.level
	if target.color_type == "yellow" and tgt_level == 3: return 1.0
	if tgt_level == 3: return 0.0
	if src_level < tgt_level: return 0.0
	if tgt_level == 2: return 0.2
	return 1.0


func _process_group(villagers: Array, delta: float) -> void:
	var negations: Array[String] = []
	for v in villagers:
		var vdef: Dictionary = ColorRegistry.get_def(v.color_type)
		negations.append_array(vdef.get("negates_influences", []))

	var inf_rate: Dictionary = {}
	var attractor_sum: Dictionary = {}
	var attractor_weight: Dictionary = {}
	var dominant_color: Dictionary = {}  # villager -> strongest influencer color
	var dominant_strength: Dictionary = {}  # villager -> strength of dominant
	for v in villagers:
		inf_rate[v] = 0.0
		attractor_sum[v] = Vector2.ZERO
		attractor_weight[v] = 0.0
		dominant_color[v] = ""
		dominant_strength[v] = 0.0

	var by_color: Dictionary = {}
	for v in villagers:
		if not by_color.has(v.color_type): by_color[v.color_type] = []
		by_color[v.color_type].append(v)

	for src_color in by_color:
		var src_def: Dictionary = ColorRegistry.get_def(src_color)
		var src_list: Array = by_color[src_color]
		var targets_colors: Array = src_def.get("influence_targets", [])
		var delivery: String = src_def.get("influence_delivery", "standard")
		var base_rate: float = src_def.get("influence_rate", 1.0)
		var stack_bonus: float = src_def.get("stacking_bonus", 0.1)
		var src_radius: float = float(src_def.get("radius", 22))

		var color_valid_targets: Array = []
		for v in villagers:
			if v.color_type in targets_colors:
				var v_def: Dictionary = ColorRegistry.get_def(v.color_type)
				var shift_key: String = v.color_type + "->" + v_def.get("shifts_to", "")
				if shift_key not in negations:
					color_valid_targets.append(v)
		if color_valid_targets.is_empty(): continue

		if delivery == "single_target":
			var claimed: Dictionary = {}
			for src in src_list:
				for t in color_valid_targets:
					if claimed.has(t): continue
					var lv_mult: float = _level_multiplier(src.level, t)
					if lv_mult <= 0.0: continue
					var prox: float = _proximity_factor(src.global_position, t.global_position, src_radius)
					if prox <= 0.0: continue
					var contrib: float = base_rate * prox * lv_mult
					inf_rate[t] += contrib
					attractor_sum[t] += src.global_position * prox
					attractor_weight[t] += prox
					if contrib > dominant_strength.get(t, 0.0):
						dominant_strength[t] = contrib
						dominant_color[t] = src_color
					claimed[t] = true; break
		else:
			for t in color_valid_targets:
				var total: float = 0.0
				var count: int = 0
				for src in src_list:
					var lv_mult: float = _level_multiplier(src.level, t)
					if lv_mult <= 0.0: continue
					var prox: float = _proximity_factor(src.global_position, t.global_position, src_radius)
					if prox > 0.0:
						total += base_rate * prox * lv_mult
						count += 1
						attractor_sum[t] += src.global_position * prox
						attractor_weight[t] += prox
				if count > 1: total += stack_bonus * (count - 1)
				inf_rate[t] += total
				if total > dominant_strength.get(t, 0.0):
					dominant_strength[t] = total
					dominant_color[t] = src_color

	var shift_queue: Array = []
	for v in villagers:
		var rate: float = inf_rate.get(v, 0.0)
		var vdef: Dictionary = ColorRegistry.get_def(v.color_type)
		if vdef.get("shifts_to", "").is_empty():
			v.shift_meter = 0.0; continue
		if rate > 0.0:
			var shift_mult: float = 3.0 if vdef.get("fast_shifter", false) else 1.0
			v.shift_meter += rate * BASE_SHIFT_SPEED * shift_mult * delta
			v._decay_grace_timer = DECAY_GRACE_PERIOD
			# Track dominant influencer color for colorless dynamic shifting
			var dom: String = dominant_color.get(v, "")
			if dom != "" and v.color_type == "colorless":
				v.pending_shift_color = dom
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
		# Grace period: wait before decaying
		if v._decay_grace_timer > 0.0:
			v._decay_grace_timer -= delta
			return
		v.shift_meter -= DECAY_MULTIPLIER * BASE_SHIFT_SPEED * delta
		v.shift_meter = maxf(v.shift_meter, 0.0)


func _trigger_shift(v: Node) -> void:
	var old_color: String = str(v.color_type)
	var def: Dictionary = ColorRegistry.get_def(old_color)
	var new_color: String
	# Colorless: shift to whatever color was influencing them
	if old_color == "colorless" and v.pending_shift_color != "":
		new_color = v.pending_shift_color
		v.pending_shift_color = ""
	else:
		new_color = def.get("shifts_to", "")
	var spawn_count: int = def.get("on_shift_spawn_count", 1)
	if new_color.is_empty():
		v.shift_meter = 0.0; return
	v.shift_meter = 0.0
	villager_shifted.emit(v, old_color, new_color, spawn_count)


func process_building_group(villagers: Array, delta: float) -> void:
	## Influence for villagers sheltered together inside a building.
	## They're all co-located so proximity factor = 1.0 (touching).
	_process_group(villagers, delta)
