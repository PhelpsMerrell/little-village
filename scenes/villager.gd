extends Node2D
## Villager with AI brain, levels, ranged combat (red), carrying, hunger.
##
## Brain priority order (first match wins):
##   1. DANGER — enemy nearby → color-specific reaction
##   2. JOB — collecting/depositing resources → blocks influence movement
##   3. INFLUENCE — being shifted → orbit attractor
##   4. IDLE — wander randomly
##
## Influence shift meter fills passively regardless of brain state.
## Only MOVEMENT toward the influencer is gated by priority.

const SPEED_SCALE := 8.0
const BAR_H := 5.0
const YELLOW_LEVEL_TIME := 8.0

const AWARENESS_RANGE := 300.0
const SHOOT_RANGE := 200.0
const SHOOT_COOLDOWN := 1.0
const FLEE_DIST := 250.0
const FRONTLINE_DIST := 80.0
const RED_BEHIND_BLUE_DIST := 60.0
const WANDER_PAUSE_MIN := 0.8
const WANDER_PAUSE_MAX := 2.5
const SEPARATION_DIST := 8.0
const SEPARATION_FORCE := 0.4

@export var color_type: String = "red"

var faction_id: int = 0  ## Which faction owns this villager (0 = local player in solo)
var net_id: int = -1  ## Unique ID for network command targeting
var villager_name: String = ""  ## Display name
var is_puppet: bool = false  ## Client-side puppet: interpolates, no brain
var interp_target: Vector2 = Vector2.ZERO  ## Target position for puppet interpolation

var level: int = 1
var shift_meter: float = 0.0
var _decay_grace_timer: float = 0.0  # 3s grace before shift decay starts
var health: float = 0.0
var max_health: float = 0.0
var current_room_id: int = -1
var radius: float = 22.0

var is_being_influenced: bool = false
var influence_attractor: Vector2 = Vector2.ZERO

## Player commands — override AI brain when active
var command_mode: String = "none"  # none, move_to, hold
var command_target: Vector2 = Vector2.ZERO
var is_selected: bool = false

## Dynamic shift target for colorless villagers (set by influence_manager)
var pending_shift_color: String = ""

var kill_count: int = 0
var is_fed: bool = true
var _satiation_timer: float = 0.0  # seconds remaining before next fish needed

const SATIATION_PER_LEVEL := [0.0, 1200.0, 2400.0, 3600.0]  # L1=1day, L2=2days, L3=3days
const L2_SPEED_MULT := 1.4  # L2 villagers move 40% faster

var leveling_partner: Node2D = null
var leveling_meter: float = 0.0

var carrying_resource: String = ""
var carrying_stone: bool:
	get: return carrying_resource == "stone"
	set(v): carrying_resource = "stone" if v else ""

var deposit_position: Vector2 = Vector2.ZERO
var has_deposit_in_room: bool = false
var bank_position: Vector2:
	get: return deposit_position
	set(v): deposit_position = v
var has_bank_in_room: bool:
	get: return has_deposit_in_room
	set(v): has_deposit_in_room = v

var brain_enemies: Array = []
var brain_room_villagers: Array = []
var brain_nearest_resource_pos: Vector2 = Vector2.ZERO
var brain_has_resource: bool = false

## Waypoint: player-assigned resource target (cross-room)
var waypoint_target_pos: Vector2 = Vector2.ZERO
var has_waypoint: bool = false

## Church healing: main.gd sets these for damaged blues
var brain_church_pos: Vector2 = Vector2.ZERO
var brain_has_church: bool = false

## Colorless attraction: main.gd sets when a controlled villager is nearby
var colorless_attract_pos: Vector2 = Vector2.ZERO
var has_attract_target: bool = false

## Wall segments for collision (set by main.gd)
var brain_walls: Array = []  # [{start: Vector2, end: Vector2, is_open: bool}]
var brain_doorways: Array = []  # [{mid: Vector2, room_a: int, room_b: int}]
var _doorway_waypoint: Vector2 = Vector2.ZERO  # intermediate target to navigate through a door
var _has_doorway_waypoint: bool = false
var break_door_target: Vector2 = Vector2.ZERO  ## Set by break-door command; cleared after breaking

