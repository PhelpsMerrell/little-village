extends Node2D
## Small collectable on the ground. Only yellows pick it up (touch to collect).

const RADIUS := 12.0
var collected: bool = false

@export var resource_type: String = "stone"


func _draw() -> void:
	if collected:
		return
	draw_circle(Vector2.ZERO, RADIUS, Color(0.5, 0.52, 0.48))
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 24, Color(0.35, 0.35, 0.35), 1.5, true)
	draw_circle(Vector2(-3, -4), 3.0, Color(0.7, 0.72, 0.68, 0.6))


func try_collect(villager: Node) -> bool:
	if collected:
		return false
	if str(villager.color_type) != "yellow":
		return false
	var dist: float = villager.global_position.distance_to(global_position)
	if dist < float(villager.radius) + RADIUS + 4.0:
		collected = true
		Economy.add_stone(1)
		queue_redraw()
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)
		return true
	return false
