extends Node
## Tracks per-room faction ownership. A faction gains ownership when it has
## 4+ units in a room with no other faction/NPC/enemy present. Capture takes
## 3 minutes of uncontested presence. Progress pauses if contested, and
## declines at 2x speed after a 3-second grace period when abandoned.

const CAPTURE_THRESHOLD := 4         ## min faction units to start capture
const CAPTURE_TIME := 180.0          ## seconds to fully capture
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


func process_ownership(room_villagers: Dictionary, room_enemies: Dictionary, delta: float) -> void:
	for rid in room_villagers:
		# Already owned — skip capture logic
		if ownership.get(rid, -1) >= 0:
			_handle_owned_room(rid, room_villagers, room_enemies, delta)
			continue

		# Count factions present
		var faction_counts: Dictionary = {}  # faction_id -> count
		var has_npc: bool = false
		for v in room_villagers[rid]:
			if not is_instance_valid(v) or not v.visible:
				continue
			if v.faction_id < 0:
				has_npc = true
				continue
			faction_counts[v.faction_id] = faction_counts.get(v.faction_id, 0) + 1

		var enemy_count: int = room_enemies.get(rid, []).size()
		if enemy_count > 0:
			has_npc = true

		# Determine if exactly one faction qualifies
		var capturing_faction: int = -1
		var capturing_count: int = 0
		var contested: bool = has_npc

		for fid in faction_counts:
			if faction_counts[fid] >= CAPTURE_THRESHOLD:
				if capturing_faction >= 0:
					contested = true  # multiple factions qualify
					break
				capturing_faction = fid
				capturing_count = faction_counts[fid]
			elif faction_counts[fid] > 0:
				contested = true  # another faction present

		if not _capture_state.has(rid):
			# No capture in progress — start one if conditions met
			if capturing_faction >= 0 and not contested:
				_capture_state[rid] = {
					"faction_id": capturing_faction,
					"progress": 0.0,
					"grace_timer": 0.0,
				}
			continue

		var state: Dictionary = _capture_state[rid]
		var cap_fid: int = state["faction_id"]

		# Check if the capturing faction is still present and uncontested
		var cap_present: bool = faction_counts.get(cap_fid, 0) >= CAPTURE_THRESHOLD
		var others_present: bool = contested or (capturing_faction >= 0 and capturing_faction != cap_fid)

		if cap_present and not others_present:
			# Actively capturing
			state["grace_timer"] = 0.0
			state["progress"] += delta
			if state["progress"] >= CAPTURE_TIME:
				# Captured!
				ownership[rid] = cap_fid
				_capture_state.erase(rid)
				EventFeed.push("Faction %d captured room %d!" % [cap_fid, rid], Color(0.4, 0.8, 0.3))
		elif others_present:
			# Contested — pause (don't advance, don't decline)
			state["grace_timer"] = 0.0
		else:
			# Abandoned — grace period then decline
			state["grace_timer"] += delta
			if state["grace_timer"] > ABANDON_GRACE:
				state["progress"] -= delta * DECLINE_MULTIPLIER
				if state["progress"] <= 0.0:
					_capture_state.erase(rid)


func _handle_owned_room(rid: int, room_villagers: Dictionary, room_enemies: Dictionary, _delta: float) -> void:
	## Once owned, ownership is permanent for now. Could add contestation later.
	pass


func clear() -> void:
	_capture_state.clear()
	ownership.clear()
