extends Control
## Pre-game lobby. Solo/Host/Join modes.
## Config: Players, Max Pop, Mode, Seed. Faction picking in waiting screens.
## Solo: configure → Start → straight to game.

var player_count: int = 1
var max_pop: int = 50
var map_seed_text: String = ""
var _hover: String = ""

var net_mode: String = "solo"
var join_address: String = "localhost"

## Lobby state: "config", "waiting_host", "waiting_client"
var _state: String = "config"

const MAX_PLAYERS := 8
const MAX_FACTIONS := 8
const FACTION_COLORS: Array[Color] = [
	Color(0.2, 0.6, 0.9), Color(0.9, 0.3, 0.25), Color(0.2, 0.75, 0.3),
	Color(0.9, 0.75, 0.15), Color(0.7, 0.3, 0.8), Color(0.9, 0.5, 0.2),
	Color(0.5, 0.8, 0.8), Color(0.8, 0.4, 0.6),
]
const FACTION_NAMES: Array[String] = ["$", "@", "?", "¥", "£", "€", "#", "%"]


func _ready() -> void:
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)


func _exit_tree() -> void:
	if NetworkManager.game_started.is_connected(_on_game_started):
		NetworkManager.game_started.disconnect(_on_game_started)
	if NetworkManager.connection_succeeded.is_connected(_on_connection_succeeded):
		NetworkManager.connection_succeeded.disconnect(_on_connection_succeeded)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _get_element_at(event.position)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var elem: String = _get_element_at(event.position)

		if _state == "config":
			match elem:
				"players_up": player_count = mini(player_count + 1, MAX_PLAYERS)
				"players_down": player_count = maxi(player_count - 1, 1)
				"maxpop_up": max_pop = mini(max_pop + 10, 200)
				"maxpop_down": max_pop = maxi(max_pop - 10, 10)
				"mode_solo": net_mode = "solo"
				"mode_host": net_mode = "host"
				"mode_join": net_mode = "join"
				"start": _on_start_pressed()
				"back": _go_back()
				_:
					# Solo faction picker
					if elem.begins_with("solo_f_"):
						var fi: int = int(elem.substr(7))
						NetworkManager.synced_peer_factions[1] = fi

		elif _state == "waiting_host":
			if elem == "launch": _launch_game()
			elif elem == "cancel":
				NetworkManager.disconnect_game(); _state = "config"
			elif elem == "ready": NetworkManager.send_ready_toggle()
			elif elem.begins_with("wh_pf_"):
				var idx: int = int(elem.substr(6))
				var all_p: Array[int] = NetworkManager.get_all_peer_ids()
				if idx >= 0 and idx < all_p.size():
					var pid: int = all_p[idx]
					var cur: int = NetworkManager.synced_peer_factions.get(pid, 0)
					NetworkManager.synced_peer_factions[pid] = (cur + 1) % MAX_FACTIONS

		elif _state == "waiting_client":
			if elem == "cancel":
				NetworkManager.disconnect_game(); _state = "config"
			elif elem == "ready": NetworkManager.send_ready_toggle()
			elif elem.begins_with("wc_pf_"):
				var my_pid: int = NetworkManager.get_my_peer_id()
				var cur: int = NetworkManager.synced_peer_factions.get(my_pid, 0)
				NetworkManager.send_faction_choice((cur + 1) % MAX_FACTIONS)

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if _state != "config":
				NetworkManager.disconnect_game(); _state = "config"
			else:
				get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _state == "config": _on_start_pressed()
			elif _state == "waiting_host": _launch_game()
		elif event.keycode == KEY_BACKSPACE and _state == "config":
			if net_mode == "join" and join_address.length() > 0:
				join_address = join_address.substr(0, join_address.length() - 1)
			elif map_seed_text.length() > 0:
				map_seed_text = map_seed_text.substr(0, map_seed_text.length() - 1)
		elif event.unicode > 0 and _state == "config":
			var ch: String = char(event.unicode)
			if net_mode == "join" and join_address.length() < 40:
				if ch.is_valid_int() or ch == "." or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
					join_address += ch
			elif map_seed_text.length() < 12:
				if ch.is_valid_int() or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
					map_seed_text += ch


