extends Node2D
## A toggleable wall segment between two rooms.
## Click to open/close. Influence is blocked by closed walls.

const WALL_THICKNESS := 6.0
const CLICK_PADDING := 14.0

@export var room_a_id: int = -1
@export var room_b_id: int = -1
@export var start_pos: Vector2 = Vector2.ZERO
@export var end_pos: Vector2 = Vector2.ZERO

var is_open: bool = false
var is_door: bool = false  ## Permanent opening — always open, can't be toggled

@onready var _area: Area2D = $ClickArea
@onready var _col: CollisionShape2D = $ClickArea/CollisionShape2D


func _ready() -> void:
	_area.input_event.connect(_on_input)
	_resize_click_area()


func _resize_click_area() -> void:
	var dir := end_pos - start_pos
	var length := dir.length()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length, WALL_THICKNESS + CLICK_PADDING * 2.0)
	_col.shape = shape
	_col.position = (start_pos + end_pos) * 0.5
	_col.rotation = dir.angle()
	queue_redraw()


func _on_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if is_door:
		return  # doors can't be toggled
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if NetworkManager.is_online() and not NetworkManager.is_authority():
			# Client: request wall toggle from host
			NetworkManager.send_command({
				"type": "wall_toggle",
				"room_a": room_a_id,
				"room_b": room_b_id,
				"sx": start_pos.x,
				"sy": start_pos.y,
			})
			return
		is_open = not is_open
		queue_redraw()


func _draw() -> void:
	if is_door:
		# Draw door frame markers at each end of the opening
		var dir := (end_pos - start_pos).normalized()
		var perp := Vector2(-dir.y, dir.x) * 6.0
		var frame_col := Color(0.45, 0.35, 0.2, 0.7)
		draw_line(start_pos - perp, start_pos + perp, frame_col, 3.0)
		draw_line(end_pos - perp, end_pos + perp, frame_col, 3.0)
		return

	if is_open:
		var dir := (end_pos - start_pos).normalized()
		var length := start_pos.distance_to(end_pos)
		var dash := 12.0
		var gap := 8.0
		var d := 0.0
		while d < length:
			var a := start_pos + dir * d
			var b := start_pos + dir * minf(d + dash, length)
			draw_line(a, b, Color(0.5, 0.5, 0.5, 0.25), 2.0)
			d += dash + gap
	else:
		draw_line(start_pos, end_pos, Color(0.28, 0.22, 0.18), WALL_THICKNESS)

	# Toggle indicator dot
	var mid := (start_pos + end_pos) * 0.5
	var dot_color := Color(0.3, 0.72, 0.35, 0.6) if is_open else Color(0.72, 0.3, 0.3, 0.6)
	draw_circle(mid, 7.0, dot_color)
