extends Node
## Tracks which rooms have been explored (visited by a player villager).
## Rooms are "active" if a villager is currently there, "explored" if visited before.

signal room_explored(room_id: int)

var explored_rooms: Dictionary = {}  # room_id -> true
var active_rooms: Dictionary = {}    # room_id -> true (has villager right now)


func mark_active(room_id: int) -> void:
	active_rooms[room_id] = true
	if not explored_rooms.has(room_id):
		explored_rooms[room_id] = true
		room_explored.emit(room_id)


func clear_active() -> void:
	active_rooms.clear()


func is_explored(room_id: int) -> bool:
	return explored_rooms.has(room_id)


func is_active(room_id: int) -> bool:
	return active_rooms.has(room_id)


## For save/load
func get_save_data() -> Array:
	return explored_rooms.keys()


func load_save_data(data: Array) -> void:
	explored_rooms.clear()
	for rid in data:
		explored_rooms[int(rid)] = true
