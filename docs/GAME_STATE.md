# Little Village — Game State Reference

## Architecture Overview

- **Host-authoritative**: Only the host runs simulation. Clients send commands and receive state snapshots at `SYNC_RATE` (10 Hz).
- **Solo mode**: `NetworkManager.is_online()` returns false — zero networking overhead. Same code path as host.
- **Autoloads**: ColorRegistry, GameRNG, InputConfig, InfluenceManager, GameClock, Economy, NightEvents, EventFeed, SaveManager, FogOfWar, FactionManager, RoomOwnership, NetworkManager, TutorialManager.

---

## Lobby Sync

**Pattern**: `_broadcast_lobby_state()` in `network_manager.gd`.

Every mutation to lobby state (ready toggle, faction choice, peer connect/disconnect) triggers a full broadcast of `synced_peer_factions`, `synced_peer_ready`, `synced_map_seed`, `synced_faction_count`, `synced_max_population`, and `synced_map_size` to all connected clients via `_rpc_receive_lobby_state`.

- `send_ready_toggle()` → host updates `synced_peer_ready`, broadcasts to all.
- `send_faction_choice()` → host updates `synced_peer_factions`, broadcasts to all.
- `_on_peer_connected()` → host assigns default faction, broadcasts full state.
- `_on_peer_disconnected()` → host removes peer data, broadcasts updated state.
- `broadcast_lobby_config()` → sets all synced values and broadcasts.
- New field: `synced_map_size: String` ("small"/"medium"/"large"/"xl").

Clients never update their synced dicts locally — they only receive from the authoritative broadcast.

---

## Factions

Each faction has an `id`, `name`, `color` (Color), and `eliminated` flag. Managed by `FactionManager` autoload.

- `local_faction_id`: Which faction this client controls.
- `get_faction_color(id)` / `get_faction_symbol(id)`: Returns visual identity.
- Villagers carry `faction_id`. Colorless villagers use `faction_id = -1`.

### Faction Visual Identification (Phase 3)

Each villager draws a **faction ring** in `_draw()`:
- A thick arc (`draw_arc`, width 4.0) at `radius + 6.0` using `FactionManager.get_faction_color(faction_id)`.
- Drawn **before** the body so the body renders on top.
- Not drawn for `faction_id == -1` (unowned/colorless).
- Body outline (`_get_faction_border_color()`) also uses faction color.
- `_draw_faction_symbol()` renders the faction glyph inside the body.

---

## Color System

Colors: `red`, `yellow`, `blue`, `colorless`, `magic_orb`. Defined in `color_registry.gd`.

Shift chain: colorless → red → yellow → blue → red (loop)

### Color Roles
- **Red**: Attack (ranged shoot), break doors, hunger mechanic. PvP: attacks enemy villagers.
- **Yellow**: Collect stone, deposit at bank. Levels by pairing. Duplicates on shift (spawn_count=2 at L1).
- **Blue**: Collect fish, deposit at hut. Merges to level. Heals in church. PvP: stuns enemy villagers.
- **Colorless**: Neutral wanderers. Shifts to whichever color group influences them. Joins that faction on shift.
- **Magic Orb**: Stationary influence catalyst. `influence_rate = 4.0` (doubled from original 2.0 to compensate halved BASE_SHIFT_SPEED).

### Cross-Faction Color Shifting (Phase 5)

Villagers CAN change color when influenced by a different faction — **faction does not change on shift**. The villager keeps its `faction_id`. Exception: colorless villagers (`faction_id = -1`) that shift join the faction of their dominant influencer.

Implementation: `InfluenceManager` tracks `dominant_faction` per target during group processing. `_trigger_shift()` passes `faction_override` through `villager_shifted` signal. `main.gd._on_villager_shifted()` applies it only for colorless.

---

## Influence / Shift System

Managed by `InfluenceManager` autoload (`influence_manager.gd`).

### Balance (Phase 4)
- `BASE_SHIFT_SPEED = 9.0` (was 18.0 — halved across the board).
- Magic orb `influence_rate = 4.0` (doubled to compensate, net effect unchanged).
- L3 vs L3: `_level_multiplier()` returns `0.2` (L1/L2 cannot shift L3, returns 0.0).
- Yellow L3 exception: always returns `1.0` (can always be shifted).

### Mechanics
- `SHIFT_MAX = 100.0`. Meter fills based on `BASE_SHIFT_SPEED × influence_rate × proximity_factor × level_multiplier × delta`.
- 3-second grace period before decay starts (`DECAY_GRACE_PERIOD`).
- Connected rooms (open doors) share influence groups.

---

