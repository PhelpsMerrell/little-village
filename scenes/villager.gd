extends Node2D
## Villager with AI brain, levels, ranged combat (red), carrying, hunger.
## Brain priorities: DANGER > JOB > INFLUENCE > IDLE

const SPEED_SCALE := 8.0
const BAR_H := 5.0
const YELLOW_LEVEL_TIME := 8.0

# Brain tuning
const AWARENESS_RANGE := 300.0    # distance to detect enemies
const SHOOT_RANGE := 200.0        # red ranged attack distance
const SHOOT_COOLDOWN := 1.0       # seconds between shots
const FLEE_DIST := 250.0          # how far yellows flee from danger
const FRONTLINE_DIST := 80.0      # how close blues get to enemies
const RED_BEHIND_BLUE_DIST := 60.0 # how far behind blue the red positions
const WANDER_PAUSE_MIN := 0.8
const WANDER_PAUSE_MAX := 2.5
const ATTRACT_BIAS := 0.75
const ATTRACT_ORBIT_MIN := 0.4
const ATTRACT_ORBIT_MAX := 0.8

@export var color_type: String = "red"

var level: int = 1
var shift_meter: float = 0.0
var health: float = 0.0
var max_health: float = 0.0
var current_room_id: int = -1
var radius: float = 22.0

# Influence
var is_being_influenced: bool = false
var influence_attractor: Vector2 = Vector2.ZERO

# Combat
var kill_count: int = 0
var is_fed: bool = true

# Leveling
var leveling_partner: Node2D = null
var leveling_meter: float = 0.0

# Carrying
var carrying_resource: String = ""
var carrying_stone: bool:
	get: return carrying_resource == "stone"
	set(v): carrying_resource = "stone" if v else ""

# Deposit target — set by main.gd
var deposit_position: Vector2 = Vector2.ZERO
var has_deposit_in_room: bool = false
var bank_position: Vector2:
	get: return deposit_position
	set(v): deposit_position = v
var has_bank_in_room: bool:
	get: return has_deposit_in_room
	set(v): has_deposit_in_room = v

# Brain context — populated by main.gd each frame
var brain_enemies: Array = []           # enemy refs in same room
var brain_room_villagers: Array = []    # villager refs in same room
var brain_nearest_resource_pos: Vector2 = Vector2.ZERO
var brain_has_resource: bool = false

# Shooting (red only)
var shoot_target_pos: Vector2 = Vector2.ZERO  # where the shot goes (for visual)
var shoot_target_enemy: Node = null            # who to shoot (main.gd reads this)
var _shoot_cooldown: float = 0.0
var _shot_flash_timer: float = 0.0            # visual feedback timer

# Movement
var room_bounds: Rect2 = Rect2()
var blocked_rects: Array = []
var _move_target: Vector2 = Vector2.ZERO
var _move_speed: float = 0.0
var _arrived: bool = true
var _idle_timer: float = 0.0
var _brain_state: String = "idle"  # for debug display

# Drag
var _dragging := false
var _drag_offset := Vector2.ZERO

@onready var _area: Area2D = $InputArea
@onready var _col_shape: CollisionShape2D = $InputArea/CollisionShape2D
@onready var _label: Label = $ShiftLabel


func _ready() -> void:
	_area.input_event.connect(_on_area_input)
	_sync_definition()


func setup(p_color: String, pos: Vector2, p_level: int = 1) -> void:
	color_type = p_color
	position = pos
	level = p_level
	shift_meter = 0.0
	kill_count = 0
	is_fed = true
	leveling_meter = 0.0
	leveling_partner = null
	carrying_resource = ""
	_sync_definition()
	_idle_timer = randf_range(0.3, 1.0)


func set_color_type(new_type: String) -> void:
	color_type = new_type
	level = 1
	shift_meter = 0.0
	kill_count = 0
	is_fed = true
	leveling_meter = 0.0
	leveling_partner = null
	carrying_resource = ""
	_sync_definition()

func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, 3)
	_sync_definition()

func record_kill() -> void:
	kill_count += 1

func is_carrying() -> bool:
	return carrying_resource != ""

func get_influence_multiplier() -> float:
	# Legacy — influence_manager now uses _level_multiplier(src_level, target) directly
	match level:
		2: return 0.2
		3:
			if color_type == "yellow": return 1.0
			return 0.0
		_: return 1.0


