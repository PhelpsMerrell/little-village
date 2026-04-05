# Map Generation Guidelines
# For future procedural map generation in Little Village

## Grid Constants
const ROOM_SIZE = 1350      # px per room
const GAP = 8               # px between rooms
const STRIDE = ROOM_SIZE + GAP  # 1358

## Room Type Distribution (per 24-room map)
# Start cluster (always top-left 2x2):
#   - 1 Red Start
#   - 1 Yellow Start + Bank
#   - 1 Blue Start
#   - 1 Colorless Chamber
#
# Resource rooms: ~30% of remaining (6 rooms)
#   - Stone Quarries: 3-5 rooms, 8-20 stones each
#   - River Delta: 1 room, S-curve river + 10-15 fish + fishing hut
#   - Flooded Quarry: 1 room, water + stones (blue-only access to stones)
#
# Hazard rooms: ~20% of remaining (4 rooms)
#   - Enemy Dens: 1 enemy each, NEVER 2+ in same room at start
#   - Barricade: breakable wall blocking passage
#   - Fortification: breakable wall protecting resources
#
# Passage rooms: ~25% (5 rooms)
#   - Empty rooms for movement, influence, strategy
#
# Water rooms: ~10% (2 rooms)
#   - Water crossing (blocks non-blues)
#   - Shallows (partial water)

## Placement Rules
# 1. Start cluster is always rooms [0,1] / [cols, cols+1] (top-left 2x2)
# 2. Bank placed in Yellow Start room
# 3. Fishing Hut placed in or adjacent to River Delta room
# 4. Enemies are ALWAYS alone (1 per room, never 2)
# 5. Enemy dens should be 2+ rooms away from start cluster
# 6. Resources should require traversal - not adjacent to start
# 7. At least 1 breakable wall should gate a resource-rich area
# 8. At least 1 water crossing should gate a fishing area
# 9. Colorless villager is always in the start cluster

## Difficulty Scaling
# Easy:    4x3 grid, 3 enemies, 40 stones, 10 fish, 1 breakable wall
# Medium:  6x4 grid, 5 enemies, 68 stones, 15 fish, 3 breakable walls
# Hard:    8x5 grid, 8 enemies, 100 stones, 20 fish, 5 breakable walls, more water

## Stone Distribution
# - Quarry rooms: 15-20 stones (rich)
# - Stone fields: 8-10 stones (moderate)
# - Flooded quarries: 6-8 stones behind water (gated)
# - Place stones randomly within room bounds, 80px margin from edges

## Enemy Placement
# - Min distance from start: 2 room-hops (Manhattan distance >= 2)
# - Never place 2 enemies in adjacent rooms (prevents early merging)
# - Scatter evenly: aim for 1 enemy per 4-5 rooms
# - Bottom and right edges of map preferred (player expands toward danger)

## Water Obstacle Variants
# - Vertical stripe: water_size = Vector2(60, ROOM_SIZE) -- classic crossing
# - Horizontal stripe: water_size = Vector2(ROOM_SIZE, 60) -- floor divide
# - River (multi-segment): S-curve using river_obstacle.tscn segments array

## Wall Connectivity
# - Every adjacent pair of rooms gets a wall segment
# - All walls start closed
# - Player must click to open them
# - Consider pre-opening some walls in easy mode for less tedium

## Seed-Based Generation Algorithm (future)
# 1. Create COLS x ROWS grid
# 2. Place start cluster at [0,0]
# 3. Flood-fill room types using weighted random:
#    - Distance from start determines type weights
#    - Near start: more passages, fewer hazards
#    - Far from start: more enemies, more resources
# 4. Place obstacles as children of their rooms
# 5. Scatter collectables within resource rooms
# 6. Place enemies (1 per den, isolated)
# 7. Generate wall segments for all adjacent pairs
# 8. Place bank in start cluster, hut near river
# 9. Validate: ensure all resources are reachable via some path
