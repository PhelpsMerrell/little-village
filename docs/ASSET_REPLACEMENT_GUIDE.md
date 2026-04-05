# Asset Replacement Guide
# How to replace all procedural drawings with your own PNG art.

## Overview
Everything in Little Village is currently drawn with GDScript `_draw()` calls.
To replace with sprites, you add a Sprite2D child to each scene and disable
the procedural drawing. This guide lists every asset you need.

---

## Directory Structure
Put all PNGs in `assets/`. Suggested subfolder layout:
```
assets/
  villagers/
    red_l1.png          # Red circle (L1)
    red_l2.png          # Red square (L2)
    red_l3.png          # Red triangle (L3)
    yellow_l1.png
    yellow_l2.png
    yellow_l3.png
    blue_l1.png
    blue_l2.png
    blue_l3.png
    colorless.png       # Colorless doesn't level
  enemies/
    enemy_l1.png        # Black circle
    enemy_l2.png        # Black square
    enemy_l3.png        # Black triangle
    demon.png           # Purple pentagon with horns
    zombie.png          # Green shambler
  buildings/
    home.png            # House (80×80 ish)
    bank.png            # Stone deposit building (100×60)
    fishing_hut.png     # Blue-roofed hut (110×55)
  resources/
    stone.png           # Grey rock (24×24)
    fish.png            # Blue fish (28×28)
    stone_carry.png     # Small stone icon above head (14×14)
    fish_carry.png      # Small fish icon above head (14×14)
  obstacles/
    water_tile.png      # Water texture (tileable, 64×64)
    breakable_wall.png  # Cracked wall segment
    river_segment.png   # River water texture (tileable)
  ui/
    hud_bg.png          # Optional HUD panel background
    shop_bg.png         # Optional shop panel background
  rooms/
    room_bg_default.png # Default room background (1350×1350 or tileable)
    room_bg_stone.png   # Quarry room background
    room_bg_water.png   # Water room background
    room_bg_enemy.png   # Enemy den background
    room_bg_river.png   # River delta background
```

## Total PNGs Needed
| Category | Count | Notes |
|----------|-------|-------|
| Villagers | 10 | 3 levels × 3 colors + 1 colorless |
| Enemies | 5 | 3 standard levels + demon + zombie |
| Buildings | 3 | Home, bank, fishing hut |
| Resources | 4 | Stone, fish, + carry icons |
| Obstacles | 3 | Water, breakable wall, river |
| UI | 2 | Optional HUD/shop backgrounds |
| Rooms | 5 | Optional room backgrounds |
| **Total** | **~32** | Only first 22 are essential |

---

## How to Hook Up Each Asset

### Villagers (villager.tscn + villager.gd)

1. Open `villager.tscn` in Godot editor
2. Add a `Sprite2D` child node to the root, name it `Sprite`
3. Leave the texture empty — it gets set from code

4. In `villager.gd`, add at the top with other @onready vars:
```gdscript
@onready var _sprite: Sprite2D = $Sprite

# Preload all villager textures
var _textures: Dictionary = {
    "red_1": preload("res://assets/villagers/red_l1.png"),
    "red_2": preload("res://assets/villagers/red_l2.png"),
    "red_3": preload("res://assets/villagers/red_l3.png"),
    "yellow_1": preload("res://assets/villagers/yellow_l1.png"),
    "yellow_2": preload("res://assets/villagers/yellow_l2.png"),
    "yellow_3": preload("res://assets/villagers/yellow_l3.png"),
    "blue_1": preload("res://assets/villagers/blue_l1.png"),
    "blue_2": preload("res://assets/villagers/blue_l2.png"),
    "blue_3": preload("res://assets/villagers/blue_l3.png"),
    "colorless_1": preload("res://assets/villagers/colorless.png"),
}
```

5. In `_sync_definition()`, add after existing code:
```gdscript
if _sprite:
    var key: String = color_type + "_" + str(level)
    if _textures.has(key):
        _sprite.texture = _textures[key]
    _sprite.visible = true
```

