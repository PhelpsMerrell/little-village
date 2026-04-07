extends Node
## Manages input bindings. Registers InputMap actions, saves/loads custom
## bindings to user://input_config.cfg, provides reset-to-defaults.

const CONFIG_PATH := "user://input_config.cfg"

## action_name -> { "default_key": KEY_*, "label": "Display Name" }
const ACTIONS: Dictionary = {
	"cmd_hold": {"default_key": KEY_G, "label": "Hold Position"},
	"cmd_house": {"default_key": KEY_H, "label": "Enter/Exit House"},
	"cmd_release": {"default_key": KEY_X, "label": "Release Command"},
	"cmd_move": {"default_key": KEY_M, "label": "Move (then click)"},
	"toggle_shop": {"default_key": KEY_B, "label": "Toggle Shop"},
	"quick_save": {"default_key": KEY_F5, "label": "Quick Save"},
	"toggle_fog_dev": {"default_key": KEY_0, "label": "[DEV] Toggle Fog"},
	"deselect": {"default_key": KEY_ESCAPE, "label": "Deselect / Menu"},
}

var _bindings: Dictionary = {}  ## action_name -> keycode


func _ready() -> void:
	_register_defaults()
	_load_config()


func _register_defaults() -> void:
	for action in ACTIONS:
		_bindings[action] = ACTIONS[action]["default_key"]
		_ensure_action(action, ACTIONS[action]["default_key"])


func _ensure_action(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# Clear existing events
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action, ev)


func get_binding(action: String) -> int:
	return _bindings.get(action, KEY_NONE)


func get_key_name(action: String) -> String:
	var kc: int = get_binding(action)
	return OS.get_keycode_string(kc) if kc != KEY_NONE else "None"


func set_binding(action: String, keycode: int) -> void:
	_bindings[action] = keycode
	_ensure_action(action, keycode)


func reset_defaults() -> void:
	for action in ACTIONS:
		set_binding(action, ACTIONS[action]["default_key"])
	save_config()


func save_config() -> void:
	var cfg := ConfigFile.new()
	for action in _bindings:
		cfg.set_value("bindings", action, _bindings[action])
	cfg.save(CONFIG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for action in ACTIONS:
		if cfg.has_section_key("bindings", action):
			var kc: int = cfg.get_value("bindings", action)
			set_binding(action, kc)


func get_action_list() -> Array:
	## Returns array of { "action": String, "label": String, "key": String }
	var result: Array = []
	for action in ACTIONS:
		result.append({
			"action": action,
			"label": ACTIONS[action]["label"],
			"key": get_key_name(action),
		})
	return result
