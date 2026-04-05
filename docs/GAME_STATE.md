# Little Village -- Game State Document

## Project Structure
```
autoload/
  color_registry.gd        -- Color type definitions (red/yellow/blue/colorless/magic_orb)
  influence_manager.gd      -- Range + level-aware influence, 3s decay grace, fast_shifter
  game_clock.gd             -- Day/night cycle (20min/10min), 8-phase lunar cycle
  economy.gd                -- Stone + fish currency, shop
  night_events.gd           -- Moon-phase-aware night event system
  event_feed.gd             -- Global event log, time-of-day + moon messages
  save_manager.gd           -- Save/load to user://savegame.json
scenes/
  title_screen.gd + .tscn   -- New Game / Continue menu
  main.gd + main.tscn       -- 24-room orchestrator, all systems
  camera.gd                 -- Pan/zoom/fullscreen
  villager.gd + villager.tscn -- AI brain, levels, ranged combat, carrying, death anim
  enemy.gd + enemy.tscn     -- Standard enemy (L1-L3, dupe, merge, stun)
  demon.gd + demon.tscn     -- Night enemy: only L3 red can kill (will become werewolf)
  zombie.gd + zombie.tscn   -- Night enemy: converts villagers on touch
  room.gd, wall_segment.gd, collectable.gd, fish_spot.gd
  bank.gd, fishing_hut.gd, home.gd, church.gd, hud.gd
  obstacles/ -- water, breakable_wall, river
docs/
  GAME_STATE.md, MAP_GENERATION_GUIDELINES.md
```

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

Moon phase name shown in HUD time bar. Dusk warnings reference the upcoming moon.
Full moon: "A full moon rises tonight... beware."
New moon: "Darkness gathers under the new moon."

---

## Save System (save_manager.gd)
- **F5**: Quick save during gameplay
- **Escape**: Save and return to title screen
- Saves to `user://savegame.json`
- **Data saved**: clock state (elapsed, day_count), economy (stone, fish), wall open/closed states, all villagers (position, color, level, HP, shift meter, kill count, satiation, carrying), all enemies (position, level, HP, dupe meter), all collectables + fish spots (positions), all buildings (type + position)
- Title screen shows "Continue" only when a save exists
- "New Game" deletes existing save

---

## Influence System
- **Range**: radius x 15.0 (Red=420px, Yellow=330px, Blue=540px, Colorless=300px)
- **Falloff**: 1.0x at touch -> 0.15x at max range (linear)
- **Level-aware**: source level must be >= target level
- **Fast shifters**: colorless villagers receive influence at 3x speed
- **Inside buildings**: influence still runs on co-sheltered villagers

---

## Villager Stats
| Color     | HP  | Speed  | L2 Speed | Radius | Role                         |
|-----------|-----|--------|----------|--------|------------------------------|
| Yellow    | 15  | 80px/s | 112px/s  | 22     | Gatherer (stone -> bank)     |
| Red       | 50  | 48px/s | 67px/s   | 28     | Fighter (ranged, needs fish) |
| Blue      | 200 | 24px/s | 34px/s   | 36     | Tank + fisher (fish -> hut)  |
| Colorless | 25  | 56px/s | 78px/s   | 20     | Fast shifter (joins groups)  |

**Magic Orb** (color_type = "magic_orb"): Stationary catalyst. Influences all colors at 2x rate. Cannot move or shift. Drag-only.

---

## Colorless Villager
- Shifts into red at 3x normal speed. Then follows cycle: red -> yellow -> blue -> red.
- No job. Wanders and shifts. Flees enemies like yellows.
- Finding colorless = free recruits. Expose to any influence and they convert fast.
- Low HP (25), medium speed. If they shift red->yellow they duplicate.

---

## Level 2 Speed Boost
All L2 villagers move 40% faster. L3 returns to base speed but has 2x HP.

---

## Red Hunger (Per-Villager Satiation)
- Each red has an individual satiation timer.
- L1: 1 fish lasts 1 day (1200s). L2: 2 days. L3: 3 days.
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
- Moon-aware dusk warnings. Game events for deaths, shifts, levels, enemies, buildings.

---

## Economy
- **Stone**: Yellow -> bank. Buys: House (5), Church (50)
- **Fish**: Blue -> hut. Feeds reds (1 fish per 1/2/3 days by level)

---

## Leveling
| Color | Method | L2 | L3 |
|-------|--------|----|----|
| Red | Kills | 10 kills | 30 total |
| Blue | Merge | 3 same-level nearby | 3 L2s merge |
| Yellow | Pair | 2 same-level, 8s together | 2 L2s pair |

On shift: resets to L1. HP% preserved. L2 = +40% speed. L3 = 2x HP.

---

## Controls
WASD/Arrows: Pan | Q/E/Scroll: Zoom | F11: Fullscreen | B: Shop | F5: Save | Esc: Save + Menu
Click resource then click matching villager: Waypoint assignment
