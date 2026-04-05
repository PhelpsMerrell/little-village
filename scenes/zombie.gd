extends Node2D
## Zombie enemy. Spawns at nightfall during zombie plague event.
## On touch, converts non-sheltered villagers into more zombies.
## Slow but relentless. Killed by any red. Despawns at dawn.

const RADIUS := 26.0
const SPEED := 25.0             # slow shamble
const HEALTH := 30.0
const PURSUIT_RANGE := 400.0
const CONVERT_COOLDOWN := 2.0   # seconds between conversion attempts

var current_room_id: int = -1
var room_bounds: Rect2 = Rect2()
var is_dead: bool = false
var health: float = HEALTH
var max_health: float = HEALTH

# Required interface for main.gd
var level: int = 1
var radius: float = RADIUS
var dupe_meter: float = 0.0
var enemy_type: String = "zombie"

var _convert_cooldowns: Dictionary = {}
var _state_timer: float = 0.0

# Brain context
var brain_villagers: Array = []


func is_stunned() -> bool:
	return false


func _process(delta: float) -> void:
	if is_dead: return
	var expired: Array = []
	for key in _convert_cooldowns:
		_convert_cooldowns[key] -= delta
		if _convert_cooldowns[key] <= 0.0: expired.append(key)
	for key in expired:
		_convert_cooldowns.erase(key)

	_pursue_villager(delta)
	queue_redraw()


func _pursue_villager(delta: float) -> void:
	var best: Node = null; var best_d: float = INF
	for v in brain_villagers:
		if not is_instance_valid(v) or not v.visible: continue
		var d: float = global_position.distance_to(v.global_position)
		if d < best_d: best_d = d; best = v
	if best and best_d < PURSUIT_RANGE:
		var dir: Vector2 = (best.global_position - global_position).normalized()
		global_position += dir * SPEED * delta
	else:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_state_timer = randf_range(1.5, 3.0)
			if room_bounds.has_area():
				var m := RADIUS + 8.0
				var target := Vector2(
					randf_range(room_bounds.position.x + m, room_bounds.end.x - m),
					randf_range(room_bounds.position.y + m, room_bounds.end.y - m))
				var to_t := target - global_position
				if to_t.length() > 5.0:
					global_position += to_t.normalized() * SPEED * 0.3 * delta


## Zombie touch: converts villager. Returns "convert" if successful.
## Main.gd handles the actual conversion (remove villager, spawn zombie).
func try_attack(villager: Node) -> String:
	if _convert_cooldowns.has(villager): return "immune"
	var color: String = str(villager.color_type)
	# Reds fight back — immune to conversion
	if color == "red": return "immune"
	_convert_cooldowns[villager] = CONVERT_COOLDOWN
	return "convert"


## Any red kills a zombie.
func take_red_hit(red_level: int) -> bool:
	var dmg: float = 30.0 + float(red_level) * 10.0
	health -= dmg
	return health <= 0.0


func die() -> void:
	is_dead = true; queue_free()


func _draw() -> void:
	# Sickly green body
	var body_col := Color(0.2, 0.4, 0.15)
	var outline_col := Color(0.35, 0.5, 0.2)

	# Irregular circle
	draw_circle(Vector2.ZERO, RADIUS, body_col)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, outline_col, 2.0, true)

	# Dead eyes
	draw_circle(Vector2(-7, -5), 4.0, Color(0.6, 0.7, 0.2))
	draw_circle(Vector2(7, -5), 4.0, Color(0.6, 0.7, 0.2))
	# X pupil on one eye
	draw_line(Vector2(5, -7), Vector2(9, -3), Color(0.2, 0.3, 0.1), 1.5)
	draw_line(Vector2(9, -7), Vector2(5, -3), Color(0.2, 0.3, 0.1), 1.5)

	# Drool / decay marks
	draw_line(Vector2(-4, 6), Vector2(-6, 14), Color(0.3, 0.5, 0.15, 0.5), 2.0)
	draw_line(Vector2(3, 7), Vector2(5, 13), Color(0.3, 0.5, 0.15, 0.5), 2.0)

	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-20, RADIUS + 16), "ZOMBIE",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.3, 0.5, 0.15, 0.7))
