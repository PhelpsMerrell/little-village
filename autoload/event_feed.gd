extends Node
## Global event feed. Any system can push messages. HUD reads and displays them.

signal message_added(msg: String, color: Color)

const MAX_HISTORY := 50

var messages: Array = []  # [{text, color, time}]
var _last_time_event: String = ""


func push(text: String, color: Color = Color(0.75, 0.75, 0.7)) -> void:
	messages.append({"text": text, "color": color, "time": Time.get_ticks_msec()})
	if messages.size() > MAX_HISTORY:
		messages.pop_front()
	message_added.emit(text, color)


func get_recent(count: int = 5) -> Array:
	var start: int = maxi(0, messages.size() - count)
	return messages.slice(start)


## Called by main.gd each frame to emit time-of-day flavor text
func check_time_events() -> void:
	var progress: float = GameClock.get_cycle_progress()
	var event: String = ""

	if GameClock.is_daytime:
		var day_progress: float = GameClock.get_phase_progress()
		if day_progress < 0.02:
			event = "dawn"
		elif day_progress > 0.45 and day_progress < 0.55:
			event = "midday"
		elif day_progress > 0.80 and day_progress < 0.85:
			event = "dusk_warning"
	else:
		var night_progress: float = GameClock.get_phase_progress()
		if night_progress < 0.03:
			event = "nightfall"
		elif night_progress > 0.45 and night_progress < 0.55:
			event = "midnight"

	if event != "" and event != _last_time_event:
		_last_time_event = event
		match event:
			"dawn":
				push("A new day begins...", Color(0.95, 0.85, 0.4))
			"midday":
				push("The sun reaches its peak.", Color(0.9, 0.8, 0.3))
			"dusk_warning":
				var moon: String = GameClock.get_moon_phase_name()
				if GameClock.is_full_moon():
					push("A full moon rises tonight... beware.", Color(0.8, 0.4, 0.3))
				elif GameClock.is_new_moon():
					push("Darkness gathers under the new moon.", Color(0.4, 0.5, 0.6))
				else:
					push("Darkness approaches! Get in your homes!", Color(0.8, 0.4, 0.25))
			"nightfall":
				push("The %s rises." % GameClock.get_moon_phase_name().to_lower(), Color(0.4, 0.4, 0.7))
			"midnight":
				push("The deepest hour of night.", Color(0.3, 0.3, 0.6))
