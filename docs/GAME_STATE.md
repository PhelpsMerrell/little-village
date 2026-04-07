# Little Village — Game State

## Architecture

- **Engine:** Godot 4.6, GDScript
- **Scenes:** `scenes/` — villager, main, hud, home, camera, map_generator, player_controller, lobby, title_screen, wall_segment, room, options_menu, enemy, demon, zombie, bank, fishing_hut, church, collectable, fish_spot, fog_overlay
- **Obstacles:** `scenes/obstacles/` — breakable_wall_obstacle, river_obstacle, water_obstacle
- **Autoloads (load order):** ColorRegistry → GameRNG → InputConfig → InfluenceManager → GameClock → Economy → NightEvents → EventFeed → SaveManager → FogOfWar → FactionManager → RoomOwnership → NetworkManager
- **Docs:** `docs/` — GAME_STATE.md, ASSET_REPLACEMENT_GUIDE.md, MAP_GENERATION_GUIDELINES.md

## Multiplayer (Host-Authoritative)

- **Model:** Host-authoritative via ENet. Host runs full simulation, clients send commands only.
- **Snapshots:** Host broadcasts state at 10Hz. Clients interpolate between snapshots.
- **Commands:** Clients send commands (move, hold, build, break_door, etc.) via RPC to host.
- **Determinism:** `GameRNG` autoload wraps `RandomNumberGenerator` with shared seed. ALL gameplay-affecting randomness uses `GameRNG.*`.
- **Solo:** `NetworkManager.is_online()` = false → commands apply directly → zero overhead.

## Lobby (`scenes/lobby.gd`)

Three modes with separate UX flows:

- **Solo:** Max pop (default 300), map seed, faction picker, Start button → straight to game.
- **Host:** Player count, max pop, map seed → Start → waiting room. Players pick factions and ready up. Host can override factions. Launch when all ready.
- **Join:** Address field + Submit → waiting room. Pick faction, ready up, wait for host launch.

Scene transition uses `call_deferred("_deferred_change_to_main")` with `is_inside_tree()` guard.

## Faction System (`autoload/faction_manager.gd`)

- `faction_id` on every villager. Solo = faction 0. Multi = 0..N-1. Unowned colorless = -1.
- Selection, fog visibility, dragging all gated to `FactionManager.is_local_faction(v.faction_id)`.
- Shifted villagers inherit faction from nearest same-color villager.
- `max_population` set from lobby (default 300 solo, configurable in host).

## Starting Layout (Multi-faction)

- Each faction gets a 2x2 home room (4 corners of map).
- 3 starting villagers (red, yellow, blue) placed in separate corners of room, >540px apart.
- Magic orb in room center. Player must drag villagers together to begin shifting.
- Same faction on multiple players = single starting setup.

## PlayerController (`scenes/player_controller.gd`)

- Owns selection state, command input. Faction-aware.
- Solo: commands apply directly. Multiplayer: sent via NetworkManager RPC.
- Commands: move_to, hold, release, enter_exit_house, break_door.

## Selection System

### Standard Mode (no modifier)
- Left-click: select single villager. Shift+click: add/remove from selection.
- Right-click: move command for selected villagers.
- Left-click empty ground: deselect all.
- Drag-and-drop: click and drag individual villagers.

### Shift-Hover Selection Mode
- **Hold Shift** to enter selection mode (cyan ring cursor indicator).
- While holding Shift, hovering over any owned villager auto-selects it (additive).
- Drag-and-drop is suppressed while Shift is held.
- Selection persists when Shift is released.
- Designed for rapidly selecting large groups (10-20+ units) via sweeping.

## Command Menu (HUD)

- Bottom-right panel shown when villagers are selected.
- **Only shared commands shown:** Commands are filtered based on selected unit types. A command only appears if ALL selected units support it.
- Universal commands: Move, Hold, House, Release.
- Red-only commands: Break Door.
- **Move** sets pending mode, next click = target position.
- **Break Door** sets pending mode, next click near a closed door = red moves to break it.
- Keyboard shortcuts: G=Hold, H=House, X=Release, M=Move, R=Break Door.
- Signal `command_issued` → main.gd `_on_hud_command()`.

