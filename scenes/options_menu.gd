extends Control
## In-game options menu. Scene/node based and resilient to missing nodes.
## Expects options_menu.tscn to provide:
## - PausedIndicator
## - KeyBindings
## - LeftButtons
## - RightButtons
## - DevToolsLabel

signal dev_command(cmd: String)

var _rebinding_idx: int = -1
var _actions: Array = []
var _dev_mode_on: bool = false
var _key_buttons: Array[Button] = []

@onready var _paused_indicator: Label = get_node_or_null("PausedIndicator")
@onready var _key_bindings: VBoxContainer = get_node_or_null("KeyBindings")
@onready var _left_buttons: VBoxContainer = get_node_or_null("LeftButtons")
@onready var _right_buttons: VBoxContainer = get_node_or_null("RightButtons")
@onready var _dev_tools_label: Label = get_node_or_null("DevToolsLabel")

var _dev_mode_btn: Button
var _pause_btn: Button


func _ready() -> void:
	visible = false

	if _paused_indicator == null or _key_bindings == null or _left_buttons == null or _right_buttons == null or _dev_tools_label == null:
		push_error("options_menu.gd: options_menu.tscn is missing one or more required child nodes.")
		return

	_build_buttons()
	_refresh()


func _build_buttons() -> void:
	_clear(_left_buttons)

	var reset_btn := _make_btn("Reset Keys", Color(0.5, 0.3, 0.3))
	reset_btn.pressed.connect(func():
		InputConfig.reset_defaults()
		_refresh())
	_left_buttons.add_child(reset_btn)

	var close_btn := _make_btn("Close", Color(0.3, 0.5, 0.3))
	close_btn.pressed.connect(func(): close())
	_left_buttons.add_child(close_btn)

	var main_menu_btn := _make_btn("Quit to Main Menu", Color(0.35, 0.25, 0.15))
	main_menu_btn.pressed.connect(_quit_to_main_menu)
	_left_buttons.add_child(main_menu_btn)

	var exit_btn := _make_btn("Exit to Desktop", Color(0.6, 0.15, 0.15))
	exit_btn.pressed.connect(func():
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
		get_tree().quit())
	_left_buttons.add_child(exit_btn)

	_dev_mode_btn = _make_btn("Dev Mode: OFF", Color(0.25, 0.2, 0.35))
	_dev_mode_btn.pressed.connect(func():
		set_dev_mode_enabled(not _dev_mode_on)
		dev_command.emit("toggle_dev_mode"))
	_left_buttons.add_child(_dev_mode_btn)
	set_dev_mode_enabled(_dev_mode_on)

	_clear(_right_buttons)

	_pause_btn = _make_btn("Pause Game", Color(0.5, 0.5, 0.2))
	_pause_btn.pressed.connect(func():
		GameClock.is_paused = not GameClock.is_paused
		dev_command.emit("pause"))
	_right_buttons.add_child(_pause_btn)

	var next_phase_btn := _make_btn("Next Phase", Color(0.3, 0.4, 0.5))
	next_phase_btn.pressed.connect(func():
		GameClock.advance_phase()
		dev_command.emit("next_phase"))
	_right_buttons.add_child(next_phase_btn)

	var reset_game_btn := _make_btn("Reset Game", Color(0.5, 0.2, 0.2))
	reset_game_btn.pressed.connect(func(): dev_command.emit("reset"))
	_right_buttons.add_child(reset_game_btn)


func _refresh() -> void:
	if _key_bindings == null:
		return
	_actions = InputConfig.get_action_list()
	_rebuild_key_list()


func _rebuild_key_list() -> void:
	_clear(_key_bindings)
	_key_buttons.clear()

	for i in range(_actions.size()):
		var a: Dictionary = _actions[i]

		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 34

		var label := Label.new()
		label.text = a["label"]
		label.custom_minimum_size.x = 180
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		row.add_child(label)

		var key_btn := Button.new()
		key_btn.text = a["key"]
		key_btn.custom_minimum_size = Vector2(160, 34)
		_style_btn(key_btn, Color(0.12, 0.14, 0.18))
		var idx: int = i
		key_btn.pressed.connect(func(): _start_rebind(idx))
		row.add_child(key_btn)
		_key_buttons.append(key_btn)

		_key_bindings.add_child(row)

	var btn_y: float = 120.0 + _actions.size() * 38.0 + 20.0
	_left_buttons.offset_top = btn_y
	_left_buttons.offset_bottom = btn_y + 250.0
	_right_buttons.offset_top = btn_y + 18.0
	_right_buttons.offset_bottom = btn_y + 200.0
	_dev_tools_label.offset_top = btn_y - 2.0
	_dev_tools_label.offset_bottom = btn_y + 14.0


func _start_rebind(idx: int) -> void:
	if idx < 0 or idx >= _key_buttons.size():
		return
	_rebinding_idx = idx
	_key_buttons[idx].text = "Press key..."
	_style_btn(_key_buttons[idx], Color(0.4, 0.25, 0.1))


func open() -> void:
	if _paused_indicator == null:
		return
	_refresh()
	_rebinding_idx = -1
	visible = true
	_paused_indicator.visible = GameClock.is_paused
	if _pause_btn != null:
		_pause_btn.text = "Unpause" if GameClock.is_paused else "Pause Game"

	var is_host: bool = NetworkManager.is_authority()
	if _right_buttons != null:
		_right_buttons.visible = is_host
	if _dev_tools_label != null:
		_dev_tools_label.visible = is_host


func set_dev_mode_enabled(enabled: bool) -> void:
	_dev_mode_on = enabled
	if _dev_mode_btn != null:
		_dev_mode_btn.text = "Dev Mode: ON" if _dev_mode_on else "Dev Mode: OFF"
		_style_btn(_dev_mode_btn, Color(0.45, 0.2, 0.55) if _dev_mode_on else Color(0.25, 0.2, 0.35))


func close() -> void:
	visible = false
	_rebinding_idx = -1


func _process(_delta: float) -> void:
	if not visible:
		return
	if _paused_indicator != null:
		_paused_indicator.visible = GameClock.is_paused
	if _pause_btn != null:
		_pause_btn.text = "Unpause" if GameClock.is_paused else "Pause Game"


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if _rebinding_idx >= 0 and event is InputEventKey and event.pressed:
		var action: String = _actions[_rebinding_idx]["action"]
		InputConfig.set_binding(action, event.keycode)
		InputConfig.save_config()
		_rebinding_idx = -1
		_refresh()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _quit_to_main_menu() -> void:
	TutorialManager.active = false
	TutorialManager.current_phase = 0
	TutorialManager._pending_advance = false
	SaveManager.delete_save()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


func _make_btn(label: String, col: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(180, 34)
	_style_btn(btn, col)
	return btn


func _style_btn(btn: Button, col: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = col.darkened(0.2)
	normal.bg_color.a = 0.65
	normal.border_color = Color(0.5, 0.5, 0.5, 0.3)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(4)

	var hover := StyleBoxFlat.new()
	hover.bg_color = col.lightened(0.2)
	hover.bg_color.a = 0.85
	hover.border_color = Color(0.5, 0.5, 0.5, 0.3)
	hover.set_border_width_all(1)
	hover.set_content_margin_all(4)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.95))
	btn.add_theme_font_size_override("font_size", 16)


func _clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.queue_free()
