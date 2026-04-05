# Little Village — Game State Document
# Living reference for all game systems, constants, and mechanics.
# Last updated: Session 1 — initial comprehensive build.

## Project Structure
```
autoload/
  color_registry.gd        — Color type definitions (red/yellow/blue/colorless)
  influence_manager.gd      — Range-based proximity influence with attractor system
  game_clock.gd             — Day/night cycle (20min day, 10min night)
  economy.gd                — Stone + fish currency, shop catalog
scenes/
  main.gd + main.tscn       — 24-room (6x4) map, all game system orchestration
  camera.gd                 — Pan (WASD/arrows/right-click), zoom (Q/E/scroll), F11 fullscreen
  villager.gd + villager.tscn — Villager with AI brain, levels, carrying, shooting
  enemy.gd + enemy.tscn     — Enemy with levels, stun, duplication, merging
  room.gd + room.tscn       — Drag-drop room (@export room_id, room_size, room_color)
  wall_segment.gd + .tscn   — Click-to-toggle walls between rooms
  collectable.gd + .tscn    — Stone pickup (yellow-only)
  fish_spot.gd + .tscn      — Fish pickup (blue-only, animated bobbing)
  bank.gd + .tscn           — Yellow deposits stone here
  fishing_hut.gd + .tscn    — Blue deposits fish here
  home.gd + .tscn           — Shelters 4 villagers at night
  obstacles/
    water_obstacle.gd + .tscn           — Blocks non-swimmers
    breakable_wall_obstacle.gd + .tscn  — Reds break on contact
    river_obstacle.gd + .tscn           — Multi-segment S-curve river
docs/
  GAME_STATE.md             — This file
  MAP_GENERATION_GUIDELINES.md — Procedural map gen rules
```

---

## Color Shift Cycle
Red → Yellow (spawns 2) → Blue → Red.
Colorless accelerates all others at 2x rate, never shifts itself.

### Influence System
- **Range-based**: max range = influencer_radius × 7.5
  - Red (r=28): 210px range
  - Yellow (r=22): 165px range
  - Blue (r=36): 270px range
  - Colorless (r=20): 150px range
- **Proximity falloff**: 1.0× at touch → 0.15× at max range edge (linear)
- **Level-aware**: influencer level must be >= target level to affect them
  - L1 influencer affects L1 targets only
  - L2 influencer affects L1 and L2 targets
  - L3 influencer affects all targets
  - Exception: Yellow L3 is always influenceable at 1.0×
- **Attraction**: influenced villagers orbit the influencer at 40-80% of range
- **Speed**: BASE_SHIFT_SPEED = 18.0, DECAY_MULTIPLIER = 1.3
- **Yellow delivery**: single_target at 0.6× rate, no stacking
- **Standard delivery**: stacks with +0.1× per extra influencer in range

### On Shift
- Villager becomes L1 of the new color (always resets to L1)
- Red → Yellow spawns 2 yellows (original + 1 new)
- All other shifts spawn 1

---

## Villager Stats
| Color     | HP  | Speed | Radius | Abilities               |
|-----------|-----|-------|--------|--------------------------|
| Yellow    | 15  | 10    | 22     | Collect stone            |
| Red       | 50  | 6     | 28     | Ranged attack, break walls |
| Blue      | 200 | 3     | 36     | Collect fish, swim       |
| Colorless | 100 | 0     | 20     | Accelerate influence 2×  |

Speed is multiplied by SPEED_SCALE (8.0) for actual px/s.

---

## Leveling System
| Level | Shape    | Influence Resistance           | Health   | On Shift      |
|-------|----------|--------------------------------|----------|---------------|
| L1    | Circle   | Affected by L1+ influencers    | Base     | → L1 new color |
| L2    | Square   | Affected by L2+ influencers only | Base   | → L1 new color |
| L3    | Triangle | Immune (except yellow L3)      | 2× base  | → L1 new color |

