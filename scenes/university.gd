extends HousingBuilding
class_name University
## Trains red villagers overnight. Each night spent raises fire rate by 1%.

const FIRE_RATE_BONUS_PER_NIGHT := 0.01  ## 1% faster cooldown per stay

@onready var _count_label: Label = $CountLabel


func _ready() -> void:
	capacity = 6
	intake_radius = 65.0


func can_house_villager(v: Node) -> bool:
	if not super.can_house_villager(v):
		return false
	# Only trains reds
	return str(v.color_type) == "red"


func apply_training() -> void:
	## Called at dawn — buff all sheltered reds' fire rate.
	for v in sheltered:
		if not is_instance_valid(v):
			continue
		if str(v.color_type) != "red":
			continue
		v.fire_rate_bonus += FIRE_RATE_BONUS_PER_NIGHT


var _prev_count_text: String = ""

func _process(_delta: float) -> void:
	if _count_label:
		var txt: String = "%d/%d" % [get_sheltered_count(), capacity]
		if txt != _prev_count_text:
			_prev_count_text = txt
			_count_label.text = txt
	_check_selection_redraw()
	# Training glow animation when reds are sheltered
	if not is_selected:
		for v in sheltered:
			if is_instance_valid(v) and str(v.color_type) == "red":
				queue_redraw()
				break


func _draw() -> void:
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 55.0, 0.0, TAU, 24, Color(0.9, 0.6, 0.2, pulse), 2.5, true)

	# Training glow when reds are inside
	var has_reds := false
	for v in sheltered:
		if is_instance_valid(v) and str(v.color_type) == "red":
			has_reds = true
			break
	if has_reds:
		draw_arc(Vector2.ZERO, intake_radius, 0.0, TAU, 32,
			Color(0.9, 0.4, 0.2, 0.15 + sin(Time.get_ticks_msec() * 0.003) * 0.08), 2.0, true)
