extends Node
## Tracks per-room faction ownership.
## One faction present → captures. Two+ factions → frozen.
## No faction present → decays at 2x. Capturing enemy room takes 2x (neutralize first).
## Solo mode: faction 0 can still capture and borders are shown.

const CAPTURE_THRESHOLD := 1         ## min faction units to start capture
const CAPTURE_TIME := 90.0           ## seconds to fully capture unowned room
const ENEMY_CAPTURE_MULT := 2.0      ## capturing enemy-owned room takes 2x
const ABANDON_GRACE := 3.0           ## seconds before decline starts
const DECLINE_MULTIPLIER := 2.0      ## decay speed relative to capture speed

## room_id -> { "faction_id": int, "progress": float, "grace_timer": float }
var _capture_state: Dictionary = {}

## room_id -> int (faction that owns it, -1 = unowned)
var ownership: Dictionary = {}


func get_room_owner(room_id: int) -> int:
	return ownership.get(room_id, -1)


func get_progress(room_id: int) -> Dictionary:
	return _capture_state.get(room_id, {})


func get_capture_progress_ratio(room_id: int) -> float:
	var state: Dictionary = _capture_state.get(room_id, {})
	if state.is_empty():
		return 0.0
	var cap_time: float = CAPTURE_TIME
	# If capturing a room owned by another faction, it takes 2x
	var current_owner: int = ownership.get(room_id, -1)
	if current_owner >= 0 and current_owner != state.get("faction_id", -1):
		cap_time *= ENEMY_CAPTURE_MULT
	return clampf(float(state.get("progress", 0.0)) / cap_time, 0.0, 1.0)


func get_capture_faction(room_id: int) -> int:
	return _capture_state.get(room_id, {}).get("faction_id", -1)


func process_ownership(room_villagers: Dictionary, room_enemies: Dictionary, delta: float) -> void:
	for rid in room_villagers:
		# Count factions present
		var faction_counts: Dictionary = {}  # faction_id -> count
		for v in room_villagers[rid]:
			if not is_instance_valid(v) or not v.visible:
				continue
			if v.faction_id < 0:
				continue
			if str(v.color_type) == "magic_orb":
				continue
			faction_counts[v.faction_id] = faction_counts.get(v.faction_id, 0) + 1

		var factions_present: Array = faction_counts.keys()
		var current_owner: int = ownership.get(rid, -1)

		# Determine capture scenario
		if factions_present.size() == 1:
			var fid: int = factions_present[0]
			if fid == current_owner:
				# Already owned by this faction — nothing to do, clear any capture state
				_capture_state.erase(rid)
				continue

			# Single faction present, not the owner — capture/contest
			var cap_time: float = CAPTURE_TIME
			if current_owner >= 0:
				cap_time *= ENEMY_CAPTURE_MULT  # takes 2x to capture enemy room

			if not _capture_state.has(rid):
				_capture_state[rid] = {"faction_id": fid, "progress": 0.0, "grace_timer": 0.0}
			var state: Dictionary = _capture_state[rid]

			# If a different faction was capturing, reset
			if state["faction_id"] != fid:
				state["faction_id"] = fid
				state["progress"] = 0.0
				state["grace_timer"] = 0.0

			state["grace_timer"] = 0.0
			state["progress"] += delta
			if state["progress"] >= cap_time:
				if current_owner >= 0 and current_owner != fid:
					# Neutralize first — make unowned
					ownership[rid] = -1
					state["progress"] = 0.0
					EventFeed.push("Room %d neutralized!" % rid, Color(0.7, 0.7, 0.5))
				else:
					# Capture!
					ownership[rid] = fid
					_capture_state.erase(rid)
					var sym: String = FactionManager.get_faction_symbol(fid)
					EventFeed.push("Faction %s captured room %d!" % [sym, rid], FactionManager.get_faction_color(fid))

		elif factions_present.size() >= 2:
			# Contested — freeze timer (don't advance, don't decline)
			if _capture_state.has(rid):
				_capture_state[rid]["grace_timer"] = 0.0

		else:
			# No faction present — decay
			if _capture_state.has(rid):
				var state: Dictionary = _capture_state[rid]
				state["grace_timer"] += delta
				if state["grace_timer"] > ABANDON_GRACE:
					state["progress"] -= delta * DECLINE_MULTIPLIER
					if state["progress"] <= 0.0:
						_capture_state.erase(rid)


func clear() -> void:
	_capture_state.clear()
	ownership.clear()