var shoot_target_pos: Vector2 = Vector2.ZERO
var shoot_target_enemy: Node = null
var _shoot_cooldown: float = 0.0
var _shot_flash_timer: float = 0.0

var room_bounds: Rect2 = Rect2()
var blocked_rects: Array = []
var _move_target: Vector2 = Vector2.ZERO
var _move_speed: float = 0.0
var _arrived: bool = true
var _idle_timer: float = 0.0
var _brain_state: String = "idle"

var _dragging := false
var _drag_offset := Vector2.ZERO
var _client_dragging := false  ## Client puppet is being dragged locally
var _drag_send_timer := 0.0  ## Throttle drag position RPCs
const DRAG_SEND_INTERVAL := 0.066  ## ~15 updates/sec
var _dying := false
var _death_timer := 0.0
const DEATH_TWITCH_DURATION := 1.2

@onready var _area: Area2D = $InputArea
@onready var _col_shape: CollisionShape2D = $InputArea/CollisionShape2D
@onready var _label: Label = $ShiftLabel

signal resource_dropped(villager: Node2D, resource_type: String)


func _ready() -> void:
	_area.input_event.connect(_on_area_input); _sync_definition()

func setup(p_color: String, pos: Vector2, p_level: int = 1) -> void:
	color_type = p_color; position = pos; level = p_level
	shift_meter = 0.0; _decay_grace_timer = 0.0; kill_count = 0; is_fed = true
	leveling_meter = 0.0; leveling_partner = null; carrying_resource = ""
	_sync_definition(); _idle_timer = GameRNG.randf_range(0.3, 1.0)

func set_color_type(new_type: String) -> void:
	var hp_ratio: float = health / max_health if max_health > 0.0 else 1.0
	color_type = new_type; level = 1
	shift_meter = 0.0; _decay_grace_timer = 0.0; kill_count = 0; is_fed = true
	leveling_meter = 0.0; leveling_partner = null; carrying_resource = ""
	_sync_definition()
	health = max_health * hp_ratio

func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, 3); _sync_definition()

func record_kill() -> void: kill_count += 1
func is_carrying() -> bool: return carrying_resource != ""

func get_influence_multiplier() -> float:
	match level:
		2: return 0.2
		3: return 1.0 if color_type == "yellow" else 0.0
		_: return 1.0

func _sync_definition() -> void:
	var def: Dictionary = ColorRegistry.get_def(color_type)
	max_health = float(def.get("health", 100)) * (2.0 if level == 3 else 1.0)
	health = max_health
	radius = float(def.get("radius", 22))
	var base_speed: float = float(def.get("movement_speed", 0)) * SPEED_SCALE
	# L2 speed boost
	if level == 2:
		_move_speed = base_speed * L2_SPEED_MULT
	else:
		_move_speed = base_speed
	if _col_shape:
		var shape := CircleShape2D.new(); shape.radius = radius; _col_shape.shape = shape
	if _label:
		_label.position = Vector2(-radius, -radius * 0.35)
		_label.size = Vector2(radius * 2.0, radius * 0.7)

func _process(delta: float) -> void:
	if _dying:
		_death_timer -= delta
		if _death_timer <= 0.0:
			queue_free()
			return
		queue_redraw()
		return
	if is_puppet:
		# Client mode: smooth interpolation, no simulation
		if _client_dragging:
			# Client is dragging this puppet — use local mouse, skip interp
			_drag_send_timer += delta
		else:
			if interp_target != Vector2.ZERO:
				global_position = global_position.lerp(interp_target, clampf(delta * 14.0, 0.0, 1.0))
		_update_label()
		_shot_flash_timer = maxf(0.0, _shot_flash_timer - delta)
		queue_redraw()
		return
	_update_label()
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_shot_flash_timer = maxf(0.0, _shot_flash_timer - delta)
	if not _dragging and _move_speed > 0.0:
		_evaluate_brain(delta); _do_movement(delta); _apply_separation()
	queue_redraw()