## Level 3 Lifecycle (Phase 6)

All L3 units have a **2-day base lifespan** (`L3_BASE_LIFESPAN_DAYS = 2`).

### Timer
- `_l3_lifespan_timer` starts when `set_level(3)` is called.
- Ticks down in `_process()` on the host only (not puppets).
- Reaches 0 → `_die_from_lifespan()` → death animation + EventFeed message.
- Timer clears if villager is shifted back below L3.

### Sustain Conditions
- **Red L3**: Each fish eaten via the hunger system calls `extend_l3_lifespan()`, resetting the timer.
- **Blue L3**: If sheltered in a church during the night and still inside at dawn, `extend_l3_lifespan()` is called in `_on_phase_changed()`.
- **Yellow L3**: No sustain — expires after exactly 2 days. (Yellow L3 can still be shifted by any source.)

### `extend_l3_lifespan()`
Resets `_l3_lifespan_timer = L3_BASE_LIFESPAN_DAYS × GameClock.DAY_DURATION`.

---

## Satiation (Hunger)

Managed in `main.gd._process_red_hunger()`. Only red villagers have hunger.

- `SATIATION_PER_LEVEL = [0.0, 600.0, 600.0, 600.0]` — 1 fish per game day (600s cycle) at all levels.
- When satiation runs out, checks `Economy.get_fish(faction_id)`. If available, consumes 1 fish and resets timer.
- If no fish: `is_fed = false`, takes `RED_STARVE_DPS` (50/1200 ≈ 0.042) damage per second. Dies at 0 HP after ~2 game days.
- L3 red: each fish also calls `extend_l3_lifespan()`.

---

## Combat System (Phase 7)

### PvE (Automatic)
- Red villagers auto-shoot enemies within `SHOOT_RANGE = 200px` when `brain_enemies` is populated.
- Enemies auto-attack non-red villagers on contact.
- Kill tracking on `villager.kill_count` drives red leveling.

### PvP (Player-Commanded)
Commands: `command_attack(target)` and `command_stun(target)` on villager.gd.

- Sets `command_mode = "combat"`, `combat_target`, `combat_mode`.
- `_check_combat_command()` runs in brain (priority: after command, before danger).
- **Attack** (red only): moves to SHOOT_RANGE, fires. Deals `10 × level` damage per shot. Target keeps faction. Persists until target dies or command cleared.
- **Stun** (blue only): moves to melee range, calls `combat_target.apply_stun(2.0)`. Stun freezes target brain for 2s. One-shot: command clears after successful stun. Respects shoot cooldown.
- Stunned villagers show spinning gold stars and skip all brain evaluation.

### Player Flow
1. Select red/blue villagers.
2. Press **A** (attack) or **S** (stun), or click the button in the command panel.
3. Click an enemy-faction villager — command issued.
4. In multiplayer: sent as `"attack"`/`"stun"` RPC with `target_net_id`.

### `_process_red_shooting()`
Handles both PvE and PvP targets. Checks `target.get("faction_id")` to distinguish:
- PvP: applies damage directly to `target.health`, calls `_set_war_state()`.
- PvE: calls `target.take_red_hit()`.

### War State
`_war_state: Dictionary` in main.gd. `_set_war_state(a, b, true)` marks factions as at war symmetrically. First declaration fires an EventFeed message. Accessed via `_are_at_war(a, b)`.

---

## Network Commands

All commands flow through `NetworkManager.send_command()` → host `_apply_net_command()`.

| type | data | effect |
|------|------|--------|
| move_to | net_ids, tx, ty | villagers move |
| hold | net_ids | toggle hold |
| release | net_ids | clear commands |
| enter_exit_house | net_ids | shelter/release |
| break_door | net_ids, tx, ty | red breaks door |
| build_place | item_id, px, py | place building |
| drag_start/move/end | net_id, px, py | drag villager |
| attack | net_ids, target_net_id | red PvP attack |
| stun | net_ids, target_net_id | blue PvP stun |

---

## State Snapshots

Host broadcasts at `SYNC_RATE = 10Hz`. Clients interpolate. Snapshot keys:
- `v`: villager array `[net_id, x*10, y*10, hp, max_hp, color_idx, level, carry, visible, cmd, faction_id, shift_meter, is_fed]`
- `e`: enemy array, `ne`: night enemy array
- `cc`/`fc`: collected resource indices
- `eco`: per-faction `[stone, fish]`
- `clk`: `[elapsed, day_count, is_paused]`
- `own`: room ownership dict
- `ws`: wall open/closed states

---

## Tutorial System (Phase 8)

Autoload: `TutorialManager` (`autoload/tutorial_manager.gd`).

