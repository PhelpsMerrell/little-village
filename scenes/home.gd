extends HousingBuilding
class_name Home

@onready var _count_label: Label = $CountLabel

func _ready() -> void:
	capacity = 4
	intake_radius = 60.0


var _prev_count_text: String = ""

func _process(_delta: float) -> void:
	if _count_label:
		var txt: String = "%d/%d" % [get_sheltered_count(), capacity]
		if txt != _prev_count_text:
			_prev_count_text = txt
			_count_label.text = txt
	_check_selection_redraw()


func _draw() -> void:
	# Dynamic overlay: selection pulse only
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 50.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, pulse), 2.5, true)