func _on_start_pressed() -> void:
	match net_mode:
		"solo":
			# Determine faction count from solo faction pick (always 1 faction in solo)
			var solo_fid: int = NetworkManager.synced_peer_factions.get(1, 0)
			FactionManager.clear()
			FactionManager.register_faction(solo_fid, FACTION_NAMES[solo_fid], FACTION_COLORS[solo_fid])
			FactionManager.local_faction_id = solo_fid
			_set_game_config(1)
			SaveManager.delete_save()
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		"host":
			var err := NetworkManager.host_game()
			if err != OK:
				EventFeed.push("Failed to host!", Color(0.9, 0.3, 0.3)); return
			NetworkManager.synced_peer_factions[1] = NetworkManager.synced_peer_factions.get(1, 0)
			NetworkManager.synced_faction_count = MAX_FACTIONS
			var seed_val: int = hash(map_seed_text) if map_seed_text != "" else -1
			NetworkManager.broadcast_lobby_config(seed_val, MAX_FACTIONS, NetworkManager.synced_peer_factions, max_pop)
			_state = "waiting_host"
		"join":
			var err := NetworkManager.join_game(join_address)
			if err != OK:
				EventFeed.push("Failed to connect!", Color(0.9, 0.3, 0.3)); return
			_state = "waiting_client"


func _launch_game() -> void:
	if not is_inside_tree() or not NetworkManager.are_all_ready():
		return
	var pfmap: Dictionary = NetworkManager.synced_peer_factions.duplicate()
	# Count distinct factions used
	var used_factions: Dictionary = {}
	for pid in pfmap:
		used_factions[pfmap[pid]] = true
	var fcount: int = used_factions.size()
	# Setup FactionManager from synced state
	FactionManager.clear()
	for fid in used_factions:
		FactionManager.register_faction(fid, FACTION_NAMES[fid], FACTION_COLORS[fid])
	FactionManager.local_faction_id = pfmap.get(1, 0)
	FactionManager.max_population = max_pop
	_set_game_config(fcount)
	NetworkManager.broadcast_lobby_config(
		hash(map_seed_text) if map_seed_text != "" else -1,
		fcount, pfmap, max_pop)
	NetworkManager.broadcast_start_game()
	SaveManager.delete_save()
	call_deferred("_deferred_change_to_main")


func _on_game_started() -> void:
	if not is_inside_tree():
		return
	FactionManager.clear()
	# Register only factions that are actually used
	var used: Dictionary = {}
	for pid in NetworkManager.synced_peer_factions:
		var fid: int = int(NetworkManager.synced_peer_factions[pid])
		used[fid] = true
	for fid in used:
		FactionManager.register_faction(fid, FACTION_NAMES[fid], FACTION_COLORS[fid])
	var my_peer: int = NetworkManager.get_my_peer_id()
	FactionManager.local_faction_id = NetworkManager.get_faction_for_peer(my_peer)
	FactionManager.max_population = NetworkManager.synced_max_population
	FactionManager.set_meta("map_seed", NetworkManager.synced_map_seed)
	FactionManager.set_meta("faction_count", NetworkManager.synced_faction_count)
	FactionManager.set_meta("player_count", NetworkManager.get_all_peer_ids().size())
	FactionManager.set_meta("peer_factions", NetworkManager.synced_peer_factions.duplicate())
	SaveManager.delete_save()
	call_deferred("_deferred_change_to_main")


func _deferred_change_to_main() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_connection_succeeded() -> void:
	pass

func _on_connection_failed() -> void:
	_state = "config"


func _set_game_config(fcount: int) -> void:
	var seed_val: int = hash(map_seed_text) if map_seed_text != "" else -1
	FactionManager.set_meta("map_seed", seed_val)
	FactionManager.set_meta("player_count", player_count)
	FactionManager.set_meta("faction_count", fcount)
	FactionManager.max_population = max_pop


func _go_back() -> void:
	NetworkManager.disconnect_game()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


# ==============================================================================
# HIT TESTING
# ==============================================================================

