extends Node
## Night event system. Events are now tied to the moon phase.
## Full moon = demon hunt (werewolves). New moon = zombie plague.
## Other phases use weighted random from the pool.

signal night_event_started(event_id: String)
signal night_event_ended(event_id: String)

var _events: Array = []       # [{id, weight}]
var _active_event: String = ""
var _connected: bool = false

## Moon phase overrides: specific phases force specific events
var _moon_overrides: Dictionary = {}  # moon_phase_int -> event_id


func _ready() -> void:
	register_event("demon_hunt", 1.0)
	register_event("zombie_plague", 1.0)
	register_event("quiet_night", 0.5)

	# Full moon always spawns demons (werewolves later)
	set_moon_override(GameClock.MoonPhase.FULL_MOON, "demon_hunt")
	# New moon always spawns zombies
	set_moon_override(GameClock.MoonPhase.NEW_MOON, "zombie_plague")


func register_event(event_id: String, weight: float = 1.0) -> void:
	_events.append({"id": event_id, "weight": weight})


func set_moon_override(phase: int, event_id: String) -> void:
	_moon_overrides[phase] = event_id


func connect_to_clock() -> void:
	if _connected: return
	GameClock.phase_changed.connect(_on_phase_changed)
	_connected = true


func _on_phase_changed(is_daytime: bool) -> void:
	if not is_daytime:
		_roll_night_event()
	else:
		_end_night_event()


func _roll_night_event() -> void:
	if _events.is_empty(): return

	# Check moon phase override first
	var moon: int = GameClock.get_moon_phase()
	if _moon_overrides.has(moon):
		_active_event = _moon_overrides[moon]
		night_event_started.emit(_active_event)
		return

	# Weighted random for other phases
	var total_weight: float = 0.0
	for ev in _events:
		total_weight += float(ev["weight"])
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for ev in _events:
		cumulative += float(ev["weight"])
		if roll <= cumulative:
			_active_event = str(ev["id"])
			night_event_started.emit(_active_event)
			return
	_active_event = str(_events[0]["id"])
	night_event_started.emit(_active_event)


func _end_night_event() -> void:
	if _active_event != "":
		night_event_ended.emit(_active_event)
		_active_event = ""


func get_active_event() -> String:
	return _active_event
