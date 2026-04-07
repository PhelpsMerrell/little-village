extends Node2D
## Church — heals blue villagers inside. Shelters 8 any-color at night.
## Cannot be moved after placement. Selectable for sell/evict commands.

const CAPACITY := 8
const HEAL_RATE := 10.0  # HP per second (blues only)
const INTAKE_RADIUS := 70.0
const CHURCH_SIZE := Vector2(100, 90)

var sheltered: Array = []  # villager refs currently inside
var placed_by_faction: int = -1  ## Faction that built this (only they can sell)
var is_selected: bool = false

@onready var _area: Area2D = $InputArea


func _ready() -> void:
	pass


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


func release_villager(v: Node) -> void:
	if v not in sheltered:
		return
	sheltered.erase(v)
	if is_instance_valid(v):
		v.visible = true
		v.set_process(true)
		v.global_position = global_position + Vector2(randf_range(-60, 60), randf_range(50, 90))


func release_all() -> void:
	for v in sheltered:
		if is_instance_valid(v):
			v.visible = true
			v.set_process(true)
			v.global_position = global_position + Vector2(randf_range(-60, 60), randf_range(50, 90))
	sheltered.clear()


func evict_all() -> void:
	## Force all sheltered villagers out (player command).
	release_all()


func heal_tick(delta: float) -> void:
	var to_release: Array = []
	for v in sheltered:
		if not is_instance_valid(v):
			continue
		if str(v.color_type) == "blue":
			v.health = minf(v.health + HEAL_RATE * delta, v.max_health)
			if v.health >= v.max_health:
				to_release.append(v)
	for v in to_release:
		release_villager(v)


# ── drawing ──────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var count: int = get_sheltered_count()
	var hw := CHURCH_SIZE.x * 0.5
	var hh := CHURCH_SIZE.y * 0.5

	# Church body
	draw_rect(Rect2(-hw * 0.85, -hh * 0.2, hw * 1.7, hh * 1.2), Color(0.35, 0.38, 0.5))

	# Steeple / spire
	var spire := PackedVector2Array([
		Vector2(0, -hh - 20),
		Vector2(14, -hh * 0.2),
		Vector2(-14, -hh * 0.2),
	])
	draw_colored_polygon(spire, Color(0.3, 0.35, 0.55))
	draw_polyline(PackedVector2Array([spire[0], spire[1], spire[2], spire[0]]),
		Color(0.2, 0.22, 0.35), 2.0)

	# Cross on top
	draw_line(Vector2(0, -hh - 28), Vector2(0, -hh - 16), Color(0.8, 0.8, 0.6), 2.5)
	draw_line(Vector2(-5, -hh - 24), Vector2(5, -hh - 24), Color(0.8, 0.8, 0.6), 2.5)

	# Stained glass window
	draw_circle(Vector2(0, -hh * 0.05), 12.0, Color(0.2, 0.35, 0.7, 0.8))
	draw_arc(Vector2(0, -hh * 0.05), 12.0, 0.0, TAU, 24, Color(0.5, 0.55, 0.7, 0.6), 1.5)

	# Door
	draw_rect(Rect2(-10, hh * 0.3, 20, hh * 0.7), Color(0.25, 0.2, 0.15))

	# Outline
	draw_rect(Rect2(-hw * 0.85, -hh * 0.2, hw * 1.7, hh * 1.2),
		Color(0.2, 0.22, 0.35), false, 2.0)

	# Selection ring
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, hw + 10.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, pulse), 2.5, true)

	# Healing glow when blues inside
	var has_blues := false
	for v in sheltered:
		if is_instance_valid(v) and str(v.color_type) == "blue":
			has_blues = true; break
	if has_blues:
		draw_arc(Vector2.ZERO, INTAKE_RADIUS, 0.0, TAU, 32,
			Color(0.3, 0.5, 0.9, 0.2 + sin(Time.get_ticks_msec() * 0.003) * 0.1), 2.0, true)

	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-30, -hh - 32), "CHURCH",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(0.6, 0.7, 0.9))

	# Capacity
	var label := "%d/%d" % [count, CAPACITY]
	draw_string(ThemeDB.fallback_font,
		Vector2(-16, hh + 22), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.7, 0.75, 0.85))

	# Intake radius hint
	draw_arc(Vector2.ZERO, INTAKE_RADIUS, 0.0, TAU, 32,
		Color(0.3, 0.4, 0.8, 0.1), 1.0, true)
