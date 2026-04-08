extends Node2D
## A wall segment between two rooms.
## Walls are solid barriers. Doors start CLOSED and must be broken by red villagers.

const WALL_THICKNESS := 6.0
const DOOR_THICKNESS := 8.0
const BREAK_RADIUS := 60.0  ## How close a red must be to break

@export var room_a_id: int = -1
@export var room_b_id: int = -1
@export var start_pos: Vector2 = Vector2.ZERO
@export var end_pos: Vector2 = Vector2.ZERO

var is_open: bool = false    ## True once broken/opened
var is_door: bool = false    ## Marks this segment as a breakable door (not solid wall)
var is_selected: bool = false  ## True when player has selected this door
var _hover: bool = false       ## True when mouse is hovering


func get_midpoint() -> Vector2:
	return (start_pos + end_pos) * 0.5


func break_door() -> void:
	## Called when a red villager breaks this door open.
	if is_door and not is_open:
		is_open = true
		is_selected = false
		queue_redraw()


func set_hovered(h: bool) -> void:
	if _hover != h:
		_hover = h
		queue_redraw()


func _ready() -> void:
	queue_redraw()

func _process(_delta: float) -> void:
	# Keep redrawing while selected (for pulsing animation)
	if is_selected or _hover:
		queue_redraw()


func _draw() -> void:
	if is_open:
		# Broken door — open gap with rubble marks
		var mid := get_midpoint()
		var dir := (end_pos - start_pos).normalized()
		var perp := Vector2(-dir.y, dir.x)
		# Frame posts at each end
		draw_line(start_pos - perp * 6, start_pos + perp * 6, Color(0.4, 0.3, 0.18, 0.5), 3.0)
		draw_line(end_pos - perp * 6, end_pos + perp * 6, Color(0.4, 0.3, 0.18, 0.5), 3.0)
		# Rubble dots
		for i in 3:
			var t: float = 0.25 + i * 0.25
			var p: Vector2 = start_pos.lerp(end_pos, t) + perp * (4.0 if i % 2 == 0 else -4.0)
			draw_circle(p, 2.5, Color(0.45, 0.35, 0.2, 0.35))

	elif is_door:
		# Unbroken door — thick barricade with planks
		var dir := (end_pos - start_pos).normalized()
		var perp := Vector2(-dir.y, dir.x)
		# Selection/hover glow underneath
		if is_selected:
			var pulse: float = 0.7 + sin(Time.get_ticks_msec() * 0.008) * 0.3
			draw_line(start_pos, end_pos, Color(1.0, 0.6, 0.0, pulse), DOOR_THICKNESS + 12)
			draw_line(start_pos, end_pos, Color(1.0, 0.85, 0.3, pulse * 0.5), DOOR_THICKNESS + 18)
		elif _hover:
			draw_line(start_pos, end_pos, Color(1.0, 0.7, 0.2, 0.4), DOOR_THICKNESS + 8)
		# Main barricade body (wider, warm brown — clearly distinct from stone walls)
		draw_line(start_pos, end_pos, Color(0.55, 0.3, 0.12), DOOR_THICKNESS + 4)
		# Plank lines across
		var seg_len := start_pos.distance_to(end_pos)
		var plank_count: int = maxi(2, int(seg_len / 30.0))
		for i in plank_count:
			var t: float = float(i + 1) / float(plank_count + 1)
			var p: Vector2 = start_pos.lerp(end_pos, t)
			draw_line(p - perp * (DOOR_THICKNESS * 0.7), p + perp * (DOOR_THICKNESS * 0.7),
				Color(0.35, 0.18, 0.08), 2.0)
		# Edge highlights
		draw_line(start_pos + perp * (DOOR_THICKNESS * 0.5 + 3), end_pos + perp * (DOOR_THICKNESS * 0.5 + 3),
			Color(0.7, 0.45, 0.2, 0.5), 1.5)
		draw_line(start_pos - perp * (DOOR_THICKNESS * 0.5 + 3), end_pos - perp * (DOOR_THICKNESS * 0.5 + 3),
			Color(0.25, 0.1, 0.02, 0.5), 1.5)
		# Label
		var mid := get_midpoint()
		var label_col: Color = Color(1.0, 0.7, 0.1, 0.95) if is_selected else Color(0.75, 0.45, 0.2, 0.7)
		var label_offset: Vector2 = perp * (DOOR_THICKNESS + 10)
		draw_string(ThemeDB.fallback_font, mid + label_offset + Vector2(-16, 4),
			"DOOR", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, label_col)
		if is_selected:
			draw_string(ThemeDB.fallback_font, mid + label_offset + Vector2(-24, 16),
				"[SELECTED]", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(1.0, 0.8, 0.2, 0.9))

	else:
		# Solid wall — dark stone, thicker, clearly impassable
		draw_line(start_pos, end_pos, Color(0.22, 0.18, 0.14), WALL_THICKNESS + 2)
		draw_line(start_pos, end_pos, Color(0.32, 0.26, 0.20), WALL_THICKNESS)
		var dir := (end_pos - start_pos).normalized()
		var perp := Vector2(-dir.y, dir.x) * (WALL_THICKNESS * 0.5)
		draw_line(start_pos + perp, end_pos + perp, Color(0.42, 0.36, 0.28, 0.45), 1.0)
		draw_line(start_pos - perp, end_pos - perp, Color(0.14, 0.10, 0.08, 0.5), 1.0)
