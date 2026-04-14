extends Control
## Pre-game lobby. Solo/Host/Join modes with streamlined UX.
## Solo: seed + max_pop + start.
## Join: address + submit.
## Host: players + max_pop → waiting room with faction picking.

var player_count: int = 2
var max_pop: int = 300
var map_seed_text: String = ""
var map_size: String = "medium"  ## "small", "medium", "large", "xl"
var game_mode: String = "standard"  ## "standard" or "survival"
var ai_count: int = 0  ## Number of AI opponents
var faction_name: String = ""  ## Player's custom faction name
var _hover: String = ""

const MAP_SIZES: Array[String] = ["small", "medium", "large", "xl"]
const MAP_SIZE_LABELS: Array[String] = ["Small", "Medium", "Large", "XL"]

var net_mode: String = "solo"
var join_address: String = "localhost"

## Lobby state: "config", "waiting_host", "waiting_client"
var _state: String = "config"
var _scene_changing: bool = false

## Which text field is active for typing: "seed", "address", or ""
var _typing_field: String = ""

## Client connection state
var _connecting: bool = false
var _connect_timer: float = 0.0
var _connect_status: String = ""  ## status message shown on join screen
const CONNECT_TIMEOUT := 8.0

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


func _process(delta: float) -> void:
	if _connecting:
		_connect_timer += delta
		if _connect_timer >= CONNECT_TIMEOUT:
			_connecting = false
			_connect_status = "Connection timed out."
			NetworkManager.disconnect_game()
			_state = "config"
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _get_element_at(event.position)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var elem: String = _get_element_at(event.position)
		_handle_click(elem)

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
		elif event.keycode == KEY_BACKSPACE:
			if _typing_field == "address" and join_address.length() > 0:
				join_address = join_address.substr(0, join_address.length() - 1)
			elif _typing_field == "seed" and map_seed_text.length() > 0:
				map_seed_text = map_seed_text.substr(0, map_seed_text.length() - 1)
			elif _typing_field == "faction_name" and faction_name.length() > 0:
				faction_name = faction_name.substr(0, faction_name.length() - 1)
		elif _typing_field == "address" and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_V:
			var pasted := DisplayServer.clipboard_get()
			if pasted != "":
				join_address = _sanitize_address(join_address + pasted).substr(0, 80)
		elif _typing_field == "seed" and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_V:
			var pasted := DisplayServer.clipboard_get()
			if pasted != "":
				map_seed_text = _sanitize_seed(map_seed_text + pasted).substr(0, 12)
		elif _typing_field == "faction_name" and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_V:
			var pasted := DisplayServer.clipboard_get()
			if pasted != "":
				faction_name = _sanitize_faction_name(faction_name + pasted).substr(0, 20)
		elif event.unicode > 0 and _state == "config":
			var ch: String = char(event.unicode)
			if _typing_field == "address" and join_address.length() < 80:
				var candidate := _sanitize_address(ch)
				if candidate != "":
					join_address += candidate
			elif _typing_field == "seed" and map_seed_text.length() < 12:
				var seed_candidate := _sanitize_seed(ch)
				if seed_candidate != "":
					map_seed_text += seed_candidate
			elif _typing_field == "faction_name" and faction_name.length() < 20:
				var name_candidate := _sanitize_faction_name(ch)
				if name_candidate != "":
					faction_name += name_candidate


