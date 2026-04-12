extends ResourceBuilding
class_name FishingHut

@onready var _stored_label: Label = $StoredLabel

func _ready() -> void:
	deposit_radius = 70.0
	accepted_resource = "fish"


func _on_deposit(fid: int, amount: int) -> void:
	Economy.add_fish(amount, fid)


func _process(_delta: float) -> void:
	if _stored_label:
		_stored_label.text = "Stored: %d" % stored_total
	queue_redraw()


func _draw() -> void:
	# Dynamic overlays: deposit radius ring + selection pulse
	draw_arc(Vector2.ZERO, deposit_radius, 0.0, TAU, 32, Color(0.3, 0.5, 0.7, 0.12), 1.0, true)
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 60.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, pulse), 2.5, true)
