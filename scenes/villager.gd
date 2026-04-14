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
const WANDER_PAUSE_MIN := 2.0
const WANDER_PAUSE_MAX := 5.5
const IDLE_STAND_CHANCE := 0.60
const IDLE_LOCAL_STEP_CHANCE := 0.50
const IDLE_BUILDING_VISIT_CHANCE := 0.35
const IDLE_SOCIAL_VISIT_CHANCE := 0.35
const IDLE_ROOM_TRAVEL_CHANCE := 0.30
const IDLE_JIGGLE_RADIUS := 18.0
const IDLE_LOCAL_STEP_MIN := 14.0
const IDLE_LOCAL_STEP_MAX := 34.0
const SEPARATION_DIST := 8.0
const SEPARATION_FORCE := 0.4
const COMMAND_SPEED_MULT := 1.5  ## Player-commanded villagers move 50% faster

@export var color_type: String = "red"

var faction_id: int = 0  ## Which faction owns this villager (0 = local player in solo)
var net_id: int = -1  ## Unique ID for network command targeting
var villager_name: String = ""  ## Display name (lineage base name)
var generation: int = 1  ## Generational counter for lineage display
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
var command_mode: String = "none"  # none, move_to, hold, combat
var command_target: Vector2 = Vector2.ZERO
var is_selected: bool = false

## PvP combat command state
var combat_target: Node = null   ## Target villager for PvP combat command
var combat_mode: String = ""     ## "attack" or "stun"

## Dynamic shift target for colorless villagers (set by influence_manager)
var pending_shift_color: String = ""

var kill_count: int = 0
var fire_rate_bonus: float = 0.0  ## cumulative % reduction from university training
var is_fed: bool = true
var _satiation_timer: float = 0.0  # seconds remaining before next fish needed

const SATIATION_PER_LEVEL := [0.0, 600.0, 600.0, 600.0]  # All levels: 1 fish per game day (600s cycle)
const L2_SPEED_MULT := 1.4  # L2 villagers move 40% faster
const L3_BASE_LIFESPAN_DAYS: int = 2   ## All L3 units live 2 game-days without sustain

## L3 lifecycle state
var _l3_lifespan_timer: float = 0.0   ## Countdown timer; 0 = not L3 or not started
var _l3_church_slept: bool = false     ## True if blue L3 slept in church this night cycle

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

## Work room assignment: villager loops collecting in this room
var assigned_room_id: int = -1  ## -1 = no assignment

## Church healing: main.gd sets these for damaged blues
var brain_church_pos: Vector2 = Vector2.ZERO
var brain_has_church: bool = false

## Idle world awareness: main.gd can populate these for calmer town behavior
var brain_buildings: Array = []  # building nodes in the room / nearby
var brain_room_centers: Array = []  # Vector2 room centers reachable through open doors

## Colorless attraction: main.gd sets when a controlled villager is nearby
var colorless_attract_pos: Vector2 = Vector2.ZERO
var has_attract_target: bool = false

## Wall segments for collision (set by main.gd)
var brain_walls: Array = []  # [{start: Vector2, end: Vector2, is_open: bool}]
var brain_doorways: Array = []  # [{mid: Vector2, room_a: int, room_b: int, is_open: bool}]
var _doorway_waypoint: Vector2 = Vector2.ZERO  # intermediate target to navigate through a door
var _has_doorway_waypoint: bool = false
var break_door_target: Vector2 = Vector2.ZERO  ## Set by break-door command; cleared after breaking
var break_door_node: Node = null  ## Reference to the actual door node being targeted

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

var _brain_frame_offset: int = 0  ## Set at creation to stagger brain ticks
var _frame_counter: int = 0
const BRAIN_SKIP_FRAMES := 3  ## Idle villagers only think every N frames

@onready var _area: Area2D = $InputArea
@onready var _col_shape: CollisionShape2D = $InputArea/CollisionShape2D
@onready var _label: Label = $ShiftLabel
@onready var _faction_glow: Line2D = $FactionGlow
@onready var _faction_ring: Line2D = $FactionRing
@onready var _l1_body: Polygon2D = $L1Body
@onready var _l1_outline: Line2D = $L1Outline
@onready var _l2_body: Polygon2D = $L2Body
@onready var _l2_outline: Line2D = $L2Outline
@onready var _l3_body: Polygon2D = $L3Body
@onready var _l3_outline: Line2D = $L3Outline
@onready var _faction_symbol: Label = $FactionSymbol
@onready var _carry_indicator: Polygon2D = $CarryIndicator
@onready var _selection_ring: Line2D = $SelectionRing
@onready var _command_label: Label = $CommandLabel
@onready var _hunger_label: Label = $HungerLabel