func _sanitize_address(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch.is_valid_int() \
		or ch == "." \
		or ch == ":" \
		or ch == "-" \
		or ch == "_" \
		or ch == "[" \
		or ch == "]" \
		or (ch >= "a" and ch <= "z") \
		or (ch >= "A" and ch <= "Z"):
			out += ch
	return out


func _sanitize_seed(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch.is_valid_int() or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z"):
			out += ch
	return out


func _sanitize_faction_name(text: String) -> String:
	var out := ""
	for i in text.length():
		var ch := text.substr(i, 1)
		if ch.is_valid_int() or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == " " or ch == "_" or ch == "-":
			out += ch
	return out


func _handle_click(elem: String) -> void:
	if _state == "config":
		match elem:
			"mode_solo":
				net_mode = "solo"
				_typing_field = "seed"
			"mode_host":
				net_mode = "host"
				_typing_field = "seed"
			"mode_join":
				net_mode = "join"
				_typing_field = "address"
			"players_up":
				player_count = mini(player_count + 1, MAX_PLAYERS)
			"players_down":
				player_count = maxi(player_count - 1, 2)
			"ai_up":
				ai_count = mini(ai_count + 1, MAX_FACTIONS - 1)
			"ai_down":
				ai_count = maxi(ai_count - 1, 0)
			"maxpop_up":
				max_pop = mini(max_pop + 50, 1000)
			"maxpop_down":
				max_pop = maxi(max_pop - 50, 50)
			"field_seed":
				_typing_field = "seed"
			"field_address":
				_typing_field = "address"
			"start":
				_on_start_pressed()
			"back":
				_go_back()
			_:
				if elem.begins_with("solo_f_"):
					var fi: int = int(elem.substr(7))
					## Solo-only: direct local write is correct here (no network, no lobby)
					NetworkManager.synced_peer_factions[1] = fi
					return
				if elem.begins_with("map_size_"):
					map_size = elem.substr(9)
				if elem == "toggle_game_mode":
					game_mode = "survival" if game_mode == "standard" else "standard"
				if elem == "field_faction_name":
					_typing_field = "faction_name"

	elif _state == "waiting_host":
		if elem == "launch":
			_launch_game()
		elif elem == "cancel":
			NetworkManager.disconnect_game()
			_state = "config"
		elif elem == "ready":
			NetworkManager.send_ready_toggle()
		elif elem.begins_with("wh_pf_"):
			var idx: int = int(elem.substr(6))
			var sorted_peers: Array[int] = NetworkManager.get_peers_sorted_by_slot()
			if idx >= 0 and idx < sorted_peers.size():
				var pid: int = sorted_peers[idx]
				var cur: int = NetworkManager.synced_peer_factions.get(pid, 0)
				var next_fid: int = (cur + 1) % MAX_FACTIONS
				if pid == NetworkManager.get_my_peer_id():
					# Host changing their own faction — use the broadcast path
					NetworkManager.send_faction_choice(next_fid)
				else:
					# Host changing another player's faction — host has authority to do this directly
					NetworkManager.synced_peer_factions[pid] = next_fid
					NetworkManager._broadcast_lobby_state()

	elif _state == "waiting_client":
		if elem == "cancel":
			_connecting = false
			_connect_status = ""
			NetworkManager.disconnect_game()
			_state = "config"
		elif elem == "ready":
			NetworkManager.send_ready_toggle()
		elif elem.begins_with("wc_pf_"):
			var my_pid: int = NetworkManager.get_my_peer_id()
			var cur: int = NetworkManager.synced_peer_factions.get(my_pid, 0)
			NetworkManager.send_faction_choice((cur + 1) % MAX_FACTIONS)


func _on_start_pressed() -> void:
	match net_mode:
		"solo":
			var solo_fid: int = NetworkManager.synced_peer_factions.get(1, 0)
			var display_name: String = faction_name.strip_edges() if faction_name.strip_edges() != "" else FACTION_NAMES[solo_fid]
			FactionManager.clear()
			FactionManager.register_faction(solo_fid, display_name, FACTION_COLORS[solo_fid])
			FactionManager.local_faction_id = solo_fid
			FactionManager.game_mode = game_mode
			# Register AI factions
			var ai_fids: Array = []
			var next_ai_slot: int = 0
			for _i in ai_count:
				while next_ai_slot == solo_fid:
					next_ai_slot += 1
				if next_ai_slot >= MAX_FACTIONS:
					break
				FactionManager.register_faction(next_ai_slot, FACTION_NAMES[next_ai_slot], FACTION_COLORS[next_ai_slot], true)
				ai_fids.append(next_ai_slot)
				next_ai_slot += 1
			var total_factions: int = 1 + ai_fids.size()
			FactionManager.set_meta("ai_factions", ai_fids)
			_set_game_config(total_factions)
			SaveManager.delete_save()
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		"host":
			var err := NetworkManager.host_game()
			if err != OK:
				EventFeed.push("Failed to host!", Color(0.9, 0.3, 0.3))
				return
			NetworkManager.synced_peer_factions[1] = NetworkManager.synced_peer_factions.get(1, 0)
			NetworkManager.synced_faction_count = MAX_FACTIONS
			var seed_val: int = hash(map_seed_text) if map_seed_text != "" else -1
			NetworkManager.broadcast_lobby_config(seed_val, MAX_FACTIONS, NetworkManager.synced_peer_factions, max_pop, map_size)
			_state = "waiting_host"
		"join":
			if join_address.strip_edges() == "":
				_connect_status = "Enter a host address first."
				return
			_connect_status = "Connecting..."
			_connecting = true
			_connect_timer = 0.0
			var err := NetworkManager.join_game(join_address)
			if err != OK:
				_connecting = false
				_connect_status = "Failed to create connection."
				EventFeed.push("Failed to connect!", Color(0.9, 0.3, 0.3))
				return
			_state = "waiting_client"


func _launch_game() -> void:
	if not is_inside_tree() or not NetworkManager.are_all_ready():
		return
	var pfmap: Dictionary = NetworkManager.synced_peer_factions.duplicate()
	var used_factions: Dictionary = {}
	for pid in pfmap:
		used_factions[pfmap[pid]] = true
	var fcount: int = used_factions.size()
	FactionManager.clear()
	var my_fid: int = pfmap.get(1, 0)
	for fid in used_factions:
		var fname: String = FACTION_NAMES[fid]
		if fid == my_fid and faction_name.strip_edges() != "":
			fname = faction_name.strip_edges()
		FactionManager.register_faction(fid, fname, FACTION_COLORS[fid])
	FactionManager.local_faction_id = my_fid
	FactionManager.max_population = max_pop
	_set_game_config(fcount)
	NetworkManager.broadcast_lobby_config(
		hash(map_seed_text) if map_seed_text != "" else -1,
		fcount, pfmap, max_pop, map_size)
	NetworkManager.broadcast_start_game()
	SaveManager.delete_save()


func _on_game_started() -> void:
	if not is_inside_tree() or _scene_changing:
		return
	_scene_changing = true
	FactionManager.clear()
	var used: Dictionary = {}
	for pid in NetworkManager.synced_peer_factions:
		var fid: int = int(NetworkManager.synced_peer_factions[pid])
		used[fid] = true
	for fid in used:
		var fname: String = FACTION_NAMES[fid]
		if fid == NetworkManager.get_faction_for_peer(NetworkManager.get_my_peer_id()) and faction_name.strip_edges() != "":
			fname = faction_name.strip_edges()
		FactionManager.register_faction(fid, fname, FACTION_COLORS[fid])
	var my_peer: int = NetworkManager.get_my_peer_id()
	FactionManager.local_faction_id = NetworkManager.get_faction_for_peer(my_peer)
	FactionManager.max_population = NetworkManager.synced_max_population
	FactionManager.set_meta("map_seed", NetworkManager.synced_map_seed)
	FactionManager.set_meta("faction_count", NetworkManager.synced_faction_count)
	FactionManager.set_meta("player_count", NetworkManager.get_all_peer_ids().size())
	FactionManager.set_meta("peer_factions", NetworkManager.synced_peer_factions.duplicate())
	FactionManager.set_meta("map_size", NetworkManager.synced_map_size)
	SaveManager.delete_save()
	call_deferred("_deferred_change_to_main")


func _deferred_change_to_main() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_connection_succeeded() -> void:
	_connecting = false
	_connect_status = ""

func _on_connection_failed() -> void:
	_connecting = false
	_connect_status = "Connection failed — host unreachable."
	_state = "config"


func _set_game_config(fcount: int) -> void:
	var seed_val: int = hash(map_seed_text) if map_seed_text != "" else -1
	FactionManager.set_meta("map_seed", seed_val)
	FactionManager.set_meta("player_count", player_count)
	FactionManager.set_meta("faction_count", fcount)
	FactionManager.set_meta("map_size", map_size)
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
		return _get_waiting_element(pos, vp, cx, true)
	if _state == "waiting_client":
		return _get_waiting_element(pos, vp, cx, false)

	# Config screen — mode tabs always visible
	var top: float = 80.0
	var mode_y: float = top + 40
	if Rect2(cx - 140, mode_y, 80, 30).has_point(pos): return "mode_solo"
	if Rect2(cx - 45, mode_y, 80, 30).has_point(pos): return "mode_host"
	if Rect2(cx + 50, mode_y, 80, 30).has_point(pos): return "mode_join"

	# Back button
	if Rect2(20, 20, 80, 32).has_point(pos): return "back"

	# Mode-specific elements
	match net_mode:
		"solo":
			return _get_solo_element(pos, vp, cx, top)
		"host":
			return _get_host_element(pos, vp, cx, top)
		"join":
			return _get_join_element(pos, vp, cx, top)
	return ""


func _get_solo_element(pos: Vector2, vp: Vector2, cx: float, top: float) -> String:
	var row_y: float = top + 100
	# Max Pop
	if Rect2(cx + 60, row_y - 4, 40, 32).has_point(pos): return "maxpop_up"
	if Rect2(cx + 110, row_y - 4, 40, 32).has_point(pos): return "maxpop_down"
	# Map Size
	var ms_y: float = top + 150
	for i in MAP_SIZES.size():
		if Rect2(cx + 10 + i * 52, ms_y - 2, 46, 28).has_point(pos): return "map_size_%s" % MAP_SIZES[i]
	# Seed field
	var seed_y: float = top + 200
	if Rect2(cx + 10, seed_y - 2, 160, 28).has_point(pos): return "field_seed"
	# Game Mode toggle
	var gm_y: float = top + 250
	if Rect2(cx + 10, gm_y - 2, 160, 28).has_point(pos): return "toggle_game_mode"
	# AI Opponents
	var ai_y: float = top + 300
	if Rect2(cx + 60, ai_y - 4, 40, 32).has_point(pos): return "ai_up"
	if Rect2(cx + 110, ai_y - 4, 40, 32).has_point(pos): return "ai_down"
	# Faction Name
	var fn_y: float = top + 350
	if Rect2(cx + 10, fn_y - 2, 200, 28).has_point(pos): return "field_faction_name"
	# Faction picker
	var fy: float = top + 400
	for i in MAX_FACTIONS:
		if Rect2(cx - 140 + i * 38, fy, 32, 32).has_point(pos): return "solo_f_%d" % i
	# Start
	if Rect2(cx - 100, vp.y - 100, 200, 50).has_point(pos): return "start"
	return ""


func _get_host_element(pos: Vector2, vp: Vector2, cx: float, top: float) -> String:
	var row_y: float = top + 100
	# Players
	if Rect2(cx + 60, row_y - 4, 40, 32).has_point(pos): return "players_up"
	if Rect2(cx + 110, row_y - 4, 40, 32).has_point(pos): return "players_down"
	# Max Pop
	row_y = top + 145
	if Rect2(cx + 60, row_y - 4, 40, 32).has_point(pos): return "maxpop_up"
	if Rect2(cx + 110, row_y - 4, 40, 32).has_point(pos): return "maxpop_down"
	# Map Size
	var ms_y: float = top + 195
	for i in MAP_SIZES.size():
		if Rect2(cx + 10 + i * 52, ms_y - 2, 46, 28).has_point(pos): return "map_size_%s" % MAP_SIZES[i]
	# Seed
	var seed_y: float = top + 250
	if Rect2(cx + 10, seed_y - 2, 160, 28).has_point(pos): return "field_seed"
	# Faction Name
	var fn_y: float = top + 300
	if Rect2(cx + 10, fn_y - 2, 200, 28).has_point(pos): return "field_faction_name"
	# Start
	if Rect2(cx - 100, vp.y - 100, 200, 50).has_point(pos): return "start"
	return ""


func _get_join_element(pos: Vector2, vp: Vector2, cx: float, top: float) -> String:
	# Address field
	var addr_y: float = top + 100
	if Rect2(cx - 30, addr_y - 2, 220, 28).has_point(pos): return "field_address"
	# Faction Name
	var fn_y: float = top + 160
	if Rect2(cx + 10, fn_y - 2, 200, 28).has_point(pos): return "field_faction_name"
	# Submit
	if Rect2(cx - 100, vp.y - 100, 200, 50).has_point(pos): return "start"
	return ""


func _get_waiting_element(pos: Vector2, vp: Vector2, cx: float, is_host_view: bool) -> String:
	if is_host_view and NetworkManager.are_all_ready():
		if Rect2(cx - 100, vp.y - 100, 200, 50).has_point(pos): return "launch"
	if Rect2(cx - 100, vp.y - 170, 200, 40).has_point(pos): return "cancel"
	var sorted_peers: Array[int] = NetworkManager.get_peers_sorted_by_slot()
	var rby: float = 150.0 + sorted_peers.size() * 40.0 + 20
	if Rect2(cx - 100, rby, 200, 36).has_point(pos): return "ready"
	var prefix: String = "wh_pf_" if is_host_view else "wc_pf_"
	var my_pid: int = NetworkManager.get_my_peer_id()
	for i in sorted_peers.size():
		var can_click: bool = is_host_view or (sorted_peers[i] == my_pid)
		if can_click and Rect2(cx - 20, 150.0 + i * 40.0 - 2, 80, 28).has_point(pos):
			return "%s%d" % [prefix, i]
	return ""


# ==============================================================================
# DRAWING
# ==============================================================================

func _draw() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var cx: float = vp.x * 0.5
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0.06, 0.06, 0.1))
	if _state == "waiting_host":
		_draw_waiting(vp, cx, true)
		return
	if _state == "waiting_client":
		_draw_waiting(vp, cx, false)
		return
	_draw_config(vp, cx)


