extends Node2D
class_name RoomTemplate
## Base class for room shape templates.
## Each template defines a set of grid cells (Vector2i offsets from origin).
## The map generator picks from these to create varied room shapes.
## Open in the editor to see the visual preview and tweak layout.

## Cell offsets relative to origin (0,0). Each Vector2i is a grid cell.
@export var cells: Array[Vector2i] = [Vector2i(0, 0)]

## Preview cell size in the editor (visual only, not used at runtime)
const PREVIEW_CELL := 64


func _ready() -> void:
	# Templates are data-only; remove from tree after being read
	pass


func get_cells() -> Array[Vector2i]:
	return cells


func get_footprint_size() -> Vector2i:
	## Returns (width, height) in cells.
	if cells.is_empty():
		return Vector2i(1, 1)
	var min_c := Vector2i(999, 999)
	var max_c := Vector2i(-999, -999)
	for c in cells:
		min_c.x = mini(min_c.x, c.x)
		min_c.y = mini(min_c.y, c.y)
		max_c.x = maxi(max_c.x, c.x)
		max_c.y = maxi(max_c.y, c.y)
	return max_c - min_c + Vector2i(1, 1)


func _draw() -> void:
	# Editor preview: draw colored cells
	if not Engine.is_editor_hint():
		return
	for c in cells:
		var rect := Rect2(Vector2(c) * PREVIEW_CELL, Vector2(PREVIEW_CELL, PREVIEW_CELL))
		draw_rect(rect, Color(0.25, 0.3, 0.35, 0.5))
		draw_rect(rect, Color(0.4, 0.5, 0.55, 0.8), false, 2.0)
