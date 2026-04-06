# Little Village — Game State Document

## Project Structure
```
autoload/
  color_registry.gd        -- Color type definitions (red/yellow/blue/colorless/magic_orb)
  influence_manager.gd      -- Range + level-aware influence, 3s decay grace, fast_shifter
  game_clock.gd             -- Day/night cycle (20min/10min), 8-phase lunar cycle
  economy.gd                -- Stone + fish currency, shop
  night_events.gd           -- Moon-phase-aware night event system
  event_feed.gd             -- Global event log, time-of-day + moon messages
  save_manager.gd           -- Save/load to user://savegame.json (includes fog state)
  fog_of_war.gd             -- Tracks explored/active rooms per villager presence
scenes/
  title_screen.gd + .tscn   -- New Game / Continue menu
  main.gd + main.tscn       -- Procedural map gen (26 rooms, 9 sizes), all systems
  camera.gd                 -- Pan/zoom/fullscreen, clamped to map & explored bounds
  fog_overlay.gd            -- Draws fog: unexplored=black, explored-inactive=dim, active=clear
  villager.gd + villager.tscn -- AI brain, levels, ranged combat, carrying, death anim
  enemy.gd + enemy.tscn     -- Standard enemy (L1-L3, dupe, merge, stun)
  demon.gd + demon.tscn     -- Night enemy: only L3 red can kill (will become werewolf)
  zombie.gd + zombie.tscn   -- Night enemy: converts villagers on touch
  room.gd + room.tscn       -- Room template (variable size via room_size export)
  wall_segment.gd + .tscn   -- Toggleable wall between rooms
  collectable.gd, fish_spot.gd
  bank.gd, fishing_hut.gd, home.gd, church.gd, hud.gd
  obstacles/ -- water, breakable_wall, river
docs/
  GAME_STATE.md, MAP_GENERATION_GUIDELINES.md
```

---