func _draw_config(vp: Vector2, cx: float) -> void:
	var top: float = 80.0
	draw_string(ThemeDB.fallback_font, Vector2(cx - 80, top), "Game Setup",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	# Back
	var back_h: bool = (_hover == "back")
	draw_rect(Rect2(20, 20, 80, 32), Color(0.2, 0.2, 0.25, 0.8) if back_h else Color(0.12, 0.12, 0.15, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(36, 42), "< Back",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.8, 0.8, 0.8) if back_h else Color(0.5, 0.5, 0.5))

	# Mode tabs
	var mode_y: float = top + 40
	_draw_mode_btn(cx - 140, mode_y, 80, 30, "Solo", "mode_solo", net_mode == "solo")
	_draw_mode_btn(cx - 45, mode_y, 80, 30, "Host", "mode_host", net_mode == "host")
	_draw_mode_btn(cx + 50, mode_y, 80, 30, "Join", "mode_join", net_mode == "join")

	match net_mode:
		"solo":
			_draw_solo_config(vp, cx, top)
		"host":
			_draw_host_config(vp, cx, top)
		"join":
			_draw_join_config(vp, cx, top)


func _draw_solo_config(vp: Vector2, cx: float, top: float) -> void:
	# Max Pop
	var row_y: float = top + 100
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, row_y + 18), "Max Pop:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, row_y + 18), str(max_pop),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, row_y - 4, 40, 32, "+", "maxpop_up")
	_draw_btn(cx + 110, row_y - 4, 40, 32, "-", "maxpop_down")

	# Map Size
	var ms_y: float = top + 150
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, ms_y + 16), "Map Size:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	_draw_map_size_buttons(cx + 10, ms_y - 2)

	# Seed
	var seed_y: float = top + 200
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, seed_y + 18), "Map Seed:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var sd: String = map_seed_text if map_seed_text != "" else "(random)"
	var active: bool = (_typing_field == "seed")
	draw_rect(Rect2(cx + 10, seed_y - 2, 160, 28), Color(0.15, 0.15, 0.2, 0.9) if active else Color(0.1, 0.1, 0.14, 0.8))
	if active:
		draw_rect(Rect2(cx + 10, seed_y - 2, 160, 28), Color(0.4, 0.5, 0.6, 0.5), false, 1.5)
	var cur: String = "|" if active and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, seed_y + 16), sd + cur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7) if map_seed_text != "" else Color(0.45, 0.45, 0.45))

	# Game Mode toggle
	var gm_y: float = top + 250
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, gm_y + 18), "Game Mode:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var gm_hovered: bool = (_hover == "toggle_game_mode")
	var gm_is_survival: bool = (game_mode == "survival")
	var gm_bg: Color = Color(0.5, 0.2, 0.15, 0.9) if gm_is_survival else Color(0.15, 0.3, 0.2, 0.9)
	if gm_hovered: gm_bg = gm_bg.lightened(0.15)
	draw_rect(Rect2(cx + 10, gm_y - 2, 160, 28), gm_bg)
	draw_rect(Rect2(cx + 10, gm_y - 2, 160, 28), Color(0.5, 0.5, 0.5, 0.5), false, 1.0)
	var gm_label: String = "Survival (No Orb)" if gm_is_survival else "Standard (Orb)"
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, gm_y + 16), gm_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7))

	# AI Opponents
	var ai_y: float = top + 300
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, ai_y + 18), "AI Opponents:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, ai_y + 18), str(ai_count),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, ai_y - 4, 40, 32, "+", "ai_up")
	_draw_btn(cx + 110, ai_y - 4, 40, 32, "-", "ai_down")

	# Faction Name
	var fn_y: float = top + 350
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, fn_y + 18), "Faction Name:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var fn_active: bool = (_typing_field == "faction_name")
	var fn_display: String = faction_name if faction_name != "" else "(enter name)"
	draw_rect(Rect2(cx + 10, fn_y - 2, 200, 28), Color(0.15, 0.15, 0.2, 0.9) if fn_active else Color(0.1, 0.1, 0.14, 0.8))
	if fn_active:
		draw_rect(Rect2(cx + 10, fn_y - 2, 200, 28), Color(0.4, 0.5, 0.6, 0.5), false, 1.5)
	var fn_cur: String = "|" if fn_active and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, fn_y + 16), fn_display + fn_cur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7) if faction_name != "" else Color(0.45, 0.45, 0.45))

	# Faction picker
	var fy: float = top + 400
	var solo_fid: int = NetworkManager.synced_peer_factions.get(1, 0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, fy - 6), "Faction:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.55, 0.6))
	for i in MAX_FACTIONS:
		var fc: Color = FACTION_COLORS[i]
		var selected: bool = (i == solo_fid)
		var hovered: bool = (_hover == "solo_f_%d" % i)
		var bg: Color = fc.lightened(0.1) if selected else (fc.darkened(0.2) if hovered else fc.darkened(0.5))
		bg.a = 0.95 if selected else 0.6
		draw_rect(Rect2(cx - 140 + i * 38, fy, 32, 32), bg)
		if selected:
			draw_rect(Rect2(cx - 140 + i * 38, fy, 32, 32), Color(1, 1, 1, 0.8), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(cx - 130 + i * 38, fy + 22), FACTION_NAMES[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

	# Start
	_draw_start_btn(vp, cx, "START")


func _draw_host_config(vp: Vector2, cx: float, top: float) -> void:
	# Players
	var row_y: float = top + 100
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, row_y + 18), "Players:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, row_y + 18), str(player_count),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, row_y - 4, 40, 32, "+", "players_up")
	_draw_btn(cx + 110, row_y - 4, 40, 32, "-", "players_down")

	# Max Pop
	row_y = top + 145
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, row_y + 18), "Max Pop:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	draw_string(ThemeDB.fallback_font, Vector2(cx + 10, row_y + 18), str(max_pop),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.9, 0.7))
	_draw_btn(cx + 60, row_y - 4, 40, 32, "+", "maxpop_up")
	_draw_btn(cx + 110, row_y - 4, 40, 32, "-", "maxpop_down")

	# Map Size
	var ms_y: float = top + 195
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, ms_y + 16), "Map Size:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	_draw_map_size_buttons(cx + 10, ms_y - 2)

	# Seed
	var seed_y: float = top + 250
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, seed_y + 18), "Map Seed:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var sd: String = map_seed_text if map_seed_text != "" else "(random)"
	var active: bool = (_typing_field == "seed")
	draw_rect(Rect2(cx + 10, seed_y - 2, 160, 28), Color(0.15, 0.15, 0.2, 0.9) if active else Color(0.1, 0.1, 0.14, 0.8))
	if active:
		draw_rect(Rect2(cx + 10, seed_y - 2, 160, 28), Color(0.4, 0.5, 0.6, 0.5), false, 1.5)
	var cur: String = "|" if active and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, seed_y + 16), sd + cur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7) if map_seed_text != "" else Color(0.45, 0.45, 0.45))

	# Faction Name
	var fn_y: float = top + 300
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, fn_y + 18), "Faction Name:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var fn_active: bool = (_typing_field == "faction_name")
	var fn_display: String = faction_name if faction_name != "" else "(enter name)"
	draw_rect(Rect2(cx + 10, fn_y - 2, 200, 28), Color(0.15, 0.15, 0.2, 0.9) if fn_active else Color(0.1, 0.1, 0.14, 0.8))
	if fn_active:
		draw_rect(Rect2(cx + 10, fn_y - 2, 200, 28), Color(0.4, 0.5, 0.6, 0.5), false, 1.5)
	var fn_cur: String = "|" if fn_active and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, fn_y + 16), fn_display + fn_cur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7) if faction_name != "" else Color(0.45, 0.45, 0.45))

	_draw_start_btn(vp, cx, "HOST")


