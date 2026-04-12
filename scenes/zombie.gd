extends Node2D
## Zombie enemy. Spawns at nightfall during zombie plague event.
## On touch, converts non-sheltered villagers into more zombies.
## Slow but relentless. Killed by any red. Despawns at dawn.

const RADIUS := 32.0
const SPEED := 25.0
const HEALTH := 30.0
const PURSUIT_RANGE := 400.0
const CONVERT_COOLDOWN := 2.0

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
var enemy_type: String = "zombie"

var _convert_cooldowns: Dictionary = {}
var _state_timer: float = 0.0
var _stun_timer: float = 0.0

var brain_villagers: Array = []


func is_stunned() -> bool:
	return _stun_timer > 0.0

func apply_stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)


func _process(delta: float) -> void:
	if is_dead: return
	if is_puppet:
		if interp_target != Vector2.ZERO:
			global_position = global_position.lerp(interp_target, clampf(delta * 14.0, 0.0, 1.0))
		return
	var expired: Array = []
	for key in _convert_cooldowns:
		_convert_cooldowns[key] -= delta
		if _convert_cooldowns[key] <= 0.0: expired.append(key)
	for key in expired:
		_convert_cooldowns.erase(key)

	# Stun tick
	if _stun_timer > 0.0:
		_stun_timer -= delta
		return
	_pursue_villager(delta)


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


func try_attack(villager: Node) -> String:
	if _convert_cooldowns.has(villager): return "immune"
	var color: String = str(villager.color_type)
	if color == "red": return "immune"
	_convert_cooldowns[villager] = CONVERT_COOLDOWN
	return "convert"


func take_red_hit(red_level: int) -> bool:
	var dmg: float = 30.0 + float(red_level) * 10.0
	health -= dmg
	return health <= 0.0


func die() -> void:
	is_dead = true; queue_free()