func _get_element_at(pos: Vector2) -> String:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5

	if _state == "waiting_host":
		if NetworkManager.are_all_ready():
			if Rect2(cx - 100, vp.y - 100, 200, 50).has_point(pos): return "launch"
		if Rect2(cx - 100, vp.y - 170, 200, 40).has_point(pos): return "cancel"
		var all_p: Array[int] = NetworkManager.get_all_peer_ids()
		var rby: float = 150.0 + all_p.size() * 40.0 + 20
		if Rect2(cx - 100, rby, 200, 36).has_point(pos): return "ready"
		for i in all_p.size():
			if Rect2(cx - 20, 150.0 + i * 40.0 - 2, 80, 28).has_point(pos): return "wh_pf_%d" % i
		return ""

	if _state == "waiting_client":
		if Rect2(cx - 100, vp.y - 100, 200, 40).has_point(pos): return "cancel"
		var all_c: Array[int] = NetworkManager.get_all_peer_ids()
		var rby_c: float = 150.0 + all_c.size() * 40.0 + 20
		if Rect2(cx - 100, rby_c, 200, 36).has_point(pos): return "ready"
		var my_pid: int = NetworkManager.get_my_peer_id()
		for i in all_c.size():
			if all_c[i] == my_pid:
				if Rect2(cx - 20, 150.0 + i * 40.0 - 2, 80, 28).has_point(pos): return "wc_pf_%d" % i
		return ""

	# Config screen
	var top: float = 80.0
	var bw: float = 40.0; var bh: float = 32.0
	var mode_y: float = top + 40
	if Rect2(cx - 140, mode_y, 80, 30).has_point(pos): return "mode_solo"
	if Rect2(cx - 45, mode_y, 80, 30).has_point(pos): return "mode_host"
	if Rect2(cx + 50, mode_y, 80, 30).has_point(pos): return "mode_join"
	var row_y: float = top + 100
	if Rect2(cx + 60, row_y - 4, bw, bh).has_point(pos): return "players_up"
	if Rect2(cx + 110, row_y - 4, bw, bh).has_point(pos): return "players_down"
	row_y = top + 145
	if Rect2(cx + 60, row_y - 4, bw, bh).has_point(pos): return "maxpop_up"
	if Rect2(cx + 110, row_y - 4, bw, bh).has_point(pos): return "maxpop_down"
	# Solo faction picker
	if net_mode == "solo":
		var fy: float = top + 210
		for i in MAX_FACTIONS:
			if Rect2(cx - 140 + i * 38, fy, 32, 32).has_point(pos): return "solo_f_%d" % i
	if Rect2(cx - 100, vp.y - 100, 200, 50).has_point(pos): return "start"
	if Rect2(20, 20, 80, 32).has_point(pos): return "back"
	return ""


# ==============================================================================
# DRAWING
# ==============================================================================

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.06, 0.06, 0.1))
	if _state == "waiting_host": _draw_waiting(vp, cx, true); return
	if _state == "waiting_client": _draw_waiting(vp, cx, false); return
	_draw_config(vp, cx)