func _sync_definition() -> void:
	var def: Dictionary = ColorRegistry.get_def(color_type)
	var base_health: float = float(def.get("health", 100))
	max_health = base_health * (2.0 if level == 3 else 1.0)
	health = max_health
	radius = float(def.get("radius", 22))
	_move_speed = float(def.get("movement_speed", 0)) * SPEED_SCALE
	if _col_shape:
		var shape := CircleShape2D.new()
		shape.radius = radius
		_col_shape.shape = shape
	if _label:
		_label.position = Vector2(-radius, -radius * 0.35)
		_label.size = Vector2(radius * 2.0, radius * 0.7)


# ── main loop ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Update label
	if _label:
		var txt := ""
		if is_carrying(): txt = carrying_resource
		elif shift_meter > 0.01: txt = str(int(shift_meter))
		if level > 1:
			txt = "L%d" % level if txt.is_empty() else "L%d %s" % [level, txt]
		_label.text = txt

	# Tick shoot cooldown
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_shot_flash_timer = maxf(0.0, _shot_flash_timer - delta)

	if not _dragging and _move_speed > 0.0:
		_evaluate_brain(delta)
		_do_movement(delta)

	queue_redraw()


# ── AI brain ─────────────────────────────────────────────────────────────────

func _evaluate_brain(_delta: float) -> void:
	shoot_target_enemy = null

	# Priority 1: DANGER
	if _check_danger():
		return

	# Priority 2: JOB (carrying or collecting)
	if _check_job():
		return

	# Priority 3: INFLUENCE (being pulled toward an influencer)
	if _check_influence():
		return

	# Priority 4: IDLE
	_do_idle_brain()


func _check_danger() -> bool:
	var nearest_enemy: Node = _find_nearest_enemy()
	if nearest_enemy == null:
		return false

	var enemy_dist: float = global_position.distance_to(nearest_enemy.global_position)
	if enemy_dist > AWARENESS_RANGE:
		return false

	_brain_state = "danger"

	match color_type:
		"yellow":
			# Flee from enemy, move toward nearest blue if available
			var nearest_blue: Node = _find_nearest_color("blue")
			if nearest_blue:
				_set_target(nearest_blue.global_position)
			else:
				# Flee away from enemy
				var flee_dir: Vector2 = (global_position - nearest_enemy.global_position).normalized()
				_set_target(global_position + flee_dir * FLEE_DIST)
		"blue":
			# Move to front line — toward enemy but maintain gap
			var dir_to_enemy: Vector2 = (nearest_enemy.global_position - global_position).normalized()
			var target_dist: float = enemy_dist - FRONTLINE_DIST
			if target_dist > 10.0:
				_set_target(global_position + dir_to_enemy * minf(target_dist, _move_speed * 0.5))
			else:
				_arrived = true  # hold position
		"red":
			# Get behind a blue, shoot enemies
			var nearest_blue: Node = _find_nearest_color("blue")
			if nearest_blue:
				# Position behind blue (opposite side from enemy)
				var enemy_to_blue: Vector2 = (nearest_blue.global_position - nearest_enemy.global_position).normalized()
				var behind_pos: Vector2 = nearest_blue.global_position + enemy_to_blue * RED_BEHIND_BLUE_DIST
				_set_target(behind_pos)
			# Shoot if enemy in range
			if enemy_dist <= SHOOT_RANGE and _shoot_cooldown <= 0.0:
				shoot_target_enemy = nearest_enemy
				shoot_target_pos = nearest_enemy.global_position
				_shoot_cooldown = SHOOT_COOLDOWN
				_shot_flash_timer = 0.15
		_:
			return false

	return true


func _check_job() -> bool:
	match color_type:
		"yellow":
			if is_carrying():
				# Carrying stone → head to bank
				if has_deposit_in_room:
					_brain_state = "deposit"
					_set_target(deposit_position)
					return true
				else:
					_brain_state = "carry_wander"
					# Wander while carrying — player needs to move us to bank room
					return false
			else:
				# Look for stone to pick up
				if brain_has_resource:
					_brain_state = "collect"
					_set_target(brain_nearest_resource_pos)
					return true
		"blue":
			if is_carrying():
				if has_deposit_in_room:
					_brain_state = "deposit"
					_set_target(deposit_position)
					return true
				else:
					_brain_state = "carry_wander"
					return false
			else:
				if brain_has_resource:
					_brain_state = "collect"
					_set_target(brain_nearest_resource_pos)
					return true
		"red":
			# Patrol — reds don't have a specific job yet
			# Could wander toward rooms with enemies in future
			pass
	return false


