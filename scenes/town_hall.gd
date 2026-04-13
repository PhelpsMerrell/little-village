extends HousingBuilding
class_name TownHall
## The faction's HQ building. Magic orb starts inside.
## Larger capacity and visual footprint than a regular Home.

@onready var _count_label: Label = $CountLabel


func _ready() -> void:
	capacity = 8
	intake_radius = 90.0


func can_house_villager(v: Node) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	if is_full():
		return false
	if v in sheltered:
		return false
	if not "faction_id" in v:
		return false
	# Town Hall (preplaced -2) accepts any faction; owned checks match
	if placed_by_faction >= 0 and int(v.faction_id) != placed_by_faction:
		return false
	if placed_by_faction == -1:
		return false
	return true


func _process(_delta: float) -> void:
	if _count_label:
		_count_label.text = "%d/%d" % [get_sheltered_count(), capacity]
	queue_redraw()


func _draw() -> void:
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 70.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.3, pulse), 3.0, true)