signal resource_dropped(villager: Node2D, resource_type: String)


func _ready() -> void:
	_area.input_event.connect(_on_area_input); _sync_definition()
	_brain_frame_offset = randi() % BRAIN_SKIP_FRAMES  ## Stagger across villagers

func setup(p_color: String, pos: Vector2, p_level: int = 1) -> void:
	color_type = p_color; position = pos; level = p_level
	shift_meter = 0.0; _decay_grace_timer = 0.0; kill_count = 0; is_fed = true
	leveling_meter = 0.0; leveling_partner = null; carrying_resource = ""
	_l3_lifespan_timer = 0.0; _l3_church_slept = false
	_sync_definition(); _idle_timer = GameRNG.randf_range(0.3, 1.0)

func set_color_type(new_type: String) -> void:
	var hp_ratio: float = health / max_health if max_health > 0.0 else 1.0
	color_type = new_type; level = 1
	shift_meter = 0.0; _decay_grace_timer = 0.0; kill_count = 0; is_fed = true
	leveling_meter = 0.0; leveling_partner = null; carrying_resource = ""
	_l3_lifespan_timer = 0.0; _l3_church_slept = false
	_sync_definition()
	health = max_health * hp_ratio

func set_level(new_level: int) -> void:
	var old_level: int = level
	level = clampi(new_level, 1, 3); _sync_definition()
	# Start L3 lifespan timer on promotion to L3
	if level == 3 and old_level < 3:
		_l3_lifespan_timer = float(L3_BASE_LIFESPAN_DAYS) * GameClock.DAY_DURATION
		_l3_church_slept = false
	# Clear timer if demoted from L3 (e.g. via shift)
	elif level < 3:
		_l3_lifespan_timer = 0.0
		_l3_church_slept = false

func record_kill() -> void: kill_count += 1
func is_carrying() -> bool: return carrying_resource != ""

func get_shoot_cooldown() -> float:
	## Effective cooldown after university training bonus.
	return SHOOT_COOLDOWN * maxf(0.1, 1.0 - fire_rate_bonus)

func get_display_name() -> String:
	if villager_name.is_empty():
		return color_type.capitalize()
	if generation <= 1:
		return villager_name
	return "%s %s" % [villager_name, _to_roman(generation)]

static func _to_roman(num: int) -> String:
	var result := ""
	var values := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var numerals := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	for i in values.size():
		while num >= values[i]:
			result += numerals[i]
			num -= values[i]
	return result

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
	# Scale scene body nodes to match radius
	if _l1_body:
		var s: float = radius / 22.0  # base polygon was designed for radius 22
		for node in [_l1_body, _l1_outline, _l2_body, _l2_outline, _l3_body, _l3_outline]:
			if node: node.scale = Vector2(s, s)
		# Scale faction rings
		if _faction_ring: _faction_ring.scale = Vector2(s, s)
		if _faction_glow: _faction_glow.scale = Vector2(s, s)
		if _selection_ring: _selection_ring.scale = Vector2(s, s)

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
		_update_visuals()
		queue_redraw()
		return
	_update_label()
	_shoot_cooldown = maxf(0.0, _shoot_cooldown - delta)
	_shot_flash_timer = maxf(0.0, _shot_flash_timer - delta)
	# Stun tick
	if _stun_timer > 0.0:
		_stun_timer -= delta
		_update_visuals()
		queue_redraw()
		return
	# L3 lifespan countdown (host-only; puppet state synced via snapshot)
	if level == 3 and _l3_lifespan_timer > 0.0 and not is_puppet:
		_l3_lifespan_timer -= delta
		if _l3_lifespan_timer <= 0.0:
			_die_from_lifespan()
			return
	if not _dragging and _move_speed > 0.0:
		_frame_counter += 1
		# Active states always think; idle villagers skip frames
		var should_think: bool = true
		if _brain_state == "idle" and _arrived:
			should_think = ((_frame_counter + _brain_frame_offset) % BRAIN_SKIP_FRAMES == 0)
		if should_think:
			_evaluate_brain(delta)
		_do_movement(delta); _apply_separation()
	_update_visuals()
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
	if _check_combat_command(): return
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
		"break_door":
			# Validate door target is still valid (not already broken)
			if is_instance_valid(break_door_node) and break_door_node.is_open:
				# Door already open, command fulfilled
				command_mode = "none"
				break_door_node = null
				break_door_target = Vector2.ZERO
				_arrived = true
				return true
			_brain_state = "break_door"
			var dist_to_door := global_position.distance_to(command_target)
			if dist_to_door < radius + 50.0:
				# In breaking range — stand still, main.gd handles the break
				_arrived = true
			else:
				# Navigate toward door, bypassing wall blocking
				_move_target = command_target
				_arrived = false
			return true
		"hold":
			_brain_state = "command_hold"
			_arrived = true
			return true
	return false

