extends BuildingBase
class_name ResourceBuilding
## Shared base for dropoff / production buildings.

@export var deposit_radius: float = 60.0
@export var accepted_resource: String = ""

var stored_total: int = 0


func supports_resource_dropoff() -> bool:
	return true


func accepts_villager(v: Node) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	if placed_by_faction < 0:
		return false
	if not "faction_id" in v:
		return false
	if int(v.faction_id) != placed_by_faction:
		return false
	if not "carrying_resource" in v:
		return false
	return str(v.carrying_resource) == accepted_resource


func try_deposit(v: Node) -> bool:
	if not accepts_villager(v):
		return false
	if v.global_position.distance_to(global_position) > deposit_radius:
		return false

	v.carrying_resource = ""
	stored_total += 1
	_on_deposit(int(v.faction_id), 1)
	return true


func _on_deposit(_fid: int, _amount: int) -> void:
	pass