### Selection Info Panel
- Shows total selected count.
- Per-color/type breakdown with counts.
- Individual villager details (HP) when ≤4 selected.

## Doors & Walls

### Wall Segments (`scenes/wall_segment.gd`)
- Generated between all adjacent rooms.
- **Solid walls:** Cannot be broken. Block movement and influence.
- **Doors:** Start CLOSED. Must be broken by red villagers to open.
- Once opened, doors stay open permanently. Rubble visual replaces barricade.

### Door Breaking
- **Automatic:** Red villagers within `BREAK_RADIUS + radius` of a closed door auto-break it.
- **Manual command:** Select reds → Break Door → click a closed door → reds move to and break it.
- `break_door_target` on villager tracks commanded door position. Cleared after breaking.
- Works in both solo and multiplayer (break_door network command type).

### Wall Collision
- `brain_walls` array on villager, populated by main.gd each frame.
- `_wall_blocks(from, to)` checks movement crossing closed walls via segment intersection.
- Cross-room movement blocked at closed walls. Doorway pathfinding redirects through open doors.

## Room Ownership (`autoload/room_ownership.gd`)

- Faction gains ownership: 4+ units, uncontested, 90 seconds capture time.
- Contested: progress pauses. Abandoned: 3s grace → 2x decline.
- Enemy room capture takes 2x (neutralize first).
- Ownership enables building in owned rooms.

## Influence System (`autoload/influence_manager.gd`)

- Range-based: ~15× radius. Stronger when closer.
- Level-aware: influencer level must >= target level.
- 3-second grace period before shift meter decays.
- Colorless villagers shift to strongest influence color.
- Influence does NOT cross closed walls/doors.
- Same-faction villagers DO influence each other.

## Color Types (color_registry.gd)

| Color | Radius | Health | Speed | Shifts To | Abilities |
|-------|--------|--------|-------|-----------|-----------|
| Red | 35 | 50 | 6 | Yellow | damage, break_walls |
| Yellow | 27 | 15 | 10 | Blue | — |
| Blue | 45 | 200 | 3 | Red | swim, move_boulders |
| Colorless | 25 | 25 | 7 | (dynamic) | fast_shifter |
| Magic Orb | 25 | 100 | 0 | — | catalyst |

## Input System (`autoload/input_config.gd`)

Registered InputMap actions, remappable via options menu:

| Action | Default | Description |
|--------|---------|-------------|
| cmd_hold | G | Hold Position |
| cmd_house | H | Enter/Exit House |
| cmd_release | X | Release Command |
| cmd_move | M | Move (then click) |
| cmd_break_door | R | Break Door (Red) |
| toggle_shop | B | Toggle Shop |
| quick_save | F5 | Quick Save |
| toggle_fog_dev | 0 | [DEV] Toggle Fog |
| deselect | Escape | Deselect / Menu |
| dev_next_phase | 9 | [DEV] Next Phase |

## HUD (`scenes/hud.gd`)

- Day/night bar (top), population panel (bottom-left, 420×220).
- Event feed (right, 340w, expandable).
- Selection panel (bottom-right) with filtered commands + group info.
- Building menu (bottom-right) for selected buildings.
- Score overlay (Tab) showing per-faction stats.
- Shop overlay (B key).

## Economy (`autoload/economy.gd`)

- Per-faction resources: stone, fish.
- Shop items: House (5 stone), Church (50 stone).
- Building gated to owned rooms in multi-faction mode.

## Night System

- Day/night cycle via GameClock.
- Night events: demon_hunt, zombie_plague, quiet_night.
- Auto-sheltering at nightfall. Buildings release at dawn.
- Red L3 stays outside during night.

## Remaining Work

- **PvP Phase 5:** Cross-faction combat, contested resources, influence warfare, territory scoring, victory conditions.
- **Save/load:** Needs faction_id, net_id, ownership state, wall/door states.
- **Camera improvements:** Minimap, faction home hotkey.
- **Port forwarding:** ENet uses port 7350. Users need to forward for internet play.
