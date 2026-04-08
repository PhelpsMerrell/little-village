# Little Village — Map Generation Guidelines

## Overview

Map generation is handled by `scenes/map_generator.gd` (a `RefCounted`, not a Node). Called from `main.gd._generate_map()` via `_map_gen.generate(containers, scenes, map_seed, faction_count, map_size)`.

All generation is **seed-deterministic**: given the same seed, faction count, and map size, the result is identical across all peers.

---

## Grid System

The map is a grid of cells. Each cell is `CELL = 675px` wide/tall with `MAP_GAP = 8px` between cells. Rooms can span multiple cells (footprints like 2×2, 2×1, 1×2, 1×1).

### Grid Dimensions by Size and Faction Count

| Factions | Small | Medium | Large | XL |
|----------|-------|--------|-------|----|
| 1 | 6×4 | 8×6 | 10×7 | 14×10 |
| 2 | 7×5 | 9×6 | 11×8 | 14×11 |
| 4 | 8×6 | 10×7 | 12×9 | 15×11 |
| 8 | 10×7 | 12×8 | 14×10 | 16×12 |

---

## Seed-Based Generation Algorithm

```
generate(seed, faction_count, map_size):
  1. _setup_grid_size()         — choose grid dims from table above
  2. _init_grid()               — fill all cells with -1 (empty)
  3. _place_faction_clusters()  — place core+stone+river per faction on perimeter
  4. _connect_faction_clusters() — carve backbone paths between factions (NEW)
  5. _fill_neutral_rooms()      — 3-pass organic island generation
  6. _build_room_defs_array()   — convert internal map to ROOM_DEFS
  7. _generate_rooms()          — instantiate Room nodes
  8. _generate_walls()          — instantiate Wall/Door nodes between rooms
  9. _generate_entities()       — populate neutral rooms with resources/enemies
  10. _generate_faction_starts() — spawn starting villagers/banks/huts per faction
  11. _print_debug_summary()    — ASCII grid + connectivity check
```

---

## Faction Cluster Placement

Each faction gets a 3-room cluster:
1. **Core** (2×2): Home room. Spawn point. Door-restricted to stone room only.
2. **Stone Room** (2×1 or 1×2): Adjacent to core. Contains bank + starting stones.
3. **River Room** (1×1): Adjacent to stone room. Contains fishing hut + starting fish.

Clusters are placed at evenly-spaced positions around the grid perimeter (`_spread_on_perimeter()`). Cluster direction (which way to extend stone/river) is determined by which edge the spawn cell is on.

Door restrictions: `_door_restrictions` dictionary prevents doors between core↔river (they must go through stone room).

---

## Connectivity Guarantee

After faction cluster placement, a **backbone path** is carved between all faction spawn points to guarantee a single connected landmass. This prevents any faction from being isolated on a separate island.

### Algorithm (`_connect_faction_clusters`)
1. Iterates faction spawn cells in order (circular — last faction connects back to first).
2. For each consecutive pair `(from, to)`, calls `_carve_path(from, to)`.
3. `_carve_path`: L-shaped Manhattan route with randomized horizontal midpoint for organic feel:
   - Walk horizontally to `mid_x = rng.randi_range(min(from.x, to.x), max(from.x, to.x))`
   - Walk vertically to `to.y`
   - Walk horizontally to `to.x`
4. Each cell on the path is added to `_island_mask` via `_ensure_mask()` (skips already-masked cells).

This guarantees that even with 8 factions on a small grid, all spawn clusters are reachable from each other before organic growth fills the rest.

**Note**: Separate islands are no longer acceptable. The connectivity check in `_print_debug_summary()` (`_is_island_connected()`) must always pass. Any map seed that fails connectivity is a bug.

---

## Neutral Room Generation (3-Pass Island)

### Pass 1: Island Mask Growth (`_grow_island_mask`)

Organic BFS-style growth from faction cells.