func _draw_join_config(vp: Vector2, cx: float, top: float) -> void:
	# Address field
	var addr_y: float = top + 100
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, addr_y + 16), "Address:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var active: bool = (_typing_field == "address")
	draw_rect(Rect2(cx - 30, addr_y - 2, 220, 28), Color(0.15, 0.15, 0.2, 0.9) if active else Color(0.1, 0.1, 0.14, 0.8))
	if active:
		draw_rect(Rect2(cx - 30, addr_y - 2, 220, 28), Color(0.4, 0.5, 0.6, 0.5), false, 1.5)
	var cur: String = "|" if active and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx - 22, addr_y + 14), join_address + cur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.8))

	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, addr_y + 50), "IPv6 example:  2601:abcd::1",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.4, 0.45))

	# Connection status message
	if _connect_status != "":
		var is_err: bool = _connect_status.contains("fail") or _connect_status.contains("timed") or _connect_status.contains("Enter")
		var status_col: Color = Color(0.9, 0.35, 0.3) if is_err else Color(0.5, 0.7, 0.9)
		if _connecting:
			var dots: String = ".".repeat(int(_connect_timer * 2.0) % 4)
			draw_string(ThemeDB.fallback_font, Vector2(cx - 140, addr_y + 80), _connect_status + dots,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_col)
			# Show elapsed time
			draw_string(ThemeDB.fallback_font, Vector2(cx - 140, addr_y + 100), "(%ds / %ds timeout)" % [int(_connect_timer), int(CONNECT_TIMEOUT)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.45, 0.5))
		else:
			draw_string(ThemeDB.fallback_font, Vector2(cx - 140, addr_y + 80), _connect_status,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_col)

	# Faction Name
	var fn_y: float = top + 160
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, fn_y + 18), "Faction Name:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.75, 0.75))
	var fn_active: bool = (_typing_field == "faction_name")
	var fn_display: String = faction_name if faction_name != "" else "(enter name)"
	draw_rect(Rect2(cx + 10, fn_y - 2, 200, 28), Color(0.15, 0.15, 0.2, 0.9) if fn_active else Color(0.1, 0.1, 0.14, 0.8))
	if fn_active:
		draw_rect(Rect2(cx + 10, fn_y - 2, 200, 28), Color(0.4, 0.5, 0.6, 0.5), false, 1.5)
	var fn_cur: String = "|" if fn_active and int(Time.get_ticks_msec() / 500) % 2 == 0 else ""
	draw_string(ThemeDB.fallback_font, Vector2(cx + 18, fn_y + 16), fn_display + fn_cur,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.9, 0.7) if faction_name != "" else Color(0.45, 0.45, 0.45))

	_draw_start_btn(vp, cx, "JOIN")


