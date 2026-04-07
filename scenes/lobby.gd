extends Control
## Pre-game lobby. Solo/Host/Join modes.
## Host flow: configure → Start → wait for peers → Launch Game.
## Join flow: enter address → Join → wait for host to launch.
## Solo: configure → Start → straight to game.

var player_count: int = 1
var faction_count: int = 1
var map_seed_text: String = ""
var _hover: String = ""

var net_mode: String = "solo"
var join_address: String = "localhost"

## Lobby state: "config", "waiting_host", "waiting_client"
var _state: String = "config"

const MAX_PLAYERS := 8
const MAX_FACTIONS := 4
const FACTION_COLORS: Array[Color] = [
	Color(0.2, 0.6, 0.9),
	Color(0.9, 0.3, 0.25),
	Color(0.2, 0.75, 0.3),
	Color(0.9, 0.75, 0.15),
]
const FACTION_NAMES: Array[String] = ["Blue", "Red", "Green", "Gold"]

var player_factions: Array[int] = [0]


func _ready() -> void:
	_rebuild_player_factions()
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


func _rebuild_player_factions() -> void:
	player_factions.resize(player_count)
	for i in player_count:
		if i >= player_factions.size():
			player_factions.append(0)
		player_factions[i] = clampi(player_factions[i], 0, faction_count - 1)


func _process(_delta: float) -> void:
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _get_element_at(event.position)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var elem: String = _get_element_at(event.position)

		if _state == "config":
			match elem:
				"players_up":
					player_count = mini(player_count + 1, MAX_PLAYERS)
					_rebuild_player_factions()
				"players_down":
					player_count = maxi(player_count - 1, 1)
					_rebuild_player_factions()
				"factions_up":
					faction_count = mini(faction_count + 1, MAX_FACTIONS)
					_rebuild_player_factions()
				"factions_down":
					faction_count = maxi(faction_count - 1, 1)
					_rebuild_player_factions()
				"mode_solo": net_mode = "solo"
				"mode_host": net_mode = "host"
				"mode_join": net_mode = "join"
				"start": _on_start_pressed()
				"back": _go_back()
				_:
					if elem.begins_with("pf_"):
						var idx: int = int(elem.substr(3))
						if idx >= 0 and idx < player_count:
							player_factions[idx] = (player_factions[idx] + 1) % faction_count

		elif _state == "waiting_host":
			if elem == "launch":
				_launch_game()
			elif elem == "cancel":
				NetworkManager.disconnect_game()
				_state = "config"

		elif _state == "waiting_client":
			if elem == "cancel":
				NetworkManager.disconnect_game()
				_state = "config"

	# Keyboard
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if _state != "config":
				NetworkManager.disconnect_game()
				_state = "config"
			else:
				get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if _state == "config":
				_on_start_pressed()
			elif _state == "waiting_host":
				_launch_game()
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
			_setup_factions()
			_set_game_config()
			SaveManager.delete_save()
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		"host":
			var err := NetworkManager.host_game()
			if err != OK:
				EventFeed.push("Failed to host!", Color(0.9, 0.3, 0.3))
				return
			_setup_factions()
			var seed_val: int = -1
			if map_seed_text != "":
				seed_val = hash(map_seed_text)
			# Build initial peer→faction map (just host for now)
			var pfmap := _build_peer_faction_map()
			NetworkManager.broadcast_lobby_config(seed_val, faction_count, pfmap)
			_state = "waiting_host"
		"join":
			var err := NetworkManager.join_game(join_address)
			if err != OK:
				EventFeed.push("Failed to connect!", Color(0.9, 0.3, 0.3))
				return
			_state = "waiting_client"


func _launch_game() -> void:
	if not is_inside_tree():
		return
	_set_game_config()
	var pfmap := _build_peer_faction_map()
	NetworkManager.broadcast_lobby_config(
		hash(map_seed_text) if map_seed_text != "" else -1,
		faction_count, pfmap)
	NetworkManager.broadcast_start_game()
	SaveManager.delete_save()
	call_deferred("_deferred_change_to_main")