func clear_command() -> void:
	command_mode = "none"
	command_target = Vector2.ZERO

func _check_combat_command() -> bool:
	if command_mode != "combat":
		return false

	if not is_instance_valid(combat_target) or combat_target.get("_dying"):
		combat_target = null
		combat_mode = ""
		command_mode = "none"
		return false

	_brain_state = "combat"
	var dist: float = global_position.distance_to(combat_target.global_position)

	var target_radius: float = 22.0
	if "radius" in combat_target:
		target_radius = float(combat_target.radius)

	if combat_mode == "attack" and dist < SHOOT_RANGE and _shoot_cooldown <= 0.0:
		shoot_target_enemy = combat_target
		shoot_target_pos = combat_target.global_position
		_shoot_cooldown = get_shoot_cooldown()
		_shot_flash_timer = 0.15
		_set_target(combat_target.global_position)
	elif combat_mode == "stun" and dist < radius + target_radius + 20.0 and _shoot_cooldown <= 0.0:
		if combat_target.has_method("apply_stun"):
			combat_target.apply_stun(2.0)
		_shoot_cooldown = get_shoot_cooldown()
		_shot_flash_timer = 0.15
		# After successful stun, clear command so blue doesn't perma-chase
		combat_target = null
		combat_mode = ""
		command_mode = "none"
		return false
	else:
		_set_target(combat_target.global_position)

	return true

func command_move_to(pos: Vector2) -> void:
	command_mode = "move_to"
	command_target = pos
	break_door_node = null
	break_door_target = Vector2.ZERO
	assigned_room_id = -1  # clear work assignment on manual move

func command_hold() -> void:
	command_mode = "hold"

func command_release() -> void:
	clear_command()
	combat_target = null
	combat_mode = ""
	break_door_target = Vector2.ZERO
	break_door_node = null
	assigned_room_id = -1

func command_attack(target: Node) -> void:
	combat_target = target
	combat_mode = "attack"
	command_mode = "combat"

func command_stun(target: Node) -> void:
	combat_target = target
	combat_mode = "stun"
	command_mode = "combat"

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
				_shoot_cooldown = get_shoot_cooldown(); _shot_flash_timer = 0.15
		_: return false
	return true

func _check_job() -> bool:
	match color_type:
		"yellow":
			return _check_worker_job()
		"blue":
			# Blue pre-check: seek church when damaged
			if not is_carrying() and brain_has_church and health < max_health:
				_brain_state = "seek_church"; _set_target(brain_church_pos); return true
			return _check_worker_job()
		"red": pass
		"colorless": pass
	return false


func _check_worker_job() -> bool:
	## Shared gather→deposit→return loop for any resource-collecting villager.
	## Works for yellows (stone/diamond/grain) and blues (fish) identically.
	if is_carrying():
		if has_deposit_in_room:
			_brain_state = "deposit"; _set_target(deposit_position); return true
		elif deposit_position != Vector2.ZERO:
			_brain_state = "deposit_cross"; _set_target(deposit_position); return true
		else:
			_brain_state = "carry_wander"; return false
	if has_waypoint:
		_brain_state = "waypoint"; _set_target(waypoint_target_pos); return true
	if brain_has_resource:
		_brain_state = "collect"; _set_target(brain_nearest_resource_pos); return true
	if assigned_room_id >= 0:
		_brain_state = "waypoint"; _set_target(_get_assigned_room_center()); return true
	return false


