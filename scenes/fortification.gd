extends HousingBuilding
class_name Fortification
## Military building. Reds can garrison inside and shoot from it.
## Building has 350 HP. When destroyed, all garrisoned villagers are evicted.
## Garrisoned reds are satiated (no hunger drain).

const MAX_HEALTH := 350.0
const SHOOT_RANGE := 250.0
const SHOOT_COOLDOWN := 1.2
const FORT_SIZE := Vector2(90, 70)

var fort_health: float = MAX_HEALTH
var _shoot_cooldown: float = 0.0
var _destroyed: bool = false

@onready var _health_label: Label = $HealthLabel
@onready var _count_label: Label = $CountLabel
@onready var _body: Polygon2D = $Body
@onready var _body_outline: Line2D = $BodyOutline


func _ready() -> void:
	capacity = 6
	intake_radius = 70.0


func can_house_villager(v: Node) -> bool:
	if _destroyed:
		return false
	if v == null or not is_instance_valid(v):
		return false
	if is_full():
		return false
	if v in sheltered:
		return false
	if not "faction_id" in v:
		return false
	if placed_by_faction < 0:
		return false
	if int(v.faction_id) != placed_by_faction:
		return false
	# Only reds can garrison
	if str(v.color_type) != "red":
		return false
	return true


func take_damage(amount: float) -> void:
	if _destroyed:
		return
	fort_health -= amount
	if fort_health <= 0.0:
		fort_health = 0.0
		_destroy()


func _destroy() -> void:
	_destroyed = true
	evict_all()
	EventFeed.push("A fortification was destroyed!", Color(0.9, 0.3, 0.2))
	if _body:
		_body.color = Color(0.15, 0.12, 0.1, 0.5)
	if _body_outline:
		_body_outline.default_color = Color(0.3, 0.2, 0.15, 0.4)


func is_full() -> bool:
	if _destroyed:
		return true
	return get_sheltered_count() >= capacity


func get_shoot_targets(enemies_in_range: Array) -> Array:
	## Returns enemies within shoot range that garrisoned reds can fire at.
	if _destroyed or sheltered.is_empty():
		return []
	var targets: Array = []
	for e in enemies_in_range:
		if not is_instance_valid(e):
			continue
		if e.get("is_dead") and e.is_dead:
			continue
		if global_position.distance_to(e.global_position) < SHOOT_RANGE:
			targets.append(e)
	return targets


func process_shooting(delta: float, enemies: Array, night_enemies: Array, enemy_villagers: Array) -> Array:
	## Fire at enemies from garrisoned reds. Returns killed targets.
	if _destroyed:
		return []
	_shoot_cooldown -= delta
	if _shoot_cooldown > 0.0:
		return []

	var red_count: int = 0
	for v in sheltered:
		if is_instance_valid(v) and str(v.color_type) == "red":
			red_count += 1
	if red_count == 0:
		return []

	# Find nearest enemy in range
	var best_target: Node = null
	var best_d: float = SHOOT_RANGE
	for e in enemies + night_enemies:
		if not is_instance_valid(e) or e.is_dead:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best_target = e
	for v in enemy_villagers:
		if not is_instance_valid(v) or not v.visible:
			continue
		var d: float = global_position.distance_to(v.global_position)
		if d < best_d:
			best_d = d
			best_target = v

	if best_target == null:
		return []

	_shoot_cooldown = SHOOT_COOLDOWN

	# Damage = sum of garrisoned red levels * 10
	var total_dmg: float = 0.0
	for v in sheltered:
		if is_instance_valid(v) and str(v.color_type) == "red":
			total_dmg += 10.0 * float(v.level)
			v.record_kill()

	var killed: Array = []
	if best_target.get("faction_id") != null:
		# Enemy villager
		best_target.health -= total_dmg
		if best_target.health <= 0.0:
			killed.append(best_target)
	elif best_target.has_method("take_red_hit"):
		# Use highest red level for the hit
		var max_lv: int = 1
		for v in sheltered:
			if is_instance_valid(v) and str(v.color_type) == "red":
				max_lv = maxi(max_lv, v.level)
		if best_target.take_red_hit(max_lv):
			killed.append(best_target)

	return killed


func _process(delta: float) -> void:
	# Satiate all garrisoned reds
	for v in sheltered:
		if is_instance_valid(v) and str(v.color_type) == "red":
			v.is_fed = true
			v._satiation_timer = v.SATIATION_PER_LEVEL[clampi(v.level, 1, 3)]

	if _count_label:
		_count_label.text = "%d/%d" % [get_sheltered_count(), capacity]
	if _health_label:
		if _destroyed:
			_health_label.text = "DESTROYED"
			_health_label.add_theme_color_override("font_color", Color(0.7, 0.3, 0.2))
		else:
			_health_label.text = "HP: %d/%d" % [int(fort_health), int(MAX_HEALTH)]
	_check_selection_redraw()
	if not is_selected and get_sheltered_count() > 0:
		queue_redraw()  # Range ring when garrisoned


func _draw() -> void:
	if _destroyed:
		return
	# Dynamic: selection pulse + range ring
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 55.0, 0.0, TAU, 24, Color(1.0, 0.5, 0.3, pulse), 2.5, true)
	# Shoot range indicator when garrisoned
	if get_sheltered_count() > 0:
		draw_arc(Vector2.ZERO, SHOOT_RANGE, 0.0, TAU, 48, Color(0.8, 0.3, 0.2, 0.08), 1.0, true)
