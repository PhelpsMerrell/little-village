extends Node2D
## Villager with state machine, levels, movement, influence attraction, and HUD bars.
## Level 1 = circle, Level 2 = square, Level 3 = triangle.

enum State { MOVING, PAUSED, IDLE }

const SPEED_SCALE := 8.0
const PAUSE_TIME_MIN := 1.2
const PAUSE_TIME_MAX := 3.5
const IDLE_TIME_MIN := 3.0
const IDLE_TIME_MAX := 6.0
const BAR_H := 5.0
const ATTRACT_BIAS := 0.75
const ATTRACT_ORBIT_MIN := 0.4
const ATTRACT_ORBIT_MAX := 0.8
const ATTRACT_REDIRECT_INTERVAL := 2.0

@export var color_type: String = "red"

var level: int = 1
var shift_meter: float = 0.0
var health: float = 0.0
var max_health: float = 0.0
var can_drag: bool = true
var current_room_id: int = -1
var radius: float = 22.0

var is_being_influenced: bool = false
var influence_attractor: Vector2 = Vector2.ZERO

var kill_count: int = 0

var leveling_partner: Node2D = null
var leveling_meter: float = 0.0
const YELLOW_LEVEL_TIME := 8.0

var room_bounds: Rect2 = Rect2()
var blocked_rects: Array = []
var _state: State = State.PAUSED
var _state_timer: float = randf_range(0.3, 1.5)
var _move_target: Vector2 = Vector2.ZERO
var _move_speed: float = 0.0
var _redirect_timer: float = 0.0

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
	leveling_meter = 0.0
	leveling_partner = null
	_sync_definition()
	_state = State.PAUSED
	_state_timer = randf_range(0.3, 1.0)


func set_color_type(new_type: String) -> void:
	color_type = new_type
	level = 1
	shift_meter = 0.0
	kill_count = 0
	leveling_meter = 0.0
	leveling_partner = null
	_sync_definition()
	queue_redraw()


func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, 3)
	_sync_definition()
	queue_redraw()


func record_kill() -> void:
	kill_count += 1


func get_influence_multiplier() -> float:
	match level:
		2: return 0.2
		3:
			if color_type == "yellow":
				return 1.0
			return 0.0
		_: return 1.0


func _sync_definition() -> void:
	var def := ColorRegistry.get_def(color_type)
	can_drag = true
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


func _process(delta: float) -> void:
	if _label:
		var txt := ""
		if shift_meter > 0.01:
			txt = str(int(shift_meter))
		if level > 1:
			txt = "L%d" % level if txt.is_empty() else "L%d %s" % [level, txt]
		_label.text = txt

	if not _dragging:
		match _state:
			State.MOVING:
				_do_moving(delta)
			State.PAUSED:
				_do_paused(delta)
			State.IDLE:
				_do_idle(delta)

	queue_redraw()


func _do_moving(delta: float) -> void:
	var to_target := _move_target - position
	var dist := to_target.length()
	var step := _move_speed * delta
	if step >= dist:
		position = _move_target
		var pause := randf_range(PAUSE_TIME_MIN, PAUSE_TIME_MAX)
		if is_being_influenced:
			pause *= 0.4
		_enter_state(State.PAUSED, pause)
	else:
		position += to_target.normalized() * step
		if is_being_influenced:
			_redirect_timer -= delta
			if _redirect_timer <= 0.0:
				_redirect_timer = ATTRACT_REDIRECT_INTERVAL
				if _pick_attractor_target():
					pass


func _do_paused(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		if _move_speed > 0.0 and room_bounds.has_area():
			if _pick_wander_target():
				_state = State.MOVING
				_redirect_timer = ATTRACT_REDIRECT_INTERVAL
			else:
				_state_timer = 0.5
		else:
			_state_timer = 2.0


func _do_idle(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.PAUSED, randf_range(0.3, 1.0))


func _enter_state(s: State, timer: float = 0.0) -> void:
	_state = s
	_state_timer = timer


func _pick_wander_target() -> bool:
	if is_being_influenced and randf() < ATTRACT_BIAS:
		if _pick_attractor_target():
			return true
	return _pick_random_target()


func _pick_attractor_target() -> bool:
	var inf_range: float = radius * 7.5  # match INFLUENCE_RANGE_MULT
	var orbit_min: float = inf_range * ATTRACT_ORBIT_MIN
	var orbit_max: float = inf_range * ATTRACT_ORBIT_MAX
	for _attempt in 10:
		var angle: float = randf() * TAU
		var dist: float = randf_range(orbit_min, orbit_max)
		var target: Vector2 = influence_attractor + Vector2(cos(angle), sin(angle)) * dist
		if room_bounds.has_area():
			var margin := radius + 6.0
			target.x = clampf(target.x, room_bounds.position.x + margin, room_bounds.end.x - margin)
			target.y = clampf(target.y, room_bounds.position.y + margin, room_bounds.end.y - margin)
		if _is_reachable(target):
			_move_target = target
			return true
	return false


func _pick_random_target() -> bool:
	var margin := radius + 6.0
	var inner := Rect2(
		room_bounds.position + Vector2(margin, margin),
		room_bounds.size - Vector2(margin * 2.0, margin * 2.0))
	if not inner.has_area():
		return false
	for _attempt in 15:
		var target := Vector2(
			randf_range(inner.position.x, inner.end.x),
			randf_range(inner.position.y, inner.end.y))
		if _is_reachable(target):
			_move_target = target
			return true
	return false


func _is_reachable(target: Vector2) -> bool:
	for rect in blocked_rects:
		if rect.has_point(target):
			return false
		if _path_crosses_rect(position, target, rect):
			return false
	return true


func _path_crosses_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var r_left := rect.position.x
	var r_right := rect.end.x
	var r_top := rect.position.y
	var r_bot := rect.end.y
	if (from.x < r_left and to.x > r_right) or (from.x > r_right and to.x < r_left):
		if maxf(from.y, to.y) > r_top and minf(from.y, to.y) < r_bot:
			return true
	if (from.y < r_top and to.y > r_bot) or (from.y > r_bot and to.y < r_top):
		if maxf(from.x, to.x) > r_left and minf(from.x, to.x) < r_right:
			return true
	return false


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
		_enter_state(State.IDLE, randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX))
	elif event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset


