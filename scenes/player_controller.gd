extends Node
## PlayerController: owns selection state, command input, and camera reference.
## In solo, commands apply directly. In multiplayer, commands are queued
## through NetworkManager's lockstep system for fair simultaneous execution.

var faction_id: int = 0
var selected_villagers: Array = []
var _selected_resource: Node = null
var _selected_resource_type: String = ""
var selected_building: Node = null  ## Currently selected building (home or church)
var selected_door: Node = null      ## Currently selected door for reverse break-door assignment
var pending_combat_mode: String = ""  ## "attack" or "stun", set by HUD combat buttons


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
	TutorialManager.on_villager_selected()


func deselect_villager(v: Node) -> void:
	if v in selected_villagers:
		selected_villagers.erase(v)
		v.is_selected = false


func deselect_all() -> void:
	for v in selected_villagers:
		if is_instance_valid(v):
			v.is_selected = false
	selected_villagers.clear()
	deselect_building()
	deselect_door()


func has_selection() -> bool:
	return not selected_villagers.is_empty()


func select_building(b: Node) -> void:
	deselect_all()
	selected_building = b
	b.is_selected = true


func deselect_building() -> void:
	if selected_building != null and is_instance_valid(selected_building):
		selected_building.is_selected = false
	selected_building = null


func has_building_selection() -> bool:
	if selected_building != null and is_instance_valid(selected_building):
		return true
	selected_building = null
	return false


func select_door(door: Node) -> void:
	## Select a closed door for reverse break-door assignment.
	deselect_door()
	deselect_all()
	selected_door = door
	door.is_selected = true
	door.queue_redraw()


func deselect_door() -> void:
	if selected_door != null and is_instance_valid(selected_door):
		selected_door.is_selected = false
		selected_door.queue_redraw()
	selected_door = null


func has_door_selection() -> bool:
	if selected_door != null and is_instance_valid(selected_door) and not selected_door.is_open:
		return true
	deselect_door()
	return false


func command_move_to(target_pos: Vector2) -> void:
	if selected_villagers.is_empty():
		return
	if FactionManager.is_eliminated(faction_id):
		return
	TutorialManager.on_move_command()
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
	if FactionManager.is_eliminated(faction_id):
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
	if FactionManager.is_eliminated(faction_id):
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
	if FactionManager.is_eliminated(faction_id):
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
	if FactionManager.is_eliminated(faction_id):
		return false
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


func try_click_building(click_pos: Vector2, buildings: Array, _room_id_at: Callable) -> bool:
	## Try to select a building. Any building owned by local faction is selectable.
	if FactionManager.is_eliminated(faction_id):
		return false
	var best_b: Node = null
	var best_d: float = INF
	for b in buildings:
		if not is_instance_valid(b):
			continue
		var d: float = click_pos.distance_to(b.global_position)
		if d < 60.0 and d < best_d:
			best_d = d
			best_b = b
	if best_b:
		select_building(best_b)
		return true
	return false


func command_break_door(target_pos: Vector2, door_node: Node = null) -> void:
	## Send break-door command for selected red villagers.
	if selected_villagers.is_empty():
		return
	if FactionManager.is_eliminated(faction_id):
		return
	var red_ids: Array = []
	for v in selected_villagers:
		if is_instance_valid(v) and str(v.color_type) == "red":
			red_ids.append(v.net_id)
	if red_ids.is_empty():
		EventFeed.push("Only red villagers can break doors.", Color(0.9, 0.4, 0.3))
		return
	if NetworkManager.is_online() and not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "break_door",
			"net_ids": red_ids,
			"tx": target_pos.x,
			"ty": target_pos.y,
		})
	else:
		for v in selected_villagers:
			if is_instance_valid(v) and str(v.color_type) == "red":
				v.command_mode = "break_door"
				v.command_target = target_pos
				v.break_door_target = target_pos
				v.break_door_node = door_node
				v._arrived = false
	EventFeed.push("Red sent to break door.", Color(0.9, 0.5, 0.3))


func command_attack_target(target: Node) -> void:
	## Send attack command to all selected red villagers.
	if selected_villagers.is_empty() or FactionManager.is_eliminated(faction_id):
		return
	var red_ids: Array = []
	for v in selected_villagers:
		if is_instance_valid(v) and str(v.color_type) == "red":
			red_ids.append(v.net_id)
	if red_ids.is_empty():
		return
	if NetworkManager.is_online() and not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "attack",
			"net_ids": red_ids,
			"target_net_id": target.net_id,
		})
	else:
		for v in selected_villagers:
			if is_instance_valid(v) and str(v.color_type) == "red":
				v.command_attack(target)
	pending_combat_mode = ""
	EventFeed.push("Red attacking!", Color(0.9, 0.3, 0.2))


func command_stun_target(target: Node) -> void:
	## Send stun command to all selected blue villagers.
	if selected_villagers.is_empty() or FactionManager.is_eliminated(faction_id):
		return
	var blue_ids: Array = []
	for v in selected_villagers:
		if is_instance_valid(v) and str(v.color_type) == "blue":
			blue_ids.append(v.net_id)
	if blue_ids.is_empty():
		return
	if NetworkManager.is_online() and not NetworkManager.is_authority():
		NetworkManager.send_command({
			"type": "stun",
			"net_ids": blue_ids,
			"target_net_id": target.net_id,
		})
	else:
		for v in selected_villagers:
			if is_instance_valid(v) and str(v.color_type) == "blue":
				v.command_stun(target)
	pending_combat_mode = ""
	EventFeed.push("Blue stunning!", Color(0.3, 0.5, 0.9))


func has_selected_color(color: String) -> bool:
	for v in selected_villagers:
		if is_instance_valid(v) and str(v.color_type) == color:
			return true
	return false
