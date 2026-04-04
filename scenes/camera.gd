extends Camera2D
## Pan: right-click drag, middle-mouse drag, WASD/Arrows.
## Zoom: scroll wheel, Q/E keys.
## F11: toggle fullscreen.

const PAN_SPEED := 800.0
const ZOOM_MIN := 0.15
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1
const ZOOM_KEY_SPEED := 1.0      # zoom per second when holding Q/E

var _panning := false
var _pan_start := Vector2.ZERO


func _ready() -> void:
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			if _panning:
				_pan_start = get_global_mouse_position()

	if event is InputEventMouseMotion and _panning:
		var current := get_global_mouse_position()
		position += _pan_start - current
		_pan_start = get_global_mouse_position()

	# F11 fullscreen toggle
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()


func _process(delta: float) -> void:
	# WASD + Arrow pan
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x

	# Q/E zoom
	if Input.is_key_pressed(KEY_E):
		_apply_zoom(ZOOM_KEY_SPEED * delta)
	if Input.is_key_pressed(KEY_Q):
		_apply_zoom(-ZOOM_KEY_SPEED * delta)


func _apply_zoom(amount: float) -> void:
	var z := clampf(zoom.x + amount, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
