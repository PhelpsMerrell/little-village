extends Node
## Central registry for all villager color types.
## Add new color types here -- the rest of the system reads from this.

var _color_types: Dictionary = {}


func _ready() -> void:
	_register_defaults()


func _register_defaults() -> void:
	register({
		"id": "red",
		"display_color": Color(0.9, 0.22, 0.2),
		"radius": 35.0,
		"health": 50,
		"movement_speed": 6.0,
		"shifts_to": "yellow",
		"influence_targets": ["blue", "colorless"],
		"on_shift_spawn_count": 2,
		"influence_delivery": "standard",
		"influence_rate": 1.0,
		"stacking_bonus": 0.1,
		"can_move": true,
		"special_abilities": ["damage", "break_walls"],
		"negates_influences": [],
	})

	register({
		"id": "yellow",
		"display_color": Color(0.94, 0.84, 0.12),
		"radius": 27.0,
		"health": 15,
		"movement_speed": 10.0,
		"shifts_to": "blue",
		"influence_targets": ["red", "colorless"],
		"on_shift_spawn_count": 1,
		"influence_delivery": "single_target",
		"influence_rate": 0.6,
		"stacking_bonus": 0.0,
		"can_move": true,
		"special_abilities": [],
		"negates_influences": [],
	})

	register({
		"id": "blue",
		"display_color": Color(0.2, 0.4, 0.9),
		"radius": 45.0,
		"health": 200,
		"movement_speed": 3.0,
		"shifts_to": "red",
		"influence_targets": ["yellow", "colorless"],
		"on_shift_spawn_count": 1,
		"influence_delivery": "standard",
		"influence_rate": 1.0,
		"stacking_bonus": 0.1,
		"can_move": true,
		"special_abilities": ["swim", "move_boulders"],
		"negates_influences": [],
	})

	# Colorless villager: fast shifter, joins whatever color group it shifts to.
	# Shifts into the cycle: colorless -> red -> yellow -> blue -> red ...
	# Low HP, medium speed, small. Finding a group = free numbers.
	register({
		"id": "colorless",
		"display_color": Color(0.75, 0.75, 0.75),
		"radius": 25.0,
		"health": 25,
		"movement_speed": 7.0,
		"shifts_to": "red",
		"influence_targets": [],
		"on_shift_spawn_count": 1,
		"influence_delivery": "standard",
		"influence_rate": 0.0,
		"stacking_bonus": 0.0,
		"can_move": true,
		"special_abilities": [],
		"negates_influences": [],
		"fast_shifter": true,  # shifts at 3x speed
	})

	# Magic Orb: stationary influence catalyst. Not a villager.
	# Accelerates all nearby villagers' shifts. Cannot move, cannot shift.
	register({
		"id": "magic_orb",
		"display_color": Color(0.82, 0.82, 0.82),
		"radius": 25.0,
		"health": 100,
		"movement_speed": 0.0,
		"shifts_to": "",
		"influence_targets": ["red", "yellow", "blue", "colorless"],
		"on_shift_spawn_count": 1,
		"influence_delivery": "standard",
		"influence_rate": 2.0,
		"stacking_bonus": 0.1,
		"can_move": false,
		"special_abilities": [],
		"negates_influences": [],
	})


func register(definition: Dictionary) -> void:
	_color_types[definition["id"]] = definition


func get_def(color_id: String) -> Dictionary:
	return _color_types.get(color_id, {})


func get_all_ids() -> Array:
	return _color_types.keys()


func has_ability(color_id: String, ability: String) -> bool:
	var def := get_def(color_id)
	return ability in def.get("special_abilities", [])