func _build_peer_faction_map() -> Dictionary:
	## Map peer_id → faction_id. Host = P1, connected peers = P2, P3, ...
	var pfmap: Dictionary = {}
	var ordered: Array[int] = [1]  # host is always peer_id 1
	ordered.append_array(NetworkManager.connected_peers)
	for i in mini(player_count, ordered.size()):
		pfmap[ordered[i]] = player_factions[i]
	return pfmap


func _on_game_started() -> void:
	## Client receives start signal from host.
	if not is_inside_tree():
		return
	FactionManager.clear()
	for i in NetworkManager.synced_faction_count:
		FactionManager.register_faction(i, FACTION_NAMES[i], FACTION_COLORS[i])
	# Peer→faction lookup — no index ambiguity
	var my_peer: int = NetworkManager.get_my_peer_id()
	FactionManager.local_faction_id = NetworkManager.get_faction_for_peer(my_peer)

	var all_peers: Array[int] = NetworkManager.get_all_peer_ids()
	FactionManager.set_meta("map_seed", NetworkManager.synced_map_seed)
	FactionManager.set_meta("faction_count", NetworkManager.synced_faction_count)
	FactionManager.set_meta("player_count", all_peers.size())
	FactionManager.set_meta("peer_factions", NetworkManager.synced_peer_factions.duplicate())
	SaveManager.delete_save()
	call_deferred("_deferred_change_to_main")


func _deferred_change_to_main() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_connection_succeeded() -> void:
	pass  # already in waiting_client state


func _on_connection_failed() -> void:
	_state = "config"


func _setup_factions() -> void:
	FactionManager.clear()
	for i in faction_count:
		FactionManager.register_faction(i, FACTION_NAMES[i], FACTION_COLORS[i])
	FactionManager.local_faction_id = player_factions[0]


func _set_game_config() -> void:
	var seed_val: int = -1
	if map_seed_text != "":
		seed_val = hash(map_seed_text)
	FactionManager.set_meta("map_seed", seed_val)
	FactionManager.set_meta("player_count", player_count)
	FactionManager.set_meta("faction_count", faction_count)
	FactionManager.set_meta("player_factions", player_factions.duplicate())


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
		if Rect2(cx - 100, vp.y - 100, 200, 50).has_point(pos): return "launch"
		if Rect2(cx - 100, vp.y - 170, 200, 40).has_point(pos): return "cancel"
		return ""
	if _state == "waiting_client":
		if Rect2(cx - 100, vp.y - 100, 200, 40).has_point(pos): return "cancel"
		return ""

	var top: float = 80.0
	var bw: float = 40.0
	var bh: float = 32.0
	var mode_y: float = top + 40
	if Rect2(cx - 140, mode_y, 80, 30).has_point(pos): return "mode_solo"
	if Rect2(cx - 45, mode_y, 80, 30).has_point(pos): return "mode_host"
	if Rect2(cx + 50, mode_y, 80, 30).has_point(pos): return "mode_join"
	var row_y: float = top + 100
	if Rect2(cx + 60, row_y - 4, bw, bh).has_point(pos): return "players_up"
	if Rect2(cx + 110, row_y - 4, bw, bh).has_point(pos): return "players_down"
	row_y = top + 145
	if Rect2(cx + 60, row_y - 4, bw, bh).has_point(pos): return "factions_up"
	if Rect2(cx + 110, row_y - 4, bw, bh).has_point(pos): return "factions_down"
	var assign_y: float = top + 210
	for i in player_count:
		var by: float = assign_y + i * 36.0
		if Rect2(cx + 40, by - 2, 100, 28).has_point(pos): return "pf_%d" % i
	var start_y: float = vp.y - 100
	if Rect2(cx - 100, start_y, 200, 50).has_point(pos): return "start"
	if Rect2(20, 20, 80, 32).has_point(pos): return "back"
	return ""