func _update_label() -> void:
	if not _label: return
	var txt := ""
	if is_carrying(): txt = carrying_resource
	elif shift_meter > 0.01: txt = str(int(shift_meter))
	if level > 1: txt = "L%d" % level if txt.is_empty() else "L%d %s" % [level, txt]
	_label.text = txt


# ══════════════════════════════════════════════════════════════════════════════
# AI BRAIN
# ══════════════════════════════════════════════════════════════════════════════

func _evaluate_brain(_delta: float) -> void:
	shoot_target_enemy = null
	if _check_command(): return
	if _check_danger(): return
	if _check_job(): return
	if _check_influence(): return
	_do_idle_brain()

func _check_command() -> bool:
	match command_mode:
		"move_to":
			_brain_state = "command_move"
			_set_target(command_target)
			if global_position.distance_to(command_target) < radius + 8.0:
				command_mode = "none"
				_arrived = true
			return true
		"hold":
			_brain_state = "command_hold"
			_arrived = true
			return true
	return false

func clear_command() -> void:
	command_mode = "none"
	command_target = Vector2.ZERO

func command_move_to(pos: Vector2) -> void:
	command_mode = "move_to"
	command_target = pos

func command_hold() -> void:
	command_mode = "hold"

func command_release() -> void:
	clear_command()

func _check_danger() -> bool:
	var nearest_enemy: Node = _find_nearest_enemy()
	if nearest_enemy == null: return false
	var enemy_dist: float = global_position.distance_to(nearest_enemy.global_position)
	if enemy_dist > AWARENESS_RANGE: return false
	_brain_state = "danger"
	match color_type:
		"yellow", "colorless":
			var blue: Node = _find_nearest_color("blue")
			if blue: _set_target(blue.global_position)
			else: _set_target(global_position + (global_position - nearest_enemy.global_position).normalized() * FLEE_DIST)
		"blue":
			var dir: Vector2 = (nearest_enemy.global_position - global_position).normalized()
			var gap: float = enemy_dist - FRONTLINE_DIST
			if gap > 10.0: _set_target(global_position + dir * minf(gap, _move_speed * 0.5))
			else: _arrived = true
		"red":
			var blue: Node = _find_nearest_color("blue")
			if blue:
				var away: Vector2 = (blue.global_position - nearest_enemy.global_position).normalized()
				_set_target(blue.global_position + away * RED_BEHIND_BLUE_DIST)
			if enemy_dist <= SHOOT_RANGE and _shoot_cooldown <= 0.0:
				shoot_target_enemy = nearest_enemy
				shoot_target_pos = nearest_enemy.global_position
				_shoot_cooldown = SHOOT_COOLDOWN; _shot_flash_timer = 0.15
		_: return false
	return true

func _check_job() -> bool:
	match color_type:
		"yellow":
			if is_carrying():
				if has_deposit_in_room:
					_brain_state = "deposit"; _set_target(deposit_position); return true
				elif deposit_position != Vector2.ZERO:
					# Cross-room: walk toward bank
					_brain_state = "deposit_cross"; _set_target(deposit_position); return true
				else:
					_brain_state = "carry_wander"; return false
			elif has_waypoint: _brain_state = "waypoint"; _set_target(waypoint_target_pos); return true
			elif brain_has_resource: _brain_state = "collect"; _set_target(brain_nearest_resource_pos); return true
		"blue":
			if not is_carrying() and brain_has_church and health < max_health:
				_brain_state = "seek_church"; _set_target(brain_church_pos); return true
			if is_carrying():
				if has_deposit_in_room:
					_brain_state = "deposit"; _set_target(deposit_position); return true
				elif deposit_position != Vector2.ZERO:
					_brain_state = "deposit_cross"; _set_target(deposit_position); return true
				else:
					_brain_state = "carry_wander"; return false
			elif has_waypoint: _brain_state = "waypoint"; _set_target(waypoint_target_pos); return true
			elif brain_has_resource: _brain_state = "collect"; _set_target(brain_nearest_resource_pos); return true
		"red": pass
		"colorless":
			if has_attract_target:
				_brain_state = "attract"
				_set_target(colorless_attract_pos)
				return true
	return false