## Starting Conditions (New Game)
- **Economy**: 5 stone, 3 fish (enough for a house + feed red for first days)
- **R0 "Red Start"** (2×2): 1 red villager (fed, satiation=1200s), 1 magic orb
- **R1 "Yellow Plains"** (3×2): 1 yellow villager, 1 bank
- **R6 "Blue Start"** (1×3): 1 blue villager, 1 fishing hut, river obstacle, 2 starting fish
- **R9 "Wanderer Camp"** (2×2): 4 colorless villagers (uncontrolled tribe, not visible on map)
- Starting rooms (R0, R1, R6) are immediately explored; Wanderer Camp is NOT (colorless don't reveal rooms)
- Player must explore to R9 and bring controlled villagers within 350px to attract the colorless tribe

---

## Procedural Map Generation
Map defined as data in `main.gd` (ROOM_DEFS const). Rooms, walls, and entities generated at runtime.

### Grid System
- Base cell: 675×675 px, gap: 8 px between rooms
- Grid: 12 columns × 8 rows
- Rooms span 1–4 cells in each axis, creating Tetris-like variety

### Room Size Varieties (9 distinct sizes)
| Size (cells) | Pixels | Count | Examples |
|---|---|---|---|
| 1×1 | 675×675 | 1 | Shallows |
| 1×2 | 675×1350 | 2 | Narrow Pass, Corridor |
| 1×3 | 675×2041 | 2 | Blue Start, Tall Pass |
| 2×1 | 1350×675 | 5 | Short Corridor, Wide Corridor |
| 2×2 | 1350×1350 | 10 | Red Start, Enemy Dens |
| 2×3 | 1350×2041 | 2 | Stone Field, Flooded Quarry |
| 3×1 | 2041×675 | 1 | Stone Mine |
| 3×2 | 2041×1350 | 2 | Yellow Plains, River Delta |
| 4×2 | 2724×1350 | 1 | Fortification |

### 26 Rooms
R0 Red Start, R1 Yellow Plains, R2 Narrow Pass, R3 Enemy Den, R4 Stone Field,
R5 Lookout, R6 Blue Start, R7 Gathering Hall, R8 Short Corridor, R9 Wanderer Camp,
R10 Tall Pass, R11 Passage, R12 Enemy Den, R13 Flooded Quarry, R14 Shallows,
R15 Stone Quarry, R16 Walled Quarry, R17 River Delta, R18 Short Pass,
R19 Fortification, R20 Enemy Den, R21 Corridor, R22 Wide Pass, R23 Stone Mine,
R24 Wide Corridor, R25 Overlook

### Entity Spawning (SPAWN_RULES)
- Villagers: R0=red(fed)+magic_orb, R1=yellow+bank, R6=blue+fishing_hut+river+2fish, R9=4×colorless
- Enemies: R3(2), R12(2), R20(2)
- Stone: R4(15), R5(5), R13(10), R15(15), R19(8), R23(12)
- Fish: R6(2 starting), R17(15)
- Buildings: R1=bank, R6=fishing_hut, R17=fishing_hut

### Wall Generation
Walls auto-generated from grid adjacency. Two rooms that share an edge get a toggleable wall along the shared span.

---

## River Fish Production
- River obstacle placed in R6 (Blue Start)
- Produces 1 fish every 1800s (one full day/night cycle)
- Max 4 fish in the river room at a time
- Fish spawn at random positions within the room
- Event feed announces new fish

---

## Colorless Villager Behavior
- Colorless villagers do NOT give map visibility (skipped in fog active marking)
- They are an uncontrolled "tribe" — the player must reach them
- **Attraction**: When a non-colorless (controlled) villager is within 350px, colorless villagers path toward them (cross-room capable)
- Once close enough to be influenced, they shift into red at 3× speed, then follow the normal cycle
- Finding colorless = free recruits if you can get your villagers close enough

---

## Fog of War System
Tracked by `fog_of_war.gd` autoload. Rendered by `fog_overlay.gd` (z_index=100).

### Room States
| State | Visibility | Condition |
|---|---|---|
| **Unexplored** | Near-black (97% opacity) | Never had a controlled villager |
| **Explored, Inactive** | Dimmed (55% opacity). Terrain visible, resources/actors hidden | Previously visited, no current controlled villager |
| **Active** | Fully visible | Controlled (non-colorless) villager currently present |

### Entity Visibility
- Resources (stone, fish) and enemies hidden in non-active rooms via `visible = false`
- Dim overlay covers terrain in explored-inactive rooms
- Colorless villagers do NOT activate rooms — they are uncontrolled until shifted

### Camera Fog Constraint
- Camera zoom-out limited by explored area bounds + padding
- Prevents player from seeing full map size before exploring
- Map edges covered by near-black fill rects (no brown background)

### Dev Toggle
- Press **0** to toggle fog off/on (shows "[DEV] FOG OFF/ON" in event feed)
- When off: all rooms visible, all entities visible, camera can zoom to full map

### Save/Load
Explored room IDs saved in `fog_explored` array in savegame.json.

---

## Camera System (camera.gd)
- **Pan**: WASD/Arrows, right-click drag, middle-mouse drag
- **Zoom**: Scroll wheel, Q/E keys (range: dynamic min to 2.0)
- **Map clamping**: Viewport edges never exceed map bounds (no off-map brown)
- **Zoom limit**: Max zoom-out computed from explored bounds + 1500px padding
- **Fullscreen**: F11 toggle
- Bounds updated every frame via `update_bounds(map_bounds, explored_bounds)`

---

## Moon Phase System
8-day lunar cycle tracked in game_clock.gd. Each game day advances one phase.

| Phase | Day | Night Event |
|-------|-----|-------------|
| New Moon | 1 | Zombie Plague (forced) |
| Waxing Crescent | 2 | Random |
| First Quarter | 3 | Random |
| Waxing Gibbous | 4 | Random |
| Full Moon | 5 | Demon Hunt (forced) |
| Waning Gibbous | 6 | Random |
| Last Quarter | 7 | Random |
| Waning Crescent | 8 | Random |

---

## Save System (save_manager.gd)
- **F5**: Quick save during gameplay
- **Escape**: Save and return to title screen
- Saves to `user://savegame.json`
- **Data saved**: clock state, economy, wall open/closed states, all villagers, all enemies, all collectables + fish spots, all buildings, fog explored rooms
- Title screen shows "Continue" only when a save exists
- "New Game" deletes existing save

---

## Influence System
- **Range**: radius × 15.0 (Red=420px, Yellow=330px, Blue=540px, Colorless=300px)
- **Falloff**: 1.0× at touch → 0.15× at max range (linear)
- **Level-aware**: source level must be >= target level
- **Fast shifters**: colorless villagers receive influence at 3× speed
- **Inside buildings**: influence still runs on co-sheltered villagers

---

## Villager Stats
| Color     | HP  | Speed  | L2 Speed | Radius | Role                         |
|-----------|-----|--------|----------|--------|------------------------------|
| Yellow    | 15  | 80px/s | 112px/s  | 22     | Gatherer (stone → bank)     |
| Red       | 50  | 48px/s | 67px/s   | 28     | Fighter (ranged, needs fish) |
| Blue      | 200 | 24px/s | 34px/s   | 36     | Tank + fisher (fish → hut)  |
| Colorless | 25  | 56px/s | 78px/s   | 20     | Fast shifter (joins groups)  |

**Magic Orb** (color_type = "magic_orb"): Stationary catalyst. Influences all colors at 2× rate. Cannot move or shift. Drag-only. Placed in R0 at game start.

---

## Colorless Villager
- Does NOT give map visibility (fog remains unexplored around colorless-only rooms)
- Attraction: paths toward nearest controlled villager within 350px (cross-room)
- Shifts into red at 3× normal speed. Then follows cycle: red → yellow → blue → red.
- No job. Wanders until attracted, then shifts. Flees enemies like yellows.
- Low HP (25), medium speed. If they shift red→yellow they duplicate.

---

## Level 2 Speed Boost
All L2 villagers move 40% faster. L3 returns to base speed but has 2× HP.

---

## Red Hunger (Per-Villager Satiation)
- Each red has an individual satiation timer.
- L1: 1 fish lasts 1 day (1200s). L2: 2 days. L3: 3 days.
- Starting red begins fully fed (timer=1200s).
- No fish: starves at 2 HP/s, dies at 0.

---

## Buildings
| Building | Cost | Capacity | Special |
|----------|------|----------|---------|
| Home | 5 stone | 4 night | Any color |
| Church | 50 stone | 8 night | Blues heal 10 HP/s during day |

---

## Night Event System
Moon-phase-aware. Full moon forces demon_hunt. New moon forces zombie_plague. Other phases roll randomly from weighted pool (demon_hunt=1.0, zombie_plague=1.0, quiet_night=0.5).

---

## Event Feed
- HUD right side, last 5 messages. Click to expand/scroll.
- Moon-aware dusk warnings. Game events for deaths, shifts, levels, enemies, buildings, river fish.

---

## Economy
- **Starting**: 5 stone, 3 fish
- **Stone**: Yellow → bank. Buys: House (5), Church (50)
- **Fish**: Blue → hut. Feeds reds (1 fish per 1/2/3 days by level)
- **River**: R6 produces 1 fish/day, max 4 in river at once

---

## Leveling
| Color | Method | L2 | L3 |
|-------|--------|----|----|
| Red | Kills | 10 kills | 30 total |
| Blue | Merge | 3 same-level nearby | 3 L2s merge |
| Yellow | Pair | 2 same-level, 8s together | 2 L2s pair |

On shift: resets to L1. HP% preserved. L2 = +40% speed. L3 = 2× HP.

---

## Controls
WASD/Arrows: Pan | Q/E/Scroll: Zoom | F11: Fullscreen | B: Shop | F5: Save | Esc: Save + Menu
Click resource then click matching villager: Waypoint assignment
**0**: Toggle fog of war (dev)