func _draw_start_btn(vp: Vector2, cx: float, label: String) -> void:
	var start_y: float = vp.y - 100
	var sh: bool = (_hover == "start")
	draw_rect(Rect2(cx - 100, start_y, 200, 50), Color(0.2, 0.35, 0.2, 0.95) if sh else Color(0.12, 0.2, 0.12, 0.85))
	draw_rect(Rect2(cx - 100, start_y, 200, 50), Color(0.4, 0.6, 0.3, 0.6), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 30, start_y + 32), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 22, Color(0.95, 0.95, 0.85) if sh else Color(0.7, 0.7, 0.6))


func _draw_waiting(vp: Vector2, cx: float, is_host_view: bool) -> void:
	var title: String = "LOBBY — HOST" if is_host_view else "LOBBY — CLIENT"
	draw_string(ThemeDB.fallback_font, Vector2(cx - 100, 80), title,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.9, 0.85, 0.6))

	var sorted_peers: Array[int] = NetworkManager.get_peers_sorted_by_slot()
	draw_string(ThemeDB.fallback_font, Vector2(cx - 140, 120), "%d player(s)" % sorted_peers.size(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.8, 0.5))

	# ---- Lobby settings summary (visible to all) ----
	var settings_x: float = cx + 60
	var settings_y: float = 110.0
	var lbl_col: Color = Color(0.5, 0.5, 0.55)
	var val_col: Color = Color(0.8, 0.8, 0.7)
	var s_font: int = 13
	var ms_label: String = NetworkManager.synced_map_size.capitalize() if NetworkManager.synced_map_size != "" else "?"
	draw_string(ThemeDB.fallback_font, Vector2(settings_x, settings_y), "Map:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, s_font, lbl_col)
	draw_string(ThemeDB.fallback_font, Vector2(settings_x + 70, settings_y), ms_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, s_font, val_col)
	draw_string(ThemeDB.fallback_font, Vector2(settings_x, settings_y + 20), "Max Pop:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, s_font, lbl_col)
	draw_string(ThemeDB.fallback_font, Vector2(settings_x + 70, settings_y + 20), str(NetworkManager.synced_max_population),
		HORIZONTAL_ALIGNMENT_LEFT, -1, s_font, val_col)
	var seed_display: String = str(NetworkManager.synced_map_seed) if NetworkManager.synced_map_seed != -1 else "random"
	draw_string(ThemeDB.fallback_font, Vector2(settings_x, settings_y + 40), "Seed:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, s_font, lbl_col)
	draw_string(ThemeDB.fallback_font, Vector2(settings_x + 70, settings_y + 40), seed_display,
		HORIZONTAL_ALIGNMENT_LEFT, -1, s_font, val_col)

	var list_y: float = 150.0
	var my_pid: int = NetworkManager.get_my_peer_id()
	for i in sorted_peers.size():
		var pid: int = sorted_peers[i]
		var slot: int = NetworkManager.synced_peer_slots.get(pid, i + 1)
		var fid: int = NetworkManager.synced_peer_factions.get(pid, 0)
		var is_ready: bool = NetworkManager.synced_peer_ready.get(pid, false)
		var ry: float = list_y + i * 40.0
		var fc: Color = FACTION_COLORS[fid] if fid < FACTION_COLORS.size() else Color.WHITE
		var sym: String = FACTION_NAMES[fid] if fid < FACTION_NAMES.size() else "?"
		var is_me: bool = (pid == my_pid)
		var tags: String = ""
		if pid == 1: tags += " (Host)"
		if is_me: tags += " (You)"

		draw_string(ThemeDB.fallback_font, Vector2(cx - 140, ry + 16), "P%d%s" % [slot, tags],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.9, 0.7) if is_me else Color(0.7, 0.7, 0.7))

		var can_click: bool = is_host_view or is_me
		var prefix: String = "wh_pf_" if is_host_view else "wc_pf_"
		var fh: bool = can_click and (_hover == "%s%d" % [prefix, i])
		draw_rect(Rect2(cx - 20, ry - 2, 80, 28), fc.darkened(0.3 if not fh else 0.0))
		draw_rect(Rect2(cx - 20, ry - 2, 80, 28), Color(0.5, 0.5, 0.5, 0.4), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(cx, ry + 16), sym,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))

		var ready_txt: String = "READY" if is_ready else "..."
		draw_string(ThemeDB.fallback_font, Vector2(cx + 80, ry + 16), ready_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.8, 0.3) if is_ready else Color(0.5, 0.4, 0.4))

	# Ready button
	var my_ready: bool = NetworkManager.synced_peer_ready.get(my_pid, false)
	var rby: float = list_y + sorted_peers.size() * 40.0 + 20
	var rh: bool = (_hover == "ready")
	var rbg: Color = Color(0.2, 0.4, 0.2, 0.9) if my_ready else (Color(0.25, 0.3, 0.2, 0.85) if rh else Color(0.15, 0.18, 0.12, 0.7))
	draw_rect(Rect2(cx - 100, rby, 200, 36), rbg)
	draw_rect(Rect2(cx - 100, rby, 200, 36), Color(0.4, 0.6, 0.3, 0.5), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(cx - 40, rby + 24),
		"READY" if my_ready else "Click to Ready",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.9, 0.9, 0.85))

	# Cancel
	draw_rect(Rect2(cx - 100, vp.y - 170, 200, 40),
		Color(0.25, 0.15, 0.15, 0.8) if _hover == "cancel" else Color(0.15, 0.1, 0.1, 0.7))
	draw_string(ThemeDB.fallback_font, Vector2(cx - 25, vp.y - 145), "Cancel",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.8, 0.6, 0.6) if _hover == "cancel" else Color(0.5, 0.4, 0.4))

	# Launch (host only, all ready)
	if is_host_view:
		var all_ready: bool = NetworkManager.are_all_ready()
		var lh: bool = (_hover == "launch") and all_ready
		var lbg: Color = Color(0.2, 0.4, 0.2, 0.95) if lh else (Color(0.15, 0.25, 0.15, 0.85) if all_ready else Color(0.1, 0.1, 0.1, 0.5))
		draw_rect(Rect2(cx - 100, vp.y - 100, 200, 50), lbg)
		draw_rect(Rect2(cx - 100, vp.y - 100, 200, 50), Color(0.4, 0.6, 0.3, 0.6) if all_ready else Color(0.2, 0.2, 0.2, 0.3), false, 2.0)
		var label: String = "LAUNCH GAME" if all_ready else "Waiting for ready..."
		draw_string(ThemeDB.fallback_font, Vector2(cx - 60, vp.y - 68), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.95, 0.95, 0.85) if lh else Color(0.5, 0.5, 0.5))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(cx - 80, vp.y - 60),
			"Waiting for host to launch...",
			HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.4, 0.4, 0.45))