Fill ratios by map size:
| Size | Min fill | Max fill |
|------|----------|----------|
| small | 45% | 56% |
| medium | 58% | 68% |
| large | 70% | 80% |
| xl | 80% | 90% |

Growth is biased toward cells with more island neighbors (`_weighted_frontier_pick`). Anti-rectangularization: cells that would complete a fully-surrounded 8-neighbor block are rejected with 75% probability. Peninsula tips (≤1 island neighbor) are carved out post-growth. Connectivity is repaired if carving would disconnect the island.

### Pass 2: Footprint Placement (`_place_footprints`)

Tries to fit varied room shapes (largest first: 3×2, 2×3, 2×2, 3×1, 1×3, 2×1, 1×2, 1×1) into free island mask cells. Any remaining unoccupied mask cells become 1×1 rooms.

### Pass 3: Type Assignment (`_assign_room_types`)

Neutral rooms get gameplay types based on Manhattan distance from nearest faction spawn:

| Distance | Possible Types |
|----------|---------------|
| ≤ 2 | Passage |
| 3–4 | River, Quarry, Colorless Passage, Passage |
| 5+ | River, Enemy Den, Quarry, Colorless Camp, Contested, Passage |

Target counts: ~1/6 rivers, ~1/4 quarries, ~1/8 enemy dens (of total neutral rooms).

---

## Room Types

| Type | Label | Contents |
|------|-------|----------|
| `core` | Home | Starting villagers, magic orb |
| `stone_room` | Stone Quarry | Bank, starting stones |
| `river_room` | River | Fishing hut, fish, river obstacle |
| `quarry` | Quarry | 8–15 stone collectables |
| `passage` | Passage | Empty |
| `colorless_passage` | Wanderer's Path | 1–3 colorless villagers |
| `colorless_camp` | Wanderer Camp | 6–10 colorless villagers |
| `enemy_den` | Enemy Den | 2–3 enemies |
| `contested` | Contested | 1–2 enemies + 4–8 stones |

---

## Wall & Door Generation

Walls are generated between every pair of adjacent rooms (sharing a grid edge). The wall system:
- Each shared edge between rooms A and B generates one wall pair.
- If `_door_restrictions` allows a door between A and B, a door gap (`DOOR_SIZE = 120px`) is carved at the midpoint.
- Walls without doors are solid segments.
- Door state: `is_door = true`, `is_open = false` initially. Red villagers break doors.

---

## River Fish Production

`main.gd._process_river_fish()`: every `RIVER_FISH_INTERVAL = 1800s` (30 game minutes), checks all river rooms. If a river room has fewer than `RIVER_FISH_MAX = 4` fish, spawns one new fish spot in that room.

`_river_room_ids` is populated from `_map_gen._river_room_ids` after generation. Includes both faction river rooms and neutral river rooms.

---

## Debug Output

At the end of `generate()`, `_print_debug_summary()` prints:
- Grid dimensions and fill percentages.
- Room count and bounding box.
- Footprint size breakdown.
- Room type breakdown.
- **Connectivity check**: "PASS" or "FAIL".
- ASCII grid: `C`=Core, `S`=Stone, `R`=River, `Q`=Quarry, `E`=Enemy, `W`=WandererCamp, `w`=path, `X`=Contested, `.`=Passage, `~`=Water (off-island).

If connectivity is "FAIL", this is a bug — the `_connect_faction_clusters` backbone should prevent all failures.

---

## Public API

```gdscript
map_gen.generate(containers, scenes, map_seed, faction_count, map_size)
map_gen.ROOM_DEFS        # Array of [id, col, row, cw, ch, label, color]
map_gen.FACTION_STARTS   # Array of {home_room, bank_room, river_room}
map_gen.room_map         # Dictionary: room_id -> Room node
map_gen.find_room_def(rid) -> Array
MapGenerator.room_pixel_pos(col, row) -> Vector2    # static
MapGenerator.room_pixel_size(cw, ch) -> Vector2    # static
```
