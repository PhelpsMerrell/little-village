extends Node2D
## A home that shelters up to 4 villagers.
## Cannot be moved after placement. Selectable for sell/evict commands.

const CAPACITY := 4
const HOME_SIZE := Vector2(80, 80)
const INTAKE_RADIUS := 60.0

var sheltered: Array = []   # villager refs currently inside
var placed_by_faction: int = -1  ## Faction that built this (only they can sell)
var is_selected: bool = false

@onready var _area: Area2D = $InputArea


func _ready() -> void:
	pass


func get_capacity() -> int:
	return CAPACITY


func get_sheltered_count() -> int:
	sheltered = sheltered.filter(func(v): return is_instance_valid(v))
	return sheltered.size()


func is_full() -> bool:
	return get_sheltered_count() >= CAPACITY


func shelter_villager(v: Node) -> bool:
	if is_full():
		return false
	if v in sheltered:
		return false
	sheltered.append(v)
	v.visible = false
	v.set_process(false)
	return true


func release_all() -> void:
	var offset_i := 0
	for v in sheltered:
		if is_instance_valid(v):
			v.visible = true
			v.set_process(true)
			v.global_position = global_position + Vector2(
				randf_range(-70, 70), randf_range(50, 100))
			offset_i += 1
	sheltered.clear()


func evict_all() -> void:
	## Force all sheltered villagers out (player command).
	release_all()


# ── drawing ──────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var count: int = get_sheltered_count()

	# House body
	var hw := HOME_SIZE.x * 0.5
	var hh := HOME_SIZE.y * 0.5
	# Walls
	draw_rect(Rect2(-hw * 0.8, -hh * 0.3, hw * 1.6, hh * 1.3), Color(0.55, 0.4, 0.25))
	# Roof triangle
	var roof := PackedVector2Array([
		Vector2(0, -hh),
		Vector2(hw, -hh * 0.3),
		Vector2(-hw, -hh * 0.3),
	])
	draw_colored_polygon(roof, Color(0.6, 0.2, 0.15))
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[0]]),
		Color(0.35, 0.12, 0.08), 2.0)
	# Door
	draw_rect(Rect2(-8, hh * 0.2, 16, hh * 0.8), Color(0.35, 0.25, 0.15))
	# Outline
	draw_rect(Rect2(-hw * 0.8, -hh * 0.3, hw * 1.6, hh * 1.3),
		Color(0.3, 0.2, 0.12), false, 2.0)

	# Selection ring
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, hw + 10.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, pulse), 2.5, true)

	# Capacity indicator
	var label := "%d/%d" % [count, CAPACITY]
	draw_string(ThemeDB.fallback_font,
		Vector2(-16, hh + 18), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.8, 0.8, 0.7))
