extends Node2D
## Resource on the ground. Only yellows pick it up.
## Supports "stone", "diamond", and "grain" types.

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
	var is_grain: bool = (resource_type == "grain")
	var is_stone: bool = (not is_diamond and not is_grain)
	if _stone_body:
		_stone_body.visible = is_stone
	if _stone_highlight:
		_stone_highlight.visible = is_stone
	if _diamond_body:
		_diamond_body.visible = is_diamond
	if _diamond_outline:
		_diamond_outline.visible = is_diamond
	if _diamond_highlight:
		_diamond_highlight.visible = is_diamond
	# Grain uses _draw() — hide all polygon children
	if is_grain:
		queue_redraw()


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


func _draw() -> void:
	if resource_type != "grain" or collected:
		return
	# Wheat sheaf icon
	draw_line(Vector2(0, 6), Vector2(0, -8), Color(0.7, 0.6, 0.15, 1.0), 2.0)
	draw_line(Vector2(-4, 6), Vector2(-3, -5), Color(0.7, 0.6, 0.15, 1.0), 1.5)
	draw_line(Vector2(4, 6), Vector2(3, -5), Color(0.7, 0.6, 0.15, 1.0), 1.5)
	# Grain heads
	draw_circle(Vector2(0, -9), 3.0, Color(0.9, 0.8, 0.2, 1.0))
	draw_circle(Vector2(-3, -6), 2.5, Color(0.85, 0.75, 0.2, 1.0))
	draw_circle(Vector2(3, -6), 2.5, Color(0.85, 0.75, 0.2, 1.0))
