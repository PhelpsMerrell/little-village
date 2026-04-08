extends Node
## Host-authoritative multiplayer via ENet.
##
## Architecture:
##   - Host runs the full game simulation (sole authority)
##   - Clients send only commands (move, hold, build, etc.) and cursor pos
##   - Host broadcasts state snapshots at SYNC_RATE Hz
##   - Clients interpolate entities smoothly between snapshots
##
## Solo mode: is_online() returns false → zero networking overhead.

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal connection_succeeded()
signal game_started()
signal remote_command_received(cmd: Dictionary)
signal cursor_updated(peer_id: int, world_pos: Vector2, faction_id: int)

const DEFAULT_PORT := 7350
const MAX_CLIENTS := 7
const SYNC_RATE := 10.0            ## state broadcasts per second
const SYNC_INTERVAL := 1.0 / SYNC_RATE
const CURSOR_INTERVAL := 0.1       ## cursor sync interval (seconds)

var peer: ENetMultiplayerPeer = null
var is_host: bool = false
var connected_peers: Array[int] = []

## Timing
var _sync_timer: float = 0.0
var _cursor_timer: float = 0.0

## Client snapshot buffer for interpolation
var _snapshot_queue: Array[Dictionary] = []
var _has_new_snapshot: bool = false
var latest_snapshot: Dictionary = {}

## Remote cursors: peer_id → {pos: Vector2, faction_id: int}
var remote_cursors: Dictionary = {}

## Lobby sync — uses peer_id → faction_id mapping (no index ambiguity)
var synced_map_seed: int = -1
var synced_faction_count: int = 1
var synced_max_population: int = 50
var synced_map_size: String = "medium"
var synced_peer_factions: Dictionary = {}  ## { peer_id(int) : faction_id(int) }
var synced_peer_ready: Dictionary = {}  ## { peer_id(int) : bool }
var synced_peer_slots: Dictionary = {}   ## { peer_id(int) : slot(int) } — host-assigned, 1-based, stable
var _next_slot: int = 1                  ## increments on each new peer join (host only)
var lobby_ready: bool = false


# ==============================================================================
# QUERIES
# ==============================================================================

func is_online() -> bool:
	return peer != null and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_authority() -> bool:
	## True when this peer runs the simulation (host or solo offline).
	return not is_online() or is_host


func get_my_peer_id() -> int:
	if is_online():
		return multiplayer.get_unique_id()
	return 1


func get_all_peer_ids() -> Array[int]:
	var ids: Array[int] = [get_my_peer_id()]
	ids.append_array(connected_peers)
	return ids


func get_peer_count() -> int:
	return connected_peers.size()


func get_faction_for_peer(pid: int) -> int:
	return int(synced_peer_factions.get(pid, 0))


func get_my_faction() -> int:
	return get_faction_for_peer(get_my_peer_id())


func get_my_slot() -> int:
	## Returns this peer's host-assigned player slot number (1-based).
	return synced_peer_slots.get(get_my_peer_id(), 1)


func get_peers_sorted_by_slot() -> Array[int]:
	## Returns all peer ids sorted by their stable host-assigned slot number.
	## This is the canonical order for lobby UI display — identical on every machine.
	var all_ids: Array[int] = get_all_peer_ids()
	all_ids.sort_custom(func(a, b):
		return synced_peer_slots.get(a, 999) < synced_peer_slots.get(b, 999))
	return all_ids


# ==============================================================================
# HOST / JOIN
# ==============================================================================

func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	lobby_ready = false
	_next_slot = 1
	synced_peer_slots.clear()
	# Assign host (peer id 1) slot 1 immediately
	synced_peer_slots[1] = _next_slot
	_next_slot += 1
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	EventFeed.push("Hosting on port %d..." % port, Color(0.4, 0.8, 0.4))
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	lobby_ready = false
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func disconnect_game() -> void:
	if peer:
		peer.close()
	peer = null
	is_host = false
	connected_peers.clear()
	lobby_ready = false
	latest_snapshot.clear()
	_snapshot_queue.clear()
	remote_cursors.clear()
	synced_peer_factions.clear()
	synced_peer_ready.clear()
	synced_peer_slots.clear()
	_next_slot = 1
	# Disconnect signals safely
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	multiplayer.multiplayer_peer = null


# ==============================================================================
# COMMANDS (client → host)
# ==============================================================================

func send_command(cmd: Dictionary) -> void:
	## Route a player command. Solo/host applies locally; client RPCs to host.
	cmd["peer_id"] = get_my_peer_id()
	if not is_online() or is_host:
		remote_command_received.emit(cmd)
	else:
		_rpc_send_command.rpc_id(1, cmd)


