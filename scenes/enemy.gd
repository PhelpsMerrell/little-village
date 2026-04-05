extends Node2D
## Black circle enemy with levels. Wanders, duplicates (L1 only), merges (4→next).
## Gets STUNNED when hitting a blue villager.

enum State { MOVING, PAUSED, STUNNED }

const BASE_RADIUS := 28.0
const SPEED := 40.0
const BAR_H := 5.0
const PAUSE_MIN := 0.8
const PAUSE_MAX := 2.5

const BLUE_DAMAGE := 40.0
const HIT_COOLDOWN := 1.0
const STUN_DURATION := 2.5       # seconds stunned after hitting blue

const HEALTH_BY_LEVEL := {1: 50.0, 2: 50.0, 3: 150.0}
const RED_DAMAGE := {1: 50.0, 2: 75.0, 3: 150.0}

var level: int = 1
var radius: float = BASE_RADIUS
var health: float = 50.0
var max_health: float = 50.0
var current_room_id: int = -1
var room_bounds: Rect2 = Rect2()
var is_dead: bool = false

var dupe_meter: float = 0.0

var _hit_cooldowns: Dictionary = {}
var _state: State = State.PAUSED
var _state_timer: float = randf_range(0.3, 1.2)
var _stun_timer: float = 0.0
var _move_target: Vector2 = Vector2.ZERO

var _dragging := false
var _drag_offset := Vector2.ZERO

@onready var _area: Area2D = $InputArea
@onready var _col_shape: CollisionShape2D = $InputArea/CollisionShape2D


func _ready() -> void:
	_area.input_event.connect(_on_area_input)
	_sync_level()


func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, 3)
	dupe_meter = 0.0
	_sync_level()


func _sync_level() -> void:
	match level:
		1: radius = BASE_RADIUS
		2: radius = BASE_RADIUS * 1.3
		3: radius = BASE_RADIUS * 1.6
	max_health = HEALTH_BY_LEVEL.get(level, 50.0)
	health = max_health
	if _col_shape:
		var shape := CircleShape2D.new()
		shape.radius = radius
		_col_shape.shape = shape


func is_stunned() -> bool:
	return _state == State.STUNNED


func _process(delta: float) -> void:
	if is_dead:
		return
	var expired: Array = []
	for key in _hit_cooldowns:
		_hit_cooldowns[key] -= delta
		if _hit_cooldowns[key] <= 0.0:
			expired.append(key)
	for key in expired:
		_hit_cooldowns.erase(key)

	if not _dragging:
		match _state:
			State.MOVING:
				_do_moving(delta)
			State.PAUSED:
				_do_paused(delta)
			State.STUNNED:
				_do_stunned(delta)
	queue_redraw()


func _do_moving(delta: float) -> void:
	var to_target := _move_target - position
	var dist := to_target.length()
	var step := SPEED * delta
	if step >= dist:
		position = _move_target
		_state = State.PAUSED
		_state_timer = randf_range(PAUSE_MIN, PAUSE_MAX)
	else:
		position += to_target.normalized() * step


