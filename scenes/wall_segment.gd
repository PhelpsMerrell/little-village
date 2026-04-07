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


func get_midpoint() -> Vector2:
	return (start_pos + end_pos) * 0.5


func break_door() -> void:
	## Called when a red villager breaks this door open.
	if is_door and not is_open:
		is_open = true
		queue_redraw()


func _ready() -> void:
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
		# Unbroken door — thick barricade with planks, clearly different from walls
		var dir := (end_pos - start_pos).normalized()
		var perp := Vector2(-dir.y, dir.x)
		# Main barricade body (wider than wall, reddish-brown)
		draw_line(start_pos, end_pos, Color(0.5, 0.28, 0.12), DOOR_THICKNESS + 4)
		# Plank lines across
		var seg_len := start_pos.distance_to(end_pos)
		var plank_count: int = maxi(2, int(seg_len / 30.0))
		for i in plank_count:
			var t: float = float(i + 1) / float(plank_count + 1)
			var p: Vector2 = start_pos.lerp(end_pos, t)
			draw_line(p - perp * (DOOR_THICKNESS * 0.6), p + perp * (DOOR_THICKNESS * 0.6),
				Color(0.35, 0.18, 0.08), 2.0)
		# Edge highlights
		draw_line(start_pos + perp * (DOOR_THICKNESS * 0.5 + 2), end_pos + perp * (DOOR_THICKNESS * 0.5 + 2),
			Color(0.6, 0.35, 0.15, 0.4), 1.5)
		draw_line(start_pos - perp * (DOOR_THICKNESS * 0.5 + 2), end_pos - perp * (DOOR_THICKNESS * 0.5 + 2),
			Color(0.3, 0.15, 0.05, 0.4), 1.5)
		# "BREAK" hint text at midpoint
		var mid := get_midpoint()
		draw_string(ThemeDB.fallback_font, mid + Vector2(-16, -DOOR_THICKNESS - 4),
			"DOOR", HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color(0.7, 0.4, 0.2, 0.6))

	else:
		# Solid wall — cannot be broken
		draw_line(start_pos, end_pos, Color(0.32, 0.26, 0.2), WALL_THICKNESS)
		var dir := (end_pos - start_pos).normalized()
		var perp := Vector2(-dir.y, dir.x) * (WALL_THICKNESS * 0.5)
		draw_line(start_pos + perp, end_pos + perp, Color(0.4, 0.34, 0.26, 0.4), 1.0)
		draw_line(start_pos - perp, end_pos - perp, Color(0.2, 0.16, 0.12, 0.4), 1.0)
