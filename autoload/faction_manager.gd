extends Node
## Manages factions/teams. Solo play uses faction 0 (local player).
## Multiplayer will assign players to factions via lobby.

const LOCAL_FACTION_ID := 0

const FACTION_SYMBOLS: Array[String] = ["$", "@", "?", "¥", "£", "€", "#", "%"]

var factions: Dictionary = {}  # faction_id -> FactionData
var local_faction_id: int = LOCAL_FACTION_ID
var max_population: int = 50  ## Per-faction max pop, set from lobby


func _ready() -> void:
	# Default solo faction
	register_faction(LOCAL_FACTION_ID, "Player", Color(1, 1, 1))


func register_faction(id: int, faction_name: String, faction_color: Color) -> void:
	factions[id] = {
		"id": id,
		"name": faction_name,
		"color": faction_color,
		"player_ids": [],  # for multiplayer: which players control this faction
	}


func get_faction(id: int) -> Dictionary:
	return factions.get(id, {})


func get_faction_name(id: int) -> String:
	return factions.get(id, {}).get("name", "Unknown")


func get_faction_color(id: int) -> Color:
	return factions.get(id, {}).get("color", Color.WHITE)


func get_faction_symbol(id: int) -> String:
	if id >= 0 and id < FACTION_SYMBOLS.size():
		return FACTION_SYMBOLS[id]
	return "?"


func is_local_faction(faction_id: int) -> bool:
	if faction_id < 0:
		return false  # unowned (e.g. colorless in multi-faction)
	return faction_id == local_faction_id


func get_all_faction_ids() -> Array:
	return factions.keys()


func clear() -> void:
	factions.clear()
	register_faction(LOCAL_FACTION_ID, "Player", Color(1, 1, 1))