# ==============================================================================
# DRAWING
# ==============================================================================

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.06, 0.06, 0.1))

	if _state == "waiting_host":
		_draw_waiting_host(vp, cx)
		return
	if _state == "waiting_client":
		_draw_waiting_client(vp, cx)
		return

	_draw_config(vp, cx)


func _draw_config(vp: Vector2, cx: float) -> void:
	var top: float = 80.0

	draw_string(ThemeDB.fallback_font, Vector2(cx - 80, top),
		"Game Setup", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	# Back
	var back_h: bool = (_hover == "back")
	draw_rect(Rect2(20, 20, 80, 32), Color(0.2, 0.2, 0.25, 0.8) if back_h else Color(0.12, 0.12, 0.15, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(36, 42), "< Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(0.8, 0.8, 0.8) if back_h else Color(0.5, 0.5, 0.5))

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
		draw_rect(Rect2(cx - 30, addr_y - 2, 180, 24), Color(0.35, 0.35, 0.4, 0.5), false, 1.0)
		var cur: String = "|" if int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
		draw_string(ThemeDB.fallback_font, Vector2(cx - 22, addr_y + 14), join_address + cur, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.9, 0.8))

	# Players / Factions
	var row_y: float = top + 100
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, row_y + 18), "Players:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, row_y + 18), str(player_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, row_y - 4, 40, 32, "+", "players_up")
	_draw_btn(cx + 110, row_y - 4, 40, 32, "-", "players_down")
	row_y = top + 145
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, row_y + 18), "Factions:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, row_y + 18), str(faction_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, row_y - 4, 40, 32, "+", "factions_up")
	_draw_btn(cx + 110, row_y - 4, 40, 32, "-", "factions_down")

	# Assignments
	var assign_y: float = top + 210
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, assign_y - 6), "Assignments (click to cycle):", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.6))
	for i in player_count:
		var by: float = assign_y + i * 36.0
		var fi: int = player_factions[i]
		var fc: Color = FACTION_COLORS[fi]
		var fn: String = FACTION_NAMES[fi]
		var label: String = "P%d%s" % [i + 1, " (You)" if i == 0 else ""]
		draw_string(ThemeDB.fallback_font, Vector2(cx - 140, by + 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.7, 0.7))
		var bh: bool = (_hover == "pf_%d" % i)
		draw_rect(Rect2(cx + 40, by - 2, 100, 28), fc.darkened(0.3 if not bh else 0.0))
		draw_rect(Rect2(cx + 40, by - 2, 100, 28), Color(0.5, 0.5, 0.5, 0.4), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(cx + 60, by + 16), fn, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))

	# Seed
	var seed_y: float = assign_y + player_count * 36.0 + 20
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, seed_y + 18), "Map Seed:", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var sd: String = map_seed_text if map_seed_text != "" else "(random)"
	var sc: Color = Color(0.95, 0.9, 0.7) if map_seed_text != "" else Color(0.45, 0.45, 0.45)
	draw_rect(Rect2(cx + 10, seed_y - 2, 160, 28), Color(0.1, 0.1, 0.14, 0.8))
	draw_rect(Rect2(cx + 10, seed_y - 2, 160, 28), Color(0.35, 0.35, 0.4, 0.5), false, 1.0)
	var cur2: String = "|" if net_mode != "join" and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, seed_y + 16), sd + cur2, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, sc)

	# Start
	var start_y: float = vp.y - 100
	var sh: bool = (_hover == "start")
	var sl: String = "START" if net_mode != "join" else "JOIN"
	draw_rect(Rect2(cx - 100, start_y, 200, 50), Color(0.2, 0.35, 0.2, 0.95) if sh else Color(0.12, 0.2, 0.12, 0.85))
	draw_rect(Rect2(cx - 100, start_y, 200, 50), Color(0.4, 0.6, 0.3, 0.6), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 30, start_y + 32), sl, HORIZONTAL_ALIGNMENT_CENTER, -1, 22,
		Color(0.95, 0.95, 0.85) if sh else Color(0.7, 0.7, 0.6))

	draw_string(ThemeDB.fallback_font, Vector2(cx - 100, vp.y - 20),
		"Solo = offline  |  Host/Join = ENet multiplayer",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.35, 0.35, 0.4))


