@tool
extends Node2D
class_name RoomSpawnMarker

@export_enum("stone", "fish", "diamond", "enemy", "colorless", "bank", "fishing_hut", "town_hall", "portal", "river", "red", "yellow", "blue", "magic_orb") var spawn_kind: String = "stone"
@export var label_override: String = ""
@export var radius: float = 14.0

const KIND_COLORS := {
	"stone": Color(0.7, 0.7, 0.75, 1.0),
	"fish": Color(0.25, 0.65, 0.9, 1.0),
	"diamond": Color(0.45, 0.9, 1.0, 1.0),
	"enemy": Color(0.9, 0.25, 0.2, 1.0),
	"colorless": Color(0.8, 0.8, 0.85, 1.0),
	"bank": Color(0.85, 0.75, 0.35, 1.0),
	"fishing_hut": Color(0.4, 0.75, 0.95, 1.0),
	"town_hall": Color(0.95, 0.8, 0.35, 1.0),
	"portal": Color(0.85, 0.25, 0.95, 1.0),
	"river": Color(0.2, 0.45, 0.9, 1.0),
	"red": Color(0.9, 0.3, 0.25, 1.0),
	"yellow": Color(0.95, 0.85, 0.25, 1.0),
	"blue": Color(0.3, 0.55, 0.95, 1.0),
	"magic_orb": Color(0.9, 0.85, 0.45, 1.0),
}


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var col: Color = KIND_COLORS.get(spawn_kind, Color.WHITE)
	draw_circle(Vector2.ZERO, radius, Color(col.r, col.g, col.b, 0.2))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, col, 2.0, true)
	draw_circle(Vector2.ZERO, 3.0, col)
	var font := ThemeDB.fallback_font
	if font != null:
		var label := label_override if not label_override.is_empty() else spawn_kind
		draw_string(font, Vector2(radius + 6.0, 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, col)
