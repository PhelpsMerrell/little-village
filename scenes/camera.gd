extends Camera2D
## Pan: middle-mouse drag, WASD/Arrows.
## Zoom: scroll wheel, Q/E keys.
## F11: toggle fullscreen.
## Camera is clamped to map bounds. Zoom limited by explored area.

const PAN_SPEED := 800.0
const ZOOM_MIN := 0.2
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1
const ZOOM_KEY_SPEED := 1.0
const FOG_PADDING_ROOMS := 1  # how many unexplored rooms beyond edge to allow seeing

var _panning := false

## Set by main.gd after rooms are collected
var map_bounds: Rect2 = Rect2()
var explored_bounds: Rect2 = Rect2()

## Home room center for spacebar snap (set by main.gd)
var home_room_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_apply_zoom(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_apply_zoom(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed

	if event is InputEventMouseMotion and _panning:
		position -= event.relative / zoom.x
		_clamp_position()

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
		elif event.keycode == KEY_SPACE:
			_snap_to_home()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S): dir.y += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
		_clamp_position()

	if Input.is_key_pressed(KEY_E): _apply_zoom(ZOOM_KEY_SPEED * delta)
	if Input.is_key_pressed(KEY_Q): _apply_zoom(-ZOOM_KEY_SPEED * delta)


func _apply_zoom(amount: float) -> void:
	var max_zoom: float = _get_max_zoom_out()
	var z := clampf(zoom.x + amount, max_zoom, ZOOM_MAX)
	zoom = Vector2(z, z)
	_clamp_position()


func _get_max_zoom_out() -> float:
	## Limit zoom-out so viewport fits within explored area (+ padding).
	## This prevents the player from seeing the full map before exploring.
	if not explored_bounds.has_area():
		return ZOOM_MAX  # no explored area yet, stay zoomed in

	var vp_size: Vector2 = get_viewport_rect().size
	# Add padding so you can see a ring of fog around explored area
	var padded: Rect2 = explored_bounds.grow(1500.0)

	# Zoom where viewport exactly fits the padded explored bounds
	var zoom_x: float = vp_size.x / padded.size.x
	var zoom_y: float = vp_size.y / padded.size.y
	var fit_zoom: float = minf(zoom_x, zoom_y)

	# Don't allow zooming out more than this, but also not less than absolute min
	return maxf(fit_zoom, ZOOM_MIN)


func _clamp_position() -> void:
	## Keep camera viewport within map bounds. No off-map brown visible.
	if not map_bounds.has_area(): return

	var vp_size: Vector2 = get_viewport_rect().size
	var half_vp: Vector2 = vp_size / (2.0 * zoom.x)

	# Clamp so viewport edges don't exceed map edges
	var min_pos: Vector2 = map_bounds.position + half_vp
	var max_pos: Vector2 = map_bounds.end - half_vp

	# If map is smaller than viewport in either axis, center on that axis
	if min_pos.x > max_pos.x:
		position.x = map_bounds.get_center().x
	else:
		position.x = clampf(position.x, min_pos.x, max_pos.x)

	if min_pos.y > max_pos.y:
		position.y = map_bounds.get_center().y
	else:
		position.y = clampf(position.y, min_pos.y, max_pos.y)


func update_bounds(p_map_bounds: Rect2, p_explored_bounds: Rect2) -> void:
	map_bounds = p_map_bounds
	explored_bounds = p_explored_bounds
	_clamp_position()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _snap_to_home() -> void:
	if home_room_center != Vector2.ZERO:
		position = home_room_center
		_clamp_position()