func _get_assigned_room_center() -> Vector2:
	## Get center of assigned room for return-to-work navigation.
	if room_bounds.has_area() and current_room_id == assigned_room_id:
		return room_bounds.get_center()
	# Room center will be set by main.gd via brain_room_centers or waypoint
	return waypoint_target_pos if has_waypoint else global_position

func _check_influence() -> bool:
	# Influence still changes shift_meter elsewhere, but it should not hard-override idle movement.
	return false

func _do_idle_brain() -> void:
	_brain_state = "idle"
	if not _arrived:
		return

	_idle_timer -= get_process_delta_time()
	if _idle_timer > 0.0:
		return

	_idle_timer = GameRNG.randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
	_pick_idle_behavior()


func _pick_idle_behavior() -> void:
	var roll: float = GameRNG.randf()

	if roll < IDLE_STAND_CHANCE:
		_pick_idle_stand_or_jiggle()
		return

	roll = (roll - IDLE_STAND_CHANCE) / maxf(0.001, 1.0 - IDLE_STAND_CHANCE)

	if roll < IDLE_BUILDING_VISIT_CHANCE and _pick_idle_building_visit():
		return
	roll = (roll - IDLE_BUILDING_VISIT_CHANCE) / maxf(0.001, 1.0 - IDLE_BUILDING_VISIT_CHANCE)

	if roll < IDLE_SOCIAL_VISIT_CHANCE and _pick_idle_social_visit():
		return
	roll = (roll - IDLE_SOCIAL_VISIT_CHANCE) / maxf(0.001, 1.0 - IDLE_SOCIAL_VISIT_CHANCE)

	if roll < IDLE_ROOM_TRAVEL_CHANCE and _pick_idle_room_visit():
		return

	if not _pick_local_idle_step():
		_arrived = true


func _pick_idle_stand_or_jiggle() -> void:
	if GameRNG.randf() < IDLE_LOCAL_STEP_CHANCE:
		if _pick_local_idle_step(IDLE_JIGGLE_RADIUS):
			return
	_arrived = true


func _pick_local_idle_step(max_dist: float = IDLE_LOCAL_STEP_MAX) -> bool:
	for _attempt in 10:
		var angle: float = GameRNG.randf() * TAU
		var dist: float = GameRNG.randf_range(IDLE_LOCAL_STEP_MIN, max_dist)
		var target := global_position + Vector2(cos(angle), sin(angle)) * dist
		if room_bounds.has_area():
			var m := radius + 6.0
			target.x = clampf(target.x, room_bounds.position.x + m, room_bounds.end.x - m)
			target.y = clampf(target.y, room_bounds.position.y + m, room_bounds.end.y - m)
		if _is_reachable(target) and not _wall_blocks(global_position, target):
			_set_target(target)
			return true
	return false


func _pick_idle_building_visit() -> bool:
	var candidates: Array = []
	for b in brain_buildings:
		if not is_instance_valid(b):
			continue
		if b == self:
			continue
		if "placed_by_faction" in b and int(b.placed_by_faction) >= 0 and int(b.placed_by_faction) != faction_id:
			continue
		candidates.append(b)
	if candidates.is_empty():
		return false
	var building = candidates[GameRNG.randi() % candidates.size()]
	var offset := Vector2(GameRNG.randf_range(-20.0, 20.0), GameRNG.randf_range(18.0, 36.0))
	_set_target(building.global_position + offset)
	return true


func _pick_idle_social_visit() -> bool:
	var candidates: Array = []
	for other in brain_room_villagers:
		if not is_instance_valid(other) or other == self:
			continue
		if other.get("_dying"):
			continue
		candidates.append(other)
	if candidates.is_empty():
		return false
	var other = candidates[GameRNG.randi() % candidates.size()]
	var dir := Vector2.RIGHT.rotated(GameRNG.randf() * TAU)
	_set_target(other.global_position + dir * GameRNG.randf_range(radius * 1.5, radius * 2.5))
	return true