@rpc("any_peer", "reliable")
func _rpc_send_command(cmd: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	cmd["peer_id"] = sender
	remote_command_received.emit(cmd)


# ==============================================================================
# STATE SNAPSHOTS (host → clients)
# ==============================================================================

func should_broadcast(delta: float) -> bool:
	## Called by host's main.gd each frame. Returns true when it's time to send.
	if not is_online() or not is_host:
		return false
	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer -= SYNC_INTERVAL
		return true
	return false


func broadcast_snapshot(snapshot: Dictionary) -> void:
	if not is_online() or not is_host:
		return
	_rpc_receive_snapshot.rpc(snapshot)


@rpc("authority", "unreliable")
func _rpc_receive_snapshot(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot
	_has_new_snapshot = true


func consume_snapshot() -> Dictionary:
	if _has_new_snapshot:
		_has_new_snapshot = false
		return latest_snapshot
	return {}


# ==============================================================================
# CURSOR SYNC
# ==============================================================================

func should_send_cursor(delta: float) -> bool:
	_cursor_timer += delta
	if _cursor_timer >= CURSOR_INTERVAL:
		_cursor_timer -= CURSOR_INTERVAL
		return true
	return false


func send_cursor(world_pos: Vector2, faction_id: int) -> void:
	if not is_online():
		return
	_rpc_cursor.rpc(get_my_peer_id(), world_pos.x, world_pos.y, faction_id)


@rpc("any_peer", "unreliable")
func _rpc_cursor(sender_id: int, x: float, y: float, fid: int) -> void:
	remote_cursors[sender_id] = {"pos": Vector2(x, y), "faction_id": fid}
	cursor_updated.emit(sender_id, Vector2(x, y), fid)


# ==============================================================================
# LOBBY SYNC
# ==============================================================================

func broadcast_lobby_config(seed_val: int, fcount: int, peer_faction_map: Dictionary, max_pop: int = 50, map_size: String = "medium") -> void:
	if not is_host:
		return
	synced_map_seed = seed_val
	synced_faction_count = fcount
	synced_max_population = max_pop
	synced_map_size = map_size
	synced_peer_factions = peer_faction_map.duplicate()
	_broadcast_lobby_state()


func _broadcast_lobby_state() -> void:
	if not is_host or not is_online():
		return
	_rpc_receive_lobby_state.rpc(synced_peer_factions, synced_peer_ready, synced_peer_slots, synced_map_seed, synced_faction_count, synced_max_population, synced_map_size)


@rpc("authority", "reliable")
func _rpc_receive_lobby_state(pfmap: Dictionary, pready: Dictionary, pslots: Dictionary, seed_val: int, fcount: int, max_pop: int, map_size: String) -> void:
	synced_peer_factions.clear()
	for k in pfmap:
		synced_peer_factions[int(k)] = int(pfmap[k])
	synced_peer_ready.clear()
	for k in pready:
		synced_peer_ready[int(k)] = bool(pready[k])
	synced_peer_slots.clear()
	for k in pslots:
		synced_peer_slots[int(k)] = int(pslots[k])
	synced_map_seed = seed_val
	synced_faction_count = fcount
	synced_max_population = max_pop
	synced_map_size = map_size


func broadcast_start_game() -> void:
	if not is_host:
		return
	lobby_ready = true
	if is_online():
		_rpc_start_game.rpc()
	game_started.emit()


@rpc("authority", "reliable")
func _rpc_start_game() -> void:
	lobby_ready = true
	game_started.emit()


## Client requests to toggle ready
func send_ready_toggle() -> void:
	if is_online() and not is_host:
		_rpc_ready_toggle.rpc_id(1)
	else:
		var pid: int = get_my_peer_id()
		synced_peer_ready[pid] = not synced_peer_ready.get(pid, false)
		_broadcast_lobby_state()


@rpc("any_peer", "reliable")
func _rpc_ready_toggle() -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	synced_peer_ready[sender] = not synced_peer_ready.get(sender, false)
	_broadcast_lobby_state()


## Client requests faction change
func send_faction_choice(faction_id: int) -> void:
	if is_online() and not is_host:
		_rpc_faction_choice.rpc_id(1, faction_id)
	else:
		synced_peer_factions[get_my_peer_id()] = faction_id
		_broadcast_lobby_state()


@rpc("any_peer", "reliable")
func _rpc_faction_choice(faction_id: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if faction_id >= 0 and faction_id < synced_faction_count:
		synced_peer_factions[sender] = faction_id
	_broadcast_lobby_state()


func are_all_ready() -> bool:
	var all_peers: Array[int] = get_all_peer_ids()
	for pid in all_peers:
		if not synced_peer_ready.get(pid, false):
			return false
	return all_peers.size() > 0


# ==============================================================================
# BUILDING SYNC (host → clients)
# ==============================================================================

signal building_placed_remote(item_id: String, pos_x: float, pos_y: float)

func broadcast_building_placed(item_id: String, pos: Vector2) -> void:
	if not is_online() or not is_host:
		return
	_rpc_building_placed.rpc(item_id, pos.x, pos.y)


@rpc("authority", "reliable")
func _rpc_building_placed(item_id: String, px: float, py: float) -> void:
	building_placed_remote.emit(item_id, px, py)


# ==============================================================================
# CALLBACKS
# ==============================================================================

func _on_peer_connected(id: int) -> void:
	if id not in connected_peers:
		connected_peers.append(id)
	player_connected.emit(id)
	EventFeed.push("Player connected (id %d)." % id, Color(0.4, 0.7, 0.9))
	# Assign stable slot, default faction, and broadcast full state to all
	if is_host:
		if not synced_peer_slots.has(id):
			synced_peer_slots[id] = _next_slot
			_next_slot += 1
		if not synced_peer_factions.has(id):
			synced_peer_factions[id] = 0
		synced_peer_ready[id] = false
		_broadcast_lobby_state()


func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	remote_cursors.erase(id)
	synced_peer_factions.erase(id)
	synced_peer_ready.erase(id)
	var slot_num: int = synced_peer_slots.get(id, 0)
	synced_peer_slots.erase(id)
	player_disconnected.emit(id)
	var slot_label: String = ("P%d" % slot_num) if slot_num > 0 else "A player"
	EventFeed.push("%s disconnected." % slot_label, Color(0.8, 0.5, 0.3))
	_broadcast_lobby_state()


func _on_connected_to_server() -> void:
	connection_succeeded.emit()
	EventFeed.push("Connected to host.", Color(0.4, 0.8, 0.4))


func _on_connection_failed() -> void:
	connection_failed.emit()
	peer = null
	EventFeed.push("Connection failed.", Color(0.9, 0.3, 0.3))


func _on_server_disconnected() -> void:
	EventFeed.push("Host disconnected.", Color(0.9, 0.3, 0.3))
	disconnect_game()
