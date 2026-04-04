extends Node2D
## A single villager circle with state machine, movement, dragging, and HUD bars.

enum State { MOVING, PAUSED, IDLE }

const SPEED_SCALE := 8.0        # px/s per movement_speed unit
const PAUSE_TIME_MIN := 1.2
const PAUSE_TIME_MAX := 3.5
const IDLE_TIME_MIN := 3.0
const IDLE_TIME_MAX := 6.0
const BAR_H := 5.0

@export var color_type: String = "red"

var shift_meter: float = 0.0
var health: float = 0.0
var max_health: float = 0.0
var can_drag: bool = true
var current_room_id: int = -1
var radius: float = 22.0

# Movement / state
var room_bounds: Rect2 = Rect2()
var blocked_rects: Array = []        # set by main each frame
var _state: State = State.PAUSED
var _state_timer: float = randf_range(0.3, 1.5)
var _move_target: Vector2 = Vector2.ZERO
var _move_speed: float = 0.0

# Drag
var _dragging := false
var _drag_offset := Vector2.ZERO

@onready var _area: Area2D = $InputArea
@onready var _col_shape: CollisionShape2D = $InputArea/CollisionShape2D
@onready var _label: Label = $ShiftLabel


func _ready() -> void:
	_area.input_event.connect(_on_area_input)
	_sync_definition()


func setup(p_color: String, pos: Vector2) -> void:
	color_type = p_color
	position = pos
	shift_meter = 0.0
	_sync_definition()
	_state = State.PAUSED
	_state_timer = randf_range(0.3, 1.0)


func set_color_type(new_type: String) -> void:
	color_type = new_type
	shift_meter = 0.0
	_sync_definition()
	queue_redraw()


# ── sync with registry ───────────────────────────────────────────────────────

func _sync_definition() -> void:
	var def := ColorRegistry.get_def(color_type)
	can_drag = def.get("can_move", true)
	max_health = float(def.get("health", 100))
	health = max_health
	radius = float(def.get("radius", 22))
	_move_speed = float(def.get("movement_speed", 0)) * SPEED_SCALE
	# Resize collision shape
	if _col_shape:
		var shape := CircleShape2D.new()
		shape.radius = radius
		_col_shape.shape = shape
	# Reposition label
	if _label:
		_label.position = Vector2(-radius, -radius * 0.35)
		_label.size = Vector2(radius * 2.0, radius * 0.7)


# ── state machine ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _label:
		_label.text = str(int(shift_meter)) if shift_meter > 0.01 else ""

	if not _dragging and can_drag:
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
		_enter_state(State.PAUSED, randf_range(PAUSE_TIME_MIN, PAUSE_TIME_MAX))
	else:
		position += to_target.normalized() * step


func _do_paused(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		if _move_speed > 0.0 and room_bounds.has_area():
			if _pick_wander_target():
				_state = State.MOVING
			else:
				_state_timer = 0.5   # retry soon
		else:
			_state_timer = 2.0       # immobile — just wait


func _do_idle(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_enter_state(State.PAUSED, randf_range(0.3, 1.0))


func _enter_state(s: State, timer: float = 0.0) -> void:
	_state = s
	_state_timer = timer


# ── wander target picking ────────────────────────────────────────────────────

func _pick_wander_target() -> bool:
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
	# Check if from and to are on opposite sides of the rect (either axis)
	var r_left := rect.position.x
	var r_right := rect.end.x
	var r_top := rect.position.y
	var r_bot := rect.end.y
	# Vertical barrier (thin tall rect like water)
	if (from.x < r_left and to.x > r_right) or (from.x > r_right and to.x < r_left):
		# Check y overlap
		var min_y := minf(from.y, to.y)
		var max_y := maxf(from.y, to.y)
		if max_y > r_top and min_y < r_bot:
			return true
	# Horizontal barrier (thin wide rect like breakable wall)
	if (from.y < r_top and to.y > r_bot) or (from.y > r_bot and to.y < r_top):
		var min_x := minf(from.x, to.x)
		var max_x := maxf(from.x, to.x)
		if max_x > r_left and min_x < r_right:
			return true
	return false


# ── input ────────────────────────────────────────────────────────────────────

func _on_area_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if not can_drag:
		return
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


# ── drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var def := ColorRegistry.get_def(color_type)
	var base_color: Color = def.get("display_color", Color.WHITE)
	var next_id: String = def.get("shifts_to", "")
	var bar_w := radius * 2.0

	# ── circle body (lerps toward next color) ──
	var draw_color := base_color
	if not next_id.is_empty() and shift_meter > 0.0:
		var next_color: Color = ColorRegistry.get_def(next_id).get("display_color", Color.WHITE)
		draw_color = base_color.lerp(next_color, shift_meter / 100.0)
	draw_circle(Vector2.ZERO, radius, draw_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.12, 0.12, 0.12), 2.0, true)

	# ── idle indicator (small zzz) ──
	if _state == State.IDLE:
		draw_string(ThemeDB.fallback_font,
			Vector2(radius * 0.4, -radius - 14.0), "zzz",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.4, 0.7))

	# ── shift bar (above) ──
	var shift_y := -radius - 12.0
	var shift_fill := _get_shift_fill_color(next_id)
	_draw_bar(-radius, shift_y, bar_w, shift_meter / 100.0, shift_fill, Color(0.25, 0.25, 0.25, 0.5))

	# ── health bar (below) ──
	var hp_y := radius + 5.0
	var hp_ratio := health / max_health if max_health > 0.0 else 1.0
	var hp_color := Color(0.3, 0.8, 0.35) if hp_ratio > 0.5 else Color(0.85, 0.25, 0.2)
	_draw_bar(-radius, hp_y, bar_w, hp_ratio, hp_color, Color(0.25, 0.25, 0.25, 0.5))

	# ── tiny HP text ──
	draw_string(ThemeDB.fallback_font,
		Vector2(radius + 4.0, hp_y + BAR_H),
		str(int(health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(0.6, 0.6, 0.6, 0.8))


func _draw_bar(x: float, y: float, w: float, ratio: float, fill_color: Color, track_color: Color) -> void:
	draw_rect(Rect2(x, y, w, BAR_H), track_color)
	if ratio > 0.001:
		draw_rect(Rect2(x, y, w * clampf(ratio, 0.0, 1.0), BAR_H), fill_color)
	draw_rect(Rect2(x, y, w, BAR_H), Color(0.12, 0.12, 0.12, 0.6), false, 1.0)


func _get_shift_fill_color(next_id: String) -> Color:
	if next_id.is_empty():
		return Color(0.5, 0.5, 0.5, 0.3)
	return ColorRegistry.get_def(next_id).get("display_color", Color.WHITE)
