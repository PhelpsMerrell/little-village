extends Node2D
class_name BuildingBase
## Shared base for every player-placeable building.

@export var placed_by_faction: int = -1 ## -2 = preplaced, -1 = neutral, >= 0 = owned
@export var is_selected: bool = false

@onready var _area: Area2D = $InputArea if has_node("InputArea") else null


var _prev_selected: bool = false

func _process(_delta: float) -> void:
	_check_selection_redraw()


func _check_selection_redraw() -> void:
	## Call from subclass _process to handle selection change redraws.
	if is_selected != _prev_selected:
		_prev_selected = is_selected
		queue_redraw()
	elif is_selected:
		queue_redraw()  # Pulse animation


func is_sellable() -> bool:
	return placed_by_faction != -2


func belongs_to_faction(fid: int) -> bool:
	return placed_by_faction >= 0 and placed_by_faction == fid


func can_player_sell(fid: int) -> bool:
	return is_sellable() and belongs_to_faction(fid)


func can_player_interact(fid: int) -> bool:
	return belongs_to_faction(fid)


func supports_housing() -> bool:
	return false


func supports_resource_dropoff() -> bool:
	return false


func get_capacity() -> int:
	return 0


func get_sheltered_count() -> int:
	return 0


func is_full() -> bool:
	return false


func evict_all() -> void:
	pass
