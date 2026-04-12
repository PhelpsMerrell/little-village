extends Control
## Title screen. New Game, Tutorial, Sandbox, or Continue.

@onready var _moon: Control = $CenterAnchor/Moon
@onready var _new_btn: Button = $CenterAnchor/ButtonBox/NewGameBtn
@onready var _tutorial_btn: Button = $CenterAnchor/ButtonBox/TutorialBtn
@onready var _sandbox_btn: Button = $CenterAnchor/ButtonBox/SandboxBtn
@onready var _continue_btn: Button = $CenterAnchor/ButtonBox/ContinueBtn
@onready var _no_save_label: Label = $CenterAnchor/ButtonBox/NoSaveLabel


func _ready() -> void:
	_style_button(_new_btn, Color(0.12, 0.14, 0.1), Color(0.18, 0.22, 0.15),
		Color(0.4, 0.5, 0.3, 0.6), Color(0.7, 0.7, 0.6), Color(0.9, 0.9, 0.8))
	_style_button(_tutorial_btn, Color(0.12, 0.12, 0.08), Color(0.18, 0.18, 0.12),
		Color(0.55, 0.5, 0.25, 0.6), Color(0.72, 0.68, 0.45), Color(0.95, 0.9, 0.65))
	_style_button(_sandbox_btn, Color(0.12, 0.1, 0.15), Color(0.18, 0.15, 0.22),
		Color(0.45, 0.35, 0.6, 0.6), Color(0.65, 0.6, 0.72), Color(0.9, 0.85, 0.95))
	_style_button(_continue_btn, Color(0.1, 0.12, 0.15), Color(0.15, 0.18, 0.22),
		Color(0.3, 0.4, 0.5, 0.6), Color(0.6, 0.65, 0.7), Color(0.85, 0.9, 0.95))

	_new_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/lobby.tscn"))
	_tutorial_btn.pressed.connect(_start_tutorial)
	_sandbox_btn.pressed.connect(_start_sandbox)
	_continue_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))

	var has_save: bool = SaveManager.has_save()
	_continue_btn.visible = has_save
	_no_save_label.visible = not has_save

	_moon.draw.connect(_draw_moon)
	_moon.queue_redraw()


func _draw_moon() -> void:
	var cx: float = _moon.size.x * 0.5
	var cy: float = _moon.size.y * 0.5
	_moon.draw_circle(Vector2(cx, cy), 30, Color(0.85, 0.82, 0.6, 0.3))
	_moon.draw_arc(Vector2(cx, cy), 30, 0.0, TAU, 32, Color(0.9, 0.85, 0.5, 0.5), 2.0)


func _style_button(btn: Button, bg_normal: Color, bg_hover: Color, border_col: Color, text_normal: Color, text_hover: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(bg_normal.r, bg_normal.g, bg_normal.b, 0.8)
	normal.border_color = border_col
	normal.set_border_width_all(2)
	normal.set_content_margin_all(8)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(bg_hover.r, bg_hover.g, bg_hover.b, 0.9)
	hover.border_color = border_col
	hover.set_border_width_all(2)
	hover.set_content_margin_all(8)

	var pressed := hover.duplicate()
	pressed.bg_color = bg_hover.darkened(0.1)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", text_normal)
	btn.add_theme_color_override("font_hover_color", text_hover)
	btn.add_theme_color_override("font_pressed_color", text_hover)
	btn.add_theme_font_size_override("font_size", 18)


func _start_tutorial() -> void:
	FactionManager.clear()
	FactionManager.register_faction(0, "$", Color(0.2, 0.6, 0.9))
	FactionManager.local_faction_id = 0
	FactionManager.max_population = 40
	FactionManager.set_meta("map_seed", 42)
	FactionManager.set_meta("faction_count", 1)
	FactionManager.set_meta("map_size", "small")
	FactionManager.set_meta("player_count", 1)
	SaveManager.delete_save()
	TutorialManager.start_tutorial()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _start_sandbox() -> void:
	FactionManager.clear()
	FactionManager.register_faction(0, "$", Color(0.2, 0.6, 0.9))
	FactionManager.local_faction_id = 0
	FactionManager.max_population = 100
	FactionManager.set_meta("map_seed", 99)
	FactionManager.set_meta("faction_count", 1)
	FactionManager.set_meta("map_size", "small")
	FactionManager.set_meta("player_count", 1)
	FactionManager.set_meta("sandbox", true)
	SaveManager.delete_save()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
