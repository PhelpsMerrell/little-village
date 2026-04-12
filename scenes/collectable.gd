extends Node2D
## Resource on the ground. Only yellows pick it up.
## Supports "stone" and "diamond" types.

const RADIUS := 12.0
var collected: bool = false

@export var resource_type: String = "stone"

@onready var _stone_body: Polygon2D = $StoneBody
@onready var _stone_highlight: Polygon2D = $StoneHighlight
@onready var _diamond_body: Polygon2D = $DiamondBody
@onready var _diamond_outline: Line2D = $DiamondOutline
@onready var _diamond_highlight: Polygon2D = $DiamondHighlight


func _ready() -> void:
	_update_visual()


func _update_visual() -> void:
	var is_diamond: bool = (resource_type == "diamond")
	if _stone_body:
		_stone_body.visible = not is_diamond
	if _stone_highlight:
		_stone_highlight.visible = not is_diamond
	if _diamond_body:
		_diamond_body.visible = is_diamond
	if _diamond_outline:
		_diamond_outline.visible = is_diamond
	if _diamond_highlight:
		_diamond_highlight.visible = is_diamond


func try_collect(villager: Node) -> bool:
	if collected:
		return false
	if str(villager.color_type) != "yellow":
		return false
	if villager.is_carrying():
		return false
	var dist: float = villager.global_position.distance_to(global_position)
	if dist < float(villager.radius) + RADIUS + 4.0:
		collected = true
		villager.carrying_resource = resource_type
		visible = false
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.3)
		tw.tween_callback(queue_free)
		return true
	return false