func _draw_config(vp: Vector2, cx: float) -> void:
	var top: float = 80.0
	draw_string(ThemeDB.fallback_font, Vector2(cx - 80, top), "Game Setup", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	var back_h: bool = (_hover == "back")
	draw_rect(Rect2(20, 20, 80, 32), Color(0.2, 0.2, 0.25, 0.8) if back_h else Color(0.12, 0.12, 0.15, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(36, 42), "< Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.8, 0.8) if back_h else Color(0.5, 0.5, 0.5))

	# Mode
	var mode_y: float = top + 40
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, mode_y - 6), "Mode:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.6))
	_draw_mode_btn(cx - 140, mode_y, 80, 30, "Solo", "mode_solo", net_mode == "solo")
	_draw_mode_btn(cx - 45, mode_y, 80, 30, "Host", "mode_host", net_mode == "host")
	_draw_mode_btn(cx + 50, mode_y, 80, 30, "Join", "mode_join", net_mode == "join")

	if net_mode == "join":
		var addr_y: float = mode_y + 38
		draw_string(ThemeDB.fallback_font, Vector2(cx - 140, addr_y + 16), "Address:", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
		draw_rect(Rect2(cx - 30, addr_y - 2, 180, 24), Color(0.1, 0.1, 0.14, 0.8))
		var cur: String = "|" if int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
		draw_string(ThemeDB.fallback_font, Vector2(cx - 22, addr_y + 14), join_address + cur, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.8))

	# Players
	var row_y: float = top + 100
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, row_y + 18), "Players:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, row_y + 18), str(player_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, row_y - 4, 40, 32, "+", "players_up")
	_draw_btn(cx + 110, row_y - 4, 40, 32, "-", "players_down")

	# Max Pop
	row_y = top + 145
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, row_y + 18), "Max Pop:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, row_y + 18), str(max_pop), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, row_y - 4, 40, 32, "+", "maxpop_up")
	_draw_btn(cx + 110, row_y - 4, 40, 32, "-", "maxpop_down")

	# Solo faction picker
	if net_mode == "solo":
		var fy: float = top + 210
		var solo_fid: int = NetworkManager.synced_peer_factions.get(1, 0)
		draw_string(ThemeDB.fallback_font, Vector2(cx - 140, fy - 6), "Your Faction:", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.6))
		for i in MAX_FACTIONS:
			var fc: Color = FACTION_COLORS[i]
			var selected: bool = (i == solo_fid)
			var hovered: bool = (_hover == "solo_f_%d" % i)
			var bg: Color = fc.lightened(0.1) if selected else (fc.darkened(0.2) if hovered else fc.darkened(0.5))
			bg.a = 0.95 if selected else 0.6
			draw_rect(Rect2(cx - 140 + i * 38, fy, 32, 32), bg)
			if selected:
				draw_rect(Rect2(cx - 140 + i * 38, fy, 32, 32), Color(1, 1, 1, 0.8), false, 2.0)
			draw_string(ThemeDB.fallback_font, Vector2(cx - 130 + i * 38, fy + 22), FACTION_NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

	# Seed
	var seed_y: float = top + 270
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, seed_y + 18), "Map Seed:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var sd: String = map_seed_text if map_seed_text != "" else "(random)"
	draw_rect(Rect2(cx + 10, seed_y - 2, 160, 28), Color(0.1, 0.1, 0.14, 0.8))
	var cur2: String = "|" if net_mode != "join" and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, seed_y + 16), sd + cur2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7) if map_seed_text != "" else Color(0.45, 0.45, 0.45))

	# Start
	var start_y: float = vp.y - 100
	var sh: bool = (_hover == "start")
	var sl: String = "START" if net_mode != "join" else "JOIN"
	draw_rect(Rect2(cx - 100, start_y, 200, 50), Color(0.2, 0.35, 0.2, 0.95) if sh else Color(0.12, 0.2, 0.12, 0.85))
	draw_rect(Rect2(cx - 100, start_y, 200, 50), Color(0.4, 0.6, 0.3, 0.6), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 30, start_y + 32), sl, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(0.95, 0.95, 0.85) if sh else Color(0.7, 0.7, 0.6))


