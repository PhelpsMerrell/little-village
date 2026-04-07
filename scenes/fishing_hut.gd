extends Node2D
## Fishing hut where blues deposit collected fish.
## Works like the stone bank but for fish resource.

const DEPOSIT_RADIUS := 70.0

@onready var _area: Area2D = $InputArea

var _dragging := false
var _drag_offset := Vector2.ZERO
var _deposits: int = 0


func _ready() -> void:
	_area.input_event.connect(_on_area_input)


func try_deposit(villager: Node) -> bool:
	if str(villager.color_type) != "blue":
		return false
	if str(villager.carrying_resource) != "fish":
		return false
	var dist: float = villager.global_position.distance_to(global_position)
	if dist < DEPOSIT_RADIUS:
		villager.carrying_resource = ""
		var fid: int = villager.faction_id if villager.faction_id >= 0 else 0
		Economy.add_fish(1, fid)
		_deposits += 1
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
	elif event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset


func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Hut base
	draw_rect(Rect2(-55, -25, 110, 55), Color(0.3, 0.25, 0.2))
	draw_rect(Rect2(-55, -25, 110, 55), Color(0.2, 0.15, 0.1), false, 2.0)
	# Roof
	var roof := PackedVector2Array([
		Vector2(0, -50),
		Vector2(60, -25),
		Vector2(-60, -25),
	])
	draw_colored_polygon(roof, Color(0.25, 0.35, 0.5))
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[0]]),
		Color(0.15, 0.2, 0.35), 2.0)
	# Fish icon on front
	draw_circle(Vector2(0, 5), 8.0, Color(0.3, 0.55, 0.75))
	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-35, -56), "FISHING HUT",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.6, 0.75, 0.9))
	# Count
	draw_string(ThemeDB.fallback_font, Vector2(-30, 48),
		"Fish: %d" % _deposits, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.5, 0.65, 0.7))
	# Radius hint
	draw_arc(Vector2.ZERO, DEPOSIT_RADIUS, 0.0, TAU, 32,
		Color(0.3, 0.5, 0.7, 0.12), 1.0, true)
