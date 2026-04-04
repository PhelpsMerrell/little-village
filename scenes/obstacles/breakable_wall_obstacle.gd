extends Node2D
## Drag-drop breakable wall obstacle. Place as child of a Room.
## Villagers with "break_walls" ability destroy it on contact.

@export var wall_size: Vector2 = Vector2(1350, 14)    ## width × height
@export var required_ability: String = "break_walls"  ## ability that breaks this
@export var break_radius: float = 40.0                ## how close to trigger break

var is_intact: bool = true


func get_blocked_rect() -> Rect2:
	if is_intact:
		return Rect2(global_position, wall_size)
	return Rect2()


func blocks_color(color_id: String) -> bool:
	if not is_intact:
		return false
	return not ColorRegistry.has_ability(color_id, required_ability)


## Called by main each frame — checks if a breaker villager is touching.
func check_break(villagers_in_room: Array) -> void:
	if not is_intact:
		return
	var center: Vector2 = global_position + wall_size * 0.5
	for v in villagers_in_room:
		if ColorRegistry.has_ability(str(v.color_type), required_ability):
			var dist: float = v.global_position.distance_to(center)
			if dist < float(v.radius) + break_radius:
				is_intact = false
				queue_redraw()
				return


func _draw() -> void:
	if is_intact:
		draw_rect(Rect2(Vector2.ZERO, wall_size), Color(0.45, 0.3, 0.15))
		var cx := 6.0
		var cy := wall_size.y * 0.5
		while cx < wall_size.x:
			draw_line(Vector2(cx, cy - 4), Vector2(cx + 10, cy + 4),
				Color(0.3, 0.2, 0.1, 0.6), 1.0)
			cx += 35.0
		draw_rect(Rect2(Vector2.ZERO, wall_size), Color(0.35, 0.22, 0.1, 0.6), false, 1.0)
	else:
		var mid := wall_size * 0.5
		draw_string(ThemeDB.fallback_font, Vector2(mid.x - 25, mid.y + 4),
			"[broken]", HORIZONTAL_ALIGNMENT_CENTER, -1, 11,
			Color(0.5, 0.35, 0.2, 0.5))
