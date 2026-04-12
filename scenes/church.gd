extends HousingBuilding
class_name Church

const HEAL_RATE := 10.0

@onready var _count_label: Label = $CountLabel

func _ready() -> void:
	capacity = 8
	intake_radius = 70.0


func heal_tick(delta: float) -> void:
	var to_release: Array = []
	for v in sheltered:
		if not is_instance_valid(v):
			continue
		if str(v.color_type) != "blue":
			continue
		v.health = minf(v.health + HEAL_RATE * delta, v.max_health)
		if v.health >= v.max_health:
			to_release.append(v)
	for v in to_release:
		release_villager(v)


func _process(_delta: float) -> void:
	if _count_label:
		_count_label.text = "%d/%d" % [get_sheltered_count(), capacity]
	queue_redraw()


func _draw() -> void:
	# Dynamic overlays: selection pulse, healing glow, intake radius
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 60.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, pulse), 2.5, true)

	var has_blues := false
	for v in sheltered:
		if is_instance_valid(v) and str(v.color_type) == "blue":
			has_blues = true
			break
	if has_blues:
		draw_arc(Vector2.ZERO, intake_radius, 0.0, TAU, 32,
			Color(0.3, 0.5, 0.9, 0.2 + sin(Time.get_ticks_msec() * 0.003) * 0.1), 2.0, true)

	draw_arc(Vector2.ZERO, intake_radius, 0.0, TAU, 32, Color(0.3, 0.4, 0.8, 0.1), 1.0, true)
