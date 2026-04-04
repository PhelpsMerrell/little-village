extends Node2D
## Drag-drop water obstacle. Place as child of a Room.
## Only "swim" ability villagers can cross.

@export var water_size: Vector2 = Vector2(60, 1350)  ## width × height of the water area
@export var blocked_ability: String = "swim"          ## ability that bypasses this


func get_blocked_rect() -> Rect2:
	return Rect2(global_position, water_size)


func blocks_color(color_id: String) -> bool:
	return not ColorRegistry.has_ability(color_id, blocked_ability)


func _draw() -> void:
	# Water fill
	draw_rect(Rect2(Vector2.ZERO, water_size), Color(0.15, 0.35, 0.6, 0.45))
	# Wavy lines
	var y := 8.0
	while y < water_size.y:
		var wave_x := sin(y * 0.06) * 8.0
		draw_line(Vector2(wave_x + 10, y), Vector2(wave_x + water_size.x - 10, y),
			Color(0.3, 0.55, 0.85, 0.25), 1.0)
		y += 18.0
	# Border
	draw_rect(Rect2(Vector2.ZERO, water_size), Color(0.2, 0.4, 0.7, 0.4), false, 2.0)
