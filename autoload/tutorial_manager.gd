extends Node
## Manages the optional guided tutorial.
## Phases teach real mechanics one at a time via event hooks from main.gd.
## The tutorial map uses the real gameplay simulation — only objective tracking
## and guidance text are tutorial-specific.
##
## Phases:
##   1 - Select & Move: click a villager, right-click to move
##   2 - Color Shifting: drag/walk a villager near the orb to shift
##   3 - Yellow Duplication: shift a red → spawns 2 yellows (real mechanic)
##   4 - Yellow Stone Collection: yellow picks up stone and deposits at bank
##   5 - Blue Fish Collection: blue picks up fish and delivers to hut
##   6 - Break a Door: red villager breaks the closed door to Room B
##   7 - Kill an Enemy: red villager kills an enemy in Room B
##   8 - Complete: tutorial done

signal phase_completed(phase: int)
signal tutorial_finished()

var active: bool = false
var current_phase: int = 0

## Tutorial room IDs (set by map_generator.generate_tutorial)
var tutorial_room_b_id: int = 1

var _has_selected: bool = false

const PHASE_INSTRUCTIONS: Array[String] = [
	"",  # index 0 unused
	"Phase 1 — Select & Move: Click a villager to select it, then right-click ground to move.",
	"Phase 2 — Color Shift: Walk or drag a villager near the glowing orb to shift its color.",
	"Phase 3 — Duplication: Shift a RED villager — reds produce 2 yellows when shifted!",
	"Phase 4 — Stone: Yellow villagers auto-collect stone. Walk one near stone, then to the bank.",
	"Phase 5 — Fish: Blue villagers auto-collect fish. Walk one near fish, then to the fishing hut.",
	"Phase 6 — Break Door: Move a red villager to the closed door to break it open!",
	"Phase 7 — Combat: Send a red villager near an enemy — reds shoot automatically!",
	"Phase 8 — Tutorial Complete! Press Escape or click Reset to return to title.",
]


func start_tutorial() -> void:
	active = true
	current_phase = 1
	_has_selected = false
	EventFeed.push("Tutorial started! Follow the instructions at the top.", Color(0.9, 0.85, 0.5))


func skip_tutorial() -> void:
	active = false
	current_phase = 0
	tutorial_finished.emit()


func get_current_instruction() -> String:
	if not active or current_phase < 1 or current_phase >= PHASE_INSTRUCTIONS.size():
		return ""
	return PHASE_INSTRUCTIONS[current_phase]


func _advance() -> void:
	phase_completed.emit(current_phase)
	current_phase += 1
	if current_phase >= PHASE_INSTRUCTIONS.size():
		# Don't deactivate — keep showing phase 8 "complete" message
		EventFeed.push("Tutorial complete! You know the basics.", Color(0.7, 0.9, 0.6))
		tutorial_finished.emit()
		return
	EventFeed.push(get_current_instruction(), Color(0.9, 0.85, 0.5))


func is_complete() -> bool:
	return active and current_phase >= PHASE_INSTRUCTIONS.size()


# ── Event hooks ───────────────────────────────────────────────────────────────

func on_villager_selected() -> void:
	if not active or current_phase != 1:
		return
	_has_selected = true


func on_move_command() -> void:
	if not active or current_phase != 1:
		return
	if _has_selected:
		_advance()


func on_shift(old_color: String, _new_color: String, spawn_count: int) -> void:
	if not active:
		return
	if current_phase == 2:
		_advance()
	elif current_phase == 3:
		# Red shifts to yellow and spawns 2 (on_shift_spawn_count = 2 for red)
		if old_color == "red" and spawn_count > 1:
			_advance()


func on_deposit(resource_type: String) -> void:
	if not active:
		return
	if current_phase == 4 and resource_type == "stone":
		_advance()


func on_fish_delivered() -> void:
	if not active:
		return
	if current_phase == 5:
		_advance()


func on_door_broken() -> void:
	if not active:
		return
	if current_phase == 6:
		_advance()


func on_enemy_killed() -> void:
	if not active:
		return
	if current_phase == 7:
		_advance()


func on_villager_entered_room(_room_id: int) -> void:
	pass  # No longer used as a phase trigger


# ── Stubs: called by main.gd, safe no-ops ────────────────────────────────────

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