func _check_influence() -> bool:
	if not is_being_influenced: return false
	_brain_state = "influence"
	var inf_range: float = radius * 15.0  # match INFLUENCE_RANGE_MULT
	var angle: float = GameRNG.randf() * TAU
	var dist: float = GameRNG.randf_range(inf_range * 0.4, inf_range * 0.8)
	_set_target_clamped(influence_attractor + Vector2(cos(angle), sin(angle)) * dist)
	return true

func _do_idle_brain() -> void:
	_brain_state = "idle"
	if _arrived:
		_idle_timer -= get_process_delta_time()
		if _idle_timer <= 0.0:
			_idle_timer = GameRNG.randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX); _pick_random_target()


# ══════════════════════════════════════════════════════════════════════════════
# MOVEMENT + SEPARATION
# ══════════════════════════════════════════════════════════════════════════════

func _set_target(pos: Vector2) -> void: _move_target = pos; _arrived = false

func _set_target_clamped(pos: Vector2) -> void:
	if room_bounds.has_area():
		var m := radius + 6.0
		pos.x = clampf(pos.x, room_bounds.position.x + m, room_bounds.end.x - m)
		pos.y = clampf(pos.y, room_bounds.position.y + m, room_bounds.end.y - m)
	_set_target(pos)

func _do_movement(delta: float) -> void:
	if _arrived: return
	
	# If we have a doorway waypoint, navigate to it first
	var effective_target: Vector2 = _move_target
	if _has_doorway_waypoint:
		effective_target = _doorway_waypoint
		if global_position.distance_to(_doorway_waypoint) < radius + 12.0:
			_has_doorway_waypoint = false  # reached doorway, continue to real target
			return
	
	var to_target := effective_target - global_position
	var dist := to_target.length(); var step := _move_speed * delta
	if dist <= step or dist < 5.0:
		if _wall_blocks(global_position, effective_target):
			if _try_find_doorway_redirect(effective_target):
				return
			_arrived = true
			return
		global_position = effective_target
		if _has_doorway_waypoint:
			_has_doorway_waypoint = false
			return  # keep going to real target
		_arrived = true
		_idle_timer = GameRNG.randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
	else:
		var new_pos: Vector2 = global_position + to_target.normalized() * step
		var cross_room: bool = _brain_state in ["waypoint", "seek_church", "carry_wander", "deposit_cross", "attract", "command_move"]
		if cross_room:
			if _wall_blocks(global_position, new_pos):
				if _try_find_doorway_redirect(_move_target):
					return
				_arrived = true
				return
		else:
			if room_bounds.has_area():
				var m := radius + 4.0
				new_pos.x = clampf(new_pos.x, room_bounds.position.x + m, room_bounds.end.x - m)
				new_pos.y = clampf(new_pos.y, room_bounds.position.y + m, room_bounds.end.y - m)
		global_position = new_pos


func _try_find_doorway_redirect(target: Vector2) -> bool:
	## Find the nearest doorway that would help us reach target. Returns true if found.
	var best_door: Vector2 = Vector2.ZERO
	var best_score: float = INF
	for door in brain_doorways:
		var dmid: Vector2 = door["mid"]
		# Only consider doors we can reach without wall collision
		if _wall_blocks(global_position, dmid):
			continue
		# Score: distance to door + distance from door to target
		var score: float = global_position.distance_to(dmid) + dmid.distance_to(target)
		if score < best_score:
			best_score = score
			best_door = dmid
	if best_score < INF:
		_doorway_waypoint = best_door
		_has_doorway_waypoint = true
		return true
	return false


func _wall_blocks(from: Vector2, to: Vector2) -> bool:
	## Returns true if moving from → to crosses any closed wall segment.
	for w in brain_walls:
		if w["is_open"]:
			continue
		if _segments_intersect(from, to, w["start"], w["end"]):
			return true
	return false


