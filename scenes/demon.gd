extends Node2D
## Demon enemy. Spawns in groups of 7 at nightfall.
## Only killable by L3 red villagers. Immune to L1/L2 reds.
## Pursues nearest villager aggressively. Despawns at dawn.

enum State { MOVING, PAUSED }

const RADIUS := 32.0
const SPEED := 55.0              # faster than normal enemies
const HEALTH := 200.0
const PURSUIT_RANGE := 500.0     # actively hunts villagers
const BLUE_DAMAGE := 60.0
const HIT_COOLDOWN := 0.8

var current_room_id: int = -1
var room_bounds: Rect2 = Rect2()
var is_dead: bool = false
var health: float = HEALTH
var max_health: float = HEALTH

# Required interface for main.gd enemy system
var level: int = 1
var net_id: int = -1
var is_puppet: bool = false
var interp_target: Vector2 = Vector2.ZERO
var radius: float = RADIUS
var dupe_meter: float = 0.0
var enemy_type: String = "demon"

var _hit_cooldowns: Dictionary = {}
var _state: State = State.MOVING
var _move_target: Vector2 = Vector2.ZERO
var _state_timer: float = 0.0

# Brain context — set by main.gd
var brain_villagers: Array = []


func _ready() -> void:
	pass


func is_stunned() -> bool:
	return false   # demons don't get stunned


func _process(delta: float) -> void:
	if is_dead: return
	if is_puppet:
		if interp_target != Vector2.ZERO:
			global_position = global_position.lerp(interp_target, clampf(delta * 14.0, 0.0, 1.0))
		queue_redraw()
		return
	var expired: Array = []
	for key in _hit_cooldowns:
		_hit_cooldowns[key] -= delta
		if _hit_cooldowns[key] <= 0.0: expired.append(key)
	for key in expired:
		_hit_cooldowns.erase(key)

	# Pursue nearest villager
	_pursue_villager(delta)
	queue_redraw()


func _pursue_villager(delta: float) -> void:
	var best: Node = null
	var best_d: float = INF
	for v in brain_villagers:
		if not is_instance_valid(v) or not v.visible: continue
		var d: float = global_position.distance_to(v.global_position)
		if d < best_d: best_d = d; best = v

	if best and best_d < PURSUIT_RANGE:
		var dir: Vector2 = (best.global_position - global_position).normalized()
		global_position += dir * SPEED * delta
	else:
		# Wander if no target
		_state_timer -= delta
		if _state_timer <= 0.0:
			_state_timer = randf_range(1.0, 2.5)
			if room_bounds.has_area():
				var margin := RADIUS + 8.0
				_move_target = Vector2(
					randf_range(room_bounds.position.x + margin, room_bounds.end.x - margin),
					randf_range(room_bounds.position.y + margin, room_bounds.end.y - margin))
		var to_t := _move_target - global_position
		if to_t.length() > 5.0:
			global_position += to_t.normalized() * SPEED * 0.5 * delta


## Demon attacks a villager. Called by main.gd.
func try_attack(villager: Node) -> String:
	if _hit_cooldowns.has(villager): return "immune"
	var color: String = str(villager.color_type)
	# L3 reds are immune (they fight back)
	if color == "red" and int(villager.level) == 3: return "immune"
	# All others take heavy damage
	if color == "blue":
		_hit_cooldowns[villager] = HIT_COOLDOWN
		villager.health -= BLUE_DAMAGE
		if villager.health <= 0.0: return "kill"
		return "hit"
	else:
		villager.health = 0.0
		return "kill"


## Only L3 reds can damage demons.
func take_red_hit(red_level: int) -> bool:
	if red_level < 3: return false   # immune to L1/L2
	health -= 150.0   # L3 red damage
	return health <= 0.0


func die() -> void:
	is_dead = true; queue_free()


func _draw() -> void:
	# Dark purple body with horns
	var body_col := Color(0.3, 0.08, 0.35)
	var outline_col := Color(0.5, 0.15, 0.55)

	# Pentagon body
	var pts := PackedVector2Array()
	for i in 5:
		var angle: float = -PI / 2.0 + i * TAU / 5.0
		pts.append(Vector2(cos(angle), sin(angle)) * RADIUS)
	draw_colored_polygon(pts, body_col)
	pts.append(pts[0])
	draw_polyline(pts, outline_col, 2.5)

	# Horns
	draw_line(Vector2(-12, -RADIUS + 4), Vector2(-18, -RADIUS - 16), Color(0.6, 0.2, 0.1), 3.0)
	draw_line(Vector2(12, -RADIUS + 4), Vector2(18, -RADIUS - 16), Color(0.6, 0.2, 0.1), 3.0)

	# Glowing eyes
	var glow: float = 0.7 + sin(Time.get_ticks_msec() * 0.008) * 0.3
	draw_circle(Vector2(-8, -6), 5.0, Color(0.9, 0.2, 0.1, glow))
	draw_circle(Vector2(8, -6), 5.0, Color(0.9, 0.2, 0.1, glow))

	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-18, RADIUS + 16), "DEMON",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.6, 0.2, 0.5, 0.7))

	# Health bar
	var bw := RADIUS * 2.0
	var ratio := health / max_health
	draw_rect(Rect2(-RADIUS, RADIUS + 3, bw, 5), Color(0.25, 0.15, 0.25, 0.5))
	draw_rect(Rect2(-RADIUS, RADIUS + 3, bw * clampf(ratio, 0.0, 1.0), 5), Color(0.6, 0.15, 0.5))