func _draw_waiting_host(vp: Vector2, cx: float) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(cx - 120, 120),
		"Waiting for Players", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	var peers: int = NetworkManager.get_peer_count()
	draw_string(ThemeDB.fallback_font, Vector2(cx - 60, 180),
		"%d player(s) connected" % peers, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.5, 0.8, 0.5))

	# Dots animation
	var dots: String = ".".repeat((int(Time.get_ticks_msec() / 500) % 4))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 20, 210),
		"Listening%s" % dots, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.45, 0.45, 0.5))

	# Cancel
	var ch: bool = (_hover == "cancel")
	draw_rect(Rect2(cx - 100, vp.y - 170, 200, 40), Color(0.25, 0.15, 0.15, 0.8) if ch else Color(0.15, 0.1, 0.1, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 25, vp.y - 145), "Cancel", HORIZONTAL_ALIGNMENT_CENTER, -1, 16,
		Color(0.8, 0.6, 0.6) if ch else Color(0.5, 0.4, 0.4))

	# Launch
	var can_launch: bool = peers > 0
	var lh: bool = (_hover == "launch") and can_launch
	var lbg: Color = Color(0.2, 0.4, 0.2, 0.95) if lh else (Color(0.15, 0.25, 0.15, 0.85) if can_launch else Color(0.1, 0.1, 0.1, 0.5))
	draw_rect(Rect2(cx - 100, vp.y - 100, 200, 50), lbg)
	draw_rect(Rect2(cx - 100, vp.y - 100, 200, 50), Color(0.4, 0.6, 0.3, 0.6) if can_launch else Color(0.2, 0.2, 0.2, 0.3), false, 2.0)
	var ltxt: Color = Color(0.95, 0.95, 0.85) if lh else (Color(0.7, 0.7, 0.6) if can_launch else Color(0.35, 0.35, 0.35))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 50, vp.y - 68), "LAUNCH GAME", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, ltxt)


func _draw_waiting_client(vp: Vector2, cx: float) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, 120),
		"Waiting for Host to Start", HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	var dots: String = ".".repeat((int(Time.get_ticks_msec() / 500) % 4))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 30, 180),
		"Connected%s" % dots, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.5, 0.8, 0.5))

	var ch: bool = (_hover == "cancel")
	draw_rect(Rect2(cx - 100, vp.y - 100, 200, 40), Color(0.25, 0.15, 0.15, 0.8) if ch else Color(0.15, 0.1, 0.1, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 25, vp.y - 75), "Cancel", HORIZONTAL_ALIGNMENT_CENTER, -1, 16,
		Color(0.8, 0.6, 0.6) if ch else Color(0.5, 0.4, 0.4))


func _draw_btn(x: float, y: float, w: float, h: float, label: String, elem_id: String) -> void:
	var hovered: bool = (_hover == elem_id)
	draw_rect(Rect2(x, y, w, h), Color(0.22, 0.25, 0.2, 0.9) if hovered else Color(0.14, 0.16, 0.13, 0.7))
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.4, 0.4, 0.4), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + w * 0.35, y + h * 0.7), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 16,
		Color(0.9, 0.9, 0.85) if hovered else Color(0.6, 0.6, 0.55))


func _draw_mode_btn(x: float, y: float, w: float, h: float, label: String, elem_id: String, active: bool) -> void:
	var hovered: bool = (_hover == elem_id)
	var bg: Color = Color(0.2, 0.35, 0.5, 0.95) if active else (Color(0.18, 0.22, 0.28, 0.85) if hovered else Color(0.12, 0.14, 0.18, 0.7))
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.5, 0.6, 0.5) if active else Color(0.3, 0.3, 0.3, 0.3), false, 1.5 if active else 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + 10, y + h * 0.7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(1, 1, 1, 0.95) if active else (Color(0.85, 0.85, 0.85) if hovered else Color(0.55, 0.55, 0.55)))