func _draw_waiting(vp: Vector2, cx: float, is_host_view: bool) -> void:
	var title: String = "LOBBY — HOST" if is_host_view else "LOBBY — CLIENT"
	draw_string(ThemeDB.fallback_font, Vector2(cx - 100, 80), title, HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	var all_peers: Array[int] = NetworkManager.get_all_peer_ids()
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, 120), "%d player(s)" % all_peers.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.8, 0.5))

	var list_y: float = 150.0
	var my_pid: int = NetworkManager.get_my_peer_id()
	for i in all_peers.size():
		var pid: int = all_peers[i]
		var fid: int = NetworkManager.synced_peer_factions.get(pid, 0)
		var is_ready: bool = NetworkManager.synced_peer_ready.get(pid, false)
		var ry: float = list_y + i * 40.0
		var fc: Color = FACTION_COLORS[fid] if fid < FACTION_COLORS.size() else Color.WHITE
		var sym: String = FACTION_NAMES[fid] if fid < FACTION_NAMES.size() else "?"
		var is_me: bool = (pid == my_pid)
		var tags: String = ""
		if pid == 1: tags += " (Host)"
		if is_me: tags += " (You)"

		draw_string(ThemeDB.fallback_font, Vector2(cx - 140, ry + 16), "P%d%s" % [i + 1, tags], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.7) if is_me else Color(0.7, 0.7, 0.7))

		# Faction button — host can click any, client only own
		var can_click: bool = is_host_view or is_me
		var prefix: String = "wh_pf_" if is_host_view else "wc_pf_"
		var fh: bool = can_click and (_hover == "%s%d" % [prefix, i])
		draw_rect(Rect2(cx - 20, ry - 2, 80, 28), fc.darkened(0.3 if not fh else 0.0))
		draw_rect(Rect2(cx - 20, ry - 2, 80, 28), Color(0.5, 0.5, 0.5, 0.4), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(cx, ry + 16), sym, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

		var ready_txt: String = "READY" if is_ready else "..."
		draw_string(ThemeDB.fallback_font, Vector2(cx + 80, ry + 16), ready_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.8, 0.3) if is_ready else Color(0.5, 0.4, 0.4))

	# Ready button
	var my_ready: bool = NetworkManager.synced_peer_ready.get(my_pid, false)
	var rby: float = list_y + all_peers.size() * 40.0 + 20
	var rh: bool = (_hover == "ready")
	var rbg: Color = Color(0.2, 0.4, 0.2, 0.9) if my_ready else (Color(0.25, 0.3, 0.2, 0.85) if rh else Color(0.15, 0.18, 0.12, 0.7))
	draw_rect(Rect2(cx - 100, rby, 200, 36), rbg)
	draw_rect(Rect2(cx - 100, rby, 200, 36), Color(0.4, 0.6, 0.3, 0.5), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 40, rby + 24), "READY" if my_ready else "Click to Ready", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.9, 0.9, 0.85))

	# Cancel
	draw_rect(Rect2(cx - 100, vp.y - 170, 200, 40), Color(0.25, 0.15, 0.15, 0.8) if _hover == "cancel" else Color(0.15, 0.1, 0.1, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 25, vp.y - 145), "Cancel", HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.8, 0.6, 0.6) if _hover == "cancel" else Color(0.5, 0.4, 0.4))

	# Launch (host only, all ready)
	if is_host_view:
		var all_ready: bool = NetworkManager.are_all_ready()
		var lh: bool = (_hover == "launch") and all_ready
		var lbg: Color = Color(0.2, 0.4, 0.2, 0.95) if lh else (Color(0.15, 0.25, 0.15, 0.85) if all_ready else Color(0.1, 0.1, 0.1, 0.5))
		draw_rect(Rect2(cx - 100, vp.y - 100, 200, 50), lbg)
		draw_rect(Rect2(cx - 100, vp.y - 100, 200, 50), Color(0.4, 0.6, 0.3, 0.6) if all_ready else Color(0.2, 0.2, 0.2, 0.3), false, 2.0)
		var label: String = "LAUNCH GAME" if all_ready else "Waiting for ready..."
		draw_string(ThemeDB.fallback_font, Vector2(cx - 60, vp.y - 68), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.95, 0.95, 0.85) if lh else Color(0.5, 0.5, 0.5))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(cx - 80, vp.y - 60), "Waiting for host to launch...", HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.4, 0.4, 0.45))


func _draw_btn(x: float, y: float, w: float, h: float, label: String, elem_id: String) -> void:
	var hovered: bool = (_hover == elem_id)
	draw_rect(Rect2(x, y, w, h), Color(0.22, 0.25, 0.2, 0.9) if hovered else Color(0.14, 0.16, 0.13, 0.7))
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.4, 0.4, 0.4), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + w * 0.35, y + h * 0.7), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.9, 0.9, 0.85) if hovered else Color(0.6, 0.6, 0.55))


func _draw_mode_btn(x: float, y: float, w: float, h: float, label: String, elem_id: String, active: bool) -> void:
	var hovered: bool = (_hover == elem_id)
	var bg: Color = Color(0.2, 0.35, 0.5, 0.95) if active else (Color(0.18, 0.22, 0.28, 0.85) if hovered else Color(0.12, 0.14, 0.18, 0.7))
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.5, 0.6, 0.5) if active else Color(0.3, 0.3, 0.3, 0.3), false, 1.5 if active else 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + 10, y + h * 0.7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95) if active else (Color(0.85, 0.85, 0.85) if hovered else Color(0.55, 0.55, 0.55)))