static func _segments_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	## Line segment intersection test.
	var d1: Vector2 = a2 - a1
	var d2: Vector2 = b2 - b1
	var cross: float = d1.x * d2.y - d1.y * d2.x
	if absf(cross) < 0.001:
		return false  # parallel
	var diff: Vector2 = b1 - a1
	var t: float = (diff.x * d2.y - diff.y * d2.x) / cross
	var u: float = (diff.x * d1.y - diff.y * d1.x) / cross
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0

func _apply_separation() -> void:
	for other in brain_room_villagers:
		if other == self or not is_instance_valid(other): continue
		var sep: Vector2 = global_position - other.global_position
		var dist: float = sep.length()
		var min_dist: float = radius + float(other.radius) + SEPARATION_DIST
		if dist < min_dist and dist > 0.1:
			global_position += sep.normalized() * (min_dist - dist) * SEPARATION_FORCE

func _pick_random_target() -> bool:
	var m := radius + 6.0
	var inner := Rect2(room_bounds.position + Vector2(m, m), room_bounds.size - Vector2(m * 2.0, m * 2.0))
	if not inner.has_area(): return false
	for _attempt in 10:
		var t := Vector2(GameRNG.randf_range(inner.position.x, inner.end.x), GameRNG.randf_range(inner.position.y, inner.end.y))
		if _is_reachable(t): _set_target(t); return true
	return false

func _is_reachable(target: Vector2) -> bool:
	for rect in blocked_rects:
		if rect.has_point(target): return false
	return true

func _find_nearest_enemy() -> Node:
	var best: Node = null; var best_d: float = INF
	for e in brain_enemies:
		if not is_instance_valid(e) or e.is_dead: continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d: best_d = d; best = e
	return best

func _find_nearest_color(target_color: String) -> Node:
	var best: Node = null; var best_d: float = INF
	for v in brain_room_villagers:
		if not is_instance_valid(v) or v == self: continue
		if str(v.color_type) == target_color:
			var d: float = global_position.distance_to(v.global_position)
			if d < best_d: best_d = d; best = v
	return best


# ══════════════════════════════════════════════════════════════════════════════
# INPUT
# ══════════════════════════════════════════════════════════════════════════════

func _on_area_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if _dying: return
	if not FactionManager.is_local_faction(faction_id): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_puppet:
			# Client: start local drag + notify host
			_client_dragging = true
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			_drag_send_timer = 0.0
			z_index = 10
			NetworkManager.send_command({
				"type": "drag_start",
				"net_id": net_id,
			})
			return
		_dragging = true; _drag_offset = global_position - get_global_mouse_position(); z_index = 10
		_drop_carried_resource()

func _input(event: InputEvent) -> void:
	if not _dragging: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var final_pos := global_position
		_dragging = false; z_index = 0; _arrived = true; _idle_timer = randf_range(0.5, 1.5)
		if _client_dragging:
			_client_dragging = false
			NetworkManager.send_command({
				"type": "drag_end",
				"net_id": net_id,
				"px": final_pos.x,
				"py": final_pos.y,
			})
	elif event is InputEventMouseMotion:
		if carrying_resource != "" and not is_puppet:
			_drop_carried_resource()
		global_position = get_global_mouse_position() + _drag_offset
		if _client_dragging and _drag_send_timer >= DRAG_SEND_INTERVAL:
			_drag_send_timer = 0.0
			NetworkManager.send_command({
				"type": "drag_move",
				"net_id": net_id,
				"px": global_position.x,
				"py": global_position.y,
			})


# ══════════════════════════════════════════════════════════════════════════════
# DRAWING
# ══════════════════════════════════════════════════════════════════════════════

