extends Node2D
## Fish spot near a river. Only blues can collect. Sets carrying_resource = "fish".

const RADIUS := 14.0
var collected: bool = false

var _bob_time: float = randf_range(0, TAU)


func try_collect(villager: Node) -> bool:
	if collected:
		return false
	if str(villager.color_type) != "blue":
		return false
	if str(villager.carrying_resource) != "":
		return false
	var dist: float = villager.global_position.distance_to(global_position)
	if dist < float(villager.radius) + RADIUS + 4.0:
		collected = true
		villager.carrying_resource = "fish"
		queue_redraw()
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)
		return true
	return false


func _process(delta: float) -> void:
	_bob_time += delta * 2.0
	queue_redraw()


func _draw() -> void:
	if collected:
		return
	var bob := sin(_bob_time) * 3.0
	# Fish body (oval)
	draw_circle(Vector2(0, bob), RADIUS * 0.7, Color(0.3, 0.55, 0.75))
	# Tail
	var tail := PackedVector2Array([
		Vector2(RADIUS * 0.5, bob),
		Vector2(RADIUS, bob - 6),
		Vector2(RADIUS, bob + 6),
	])
	draw_colored_polygon(tail, Color(0.25, 0.45, 0.65))
	# Eye
	draw_circle(Vector2(-4, bob - 2), 2.0, Color(0.9, 0.9, 0.9))
	# Sparkle
	draw_circle(Vector2(-2, bob - 6), 2.5, Color(0.6, 0.8, 0.95, 0.5))
