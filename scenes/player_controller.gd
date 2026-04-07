extends Node
## PlayerController: owns selection state, command input, and camera reference.
## In solo, commands apply directly. In multiplayer, commands are queued
## through NetworkManager's lockstep system for fair simultaneous execution.

var faction_id: int = 0
var selected_villagers: Array = []
var _selected_resource: Node = null
var _selected_resource_type: String = ""


func _get_selected_net_ids() -> Array:
	var ids: Array = []
	for v in selected_villagers:
		if is_instance_valid(v):
			ids.append(v.net_id)
	return ids


func select_villager(v: Node, additive: bool = false) -> void:
	if not additive:
		deselect_all()
	if v not in selected_villagers:
		selected_villagers.append(v)
		v.is_selected = true


func deselect_villager(v: Node) -> void:
	if v in selected_villagers:
		selected_villagers.erase(v)
		v.is_selected = false


func deselect_all() -> void:
	for v in selected_villagers:
		if is_instance_valid(v):
			v.is_selected = false
	selected_villagers.clear()


func has_selection() -> bool:
	return not selected_villagers.is_empty()


func command_move_to(target_pos: Vector2) -> void:
	if selected_villagers.is_empty():
		return
	if NetworkManager.is_online() and not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "move_to",
			"net_ids": _get_selected_net_ids(),
			"tx": target_pos.x,
			"ty": target_pos.y,
		})
	else:
		for v in selected_villagers:
			if is_instance_valid(v):
				v.command_move_to(target_pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
	EventFeed.push("Move command issued.", Color(0.6, 0.9, 0.6))


func command_hold() -> void:
	if selected_villagers.is_empty():
		return
	if NetworkManager.is_online() and not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "hold",
			"net_ids": _get_selected_net_ids(),
		})
	else:
		for v in selected_villagers:
			if is_instance_valid(v):
				if v.command_mode == "hold":
					v.command_release()
				else:
					v.command_hold()
	EventFeed.push("Hold command toggled.", Color(1.0, 0.8, 0.2))


func command_release() -> void:
	if selected_villagers.is_empty():
		return
	if NetworkManager.is_online() and not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "release",
			"net_ids": _get_selected_net_ids(),
		})
	else:
		for v in selected_villagers:
			if is_instance_valid(v):
				v.command_release()
	EventFeed.push("Commands cleared.", Color(0.7, 0.7, 0.7))


func command_enter_exit_house(homes: Array, churches: Array) -> void:
	if selected_villagers.is_empty():
		return
	if NetworkManager.is_online() and not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "enter_exit_house",
			"net_ids": _get_selected_net_ids(),
		})
	else:
		# Local path — apply directly (same logic as main._apply_house_command)
		var released_any := false
		for building in homes + churches:
			var to_release: Array = []
			for v in building.sheltered:
				if is_instance_valid(v) and v in selected_villagers:
					to_release.append(v)
			for v in to_release:
				building.sheltered.erase(v)
				v.visible = true
				v.set_process(true)
				v.global_position = building.global_position + Vector2(randf_range(-60, 60), randf_range(40, 80))
				released_any = true
		if released_any:
			EventFeed.push("Villagers exited building.", Color(0.7, 0.6, 0.4))
			return
		var sheltered_count := 0
		for v in selected_villagers:
			if not is_instance_valid(v) or not v.visible:
				continue
			var best_building: Node = null
			var best_bd: float = INF
			for b in homes + churches:
				if b.is_full():
					continue
				var d: float = v.global_position.distance_to(b.global_position)
				if d < best_bd:
					best_bd = d
					best_building = b
			if best_building:
				best_building.shelter_villager(v)
				sheltered_count += 1
		if sheltered_count > 0:
			EventFeed.push("%d villager(s) entered building." % sheltered_count, Color(0.7, 0.6, 0.4))


func try_click_villager(click_pos: Vector2, villagers: Array, shift_held: bool) -> bool:
	var clicked_villager: Node = null
	var best_d: float = INF
	for v in villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		if v.faction_id != faction_id:
			continue
		var d: float = click_pos.distance_to(v.global_position)
		if d < float(v.radius) + 10.0 and d < best_d:
			best_d = d
			clicked_villager = v
	if clicked_villager:
		if shift_held:
			if clicked_villager in selected_villagers:
				deselect_villager(clicked_villager)
			else:
				select_villager(clicked_villager, true)
		else:
			select_villager(clicked_villager, false)
		return true
	return false


func set_resource_selection(resource: Node, resource_type: String) -> void:
	_selected_resource = resource
	_selected_resource_type = resource_type


func clear_resource_selection() -> void:
	_selected_resource = null
	_selected_resource_type = ""


func get_selected_resource() -> Node:
	return _selected_resource


func get_selected_resource_type() -> String:
	return _selected_resource_type


func has_resource_selection() -> bool:
	if _selected_resource != null:
		if not is_instance_valid(_selected_resource) or _selected_resource.collected:
			clear_resource_selection()
			return false
		return true
	return false