func _draw() -> void:
	if _dying:
		_draw_death_twitch()
		return
	var def: Dictionary = ColorRegistry.get_def(color_type)
	var base_color: Color = def.get("display_color", Color.WHITE)
	var next_id: String = def.get("shifts_to", "")
	var bar_w := radius * 2.0
	var draw_color := base_color
	if not next_id.is_empty() and shift_meter > 0.0:
		draw_color = base_color.lerp(ColorRegistry.get_def(next_id).get("display_color", Color.WHITE), shift_meter / 100.0)
	if color_type == "red" and not is_fed:
		draw_color = draw_color.darkened(0.3 * (0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.2))
	match level:
		1: _draw_circle_body(draw_color)
		2: _draw_square_body(draw_color)
		3: _draw_triangle_body(draw_color)
	if _shot_flash_timer > 0.0:
		var a: float = _shot_flash_timer / 0.15; var lt: Vector2 = shoot_target_pos - global_position
		draw_line(Vector2.ZERO, lt, Color(1.0, 0.3, 0.2, a), 2.0)
		draw_circle(lt, 4.0, Color(1.0, 0.5, 0.2, a))
	if carrying_resource == "stone": draw_circle(Vector2(0, -radius - 6), 7.0, Color(0.5, 0.52, 0.48))
	elif carrying_resource == "fish": draw_circle(Vector2(0, -radius - 6), 7.0, Color(0.3, 0.55, 0.75))
	# Selection ring
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, pulse), 2.5, true)
	# Command indicator
	if command_mode == "hold":
		draw_string(ThemeDB.fallback_font, Vector2(-radius * 0.6, -radius - 28.0), "HOLD", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1.0, 0.8, 0.2, 0.8))
	elif command_mode == "move_to":
		var cmd_dir: Vector2 = (command_target - global_position).normalized()
		draw_line(cmd_dir * (radius + 4.0), cmd_dir * (radius + 16.0), Color(0.2, 1.0, 0.4, 0.6), 2.0)
	if is_being_influenced and shift_meter > 1.0 and _brain_state == "influence":
		var dir: Vector2 = (influence_attractor - global_position).normalized()
		draw_line(dir * (radius + 4.0), dir * (radius + 14.0), Color(1, 1, 1, 0.35), 2.0)
	if color_type == "red" and not is_fed:
		draw_string(ThemeDB.fallback_font, Vector2(-radius * 0.6, -radius - 18.0), "HUNGRY", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.9, 0.3, 0.2, 0.8))
	var shift_y := -radius - 12.0
	if is_carrying(): shift_y -= 14.0
	if color_type == "red" and not is_fed: shift_y -= 10.0
	_draw_bar(-radius, shift_y, bar_w, shift_meter / 100.0, _get_shift_fill_color(next_id), Color(0.25, 0.25, 0.25, 0.5))
	var hp_y := radius + 5.0
	var hp_ratio := health / max_health if max_health > 0.0 else 1.0
	_draw_bar(-radius, hp_y, bar_w, hp_ratio, Color(0.3, 0.8, 0.35) if hp_ratio > 0.5 else Color(0.85, 0.25, 0.2), Color(0.25, 0.25, 0.25, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(radius + 4.0, hp_y + BAR_H), str(int(health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6, 0.8))
	if color_type == "red" and kill_count > 0:
		draw_string(ThemeDB.fallback_font, Vector2(-radius, radius + 18.0), "K:%d" % kill_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.4, 0.3, 0.7))
	if color_type == "yellow" and leveling_meter > 0.01:
		_draw_bar(-radius, radius + 18.0, bar_w, leveling_meter / YELLOW_LEVEL_TIME, Color(0.94, 0.84, 0.12), Color(0.25, 0.2, 0.05, 0.5))

func _get_faction_border_color() -> Color:
	if faction_id >= 0:
		return FactionManager.get_faction_color(faction_id)
	return Color(0.12, 0.12, 0.12)

func _draw_faction_symbol() -> void:
	if faction_id < 0 or color_type == "magic_orb":
		return
	var sym: String = FactionManager.get_faction_symbol(faction_id)
	var fc: Color = FactionManager.get_faction_color(faction_id)
	fc.a = 0.9
	draw_string(ThemeDB.fallback_font, Vector2(-radius * 0.5, radius * 0.35), sym,
		HORIZONTAL_ALIGNMENT_CENTER, int(radius), 20, fc)

func _draw_circle_body(col: Color) -> void:
	draw_circle(Vector2.ZERO, radius, col)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, _get_faction_border_color(), 2.5, true)
	_draw_faction_symbol()
