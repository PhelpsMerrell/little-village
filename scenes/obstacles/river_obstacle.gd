extends Node2D
## Multi-segment river obstacle. Draws an S-curve or custom path of water.
## Each segment is a rect that blocks non-swimmers.
## Configure segments via @export arrays for creative shapes.

## Each segment: {offset_x, offset_y, width, height}
@export var segments: Array = [
	{"x": 0, "y": 0, "w": 80, "h": 400},
	{"x": 0, "y": 400, "w": 500, "h": 80},
	{"x": 420, "y": 400, "w": 80, "h": 500},
	{"x": 0, "y": 820, "w": 500, "h": 80},
	{"x": 0, "y": 820, "w": 80, "h": 530},
]
@export var blocked_ability: String = "swim"


func get_blocked_rects() -> Array:
	var rects: Array = []
	for seg in segments:
		rects.append(Rect2(
			global_position.x + float(seg["x"]),
			global_position.y + float(seg["y"]),
			float(seg["w"]), float(seg["h"])))
	return rects


func blocks_color(color_id: String) -> bool:
	return not ColorRegistry.has_ability(color_id, blocked_ability)


func get_blocked_rect() -> Rect2:
	# Return bounding box — room.gd calls this for single-rect obstacles
	# For multi-segment, main.gd should use get_blocked_rects() instead
	if segments.is_empty():
		return Rect2()
	var min_p := Vector2(float(segments[0]["x"]), float(segments[0]["y"]))
	var max_p := min_p
	for seg in segments:
		var sx: float = float(seg["x"])
		var sy: float = float(seg["y"])
		var sw: float = float(seg["w"])
		var sh: float = float(seg["h"])
		min_p.x = minf(min_p.x, sx)
		min_p.y = minf(min_p.y, sy)
		max_p.x = maxf(max_p.x, sx + sw)
		max_p.y = maxf(max_p.y, sy + sh)
	return Rect2(global_position + min_p, max_p - min_p)


func _draw() -> void:
	for seg in segments:
		var r := Rect2(float(seg["x"]), float(seg["y"]), float(seg["w"]), float(seg["h"]))
		draw_rect(r, Color(0.12, 0.3, 0.55, 0.5))
		# Wavy lines
		var y := r.position.y + 8.0
		while y < r.end.y:
			var wx := sin(y * 0.05) * 6.0
			draw_line(
				Vector2(r.position.x + 8 + wx, y),
				Vector2(r.end.x - 8 + wx, y),
				Color(0.25, 0.5, 0.8, 0.2), 1.0)
			y += 16.0
		draw_rect(r, Color(0.15, 0.35, 0.65, 0.35), false, 2.0)
