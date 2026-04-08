extends Node
## Manages the optional guided tutorial.
## The tutorial is a small sandbox with real gameplay — only objective tracking
## and guidance text are tutorial-specific. Phases auto-skip if condition already met.

signal phase_completed(phase: int)
signal tutorial_finished()

var active: bool = false
var current_phase: int = 0

## Tutorial room IDs (set by map_generator.generate_tutorial)
var tutorial_room_b_id: int = 1

var _has_selected: bool = false
var _advance_delay: float = 0.0  ## 3s display timer before moving to next phase
var _pending_advance: bool = false

const PHASE_ADVANCE_DELAY := 3.0

const PHASE_INSTRUCTIONS: Array[String] = [
	"",  # index 0 unused
	"Phase 1 — Select & Move: Click a villager to select it, then right-click ground to move.",
	"Phase 2 — Color Shift: Walk or drag a villager near the glowing orb to shift its color.",
	"Phase 3 — Duplication: Shift a RED villager — reds produce 2 yellows when shifted!",
	"Phase 4 — Stone: Yellow villagers auto-collect stone. Walk one near stone, then to the bank.",
	"Phase 5 — Fish: Blue villagers auto-collect fish. Walk one near fish, then to the fishing hut.",
	"Phase 6 — Break Door: Move a red villager to the closed door to break it open!",
	"Phase 7 — Combat: Send a red villager near an enemy — reds shoot automatically!",
	"Phase 8 — Tutorial Complete! Press Escape > 'Quit to Main Menu' to return to the title screen.",
]

const PHASE_COMPLETE_MSG: Array[String] = [
	"",
	"Great! You can select and move villagers!",
	"Color shifted! Each color has different abilities.",
	"Duplication! Reds spawn 2 yellows when shifted.",
	"Stone deposited! Yellows gather stone for building.",
	"Fish delivered! Blues gather fish to feed reds.",
	"Door broken! Reds can break into new rooms.",
	"Enemy killed! Reds are your fighters.",
	"",
]


func _process(delta: float) -> void:
	if not active:
		return
	if _pending_advance:
		_advance_delay -= delta
		if _advance_delay <= 0.0:
			_pending_advance = false
			_do_advance()


func start_tutorial() -> void:
	active = true
	current_phase = 1
	_has_selected = false
	_pending_advance = false
	_advance_delay = 0.0
	EventFeed.push("Tutorial started! Follow the instructions at the top.", Color(0.9, 0.85, 0.5))


func skip_tutorial() -> void:
	active = false
	current_phase = 0
	_pending_advance = false
	tutorial_finished.emit()


func get_current_instruction() -> String:
	if not active or current_phase < 1 or current_phase >= PHASE_INSTRUCTIONS.size():
		return ""
	if _pending_advance and current_phase < PHASE_COMPLETE_MSG.size():
		return PHASE_COMPLETE_MSG[current_phase]
	return PHASE_INSTRUCTIONS[current_phase]


func _advance() -> void:
	## Start the 3s delay before actually moving to next phase.
	if _pending_advance:
		return  # already advancing
	_pending_advance = true
	_advance_delay = PHASE_ADVANCE_DELAY
	phase_completed.emit(current_phase)
	EventFeed.push(PHASE_COMPLETE_MSG[current_phase] if current_phase < PHASE_COMPLETE_MSG.size() else "Done!", Color(0.5, 0.9, 0.5))


func _do_advance() -> void:
	## Actually move to next phase after delay.
	current_phase += 1
	if current_phase >= PHASE_INSTRUCTIONS.size():
		EventFeed.push("Tutorial complete! You know the basics.", Color(0.7, 0.9, 0.6))
		tutorial_finished.emit()
		return
	EventFeed.push(get_current_instruction(), Color(0.9, 0.85, 0.5))
	# Check if the new phase's condition is already met — auto-skip
	_check_already_completed()


func is_complete() -> bool:
	return active and current_phase >= PHASE_INSTRUCTIONS.size()


## Call from main.gd each frame to check if current phase condition already satisfied.
## This handles out-of-order completion (e.g. door broken before phase 6).
func check_conditions(game_state: Dictionary) -> void:
	if not active or _pending_advance:
		return
	match current_phase:
		6:
			# Door broken already?
			var all_open: bool = true
			for door_open in game_state.get("doors_open", []):
				if not door_open:
					all_open = false
					break
			if game_state.get("doors_open", []).is_empty():
				all_open = false
			if all_open:
				_advance()
		7:
			# Any enemy already dead?
			if game_state.get("enemies_killed", 0) > 0:
				_advance()


func _check_already_completed() -> void:
	## Stub — actual condition check happens via check_conditions() from main.gd
	pass


# ── Event hooks ───────────────────────────────────────────────────────────────

func on_villager_selected() -> void:
	if not active or current_phase != 1 or _pending_advance:
		return
	_has_selected = true


func on_move_command() -> void:
	if not active or current_phase != 1 or _pending_advance:
		return
	if _has_selected:
		_advance()


func on_shift(old_color: String, _new_color: String, spawn_count: int) -> void:
	if not active or _pending_advance:
		return
	if current_phase == 2:
		_advance()
	elif current_phase == 3:
		if old_color == "red" and spawn_count > 1:
			_advance()


func on_deposit(resource_type: String) -> void:
	if not active or _pending_advance:
		return
	if current_phase == 4 and resource_type == "stone":
		_advance()


func on_fish_delivered() -> void:
	if not active or _pending_advance:
		return
	if current_phase == 5:
		_advance()


func on_door_broken() -> void:
	if not active or _pending_advance:
		return
	if current_phase == 6:
		_advance()


func on_enemy_killed() -> void:
	if not active or _pending_advance:
		return
	if current_phase == 7:
		_advance()


func on_villager_entered_room(_room_id: int) -> void:
	pass


# ── Stubs ─────────────────────────────────────────────────────────────────────

func on_blue_merge() -> void:
	pass

func on_red_day_survived() -> void:
	pass

func on_building_placed() -> void:
	pass

func on_shelter() -> void:
	pass

func on_release() -> void:
	pass

func on_population_update(_total: int) -> void:
	pass
