extends BuildingBase
class_name HousingBuilding
## Shared base for buildings that can shelter villagers.

@export var capacity: int = 4
@export var intake_radius: float = 60.0

var sheltered: Array = []


func supports_housing() -> bool:
	return true


func get_capacity() -> int:
	return capacity


func get_sheltered_count() -> int:
	sheltered = sheltered.filter(func(v): return is_instance_valid(v))
	return sheltered.size()


func is_full() -> bool:
	return get_sheltered_count() >= capacity


func can_house_villager(v: Node) -> bool:
	if v == null or not is_instance_valid(v):
		return false
	if is_full():
		return false
	if v in sheltered:
		return false
	if not "faction_id" in v:
		return false
	if placed_by_faction == -1:
		return false  # Neutral/unassigned
	# Preplaced (-2) accepts any faction; owned checks match
	if placed_by_faction >= 0 and int(v.faction_id) != placed_by_faction:
		return false
	return true


func try_house_villager(v: Node) -> bool:
	if not can_house_villager(v):
		return false

	sheltered.append(v)
	v.visible = false
	v.set_process(false)

	if "command_mode" in v:
		v.command_mode = "none"
	if "command_target" in v:
		v.command_target = Vector2.ZERO
	if v.has_method("clear_command"):
		v.clear_command()

	return true


func release_villager(v: Node) -> void:
	if v not in sheltered:
		return

	sheltered.erase(v)
	if not is_instance_valid(v):
		return

	v.visible = true
	v.set_process(true)
	v.global_position = global_position + Vector2(
		randf_range(-70.0, 70.0),
		randf_range(40.0, 95.0)
	)


func release_all() -> void:
	for v in sheltered:
		if is_instance_valid(v):
			v.visible = true
			v.set_process(true)
			v.global_position = global_position + Vector2(
				randf_range(-70.0, 70.0),
				randf_range(40.0, 95.0)
			)
	sheltered.clear()


func evict_all() -> void:
	release_all()