func _pick_idle_room_visit() -> bool:
	if brain_room_centers.is_empty():
		return false
	var candidates: Array = []
	for center in brain_room_centers:
		if center is Vector2 and global_position.distance_to(center) > 48.0:
			candidates.append(center)
	if candidates.is_empty():
		return false
	_set_target(candidates[GameRNG.randi() % candidates.size()])
	return true


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

	# Player commands get a speed boost
	var speed: float = _move_speed
	if _brain_state in ["command_move", "break_door", "combat"]:
		speed *= COMMAND_SPEED_MULT

	# Break-door state: navigate straight to door, ignoring its wall segment
	if _brain_state == "break_door":
		var to_door := _move_target - global_position
		var dist_d := to_door.length()
		var step_d := speed * delta
		if dist_d <= step_d or dist_d < 5.0:
			global_position = _move_target
			_arrived = true
		else:
			# Move toward door ignoring wall blocking (the door IS the wall)
			global_position += to_door.normalized() * step_d
		return

	# If we have a doorway waypoint, navigate to it first
	var effective_target: Vector2 = _move_target
	if _has_doorway_waypoint:
		effective_target = _doorway_waypoint
		if global_position.distance_to(_doorway_waypoint) < radius + 12.0:
			_has_doorway_waypoint = false  # reached doorway, continue to real target
			return

	# Proactive door routing: if target is across a wall, find a door
	if not _has_doorway_waypoint and _wall_blocks(global_position, effective_target):
		if _try_find_doorway_redirect(_move_target):
			return
		# No accessible door found — slide along wall toward nearest door
		if _try_slide_toward_nearest_door():
			return
		_arrived = true
		return

	var to_target := effective_target - global_position
	var dist := to_target.length(); var step := speed * delta
	if dist <= step or dist < 5.0:
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
	## Find the nearest open doorway that would help us reach target. Returns true if found.
	var best_door: Vector2 = Vector2.ZERO
	var best_score: float = INF
	for door in brain_doorways:
		# Only use open doors for traversal (closed doors block passage)
		if not door.get("is_open", false):
			continue
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


func _try_slide_toward_nearest_door() -> bool:
	## When no direct door path is found, move toward the nearest door mid-point.
	## This handles cases where we're far from a door and need to walk along a wall.
	var best_door: Vector2 = Vector2.ZERO
	var best_d: float = INF
	for door in brain_doorways:
		var dmid: Vector2 = door["mid"]
		var d: float = global_position.distance_to(dmid)
		if d < best_d:
			best_d = d
			best_door = dmid
	if best_d < INF:
		# Try to find a position we CAN walk to that's closer to the door
		var dir: Vector2 = (best_door - global_position).normalized()
		# Try along wall: perpendicular slides
		for angle_offset in [0.0, 0.5, -0.5, 1.0, -1.0]:
			var slide_dir: Vector2 = dir.rotated(angle_offset)
			var test_pos: Vector2 = global_position + slide_dir * 30.0
			if not _wall_blocks(global_position, test_pos):
				_doorway_waypoint = test_pos
				_has_doorway_waypoint = true
				return true
	return false


func _wall_blocks(from: Vector2, to: Vector2) -> bool:
	## Returns true if moving from → to crosses any impassable segment.
	## Solid walls always block. Closed doors block regular traversal.
	## Open doors are passable. Break_door movement bypasses this entirely.
	for w in brain_walls:
		if w["is_open"]:
			continue  # Open: passable
		if _segments_intersect(from, to, w["start"], w["end"]):
			return true
	return false


func _wall_blocks_hard(from: Vector2, to: Vector2) -> bool:
	## Returns true if from→to crosses any solid wall OR closed door (full blocking).
	## Used for strict pass-through checks (not break_door pathing).
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


func _get_main_controller() -> Node:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("get_drag_target_for_villager"):
		return scene
	return null


# ══════════════════════════════════════════════════════════════════════════════
# INPUT
# ══════════════════════════════════════════════════════════════════════════════

