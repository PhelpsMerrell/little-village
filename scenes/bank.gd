extends ResourceBuilding
class_name Bank

@onready var _stored_label: Label = $StoredLabel

func _ready() -> void:
	deposit_radius = 60.0
	accepted_resource = "stone"  # primary resource


func accepts_villager(v: Node) -> bool:
	## Override: bank accepts stone, diamond, and grain.
	## Preplaced (-2) banks accept ANY faction.
	if v == null or not is_instance_valid(v):
		return false
	if placed_by_faction == -1:
		return false
	if not "faction_id" in v:
		return false
	if not "carrying_resource" in v:
		return false
	if placed_by_faction >= 0 and int(v.faction_id) != placed_by_faction:
		return false
	return str(v.carrying_resource) in ["stone", "diamond", "grain"]


func try_deposit(v: Node) -> bool:
	if not accepts_villager(v):
		return false
	if v.global_position.distance_to(global_position) > deposit_radius:
		return false
	var res_type: String = str(v.carrying_resource)
	v.carrying_resource = ""
	stored_total += 1
	_on_deposit_typed(int(v.faction_id), 1, res_type)
	return true


func _on_deposit_typed(fid: int, amount: int, res_type: String) -> void:
	if res_type == "diamond":
		Economy.add_diamonds(amount, fid)
	elif res_type == "grain":
		Economy.add_grain(amount, fid)
	else:
		Economy.add_stone(amount, fid)


func _on_deposit(fid: int, amount: int) -> void:
	Economy.add_stone(amount, fid)


var _prev_count_text: String = ""

func _process(_delta: float) -> void:
	if _stored_label:
		var txt: String = "Stored: %d" % stored_total
		if txt != _prev_count_text:
			_prev_count_text = txt
			_stored_label.text = txt
	_check_selection_redraw()


func _draw() -> void:
	# Dynamic overlays only: deposit radius ring + selection pulse
	draw_arc(Vector2.ZERO, deposit_radius, 0.0, TAU, 32, Color(0.6, 0.55, 0.3, 0.15), 1.0, true)
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 55.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, pulse), 2.5, true)
