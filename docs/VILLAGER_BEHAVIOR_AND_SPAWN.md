# Villager Behavior & Starting Position — Code Reference

> Describes what the code currently does, not design intent.

---

## Villager Idle Wandering (`villager.gd`)

### Brain Priority Order
Every frame `_evaluate_brain` runs these checks in order; first match wins:
1. `_check_command` — active player command (move_to, hold, break_door)
2. `_check_combat_command` — active attack/stun target
3. `_check_danger` — enemy within `AWARENESS_RANGE` (300px)
4. `_check_job` — color-specific resource/deposit work
5. `_check_influence` — **always returns false** (influence only affects shift_meter, not movement)
6. `_do_idle_brain` — wander

### Idle Timer
When the villager arrives at a destination (or has no destination), `_idle_timer` counts down from a random value in `[WANDER_PAUSE_MIN, WANDER_PAUSE_MAX]` = **[2.0, 5.5]** seconds. Nothing happens until it reaches 0.

### Idle Behavior Roll (`_pick_idle_behavior`)
When the timer expires, one roll determines behavior using a cascading probability chain:

| Roll range | Behavior | Probability |
|---|---|---|
| < 0.60 | Stand/jiggle (`_pick_idle_stand_or_jiggle`) | 60% |
| next 35% of remainder | Visit a building (`_pick_idle_building_visit`) | ~14% |
| next 35% of remainder | Visit a nearby villager (`_pick_idle_social_visit`) | ~9% |
| next 30% of remainder | Travel to another room center (`_pick_idle_room_visit`) | ~6% |
| remaining | Local random step (`_pick_local_idle_step`) | ~11% |

**Stand/jiggle**: 50% chance to take a tiny jiggle step within `IDLE_JIGGLE_RADIUS` (18px); otherwise stand still.

**Building visit**: picks a random building from `brain_buildings` that belongs to the villager's faction (or has no faction). Target is the building position + a random offset (±20px x, +18–36px y).

**Social visit**: picks a random living villager in the same room, targets a position `1.5–2.5 × radius` away from them.

**Room travel**: picks a random entry from `brain_room_centers` that is >48px away. These are room centers, fed by `main.gd`.

**Local step**: random direction, distance `[IDLE_LOCAL_STEP_MIN, IDLE_LOCAL_STEP_MAX]` = **[14, 34]** px, clamped inside room bounds. 10 attempts; falls through to stand still on failure.

### Per-Color Job Behavior (`_check_job`)
Only runs if no command/combat/danger is active.

- **Yellow**: seeks nearest stone collectable in same room → deposits at bank (same room first, cross-room fallback) → if no resource/bank, does idle wander.
- **Blue**: seeks church if damaged and no resource → collects fish → deposits at fishing hut → idle wander.
- **Red**: no job logic; goes straight to danger/idle.
- **Colorless**: no job logic; pure idle wander only.

### Danger Response (`_check_danger`, range = 300px)
- **Yellow/Colorless**: flee toward nearest blue, or flee directly away from enemy.
- **Blue**: advance to `FRONTLINE_DIST` (80px) from enemy, then hold.
- **Red**: position `RED_BEHIND_BLUE_DIST` (60px) behind nearest blue; shoot if enemy within `SHOOT_RANGE` (200px) and cooldown clear.

### Movement Internals
- Movement is blocked by walls. Open doors are passable; closed doors block.
- Doorway routing: if target requires crossing a wall, finds nearest open door as waypoint.
- `SEPARATION_DIST` (8px) + `SEPARATION_FORCE` (0.4): villagers push each other apart each frame.
- Speed: base from `ColorRegistry` × `SPEED_SCALE` (8.0). Level 2 gets `L2_SPEED_MULT` (1.4×).

---

## Starting Positions (`map_generator.gd` — `_generate_faction_starts`)

### Standard Mode (3 villagers + magic orb)
Starting positions are computed relative to the door between the core room and the stone room.

**Door edge approximation** (used for distance sorting):
| Cluster direction | Door edge position |
|---|---|
| RIGHT | Right edge, mid-height of core room |
| LEFT | Left edge, mid-height |
| DOWN | Bottom edge, mid-width |
| UP | Top edge, mid-width |

Four corner candidates are computed at `margin` = 150px from each corner of the core room. They are sorted by distance to the door edge:

| Sorted rank | Assigned to |
|---|---|
| corners[0] (closest to door) | Red villager |
| corners[1] | Yellow villager |
| corners[2] | Blue villager |
| corners[3] (furthest from door) | Magic Orb |

All positions get an additional random jitter of ±30px applied at spawn.

Red is pre-fed (`_satiation_timer = SATIATION_PER_LEVEL[1]`); yellow and blue are not.

### Survival Mode (5 villagers, no orb)
Positions are **fixed** (not door-aware):
- Red ×2: top-left corner area `(margin, margin)` and `(margin+60, margin+40)`
- Yellow ×2: top-right area `(hsize.x-margin, margin)` and `(hsize.x-margin-60, margin+40)`
- Blue ×1: bottom-left `(margin, hsize.y-margin)`

Both reds are pre-fed; yellows and blue are not.

### Tutorial Mode (`generate_tutorial`)
Positions are hardcoded (not door-aware):
- 3 reds: `(a_pos.x + 150 + i*80, a_pos.y + 180)` for i in 0..2
- 1 yellow: `(a_pos.x + a_size.x - 200, a_pos.y + 200)`
- 1 blue: `(a_pos.x + 200, a_pos.y + a_size.y - 250)`
- Magic Orb: room center `a_center`
