extends Node
## Tracks player resources (stone, fish) and purchases.

signal currency_changed()
signal item_purchased(item_id: String)

var stone: int = 0
var fish: int = 0

var _shop: Dictionary = {}


func _ready() -> void:
	register_shop_item("house", 5, "House", "Shelters 4 villagers at night")


func register_shop_item(id: String, cost: int, display_name: String, desc: String) -> void:
	_shop[id] = {"cost": cost, "name": display_name, "description": desc}


func get_shop_items() -> Dictionary:
	return _shop


func add_stone(amount: int = 1) -> void:
	stone += amount
	currency_changed.emit()


func add_fish(amount: int = 1) -> void:
	fish += amount
	currency_changed.emit()


func can_afford(item_id: String) -> bool:
	if not _shop.has(item_id):
		return false
	return stone >= _shop[item_id]["cost"]


func purchase(item_id: String) -> bool:
	if not can_afford(item_id):
		return false
	stone -= _shop[item_id]["cost"]
	currency_changed.emit()
	item_purchased.emit(item_id)
	return true
