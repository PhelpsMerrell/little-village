extends Node2D
## Room with ownership border visualization.

@export var room_id: int = 0
@export var room_size: Vector2 = Vector2(1350, 1350)
@export var room_color: Color = Color(0.15, 0.15, 0.15, 0.35)
@export var room_label: String = ""

@onready var _bg: ColorRect = $Background
@onready var _border: Line2D = $Border
@onready var _room_label: Label = $RoomLabel
@onready var _owner_symbol: Label = $OwnerSymbol


func _ready() -> void:
	_bg.size = room_size
	_bg.color = room_color
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Update border points to match room size
	_border.points = PackedVector2Array([
		Vector2.ZERO, Vector2(room_size.x, 0),
		room_size, Vector2(0, room_size.y), Vector2.ZERO])
	# Label
	var lbl := room_label if not room_label.is_empty() else ("Room %d" % room_id)
	_room_label.text = lbl
	# Owner symbol position
	_owner_symbol.offset_left = room_size.x - 40.0
	_owner_symbol.offset_right = room_size.x - 4.0


func get_rect() -> Rect2:
	return Rect2(global_position, room_size)


func get_blocked_rects_for(color_id: String) -> Array:
	var rects: Array = []
	for child in get_children():
		if child.has_method("get_blocked_rect") and child.has_method("blocks_color"):
			if child.blocks_color(color_id):
				rects.append(child.get_blocked_rect())
	return rects


var _prev_owner_fid: int = -99
var _prev_capture_ratio: float = -1.0


func _process(_delta: float) -> void:
	var owner_fid: int = RoomOwnership.get_room_owner(room_id)
	var cap_ratio: float = RoomOwnership.get_capture_progress_ratio(room_id)
	var changed: bool = (owner_fid != _prev_owner_fid or absf(cap_ratio - _prev_capture_ratio) > 0.005)
	if changed:
		_prev_owner_fid = owner_fid
		_prev_capture_ratio = cap_ratio
		_update_ownership_visuals()
		queue_redraw()


func _update_ownership_visuals() -> void:
	var owner_fid: int = RoomOwnership.get_room_owner(room_id)
	if owner_fid >= 0:
		var fc: Color = FactionManager.get_faction_color(owner_fid)
		fc.a = 0.7
		_border.default_color = fc
		_border.width = 4.0
		_owner_symbol.text = FactionManager.get_faction_symbol(owner_fid)
		_owner_symbol.add_theme_color_override("font_color", fc)
		_owner_symbol.visible = true
	else:
		_border.default_color = Color(0.3, 0.3, 0.3, 0.4)
		_border.width = 2.0
		_owner_symbol.visible = false


func _draw() -> void:
	# Dynamic overlay: capture progress bar only
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
