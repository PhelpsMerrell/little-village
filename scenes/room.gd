extends Node2D
## Drag-droppable room. Place in scene, set room_id and size in inspector.
## Drop obstacles (water, breakable wall) as children.

@export var room_id: int = 0
@export var room_size: Vector2 = Vector2(1350, 1350)
@export var room_color: Color = Color(0.15, 0.15, 0.15, 0.35)
@export var room_label: String = ""

@onready var _bg: ColorRect = $Background


func _ready() -> void:
	_bg.size = room_size
	_bg.color = room_color
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func get_rect() -> Rect2:
	return Rect2(global_position, room_size)


## Collect blocked rects from all child obstacles for a given color.
func get_blocked_rects_for(color_id: String) -> Array:
	var rects: Array = []
	for child in get_children():
		if child.has_method("get_blocked_rect") and child.has_method("blocks_color"):
			if child.blocks_color(color_id):
				rects.append(child.get_blocked_rect())
	return rects


func _draw() -> void:
	var label := room_label if not room_label.is_empty() else ("Room %d" % room_id)
	draw_string(ThemeDB.fallback_font, Vector2(10, 22), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.45, 0.45, 0.6))
	draw_rect(Rect2(Vector2.ZERO, room_size), Color(0.3, 0.3, 0.3, 0.4), false, 2.0)