func _check_influence() -> bool:
	if is_being_influenced and randf() < ATTRACT_BIAS:
		_brain_state = "influence"
		var inf_range: float = radius * 7.5
		var angle: float = randf() * TAU
		var dist: float = randf_range(inf_range * ATTRACT_ORBIT_MIN, inf_range * ATTRACT_ORBIT_MAX)
		var target: Vector2 = influence_attractor + Vector2(cos(angle), sin(angle)) * dist
		_set_target_clamped(target)
		return true
	return false


func _do_idle_brain() -> void:
	_brain_state = "idle"
	if _arrived:
		_idle_timer -= get_process_delta_time()
		if _idle_timer <= 0.0:
			_idle_timer = randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
			_pick_random_target()


# ── movement ─────────────────────────────────────────────────────────────────

func _set_target(pos: Vector2) -> void:
	_move_target = pos
	_arrived = false

func _set_target_clamped(pos: Vector2) -> void:
	if room_bounds.has_area():
		var margin := radius + 6.0
		pos.x = clampf(pos.x, room_bounds.position.x + margin, room_bounds.end.x - margin)
		pos.y = clampf(pos.y, room_bounds.position.y + margin, room_bounds.end.y - margin)
	_set_target(pos)


func _do_movement(delta: float) -> void:
	if _arrived:
		return
	var to_target := _move_target - global_position
	var dist := to_target.length()
	var step := _move_speed * delta
	if dist <= step or dist < 5.0:
		global_position = _move_target
		_arrived = true
		_idle_timer = randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
	else:
		var new_pos: Vector2 = global_position + to_target.normalized() * step
		# Clamp to room
		if room_bounds.has_area():
			var margin := radius + 4.0
			new_pos.x = clampf(new_pos.x, room_bounds.position.x + margin, room_bounds.end.x - margin)
			new_pos.y = clampf(new_pos.y, room_bounds.position.y + margin, room_bounds.end.y - margin)
		global_position = new_pos


func _pick_random_target() -> bool:
	var margin := radius + 6.0
	var inner := Rect2(room_bounds.position + Vector2(margin, margin),
		room_bounds.size - Vector2(margin * 2.0, margin * 2.0))
	if not inner.has_area():
		return false
	for _attempt in 10:
		var target := Vector2(randf_range(inner.position.x, inner.end.x),
			randf_range(inner.position.y, inner.end.y))
		if _is_reachable(target):
			_set_target(target)
			return true
	return false


func _is_reachable(target: Vector2) -> bool:
	for rect in blocked_rects:
		if rect.has_point(target):
			return false
	return true


# ── helpers ──────────────────────────────────────────────────────────────────

func _find_nearest_enemy() -> Node:
	var best: Node = null
	var best_d: float = INF
	for e in brain_enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _find_nearest_color(target_color: String) -> Node:
	var best: Node = null
	var best_d: float = INF
	for v in brain_room_villagers:
		if not is_instance_valid(v) or v == self:
			continue
		if str(v.color_type) == target_color:
			var d: float = global_position.distance_to(v.global_position)
			if d < best_d:
				best_d = d
				best = v
	return best


# ── input (drag) ─────────────────────────────────────────────────────────────

func _on_area_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		_drag_offset = global_position - get_global_mouse_position()
		z_index = 10

func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		z_index = 0
		_arrived = true
		_idle_timer = randf_range(0.5, 1.5)
	elif event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset


# ── drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var def: Dictionary = ColorRegistry.get_def(color_type)
	var base_color: Color = def.get("display_color", Color.WHITE)
	var next_id: String = def.get("shifts_to", "")
	var bar_w := radius * 2.0

	var draw_color := base_color
	if not next_id.is_empty() and shift_meter > 0.0:
		var next_color: Color = ColorRegistry.get_def(next_id).get("display_color", Color.WHITE)
		draw_color = base_color.lerp(next_color, shift_meter / 100.0)

	if color_type == "red" and not is_fed:
		draw_color = draw_color.darkened(0.3 * (0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.2))

	match level:
		1: _draw_circle_body(draw_color)
		2: _draw_square_body(draw_color)
		3: _draw_triangle_body(draw_color)

	# Shot flash (red line to target)
	if _shot_flash_timer > 0.0:
		var alpha: float = _shot_flash_timer / 0.15
		var local_target: Vector2 = shoot_target_pos - global_position
		draw_line(Vector2.ZERO, local_target, Color(1.0, 0.3, 0.2, alpha), 2.0)
		draw_circle(local_target, 4.0, Color(1.0, 0.5, 0.2, alpha))

	# Carrying indicator
	if carrying_resource == "stone":
		draw_circle(Vector2(0, -radius - 6), 7.0, Color(0.5, 0.52, 0.48))
		draw_arc(Vector2(0, -radius - 6), 7.0, 0.0, TAU, 16, Color(0.35, 0.35, 0.35), 1.0, true)
	elif carrying_resource == "fish":
		draw_circle(Vector2(0, -radius - 6), 7.0, Color(0.3, 0.55, 0.75))
		draw_arc(Vector2(0, -radius - 6), 7.0, 0.0, TAU, 16, Color(0.2, 0.35, 0.55), 1.0, true)

	# Influence arrow
	if is_being_influenced and shift_meter > 1.0:
		var dir: Vector2 = (influence_attractor - global_position).normalized()
		draw_line(dir * (radius + 4.0), dir * (radius + 14.0), Color(1, 1, 1, 0.35), 2.0)

	# Hunger warning
	if color_type == "red" and not is_fed:
		draw_string(ThemeDB.fallback_font, Vector2(-radius * 0.6, -radius - 18.0), "HUNGRY",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.9, 0.3, 0.2, 0.8))

	# Bars
	var shift_y := -radius - 12.0
	if is_carrying(): shift_y -= 14.0
	if color_type == "red" and not is_fed: shift_y -= 10.0
	_draw_bar(-radius, shift_y, bar_w, shift_meter / 100.0,
		_get_shift_fill_color(next_id), Color(0.25, 0.25, 0.25, 0.5))

	var hp_y := radius + 5.0
	var hp_ratio := health / max_health if max_health > 0.0 else 1.0
	var hp_color := Color(0.3, 0.8, 0.35) if hp_ratio > 0.5 else Color(0.85, 0.25, 0.2)
	_draw_bar(-radius, hp_y, bar_w, hp_ratio, hp_color, Color(0.25, 0.25, 0.25, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(radius + 4.0, hp_y + BAR_H),
		str(int(health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6, 0.8))

	if color_type == "red" and kill_count > 0:
		draw_string(ThemeDB.fallback_font, Vector2(-radius, radius + 18.0),
			"K:%d" % kill_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.4, 0.3, 0.7))

	if color_type == "yellow" and leveling_meter > 0.01:
		_draw_bar(-radius, radius + 18.0, bar_w, leveling_meter / YELLOW_LEVEL_TIME,
			Color(0.94, 0.84, 0.12), Color(0.25, 0.2, 0.05, 0.5))


func _draw_circle_body(col: Color) -> void:
	draw_circle(Vector2.ZERO, radius, col)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.12, 0.12, 0.12), 2.0, true)

func _draw_square_body(col: Color) -> void:
	var r := radius * 0.85
	draw_rect(Rect2(-r, -r, r * 2, r * 2), col)
	draw_rect(Rect2(-r, -r, r * 2, r * 2), Color(0.12, 0.12, 0.12), false, 2.0)

func _draw_triangle_body(col: Color) -> void:
	var r := radius
	var pts := PackedVector2Array([Vector2(0, -r), Vector2(r * 0.866, r * 0.5), Vector2(-r * 0.866, r * 0.5)])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.12, 0.12, 0.12), 2.0)

func _draw_bar(x: float, y: float, w: float, ratio: float, fill_color: Color, track_color: Color) -> void:
	draw_rect(Rect2(x, y, w, BAR_H), track_color)
	if ratio > 0.001: draw_rect(Rect2(x, y, w * clampf(ratio, 0.0, 1.0), BAR_H), fill_color)
	draw_rect(Rect2(x, y, w, BAR_H), Color(0.12, 0.12, 0.12, 0.6), false, 1.0)

func _get_shift_fill_color(next_id: String) -> Color:
	if next_id.is_empty(): return Color(0.5, 0.5, 0.5, 0.3)
	return ColorRegistry.get_def(next_id).get("display_color", Color.WHITE)
