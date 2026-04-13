extends Node2D
## Portal landmark. Draws a swirling vortex at room center.
## Villagers within TELEPORT_RADIUS are teleported to the partner portal.

const TELEPORT_RADIUS := 80.0
const VISUAL_RADIUS := 60.0

var room_id: int = -1
var partner_room_id: int = -1

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	# Outer glow ring
	var glow_alpha: float = 0.15 + sin(_time * 2.0) * 0.05
	draw_circle(Vector2.ZERO, VISUAL_RADIUS + 10.0, Color(0.5, 0.1, 0.7, glow_alpha))

	# Dark center
	draw_circle(Vector2.ZERO, VISUAL_RADIUS * 0.3, Color(0.05, 0.0, 0.1, 0.8))

	# Swirling arcs
	var arc_count: int = 4
	for i in arc_count:
		var base_angle: float = _time * 1.5 + (TAU / arc_count) * i
		var points: PackedVector2Array = PackedVector2Array()
		for s in range(0, 20):
			var t: float = float(s) / 19.0
			var r: float = lerpf(VISUAL_RADIUS * 0.25, VISUAL_RADIUS, t)
			var a: float = base_angle + t * 2.5
			points.append(Vector2(cos(a) * r, sin(a) * r))
		if points.size() >= 2:
			draw_polyline(points, Color(0.6, 0.2, 0.9, 0.4), 2.0)

	# Outer ring border
	var ring_points: PackedVector2Array = PackedVector2Array()
	for s in range(0, 33):
		var a: float = TAU * float(s) / 32.0
		var wobble: float = sin(_time * 3.0 + a * 3.0) * 4.0
		ring_points.append(Vector2(cos(a) * (VISUAL_RADIUS + wobble), sin(a) * (VISUAL_RADIUS + wobble)))
	draw_polyline(ring_points, Color(0.5, 0.15, 0.75, 0.6), 2.5)

	# Label
	draw_string(ThemeDB.fallback_font, Vector2(-20, VISUAL_RADIUS + 22),
		"Portal", HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(0.7, 0.3, 0.9, 0.7))
