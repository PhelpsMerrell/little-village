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
	var water_color := Color(0.04, 0.07, 0.13)
	# Top
	draw_rect(Rect2(big.position.x, big.position.y, big.size.x, mb.position.y - big.position.y), water_color)
	# Bottom
	draw_rect(Rect2(big.position.x, mb.end.y, big.size.x, big.end.y - mb.end.y), water_color)
	# Left
	draw_rect(Rect2(big.position.x, mb.position.y, mb.position.x - big.position.x, mb.size.y), water_color)
	# Right
	draw_rect(Rect2(mb.end.x, mb.position.y, big.end.x - mb.end.x, mb.size.y), water_color)

	# Water fill for non-room cells within the bounding box (island gaps)
	_draw_water_gaps(main, mb, water_color)

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


func _draw_water_gaps(main: Node, map_bounds: Rect2, water_color: Color) -> void:
	## Fill all non-room grid cells within map bounds with water.
	## Builds a set of room rects and fills everything else.
	if not main.has_method("_compute_map_bounds"):
		return

	# Build set of all room pixel rects
	var room_rects: Array = []
	for room in main.rooms:
		room_rects.append(room.get_rect())

	if room_rects.is_empty():
		return

	# Use grid cell size to fill gap cells.
	# We scan across the map bounding box in cell-sized steps and fill any
	# cell-sized tile that doesn't overlap any room rect.
	const CELL := 675
	const GAP := 8
	const STEP := CELL + GAP

	var start_x: int = int(map_bounds.position.x / STEP) * STEP
	var start_y: int = int(map_bounds.position.y / STEP) * STEP
	var end_x: int = int(map_bounds.end.x / STEP + 1) * STEP
	var end_y: int = int(map_bounds.end.y / STEP + 1) * STEP

	var x: int = start_x
	while x < end_x:
		var y: int = start_y
		while y < end_y:
			var cell_rect := Rect2(float(x), float(y), float(CELL), float(CELL))
			# Check if this cell overlaps any room
			var overlaps: bool = false
			for rr in room_rects:
				if rr.intersects(cell_rect, true):
					overlaps = true
					break
			if not overlaps and map_bounds.intersects(cell_rect, true):
				draw_rect(cell_rect, water_color)
				# Subtle wave lines for water texture
				var cx: float = float(x) + CELL * 0.5
				var cy: float = float(y) + CELL * 0.5
				draw_line(Vector2(cx - 80, cy - 30), Vector2(cx + 80, cy - 30),
					Color(0.06, 0.11, 0.2, 0.35), 3.0)
				draw_line(Vector2(cx - 60, cy + 10), Vector2(cx + 60, cy + 10),
					Color(0.06, 0.11, 0.2, 0.35), 3.0)
				draw_line(Vector2(cx - 90, cy + 50), Vector2(cx + 90, cy + 50),
					Color(0.06, 0.11, 0.2, 0.3), 2.0)
			y += STEP
		x += STEP