func _draw() -> void:
	var def := ColorRegistry.get_def(color_type)
	var base_color: Color = def.get("display_color", Color.WHITE)
	var next_id: String = def.get("shifts_to", "")
	var bar_w := radius * 2.0

	var draw_color := base_color
	if not next_id.is_empty() and shift_meter > 0.0:
		var next_color: Color = ColorRegistry.get_def(next_id).get("display_color", Color.WHITE)
		draw_color = base_color.lerp(next_color, shift_meter / 100.0)

	match level:
		1: _draw_circle_body(draw_color)
		2: _draw_square_body(draw_color)
		3: _draw_triangle_body(draw_color)

	if is_being_influenced and shift_meter > 1.0:
		var dir: Vector2 = (influence_attractor - global_position).normalized()
		var arrow_start: Vector2 = dir * (radius + 4.0)
		var arrow_end: Vector2 = dir * (radius + 14.0)
		draw_line(arrow_start, arrow_end, Color(1, 1, 1, 0.35), 2.0)

	if _state == State.IDLE:
		draw_string(ThemeDB.fallback_font,
			Vector2(radius * 0.4, -radius - 14.0), "zzz",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.4, 0.7))

	var shift_y := -radius - 12.0
	var shift_fill := _get_shift_fill_color(next_id)
	_draw_bar(-radius, shift_y, bar_w, shift_meter / 100.0, shift_fill, Color(0.25, 0.25, 0.25, 0.5))

	var hp_y := radius + 5.0
	var hp_ratio := health / max_health if max_health > 0.0 else 1.0
	var hp_color := Color(0.3, 0.8, 0.35) if hp_ratio > 0.5 else Color(0.85, 0.25, 0.2)
	_draw_bar(-radius, hp_y, bar_w, hp_ratio, hp_color, Color(0.25, 0.25, 0.25, 0.5))

	draw_string(ThemeDB.fallback_font,
		Vector2(radius + 4.0, hp_y + BAR_H),
		str(int(health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.6, 0.6, 0.6, 0.8))

	if color_type == "red" and kill_count > 0:
		draw_string(ThemeDB.fallback_font,
			Vector2(-radius, radius + 18.0),
			"K:%d" % kill_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.8, 0.4, 0.3, 0.7))

	if color_type == "yellow" and leveling_meter > 0.01:
		var ly := radius + 18.0
		_draw_bar(-radius, ly, bar_w, leveling_meter / YELLOW_LEVEL_TIME,
			Color(0.94, 0.84, 0.12), Color(0.25, 0.2, 0.05, 0.5))


func _draw_circle_body(col: Color) -> void:
	draw_circle(Vector2.ZERO, radius, col)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.12, 0.12, 0.12), 2.0, true)

func _draw_square_body(col: Color) -> void:
	var r := radius * 0.85
	draw_rect(Rect2(-r, -r, r * 2, r * 2), col)
	draw_rect(Rect2(-r, -r, r * 2, r * 2), Color(0.12, 0.12, 0.12), false, 2.0)

func _draw_triangle_body(col: Color) -> void:
	var r := radius * 1.0
	var pts := PackedVector2Array([
		Vector2(0, -r),
		Vector2(r * 0.866, r * 0.5),
		Vector2(-r * 0.866, r * 0.5),
	])
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]),
		Color(0.12, 0.12, 0.12), 2.0)

func _draw_bar(x: float, y: float, w: float, ratio: float, fill_color: Color, track_color: Color) -> void:
	draw_rect(Rect2(x, y, w, BAR_H), track_color)
	if ratio > 0.001:
		draw_rect(Rect2(x, y, w * clampf(ratio, 0.0, 1.0), BAR_H), fill_color)
	draw_rect(Rect2(x, y, w, BAR_H), Color(0.12, 0.12, 0.12, 0.6), false, 1.0)

func _get_shift_fill_color(next_id: String) -> Color:
	if next_id.is_empty():
		return Color(0.5, 0.5, 0.5, 0.3)
	return ColorRegistry.get_def(next_id).get("display_color", Color.WHITE)
