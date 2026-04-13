extends HousingBuilding
class_name Farm
## Produces grain over time. Yellow villagers collect grain like stone.
## Also shelters 8 villagers at night.

const GRAIN_INTERVAL := 45.0  ## seconds between grain spawns
const GRAIN_SPAWN_RADIUS := 120.0
const MAX_GRAIN_NEARBY := 6  ## won't spawn more if this many grain within radius

var _grain_timer: float = 0.0
var grain_produced: int = 0  ## lifetime counter

@onready var _count_label: Label = $CountLabel


func _ready() -> void:
	capacity = 8
	intake_radius = 65.0


func _process(delta: float) -> void:
	if _count_label:
		_count_label.text = "%d/%d" % [get_sheltered_count(), capacity]
	queue_redraw()


func get_grain_timer() -> float:
	return _grain_timer


func tick_grain(delta: float) -> bool:
	## Returns true when a grain should be spawned. Called by main.gd.
	_grain_timer += delta
	if _grain_timer >= GRAIN_INTERVAL:
		_grain_timer -= GRAIN_INTERVAL
		return true
	return false


func _draw() -> void:
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 55.0, 0.0, TAU, 24, Color(0.7, 0.85, 0.3, pulse), 2.5, true)

	# Grain production radius indicator
	draw_arc(Vector2.ZERO, GRAIN_SPAWN_RADIUS, 0.0, TAU, 32,
		Color(0.6, 0.7, 0.2, 0.1), 1.0, true)
