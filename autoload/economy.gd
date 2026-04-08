extends Node
## Tracks per-faction resources (stone, fish) and purchases.

signal currency_changed()
signal item_purchased(item_id: String)

## Per-faction resources: faction_id -> {stone: int, fish: int}
var _faction_resources: Dictionary = {}

## Legacy accessors — route to local faction
var stone: int:
	get: return get_stone(FactionManager.local_faction_id)
	set(v): set_stone(FactionManager.local_faction_id, v)
var fish: int:
	get: return get_fish(FactionManager.local_faction_id)
	set(v): set_fish(FactionManager.local_faction_id, v)

var _shop: Dictionary = {}


func _ready() -> void:
	register_shop_item("house", 5, "House", "Shelters 4 villagers at night")
	register_shop_item("fishing_hut", 7, "Fishing Hut", "Blues deposit fish here")
	register_shop_item("bank", 7, "Bank", "Yellows deposit stone here")
	register_shop_item("church", 10, "Church", "Blues heal / 8 shelter at night")


func _ensure_faction(fid: int) -> void:
	if not _faction_resources.has(fid):
		_faction_resources[fid] = {"stone": 0, "fish": 0}


func get_stone(fid: int) -> int:
	_ensure_faction(fid)
	return int(_faction_resources[fid]["stone"])


func set_stone(fid: int, amount: int) -> void:
	_ensure_faction(fid)
	_faction_resources[fid]["stone"] = amount
	currency_changed.emit()


func get_fish(fid: int) -> int:
	_ensure_faction(fid)
	return int(_faction_resources[fid]["fish"])


func set_fish(fid: int, amount: int) -> void:
	_ensure_faction(fid)
	_faction_resources[fid]["fish"] = amount
	currency_changed.emit()


func register_shop_item(id: String, cost: int, display_name: String, desc: String) -> void:
	_shop[id] = {"cost": cost, "name": display_name, "description": desc}


func get_shop_items() -> Dictionary:
	return _shop


func get_sell_value(item_id: String) -> int:
	if not _shop.has(item_id):
		return 0
	return int(floor(float(_shop[item_id]["cost"]) / 2.0))


func add_stone(amount: int = 1, fid: int = -1) -> void:
	if fid < 0:
		fid = FactionManager.local_faction_id
	_ensure_faction(fid)
	_faction_resources[fid]["stone"] += amount
	currency_changed.emit()


func add_fish(amount: int = 1, fid: int = -1) -> void:
	if fid < 0:
		fid = FactionManager.local_faction_id
	_ensure_faction(fid)
	_faction_resources[fid]["fish"] += amount
	currency_changed.emit()


func can_afford(item_id: String, fid: int = -1) -> bool:
	if fid < 0:
		fid = FactionManager.local_faction_id
	if not _shop.has(item_id):
		return false
	return get_stone(fid) >= _shop[item_id]["cost"]


func purchase(item_id: String, fid: int = -1) -> bool:
	if fid < 0:
		fid = FactionManager.local_faction_id
	if not can_afford(item_id, fid):
		return false
	set_stone(fid, get_stone(fid) - _shop[item_id]["cost"])
	currency_changed.emit()
	item_purchased.emit(item_id)
	return true


func clear_all() -> void:
	_faction_resources.clear()
