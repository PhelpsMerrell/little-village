extends Node
## Tracks day/night cycle. 20 min day, 10 min night.

signal phase_changed(is_daytime: bool)

const DAY_DURATION := 1200.0    # 20 minutes in seconds
const NIGHT_DURATION := 600.0   # 10 minutes in seconds
const CYCLE_DURATION := 1800.0  # total

var elapsed: float = 0.0
var day_count: int = 1
var is_daytime: bool = true


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= CYCLE_DURATION:
		elapsed -= CYCLE_DURATION
		day_count += 1

	var was_day: bool = is_daytime
	is_daytime = elapsed < DAY_DURATION
	if was_day != is_daytime:
		phase_changed.emit(is_daytime)


## 0.0 = start of cycle, 1.0 = end of cycle
func get_cycle_progress() -> float:
	return elapsed / CYCLE_DURATION


## 0.0–1.0 within current phase
func get_phase_progress() -> float:
	if is_daytime:
		return elapsed / DAY_DURATION
	return (elapsed - DAY_DURATION) / NIGHT_DURATION


func get_time_string() -> String:
	if is_daytime:
		var remaining: int = int(DAY_DURATION - elapsed)
		return "Day %d — %d:%02d remaining" % [day_count, remaining / 60, remaining % 60]
	else:
		var remaining: int = int(CYCLE_DURATION - elapsed)
		return "Night %d — %d:%02d remaining" % [day_count, remaining / 60, remaining % 60]
