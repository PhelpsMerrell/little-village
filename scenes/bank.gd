extends Node2D
## Stone bank where yellows deposit collected stones.
## Placed once — not draggable. Yellows walk here to deposit.

const DEPOSIT_RADIUS := 60.0

@onready var _area: Area2D = $InputArea

var _deposits: int = 0   # visual counter of total deposits here
var placed_by_faction: int = -1  ## -2 = pre-placed (not sellable), >= 0 = player-placed
var is_selected: bool = false


func _ready() -> void:
	pass


## Called by main.gd — yellow villager tries to deposit.
func try_deposit(villager: Node) -> bool:
	if str(villager.color_type) != "yellow":
		return false
	if not villager.carrying_stone:
		return false
	var dist: float = villager.global_position.distance_to(global_position)
	if dist < DEPOSIT_RADIUS:
		villager.carrying_stone = false
		var fid: int = villager.faction_id if villager.faction_id >= 0 else 0
		Economy.add_stone(1, fid)
		_deposits += 1
		return true
	return false


func evict_all() -> void:
	pass


func get_capacity() -> int:
	return 0


func get_sheltered_count() -> int:
	return 0


func is_full() -> bool:
	return false


# ── drawing ──────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	# Base platform
	draw_rect(Rect2(-50, -30, 100, 60), Color(0.4, 0.38, 0.32))
	draw_rect(Rect2(-50, -30, 100, 60), Color(0.28, 0.25, 0.2), false, 2.0)

	# Stone pile decoration
	draw_circle(Vector2(-15, 5), 12.0, Color(0.5, 0.52, 0.48))
	draw_circle(Vector2(10, 8), 10.0, Color(0.45, 0.47, 0.43))
	draw_circle(Vector2(0, -8), 11.0, Color(0.52, 0.54, 0.5))

	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-22, -36), "BANK",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.85, 0.8, 0.5))

	# Deposit count
	draw_string(ThemeDB.fallback_font, Vector2(-30, 48),
		"Deposited: %d" % _deposits, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.65, 0.65, 0.55))

	# Deposit radius hint (faint circle)
	draw_arc(Vector2.ZERO, DEPOSIT_RADIUS, 0.0, TAU, 32,
		Color(0.6, 0.55, 0.3, 0.15), 1.0, true)

	# Selection ring
	if is_selected:
		var pulse: float = 0.6 + sin(Time.get_ticks_msec() * 0.006) * 0.4
		draw_arc(Vector2.ZERO, 55.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, pulse), 2.5, true)
