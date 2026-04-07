# Little Village — Game State

## Architecture

- **Engine:** Godot 4.6, GDScript
- **Scenes:** `scenes/` — villager, main, hud, home, camera, map_generator, player_controller, lobby, title_screen, wall_segment, room, options_menu, enemy, demon, zombie, bank, fishing_hut, church, collectable, fish_spot, fog_overlay
- **Autoloads (load order):** ColorRegistry → GameRNG → InputConfig → InfluenceManager → GameClock → Economy → NightEvents → EventFeed → SaveManager → FogOfWar → FactionManager → RoomOwnership → NetworkManager

## Multiplayer (Lockstep Deterministic)

- **Model:** Peer-to-peer via ENet. All clients run full simulation. Only commands are exchanged.
- **Turns:** 100ms lockstep turns. Commands collected → broadcast → wait for all peers → apply simultaneously in sorted peer order.
- **Determinism:** `GameRNG` autoload wraps `RandomNumberGenerator` with shared seed. ALL gameplay-affecting randomness uses `GameRNG.*`.
- **Desync detection:** Every 50 turns, peers hash game state (positions, health, colors, counts) and compare.
- **Disconnect:** Dropped peers added to `_disconnected_peers`. Lockstep stops waiting. Their villagers continue with AI brain only.
- **Solo:** `NetworkManager.is_online()` = false → commands apply directly → zero overhead.

## Lobby (`scenes/lobby.gd`)

- Three states: `config` → `waiting_host` / `waiting_client`
- **Host:** Configure → Start → shows peer count → "Launch Game" button → broadcasts config + start → all peers transition to main.tscn
- **Client:** Configure → Join → waits → receives synced config (seed, factions, assignments) → transitions
- **Solo:** Configure → Start → straight to game
- Scene transition uses `call_deferred("_deferred_change_to_main")` with `is_inside_tree()` guard to avoid RPC timing crash.

## Faction System (`autoload/faction_manager.gd`)

- `faction_id` on every villager. Solo = faction 0. Multi = 0..N-1. Unowned colorless = -1.
- Selection, fog visibility, dragging all gated to `FactionManager.is_local_faction(v.faction_id)`.
- Shifted villagers inherit faction from nearest same-color villager.

## Starting Layout (Multi-faction)

- Each faction gets a 2x2 home room (4 corners of map).
- 3 starting villagers (red, yellow, blue) placed in **separate corners** of the room, >540px apart (beyond max influence range).
- Magic orb in room center. Player must drag villagers together to begin shifting/gameplay.
- Same faction on multiple players = single starting setup (not duplicated).

## PlayerController (`scenes/player_controller.gd`)

- Owns selection state, command input. Faction-aware.
- In solo: commands apply directly. In multiplayer: queued through `NetworkManager.queue_command()`.
- Commands: move_to, hold, release, enter_exit_house.

## Command Menu (HUD)

- Bottom-right panel shown when villager is selected.
- Buttons: **Move** (sets pending, next click = target), **Hold** (toggle), **House** (enter/exit nearest), **Release** (clear commands).
- Keyboard shortcuts also work via InputMap actions (remappable).
- Signal `command_issued` → main.gd `_on_hud_command()`.

## Input System (`autoload/input_config.gd`)

- Registers InputMap actions for all game commands.
- Saves/loads bindings to `user://input_config.cfg`.
- Defaults: G=Hold, H=House, X=Release, M=Move, B=Shop, F5=Save, 0=DevFog, Esc=Deselect/Options.
- Options menu (`scenes/options_menu.gd`) accessible via Escape when nothing selected. Click binding → press key to remap. Reset Defaults button.

## Wall Collision

- `brain_walls` array on villager, populated by main.gd each frame.
- `_wall_blocks(from, to)` checks if movement crosses any closed wall via `_segments_intersect()`.
- Cross-room movement (command_move, waypoint, etc.) blocked at closed walls.
- Room-clamping still works for non-cross-room states.
- Dragging ignores walls (sets position directly).
- Influence already blocked by closed walls (via `_find_connected_groups` in influence_manager).

## Room Ownership (`autoload/room_ownership.gd`)

- Faction gains ownership when **4+ units** in room with **no other faction/NPC/enemy**.
- Capture takes **3 minutes** of uncontested presence.
- **Contested:** progress pauses when another faction/NPC/enemy enters.
- **Abandoned:** 3-second grace, then declines at 2x speed. Re-entering pauses decline.
- Ownership enables building in owned rooms (not yet gated in shop).

## Influence System (`autoload/influence_manager.gd`)

- Range-based: within ~15× radius. Stronger when closer.
- Level-aware: influencer level must >= target level.
- 3-second grace period before shift meter decays.
- Colorless villagers shift to whichever color exerts strongest influence (`pending_shift_color`).
- Shift duplication is data-driven via `on_shift_spawn_count` in color_registry.
- Influence does NOT cross closed walls (connected groups algorithm).
- Same-faction villagers DO influence each other (core gameplay).

## Color Types (color_registry.gd)

| Color | Radius | Health | Speed | Shifts To | Influence Targets | Special |
|-------|--------|--------|-------|-----------|-------------------|---------|
| Red | 28 | 50 | 6 | Yellow | Blue, Colorless | Damage, break walls |
| Yellow | 22 | 15 | 10 | Blue | Red, Colorless | Single-target influence |
| Blue | 36 | 200 | 3 | Red | Yellow, Colorless | Swim, move boulders |
| Colorless | 20 | 25 | 7 | (dynamic) | — | Fast shifter (3x) |
| Magic Orb | 20 | 100 | 0 | — | All | Stationary catalyst |

## HUD (`scenes/hud.gd`)

- All text sizes doubled (22-24pt for body, 18-20pt for labels).
- Day/night bar (top), population panel (bottom-left, 420×220), event feed (right, 340w), command menu (bottom-right when selected), shop overlay.

## Remaining Work

- **Doors:** Procedural door generation between rooms for map traversability.
- **Building gating:** Only allow building (shop placement) in owned rooms.
- **Per-faction economy:** Currently shared Economy singleton.
- **Camera snap to faction home room** on game start.
- **PvP Phase 5:** Cross-faction combat, contested resources, influence warfare, territory scoring, victory conditions.
- **Save/load:** Needs faction_id, net_id, ownership state, input config.
- **Port forwarding:** ENet uses port 7350 by default. Users need to forward this port on their router for internet play.