func _on_area_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if _dying: return
	if not FactionManager.is_local_faction(faction_id): return
	if Input.is_key_pressed(KEY_SHIFT): return  # Shift = selection mode, suppress drag
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var main := _get_main_controller()
		if main != null and main.has_method("can_drag_villager") and not main.can_drag_villager(self):
			return
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
		var desired_pos := get_global_mouse_position() + _drag_offset
		var main := _get_main_controller()
		if main != null and main.has_method("get_drag_target_for_villager"):
			global_position = main.get_drag_target_for_villager(self, desired_pos)
		else:
			global_position = desired_pos
		if _client_dragging and _drag_send_timer >= DRAG_SEND_INTERVAL:
			_drag_send_timer = 0.0
			NetworkManager.send_command({
				"type": "drag_move",
				"net_id": net_id,
				"px": global_position.x,
				"py": global_position.y,
			})


# ══════════════════════════════════════════════════════════════════════════════
# VISUALS — scene node updates
# ══════════════════════════════════════════════════════════════════════════════

func _update_visuals() -> void:
	if _dying or not _l1_body:
		return
	var def: Dictionary = ColorRegistry.get_def(color_type)
	var base_color: Color = def.get("display_color", Color.WHITE)
	var next_id: String = def.get("shifts_to", "")
	var draw_color := base_color
	if not next_id.is_empty() and shift_meter > 0.0:
		draw_color = base_color.lerp(ColorRegistry.get_def(next_id).get("display_color", Color.WHITE), shift_meter / 100.0)
	if color_type == "red" and not is_fed:
		draw_color = draw_color.darkened(0.3 * (0.5 + sin(Time.get_ticks_msec() * 0.005) * 0.2))

	# Level shape visibility
	_l1_body.visible = (level == 1)
	_l1_outline.visible = (level == 1)
	_l2_body.visible = (level == 2)
	_l2_outline.visible = (level == 2)
	_l3_body.visible = (level == 3)
	_l3_outline.visible = (level == 3)

	# Body color
	_l1_body.color = draw_color
	_l2_body.color = draw_color
	_l3_body.color = draw_color

	# Outline color (faction border)
	var border_col: Color = FactionManager.get_faction_color(faction_id) if faction_id >= 0 else Color(0.12, 0.12, 0.12)
	_l1_outline.default_color = border_col
	_l2_outline.default_color = border_col
	_l3_outline.default_color = border_col

	# Faction ring
	if faction_id >= 0:
		var fcolor: Color = FactionManager.get_faction_color(faction_id)
		_faction_ring.visible = true
		_faction_ring.default_color = fcolor
		_faction_glow.visible = true
		_faction_glow.default_color = Color(fcolor.r, fcolor.g, fcolor.b, 0.35)
	else:
		_faction_ring.visible = false
		_faction_glow.visible = false

	# Faction symbol
	if faction_id >= 0 and color_type != "magic_orb":
		_faction_symbol.visible = true
		_faction_symbol.text = FactionManager.get_faction_symbol(faction_id)
		var fc: Color = FactionManager.get_faction_color(faction_id)
		fc.a = 1.0
		_faction_symbol.add_theme_color_override("font_color", fc)
	else:
		_faction_symbol.visible = false

	# Carry indicator
	if is_carrying():
		_carry_indicator.visible = true
		_carry_indicator.position = Vector2(0, -radius - 6)
		match carrying_resource:
			"stone": _carry_indicator.color = Color(0.5, 0.52, 0.48)
			"diamond": _carry_indicator.color = Color(0.4, 0.85, 0.95)
			"fish": _carry_indicator.color = Color(0.3, 0.55, 0.75)
			"grain": _carry_indicator.color = Color(0.85, 0.75, 0.2)
	else:
		_carry_indicator.visible = false

	# Selection ring
	if is_selected:
		_selection_ring.visible = true
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		_selection_ring.default_color = Color(1.0, 1.0, 1.0, pulse)
	else:
		_selection_ring.visible = false

	# Command label
	if command_mode == "hold":
		_command_label.visible = true
		_command_label.text = "HOLD"
		_command_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 0.8))
	elif command_mode == "break_door":
		_command_label.visible = true
		_command_label.text = "BREAK"
		_command_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.1, 0.9))
	else:
		_command_label.visible = false

	# Hunger label
	_hunger_label.visible = (color_type == "red" and not is_fed)


