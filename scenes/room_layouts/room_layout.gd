@tool
extends Node2D
class_name RoomLayout

@export var preview_size: Vector2 = Vector2(1350.0, 1350.0)
@export var preview_fill_color: Color = Color(0.14, 0.14, 0.16, 0.2)
@export var preview_border_color: Color = Color(0.45, 0.45, 0.5, 0.8)
@export var preview_grid_color: Color = Color(0.4, 0.4, 0.45, 0.18)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if preview_size.x <= 0.0 or preview_size.y <= 0.0:
		return
	var rect := Rect2(Vector2.ZERO, preview_size)
	draw_rect(rect, preview_fill_color, true)
	draw_rect(rect, preview_border_color, false, 2.0)
	draw_line(Vector2(preview_size.x * 0.5, 0.0), Vector2(preview_size.x * 0.5, preview_size.y), preview_grid_color, 1.0)
	draw_line(Vector2(0.0, preview_size.y * 0.5), Vector2(preview_size.x, preview_size.y * 0.5), preview_grid_color, 1.0)


func get_spawn_markers() -> Array:
	var markers: Array = []
	_collect_spawn_markers(self, markers)
	markers.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return markers


func get_room_position_for_marker(marker: Node2D, room_pos: Vector2, room_size: Vector2) -> Vector2:
	var local_pos: Vector2 = to_local(marker.global_position)
	var px: float = 0.0 if preview_size.x <= 0.0 else clampf(local_pos.x / preview_size.x, 0.0, 1.0)
	var py: float = 0.0 if preview_size.y <= 0.0 else clampf(local_pos.y / preview_size.y, 0.0, 1.0)
	return room_pos + Vector2(px * room_size.x, py * room_size.y)


func _collect_spawn_markers(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.get("spawn_kind") != null:
			out.append(child)
		_collect_spawn_markers(child, out)
