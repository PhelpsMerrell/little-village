extends Node
## Tracks day/night cycle and moon phase.
## 20 min day, 10 min night. 8-day lunar cycle.

signal phase_changed(is_daytime: bool)

const DAY_DURATION := 400.0     # ~6.7 minutes (1/3 of original)
const NIGHT_DURATION := 200.0   # ~3.3 minutes (1/3 of original)
const CYCLE_DURATION := 600.0   # total
const LUNAR_CYCLE_DAYS := 8     # full cycle = 8 game days

var elapsed: float = 0.0
var day_count: int = 1
var is_daytime: bool = true
var is_paused: bool = false


## Moon phases: 0=new, 1=waxing_crescent, 2=first_quarter, 3=waxing_gibbous,
##              4=full, 5=waning_gibbous, 6=last_quarter, 7=waning_crescent
enum MoonPhase {
	NEW_MOON,
	WAXING_CRESCENT,
	FIRST_QUARTER,
	WAXING_GIBBOUS,
	FULL_MOON,
	WANING_GIBBOUS,
	LAST_QUARTER,
	WANING_CRESCENT,
}

const MOON_NAMES := [
	"New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
	"Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
]


func _process(delta: float) -> void:
	if is_paused:
		return
	elapsed += delta
	if elapsed >= CYCLE_DURATION:
		elapsed -= CYCLE_DURATION
		day_count += 1

	var was_day: bool = is_daytime
	is_daytime = elapsed < DAY_DURATION
	if was_day != is_daytime:
		phase_changed.emit(is_daytime)


func get_moon_phase() -> int:
	return (day_count - 1) % LUNAR_CYCLE_DAYS


func get_moon_phase_name() -> String:
	return MOON_NAMES[get_moon_phase()]


func is_full_moon() -> bool:
	return get_moon_phase() == MoonPhase.FULL_MOON


func is_new_moon() -> bool:
	return get_moon_phase() == MoonPhase.NEW_MOON


## 0.0 = start of cycle, 1.0 = end of cycle
func get_cycle_progress() -> float:
	return elapsed / CYCLE_DURATION


## 0.0-1.0 within current phase
func get_phase_progress() -> float:
	if is_daytime:
		return elapsed / DAY_DURATION
	return (elapsed - DAY_DURATION) / NIGHT_DURATION


func get_time_string() -> String:
	var moon: String = get_moon_phase_name()
	if is_daytime:
		var remaining: int = int(DAY_DURATION - elapsed)
		return "Day %d  |  %s  |  %d:%02d" % [day_count, moon, remaining / 60, remaining % 60]
	else:
		var remaining: int = int(CYCLE_DURATION - elapsed)
		return "Night %d  |  %s  |  %d:%02d" % [day_count, moon, remaining / 60, remaining % 60]


func advance_phase() -> void:
	## Skip to next phase boundary (day→night or night→day).
	if is_daytime:
		elapsed = DAY_DURATION + 0.01
	else:
		elapsed = 0.0
		day_count += 1
	var was_day := is_daytime
	is_daytime = elapsed < DAY_DURATION
	if was_day != is_daytime:
		phase_changed.emit(is_daytime)


## For save/load
func get_save_data() -> Dictionary:
	return {"elapsed": elapsed, "day_count": day_count}


func load_save_data(data: Dictionary) -> void:
	elapsed = float(data.get("elapsed", 0.0))
	day_count = int(data.get("day_count", 1))
	is_daytime = elapsed < DAY_DURATION
