extends Node2D
## Fish spot near a river. Only blues can collect. Sets carrying_resource = "fish".

const RADIUS := 14.0
var collected: bool = false

var _bob_time: float = randf_range(0, TAU)

@onready var _fish_body: Polygon2D = $FishBody
@onready var _tail: Polygon2D = $Tail
@onready var _eye: Polygon2D = $Eye
@onready var _sparkle: Polygon2D = $Sparkle


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
		visible = false
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)
		return true
	return false


func _process(delta: float) -> void:
	if collected:
		return
	_bob_time += delta * 2.0
	var bob := sin(_bob_time) * 3.0
	# Animate all child node positions for bobbing effect
	if _fish_body:
		_fish_body.position.y = bob
	if _tail:
		_tail.position.y = bob
	if _eye:
		_eye.position.y = -2.0 + bob
	if _sparkle:
		_sparkle.position.y = -6.0 + bob