### Phases
| Phase | Objective |
|-------|-----------|
| 1 — Awakening | Drag villager to orb → shift occurs |
| 2 — Growth | Yellow duplicate produced (spawn_count > 1) |
| 3 — Control | Blue merge occurs |
| 4 — Economy | Stone deposited at bank |
| 5 — Food Chain | Fish delivered to fishing hut |
| 6 — Survival | Red survives fed through a full day |
| 7 — Expansion | Red breaks a door |
| 8 — Building | House placed via shop |
| 9 — Housing | Villager sheltered then released |
| 10 — Full Loop | 10+ villagers across all colors |

### Hooks in main.gd
- `on_shift()` — after `_on_villager_shifted`
- `on_blue_merge()` — after blue merge in `_process_blue_merging`
- `on_deposit("stone")` / `on_fish_delivered()` — in `_process_deposits`
- `on_red_day_survived()` — in `_on_phase_changed` at dawn
- `on_door_broken()` — in `_process_red_door_breaking`
- `on_building_placed()` — in `_place_building` (house only)
- `on_shelter()` / `on_release()` — in `_apply_house_command`
- `on_population_update(total)` — in `_update_hud`

### HUD Overlay
`hud.gd._draw_tutorial_overlay()`: renders a centered box below the day/night bar showing the current instruction and phase number. Press Escape to skip.

---

## Economy

`Economy` autoload. Per-faction stone and fish counts.

- `get_stone(fid)` / `set_stone(fid, v)` / `add_stone(v, fid)`
- `get_fish(fid)` / `set_fish(fid, v)`
- `purchase(item_id)` — deducts cost, returns false if insufficient.
- `get_sell_value(item_id)` — half of build cost.

---

## Room Ownership

`RoomOwnership` autoload. Tracks which faction controls each room based on villager presence. Fires `room_captured(room_id, new_owner, old_owner)` signal. Core room capture triggers faction elimination.

---

## Day/Night Cycle

`GameClock` autoload. `DAY_DURATION` and `CYCLE_DURATION` constants. `phase_changed(is_daytime)` signal. `is_daytime`, `day_count`, `elapsed` properties.

- Dawn: releases sheltered villagers, despawns night enemies, checks blue L3 church sustain, checks red survival for tutorial.
- Dusk: auto-shelters villagers (except red L3), spawns night wave if event active.

---

## Town Hall (New)

`TownHall` extends `HousingBuilding`. Placed in each faction's core room at map generation. The magic orb starts at the Town Hall's position.

- **Capacity**: 8 villagers
- **Intake radius**: 90
- **Placed by faction**: Uses faction's actual ID (not `-2` preplaced for player-owned town halls generated per-faction)
- **Preplaced acceptance**: `can_house_villager()` allows any faction when `placed_by_faction == -2`
- **Integrated into**: auto-shelter, dawn release, building influence, night proximity shelter, elimination transfer, HUD building info, house commands, building click selection
- **Scene**: `scenes/town_hall.tscn` — larger visual footprint with spire, windows, foundation, and "TOWN HALL" label

---

## Room Templates (New)

`RoomTemplate` (`@tool`) base class in `scenes/room_templates/room_template.gd`. Defines room shapes as `@export var cells: Array[Vector2i]` — editable in the Godot editor.

### 8 Template Scenes
- `single_square.tscn` — 1×1
- `big_square.tscn` — 2×2
- `horizontal_bar.tscn` — 3×1
- `vertical_bar.tscn` — 1×3
- `l_shape.tscn` — 3 tall + 1 right (4 cells)
- `reverse_l_shape.tscn` — mirrored L (4 cells)
- `t_shape.tscn` — 3 across + 2 down from center (5 cells)
- `plus_shape.tscn` — cross/plus (5 cells)

### Map Generator Integration
- `_load_room_templates()`: Loads all template scenes, extracts cell patterns, sorts by size descending
- `_place_footprints_from_templates()`: Places rooms using arbitrary cell patterns (non-rectangular supported)
- Falls back to `_place_footprints_rectangular()` (original FOOTPRINTS) if templates fail to load
- Helper functions: `_can_place_cells()`, `_mark_grid_cells()`, `_cells_bounding_box()`

---

## Performance Architecture

### Spatial Room Grid
`main.gd` maintains `_room_grid: Dictionary` mapping pixel-space grid cells (64px) to room IDs. Built once via `_build_room_grid()` after map generation. `_room_id_at()` is O(1) dictionary lookup with fallback linear scan.

