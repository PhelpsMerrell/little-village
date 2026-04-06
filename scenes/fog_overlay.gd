extends Node2D
## Fog overlay drawn at z_index 100 (above entities, below UI).
## Unexplored rooms: near-black. Explored-but-inactive: dimmed (terrain visible, no resources/actors).
## Active rooms (villager present): fully visible.


func _draw() -> void:
	var main = get_parent()
	if not main or main.rooms.is_empty():
		return

	# Draw off-map fill so camera never sees default background
	var mb: Rect2 = main._compute_map_bounds()
	var big: Rect2 = mb.grow(5000)
	var edge_color := Color(0.02, 0.02, 0.04)
	# Top
	draw_rect(Rect2(big.position.x, big.position.y, big.size.x, mb.position.y - big.position.y), edge_color)
	# Bottom
	draw_rect(Rect2(big.position.x, mb.end.y, big.size.x, big.end.y - mb.end.y), edge_color)
	# Left
	draw_rect(Rect2(big.position.x, mb.position.y, mb.position.x - big.position.x, mb.size.y), edge_color)
	# Right
	draw_rect(Rect2(mb.end.x, mb.position.y, big.end.x - mb.end.x, mb.size.y), edge_color)

	# Dev mode: skip room fog entirely
	if main._dev_fog_off:
		return

	for room in main.rooms:
		var rid: int = room.room_id
		var rect: Rect2 = room.get_rect()
		if not FogOfWar.is_explored(rid):
			# Full fog — unexplored
			draw_rect(rect, Color(0.02, 0.02, 0.04, 0.97))
		elif not FogOfWar.is_active(rid):
			# Dim overlay — explored but no villager. Terrain visible, resources/actors hidden.
			draw_rect(rect, Color(0.03, 0.03, 0.06, 0.55))