func _draw_map_size_buttons(x: float, y: float) -> void:
	for i in MAP_SIZES.size():
		var sid: String = "map_size_%s" % MAP_SIZES[i]
		var selected: bool = (map_size == MAP_SIZES[i])
		var hovered: bool = (_hover == sid)
		var bg: Color
		if selected:
			bg = Color(0.2, 0.45, 0.55, 0.95)
		elif hovered:
			bg = Color(0.18, 0.28, 0.35, 0.85)
		else:
			bg = Color(0.1, 0.14, 0.18, 0.7)
		draw_rect(Rect2(x + i * 52, y, 46, 28), bg)
		draw_rect(Rect2(x + i * 52, y, 46, 28),
			Color(0.4, 0.65, 0.75, 0.8) if selected else Color(0.3, 0.3, 0.3, 0.3),
			false, 1.5 if selected else 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(x + i * 52 + 6, y + 18),
			MAP_SIZE_LABELS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(1, 1, 1, 0.95) if selected else (Color(0.85, 0.85, 0.85) if hovered else Color(0.55, 0.55, 0.55)))


func _draw_btn(x: float, y: float, w: float, h: float, label: String, elem_id: String) -> void:
	var hovered: bool = (_hover == elem_id)
	draw_rect(Rect2(x, y, w, h), Color(0.22, 0.25, 0.2, 0.9) if hovered else Color(0.14, 0.16, 0.13, 0.7))
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.4, 0.4, 0.4), false, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + w * 0.35, y + h * 0.7), label,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color(0.9, 0.9, 0.85) if hovered else Color(0.6, 0.6, 0.55))


func _draw_mode_btn(x: float, y: float, w: float, h: float, label: String, elem_id: String, active: bool) -> void:
	var hovered: bool = (_hover == elem_id)
	var bg: Color = Color(0.2, 0.35, 0.5, 0.95) if active else (Color(0.18, 0.22, 0.28, 0.85) if hovered else Color(0.12, 0.14, 0.18, 0.7))
	draw_rect(Rect2(x, y, w, h), bg)
	draw_rect(Rect2(x, y, w, h), Color(0.4, 0.5, 0.6, 0.5) if active else Color(0.3, 0.3, 0.3, 0.3), false, 1.5 if active else 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(x + 10, y + h * 0.7), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95) if active else (Color(0.85, 0.85, 0.85) if hovered else Color(0.55, 0.55, 0.55)))