### Room-Scoped Processing
- **Pickups**: `_process_stone_pickups()` / `_process_fish_pickups()` only check villagers in the same room as each resource
- **Deposits**: `_process_deposits()` only checks villagers in the same room as each bank/hut
- **Brain context**: Pre-built per-room caches for resources (`room_stones`, `room_fish`), deposit buildings (`room_banks`, `room_huts`), buildings (`room_building_cache`), and adjacent room centers (`room_adj_centers`)

### Staggered Brain Ticks
Villagers have `_brain_frame_offset` (randomized at creation) and `BRAIN_SKIP_FRAMES = 3`. Idle+arrived villagers only evaluate brain every 3 frames, staggered across the population. Active states (danger, job, command, combat) always think every frame.

### Conditional Redraws
- **Buildings**: `BuildingBase._check_selection_redraw()` — only redraws on selection change or while selected. Subclasses call this instead of unconditional `queue_redraw()`.
- **Rooms**: `room.gd` only redraws when ownership or capture progress changes
- **Enemies**: Only redraw when stunned, L3 (health bar), or L1 with active dupe meter
- **Fish spots**: Skip bobbing animation when not visible

---

## Villager AI Architecture

### Brain Priority (unchanged)
1. **COMMAND** — player move/hold/break_door/combat commands
2. **DANGER** — enemy nearby, color-specific reaction
3. **JOB** — resource collection/deposit loop
4. **INFLUENCE** — (currently passthrough, meter fills elsewhere)
5. **IDLE** — wander, visit buildings, socialize, explore rooms

### Shared Worker Pattern
`_check_worker_job()` — unified gather→deposit→return loop used by both yellows and blues:
1. If carrying → find deposit in room (O(1) cache) → cross-room deposit → carry_wander
2. If has waypoint → go to waypoint
3. If has resource in room → collect nearest
4. If has assigned room → return to work room

Blue pre-check: seek church when damaged (before shared loop).

### Idle Behavior System
When no higher-priority state applies, villagers pick from weighted idle behaviors:
- **Stand/jiggle** (60%) — stay put or tiny local step
- **Building visit** (35%) — walk to a building in the room
- **Social visit** (35%) — walk near another villager in the room
- **Room travel** (30%) — walk to an adjacent room's center through an open door
- **Local step** — random walk within room bounds

`brain_buildings` and `brain_room_centers` are populated per-frame from room-level caches built in `_update_brain_context()`.

---

## Preplaced Building Faction Rules

Buildings with `placed_by_faction = -2` (preplaced/map-generated) accept **any faction** for deposits, housing, and other interactions. Buildings with `placed_by_faction = -1` (neutral/unassigned) reject all interactions. Buildings with `placed_by_faction >= 0` (player-placed) only accept matching faction.

This applies uniformly to: `ResourceBuilding.accepts_villager()`, `Bank.accepts_villager()`, `HousingBuilding.can_house_villager()`, and `TownHall.can_house_villager()`.

---

## Faction Naming

Players name their faction before starting a game via a text field in the solo lobby config. The name is passed to `FactionManager.register_faction()`. If left empty, falls back to the faction symbol. Max 20 characters, alphanumeric plus spaces/hyphens/underscores.

---

## Hunger / Satiation

Red villagers require fish to survive. Managed by `_process_red_hunger()` in `main.gd`.

- **Consumption**: 1 fish per game day (600s cycle) at all levels. `SATIATION_PER_LEVEL = [0, 600, 600, 600]`.
- **Starvation**: When unfed, health drains at `RED_STARVE_DPS = 50/1200` (~0.042 HP/s). At 50 HP (L1/L2 base), death takes 2 full game days (1200s). L3 with 100 HP takes 4 days.
- **Fish source**: Blues collect fish from rivers/fish spots and deposit at fishing huts. Economy stores faction fish count.
- **Visual**: Unfed reds show "HUNGRY" label and darkened pulsing body color.

---

## PvP Combat

### Red Attack (Player-Commanded)
Reds can be commanded to attack other-faction villagers or map enemies. Damage = `10.0 × level` per shot. Triggers war state between factions.

### Blue Stun (Player-Commanded)
Blues can be commanded to stun other-faction villagers. Stun freezes the target for 2.0 seconds. One-shot action: after a successful stun, the blue clears its combat command and returns to normal behavior. Stun respects `_shoot_cooldown` to prevent spam.

### Stun Visual
Stunned villagers display three spinning gold stars orbiting their body. Stars pulse in opacity and rotate continuously. Stunned villagers skip all brain evaluation until the timer expires.

### Command Speed
Villagers following player commands (`command_move`, `break_door`, `combat`) move 50% faster than their base speed (`COMMAND_SPEED_MULT = 1.5`).