### Level-up Methods
- **Red**: Kill-based. 10 kills → L2, 30 total kills → L3
- **Blue**: Merge. 3 same-level blues within 120px → 1 next-level blue (consumes 2)
- **Yellow**: Pair bond. 2 same-level yellows within 100px for 8 seconds → both level up

---

## Combat System

### Red Ranged Attack
- Reds SHOOT enemies (not touch-kill)
- Shoot range: 200px
- Shoot cooldown: 1.0s
- Damage per level: L1=50, L2=75, L3=150
- Visual: red line from shooter to target, fades over 0.2s

### Enemy Attack
- Enemies touch villagers to attack (not ranged)
- vs Yellow: instant kill (15hp → 0)
- vs Blue: 40 damage + enemy is STUNNED for 2.5s
- vs Red: immune (reds damage enemies, not the other way)

### Enemy Health
- L1: 50hp (circle, r=28) — dies to any single red shot
- L2: 50hp (square, r=36) — dies to any single red shot
- L3: 150hp (triangle, r=45) — requires multiple red hits

---

## Enemy Behavior
- **Duplication** (L1 only): when 2+ L1s within radius×5 (140px), dupe meter fills. Diminishing returns via 0.9^log2(count/2)
- **Merging**: 4 same-level enemies within 100px → 1 next-level
- **Stun**: after hitting a blue, enemy is stunned 2.5s (X eyes, stars, can't move/attack)

---

## AI Brain — Priority System
Each villager evaluates priorities top-down each frame:

### Priority 1: DANGER (enemy within awareness range ~300px)
- **Yellow**: flee from nearest enemy, move toward nearest blue for protection
- **Blue**: move to front line — position between enemies and allies, face enemies
- **Red**: get behind nearest blue (opposite side from enemy), shoot enemies in range

### Priority 2: JOB (resource work)
- **Yellow**: find nearest uncollected stone → walk to it → pick up → walk to bank → deposit
- **Blue**: find nearest uncollected fish → walk to it → pick up → walk to fishing hut → deposit
- **Red**: patrol (wander with purpose, no specific job yet)

### Priority 3: INFLUENCE
- If being influenced, orbit the attractor (existing system)

### Priority 4: IDLE
- Random wander within room bounds

---

## Economy

### Resources
- **Stone**: Yellows pick up → carry to Bank → deposit. Used to buy buildings.
- **Fish**: Blues pick up → carry to Fishing Hut → deposit. Used to feed reds.

### Red Hunger
- Every 60 seconds, each red consumes 1 fish from Economy.fish
- If no fish available: red loses 2 HP/s (starvation), shows "HUNGRY" + pulse
- Starving reds die when health reaches 0

### Shop (B key)
- House: 5 stone — shelters 4 villagers at night

---

## Day/Night Cycle
- Day: 20 minutes, Night: 10 minutes (GameClock autoload)
- At night: villagers near homes (80px) auto-shelter (hidden, paused)
- At dawn: all sheltered villagers released

---

## Map Layout (6×4, 24 rooms)
```
Row 0: Red Start     | Yellow+Bank   | Water Crossing | Enemy Den  | Passage      | Stone Field(10)
Row 1: Blue Start    | Colorless     | Barricade      | Passage    | Enemy Den    | Flooded Quarry(8)
Row 2: Passage       | Stone Quarry(20)| Walled Quarry(10)| River Delta+Hut | Enemy Den | Stone Field(10)
Row 3: Shallows      | Enemy Den     | Stone Mine(10) | Fortification| Passage     | Enemy Den
```

68 stones, 15 fish, 5 solo enemies, 3 breakable walls, 3 water crossings, 1 bank, 1 fishing hut.

---

## Known GDScript Patterns
- **Type inference bug**: `var x := untyped_array_element.property` fails. Always use `var x: Type = ...`
- **GDScript uses `sin()` not `sinf()`** but `minf()`/`maxf()` DO exist
- **Control nodes eat mouse input**: Set `mouse_filter = 2` (IGNORE) on overlapping UI
- **Signal params**: Untyped in connections — don't use `:=` inference on signal callback params
