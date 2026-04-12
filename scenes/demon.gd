extends Node2D
## Demon enemy. Spawns in groups of 7 at nightfall.
## Only killable by L3 red villagers. Immune to L1/L2 reds.
## Pursues nearest villager aggressively. Despawns at dawn.

enum State { MOVING, PAUSED }

const RADIUS := 40.0
const SPEED := 55.0
const HEALTH := 200.0
const PURSUIT_RANGE := 500.0
const BLUE_DAMAGE := 60.0
const HIT_COOLDOWN := 0.8

var current_room_id: int = -1
var room_bounds: Rect2 = Rect2()
var is_dead: bool = false
var health: float = HEALTH
var max_health: float = HEALTH

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
var _stun_timer: float = 0.0

var brain_villagers: Array = []

@onready var _eye_left: Polygon2D = $EyeLeft
@onready var _eye_right: Polygon2D = $EyeRight


func _ready() -> void:
	pass


func is_stunned() -> bool:
	return _stun_timer > 0.0

func apply_stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)


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

	# Stun tick
	if _stun_timer > 0.0:
		_stun_timer -= delta
		queue_redraw()
		return

	# Eye glow animation
	if _eye_left:
		var glow: float = 0.7 + sin(Time.get_ticks_msec() * 0.008) * 0.3
		_eye_left.color = Color(0.9, 0.2, 0.1, glow)
		_eye_right.color = Color(0.9, 0.2, 0.1, glow)

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


func try_attack(villager: Node) -> String:
	if _hit_cooldowns.has(villager): return "immune"
	var color: String = str(villager.color_type)
	if color == "red" and int(villager.level) == 3: return "immune"
	if color == "blue":
		_hit_cooldowns[villager] = HIT_COOLDOWN
		villager.health -= BLUE_DAMAGE
		if villager.health <= 0.0: return "kill"
		return "hit"
	else:
		villager.health = 0.0
		return "kill"


func take_red_hit(red_level: int) -> bool:
	if red_level < 3: return false
	health -= 150.0
	return health <= 0.0


func die() -> void:
	is_dead = true; queue_free()


func _draw() -> void:
	# Dynamic overlay: health bar only
	var bw := RADIUS * 2.0
	var ratio := health / max_health
	draw_rect(Rect2(-RADIUS, RADIUS + 3, bw, 5), Color(0.25, 0.15, 0.25, 0.5))
	draw_rect(Rect2(-RADIUS, RADIUS + 3, bw * clampf(ratio, 0.0, 1.0), 5), Color(0.6, 0.15, 0.5))
