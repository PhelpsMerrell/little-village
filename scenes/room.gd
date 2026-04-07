extends Node2D
## Room with ownership border visualization.

@export var room_id: int = 0
@export var room_size: Vector2 = Vector2(1350, 1350)
@export var room_color: Color = Color(0.15, 0.15, 0.15, 0.35)
@export var room_label: String = ""

@onready var _bg: ColorRect = $Background


func _ready() -> void:
	_bg.size = room_size
	_bg.color = room_color
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE


func get_rect() -> Rect2:
	return Rect2(global_position, room_size)


func get_blocked_rects_for(color_id: String) -> Array:
	var rects: Array = []
	for child in get_children():
		if child.has_method("get_blocked_rect") and child.has_method("blocks_color"):
			if child.blocks_color(color_id):
				rects.append(child.get_blocked_rect())
	return rects


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var label := room_label if not room_label.is_empty() else ("Room %d" % room_id)
	draw_string(ThemeDB.fallback_font, Vector2(10, 22), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.45, 0.45, 0.45, 0.6))

	# Draw border based on ownership
	var owner_fid: int = RoomOwnership.get_room_owner(room_id)
	if owner_fid >= 0:
		var fc: Color = FactionManager.get_faction_color(owner_fid)
		fc.a = 0.7
		draw_rect(Rect2(Vector2.ZERO, room_size), fc, false, 4.0)
		# Faction symbol in corner
		var sym: String = FactionManager.get_faction_symbol(owner_fid)
		draw_string(ThemeDB.fallback_font, Vector2(room_size.x - 30, 22), sym,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, fc)
	else:
		draw_rect(Rect2(Vector2.ZERO, room_size), Color(0.3, 0.3, 0.3, 0.4), false, 2.0)

	# Capture progress bar
	var cap_ratio: float = RoomOwnership.get_capture_progress_ratio(room_id)
	if cap_ratio > 0.01:
		var cap_fid: int = RoomOwnership.get_capture_faction(room_id)
		var cap_col: Color = FactionManager.get_faction_color(cap_fid) if cap_fid >= 0 else Color.WHITE
		cap_col.a = 0.5
		var bar_w: float = room_size.x * 0.6
		var bar_x: float = room_size.x * 0.2
		var bar_y: float = room_size.y - 16.0
		draw_rect(Rect2(bar_x, bar_y, bar_w, 8), Color(0.15, 0.15, 0.15, 0.5))
		draw_rect(Rect2(bar_x, bar_y, bar_w * cap_ratio, 8), cap_col)