6. In `_draw()`, wrap ALL the body drawing code in a check:
```gdscript
# Only draw procedurally if no sprite
if not _sprite or not _sprite.visible:
    match level:
        1: _draw_circle_body(draw_color)
        2: _draw_square_body(draw_color)
        3: _draw_triangle_body(draw_color)
```
Keep bars, labels, carrying icons, and shot flash — those overlay the sprite.

7. For the shift color blend effect, use `_sprite.modulate`:
```gdscript
if _sprite and _sprite.visible:
    _sprite.modulate = draw_color
```

### Enemies (enemy.tscn + enemy.gd)
Same pattern as villagers:
1. Add `Sprite2D` child named `Sprite`
2. Preload `enemy_l1.png`, `enemy_l2.png`, `enemy_l3.png`
3. Set texture in `_sync_level()`
4. Wrap `_draw()` body code in sprite check
5. Keep health bars, stun stars, dupe meter drawn on top

### Demons (demon.tscn + demon.gd)
1. Add `Sprite2D` child named `Sprite`
2. Set texture to `demon.png` in `_ready()`
3. Use `modulate` for the glowing effect instead of draw calls
4. Keep health bar and label drawn on top

### Zombies (zombie.tscn + zombie.gd)
Same as demon but with `zombie.png`.

### Buildings (home, bank, fishing_hut)
1. Add `Sprite2D` child to each .tscn
2. Set texture in `_ready()`:
```gdscript
$Sprite.texture = preload("res://assets/buildings/home.png")
```
3. Remove the `_draw()` body/roof code, keep capacity labels and radius hints

### Collectables (collectable.gd, fish_spot.gd)
1. Add `Sprite2D` child to each .tscn
2. Set texture in `_ready()`
3. Remove `_draw()` circle code
4. For fish_spot bob animation, animate the Sprite2D position instead:
```gdscript
if _sprite:
    _sprite.position.y = sin(_bob_time) * 3.0
```

### Room Backgrounds
Rooms currently use a flat `ColorRect`. To add backgrounds:
1. In `room.tscn`, add a `Sprite2D` or `TextureRect` child
2. Set the texture per room type
3. Or in `room.gd`, add an `@export var room_texture: Texture2D`
   and set it per room instance in the scene

### Water / River / Breakable Wall Obstacles
Each draws itself procedurally. Same pattern:
1. Add `Sprite2D` child
2. Set texture in `_ready()`
3. Remove procedural `_draw()` lines

---

## Art Specifications

### Recommended Sizes (in pixels)
| Asset | Size | Notes |
|-------|------|-------|
| Villager L1 (circle) | 56×56 | Diameter = radius × 2 |
| Villager L2 (square) | 48×48 | Slightly smaller than circle |
| Villager L3 (triangle) | 56×56 | Same canvas as L1 |
| Blue villager L1 | 72×72 | Blue is bigger (radius 36) |
| Enemy L1 | 56×56 | Same as red villager |
| Enemy L3 | 90×90 | 45px radius × 2 |
| Demon | 64×64 | 32px radius × 2 |
| Zombie | 52×52 | 26px radius × 2 |
| Home | 80×80 | Match HOME_SIZE constant |
| Bank | 100×60 | Wide platform shape |
| Fishing Hut | 110×60 | Wide with roof |
| Stone | 24×24 | Small ground item |
| Fish | 28×28 | Small ground item |
| Carry icons | 14×14 | Tiny, shown above head |

### Style Notes
- Top-down perspective (camera looks straight down)
- Transparent backgrounds (PNG with alpha)
- Art should be centered in the canvas
- Villager art should NOT include health bars or labels — those are drawn on top
- Consider making a sprite sheet instead of individual PNGs for animation later

---

## Quick Checklist
- [ ] Create `assets/` subfolder structure
- [ ] Export 10 villager PNGs (3 colors × 3 levels + colorless)
- [ ] Export 5 enemy PNGs (3 standard + demon + zombie)
- [ ] Export 3 building PNGs (home, bank, hut)
- [ ] Export 4 resource PNGs (stone, fish, carry icons)
- [ ] Add Sprite2D nodes to each .tscn
- [ ] Update each .gd to load textures and toggle procedural drawing
- [ ] Test each scene — bars/labels should still overlay correctly