func _do_paused(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		if room_bounds.has_area() and _pick_wander_target():
			_state = State.MOVING
		else:
			_state_timer = 0.5


func _do_stunned(delta: float) -> void:
	_stun_timer -= delta
	if _stun_timer <= 0.0:
		_state = State.PAUSED
		_state_timer = randf_range(0.3, 0.8)


func _pick_wander_target() -> bool:
	var margin := radius + 8.0
	var inner := Rect2(
		room_bounds.position + Vector2(margin, margin),
		room_bounds.size - Vector2(margin * 2.0, margin * 2.0))
	if not inner.has_area():
		return false
	_move_target = Vector2(
		randf_range(inner.position.x, inner.end.x),
		randf_range(inner.position.y, inner.end.y))
	return true


# ── input ────────────────────────────────────────────────────────────────────

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
		_state = State.PAUSED
		_state_timer = randf_range(0.5, 1.5)
	elif event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset


## Enemy attacks a villager. Called by main.gd.
func try_attack(villager: Node) -> String:
	if is_stunned():
		return "immune"
	if _hit_cooldowns.has(villager):
		return "immune"
	var color: String = str(villager.color_type)
	if color == "red":
		return "immune"
	elif color == "yellow":
		villager.health = 0.0
		return "kill"
	elif color == "blue":
		_hit_cooldowns[villager] = HIT_COOLDOWN
		villager.health -= BLUE_DAMAGE
		# Stun self after hitting blue
		_state = State.STUNNED
		_stun_timer = STUN_DURATION
		if villager.health <= 0.0:
			return "kill"
		return "hit"
	return "immune"


## Red villager hits this enemy. Returns true if dead.
func take_red_hit(red_level: int) -> bool:
	var dmg: float = RED_DAMAGE.get(red_level, 50.0)
	health -= dmg
	return health <= 0.0


func die() -> void:
	is_dead = true
	queue_free()


# ── drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var body_color := Color(0.1, 0.1, 0.1)
	var outline_color := Color(0.4, 0.08, 0.08)

	# Stunned visual — lighter, dizzy
	if _state == State.STUNNED:
		body_color = Color(0.25, 0.2, 0.2)
		outline_color = Color(0.5, 0.4, 0.1)

	match level:
		1:
			draw_circle(Vector2.ZERO, radius, body_color)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, outline_color, 2.5, true)
		2:
			var r := radius * 0.85
			draw_rect(Rect2(-r, -r, r * 2, r * 2), body_color)
			draw_rect(Rect2(-r, -r, r * 2, r * 2), outline_color, false, 2.5)
		3:
			var r := radius
			var pts := PackedVector2Array([
				Vector2(0, -r),
				Vector2(r * 0.866, r * 0.5),
				Vector2(-r * 0.866, r * 0.5),
			])
			draw_colored_polygon(pts, body_color)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]),
				outline_color, 2.5)

	# Eyes
	var es := radius / BASE_RADIUS
	if _state == State.STUNNED:
		# Dizzy X eyes
		var ex1 := Vector2(-8 * es, -6 * es)
		var ex2 := Vector2(8 * es, -6 * es)
		var xs := 3.0 * es
		draw_line(ex1 + Vector2(-xs, -xs), ex1 + Vector2(xs, xs), Color(0.9, 0.8, 0.2), 2.0)
		draw_line(ex1 + Vector2(xs, -xs), ex1 + Vector2(-xs, xs), Color(0.9, 0.8, 0.2), 2.0)
		draw_line(ex2 + Vector2(-xs, -xs), ex2 + Vector2(xs, xs), Color(0.9, 0.8, 0.2), 2.0)
		draw_line(ex2 + Vector2(xs, -xs), ex2 + Vector2(-xs, xs), Color(0.9, 0.8, 0.2), 2.0)
		# Stars above head
		draw_string(ThemeDB.fallback_font,
			Vector2(-radius * 0.5, -radius - 8), "***",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.9, 0.8, 0.2, 0.7))
	else:
		draw_circle(Vector2(-8 * es, -6 * es), 4.0 * es, Color(0.8, 0.15, 0.1))
		draw_circle(Vector2(8 * es, -6 * es), 4.0 * es, Color(0.8, 0.15, 0.1))

	# Level text
	if level > 1:
		draw_string(ThemeDB.fallback_font,
			Vector2(-radius, radius + 14.0), "L%d" % level,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.2, 0.2, 0.8))

	# Health bar (L3 only)
	if level == 3:
		var bw := radius * 2.0
		var bx := -radius
		var by := radius + 5.0
		var ratio := health / max_health
		draw_rect(Rect2(bx, by, bw, BAR_H), Color(0.25, 0.25, 0.25, 0.5))
		draw_rect(Rect2(bx, by, bw * clampf(ratio, 0.0, 1.0), BAR_H), Color(0.7, 0.12, 0.12))
		draw_rect(Rect2(bx, by, bw, BAR_H), Color(0.12, 0.12, 0.12, 0.6), false, 1.0)

	# Dupe meter bar (L1 only)
	if level == 1 and dupe_meter > 0.01:
		var bw := radius * 2.0
		var bx := -radius
		var by := -radius - 12.0
		draw_rect(Rect2(bx, by, bw, BAR_H), Color(0.25, 0.25, 0.25, 0.5))
		draw_rect(Rect2(bx, by, bw * clampf(dupe_meter / 100.0, 0.0, 1.0), BAR_H),
			Color(0.6, 0.1, 0.1))
		draw_rect(Rect2(bx, by, bw, BAR_H), Color(0.12, 0.12, 0.12, 0.6), false, 1.0)