func _draw() -> void:
	if _dying:
		_draw_death_twitch()
		return
	var def: Dictionary = ColorRegistry.get_def(color_type)
	var next_id: String = def.get("shifts_to", "")
	var bar_w := radius * 2.0

	# Shot flash line (dynamic)
	if _shot_flash_timer > 0.0:
		var a: float = _shot_flash_timer / 0.15
		var lt: Vector2 = shoot_target_pos - global_position
		draw_line(Vector2.ZERO, lt, Color(1.0, 0.3, 0.2, a), 2.0)
		draw_circle(lt, 4.0, Color(1.0, 0.5, 0.2, a))

	# Stun indicator
	if _stun_timer > 0.0:
		var star_a: float = 0.5 + sin(Time.get_ticks_msec() * 0.008) * 0.3
		var star_col := Color(0.9, 0.8, 0.2, star_a)
		var star_r: float = radius + 6.0
		var spin: float = Time.get_ticks_msec() * 0.003
		for i in 3:
			var angle: float = spin + i * TAU / 3.0
			var sp := Vector2(cos(angle), sin(angle)) * star_r * 0.6
			draw_string(ThemeDB.fallback_font, sp + Vector2(-4, 4), "*", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, star_col)

	# Move command direction indicator
	if command_mode == "move_to":
		var cmd_dir: Vector2 = (command_target - global_position).normalized()
		draw_line(cmd_dir * (radius + 4.0), cmd_dir * (radius + 16.0), Color(0.2, 1.0, 0.4, 0.6), 2.0)

	# Shift bar
	var shift_y := -radius - 12.0
	if is_carrying(): shift_y -= 14.0
	if color_type == "red" and not is_fed: shift_y -= 10.0
	_draw_bar(-radius, shift_y, bar_w, shift_meter / 100.0, _get_shift_fill_color(next_id), Color(0.25, 0.25, 0.25, 0.5))

	# Health bar
	var hp_y := radius + 5.0
	var hp_ratio := health / max_health if max_health > 0.0 else 1.0
	_draw_bar(-radius, hp_y, bar_w, hp_ratio, Color(0.3, 0.8, 0.35) if hp_ratio > 0.5 else Color(0.85, 0.25, 0.2), Color(0.25, 0.25, 0.25, 0.5))
	draw_string(ThemeDB.fallback_font, Vector2(radius + 4.0, hp_y + BAR_H), str(int(health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.6, 0.6, 0.8))

	# Kill count
	if color_type == "red" and kill_count > 0:
		draw_string(ThemeDB.fallback_font, Vector2(-radius, radius + 18.0), "K:%d" % kill_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.4, 0.3, 0.7))

	# Yellow leveling bar
	if color_type == "yellow" and leveling_meter > 0.01:
		_draw_bar(-radius, radius + 18.0, bar_w, leveling_meter / YELLOW_LEVEL_TIME, Color(0.94, 0.84, 0.12), Color(0.25, 0.2, 0.05, 0.5))


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
	# Hide scene nodes during death (draw code handles the twitch)
	if _l1_body:
		for child in [_l1_body, _l1_outline, _l2_body, _l2_outline, _l3_body, _l3_outline,
				_faction_glow, _faction_ring, _faction_symbol, _carry_indicator,
				_selection_ring, _command_label, _hunger_label]:
			if child: child.visible = false
	# Drop anything carried
	if carrying_resource != "":
		var dropped_type: String = carrying_resource
		carrying_resource = ""
		resource_dropped.emit(self, dropped_type)


func _die_from_lifespan() -> void:
	## L3 villager expires from age.
	_l3_lifespan_timer = 0.0
	EventFeed.push("%s (L3 %s) expired." % [get_display_name(), color_type], Color(0.6, 0.3, 0.3))
	start_death_animation()


func extend_l3_lifespan() -> void:
	## Called when red L3 eats fish or blue L3 sleeps in church.
	if level == 3:
		_l3_lifespan_timer = float(L3_BASE_LIFESPAN_DAYS) * GameClock.DAY_DURATION


var _stun_timer: float = 0.0

func apply_stun(duration: float) -> void:
	## Blue PvP: temporarily stuns this villager (freezes brain).
	_stun_timer = maxf(_stun_timer, duration)

func _is_stunned() -> bool:
	return _stun_timer > 0.0