func _draw_square_body(col: Color) -> void:
	var r := radius * 0.85
	draw_rect(Rect2(-r, -r, r * 2, r * 2), col)
	draw_rect(Rect2(-r, -r, r * 2, r * 2), _get_faction_border_color(), false, 2.5)
	_draw_faction_symbol()
func _draw_triangle_body(col: Color) -> void:
	var r := radius; var pts := PackedVector2Array([Vector2(0, -r), Vector2(r * 0.866, r * 0.5), Vector2(-r * 0.866, r * 0.5)])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), _get_faction_border_color(), 2.5)
	_draw_faction_symbol()
func _draw_bar(x: float, y: float, w: float, ratio: float, fill: Color, track: Color) -> void:
	draw_rect(Rect2(x, y, w, BAR_H), track)
	if ratio > 0.001: draw_rect(Rect2(x, y, w * clampf(ratio, 0.0, 1.0), BAR_H), fill)
	draw_rect(Rect2(x, y, w, BAR_H), Color(0.12, 0.12, 0.12, 0.6), false, 1.0)
func _get_shift_fill_color(next_id: String) -> Color:
	if next_id.is_empty(): return Color(0.5, 0.5, 0.5, 0.3)
	return ColorRegistry.get_def(next_id).get("display_color", Color.WHITE)


func _drop_carried_resource() -> void:
	if carrying_resource == "":
		return
	# Signal main.gd to respawn the resource at our feet
	var dropped_type: String = carrying_resource
	carrying_resource = ""
	# Emit signal so main.gd can spawn a new collectable/fish at this position
	resource_dropped.emit(self, dropped_type)


func _draw_death_twitch() -> void:
	var def: Dictionary = ColorRegistry.get_def(color_type)
	var base_color: Color = def.get("display_color", Color.WHITE)
	var progress := 1.0 - (_death_timer / DEATH_TWITCH_DURATION)
	var fade := 1.0 - progress
	# Rapid position jitter
	var twitch := Vector2(
		randf_range(-4.0, 4.0) * fade,
		randf_range(-4.0, 4.0) * fade
	)
	var col := base_color
	col.a = fade
	# Shrink slightly as death progresses
	var r := radius * lerpf(1.0, 0.4, progress)
	match level:
		1: draw_circle(twitch, r, col)
		2:
			var s := r * 0.85
			draw_rect(Rect2(twitch.x - s, twitch.y - s, s * 2, s * 2), col)
		3:
			var pts := PackedVector2Array([
				twitch + Vector2(0, -r),
				twitch + Vector2(r * 0.866, r * 0.5),
				twitch + Vector2(-r * 0.866, r * 0.5)])
			draw_colored_polygon(pts, col)
	# X eyes
	var eye_size := 3.0 * fade
	var eye_col := Color(0.1, 0.1, 0.1, fade)
	draw_line(twitch + Vector2(-5, -3), twitch + Vector2(-5 + eye_size, -3 + eye_size), eye_col, 2.0)
	draw_line(twitch + Vector2(-5 + eye_size, -3), twitch + Vector2(-5, -3 + eye_size), eye_col, 2.0)
	draw_line(twitch + Vector2(3, -3), twitch + Vector2(3 + eye_size, -3 + eye_size), eye_col, 2.0)
	draw_line(twitch + Vector2(3 + eye_size, -3), twitch + Vector2(3, -3 + eye_size), eye_col, 2.0)


func start_death_animation() -> void:
	## Begin twitch death — villager is removed from game logic but stays visible briefly.
	_dying = true
	_death_timer = DEATH_TWITCH_DURATION
	_dragging = false
	z_index = 0
	# Drop anything carried
	if carrying_resource != "":
		var dropped_type: String = carrying_resource
		carrying_resource = ""
		resource_dropped.emit(self, dropped_type)
