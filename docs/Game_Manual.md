# Little Village: A Simulation of Influence & Empire

## Welcome, Shepherd of Souls

You stand at the threshold of a humble frontier village. Here, simple folk toil and squabble. Factions rise. Colors shift. Empires are born from influence itself—not through conquest alone, but through the invisible pull of ideology, hunger, and fear.

This is *Little Village*: a multiplayer settlement simulation where 1–8 players lead villagers through a living world of shifting loyalties, primal hunger, temporal decay, and territorial warfare. What you build. What you feed. What you command. That is *empire*.

---

## The Five Colors: Villager Castes

Every villager begins as one of five types, each with purpose and limits.

### **Red: The Warriors**
*Symbol:* Circle | *Drive:* Hunger & Violence

Reds are your front line—aggressive, fragile, appetite-driven.

- **Combat**: Auto-shoot enemies in range. Player can command PvP attacks on enemy villagers (dealing `10 × level` damage).
- **Hunger**: Require fish to survive. Miss a delivery? They weaken and die.
  - L1: 1 fish per day
  - L2: 1 fish per day (but moves 40% faster)
  - L3: 2 fish per day to stay alive
- **Leveling**: Kill enemies → grow to L2, then L3. L3 reds need constant feeding or they expire after 2 days.
- **Special Ability**: Break doors to expand territory.

*Philosophy*: Reds represent martial prowess. They are your offensive edge—but their hunger makes them a constant economic burden.

---

### **Yellow: The Laborers**
*Symbol:* Square | *Drive:* Accumulation & Duplication

Yellows are your backbone—methodical gatherers and builders of wealth.

- **Job**: Collect stone from the world, deposit at your bank.
- **Leveling**: Two yellows touching for 8 seconds → third yellow spawns nearby (duplication, not merge). Creates exponential workforce.
- **Commerce**: Each deposited stone adds to your faction's wealth. Spend stone to buy buildings.
- **Influence Resistance**: Weak to influence (L1 shifts in 1× base time). L3 yellows *always* shift, making them temporary.

*Philosophy*: Yellows are workers in the classical sense—steady, duplicating, wealth-generating. They represent the economic engine of your empire.

---

### **Blue: The Caretakers**
*Symbol:* Triangle | *Drive:* Cooperation & Healing

Blues are your logistics—they gather resources, merge for strength, and heal in sacred spaces.

- **Job**: Collect fish, deposit at your fishing hut.
- **Leveling**: Two blues touching → they merge into one L2 blue. One L2 + one L1 → L3.
- **Healing**: Damaged blues visit churches to heal.
- **Shelter**: Blue villagers auto-shelter in houses at nightfall (protection from night enemies).
- **PvP**: Command stun attacks on enemies, disabling their brain for 2 seconds.
- **L3 Sustain**: Must sleep in a church during the night cycle to reset their 2-day lifespan timer.

*Philosophy*: Blues are cooperative, hierarchical, and resource-centric. They represent order and mutual aid.

---

### **Colorless: The Neutral Wanderers**
*Symbol:* None | *Drive:* Influence itself

Colorless villagers are mercenaries—they wander aimlessly until one of the three active colors influences them strongly enough to shift.

- **Behavior**: No allegiance. No job. Simple random wandering.
- **Shift**: Whichever color influences them most becomes their new color. They *also* adopt that color's faction on conversion.
- **Spawn**: Generated during map creation; rare in subsequent waves.

*Philosophy*: Colorless represent the undecided masses—territory to be won or lost through passive influence.

---

### **Magic Orb: The Catalyst**
*Symbol:* Static influence beacon | *Drive:* Transformation

Magic Orbs are environmental entities that broadcast influence to all colors around them—accelerating shifts without requiring villagers.

- **Effect**: Creates a radius of influence, pulling nearby villagers toward color change.
- **Strategic**: Mark key transition zones on your map for orbs to amplify color presence.

*Philosophy*: Magic is the hand of fate—invisible pressure that bends villagers toward your cause.

---

## The Color Shift Chain

Colors influence each other in a cycle:

```
Colorless → Red → Yellow → Blue → Red (loop)
```

Not all colors influence all others. Red influences yellow and blue. Yellow influences blue and colorless. Blue influences red and colorless.

### **Influence Mechanics**

- **Proximity**: Closer = stronger effect. Max range is ~15× a villager's radius.
- **Level**: Higher levels resist influence (L3 cannot be shifted by L1/L2, except Yellow L3 always shifts).
- **Stacking**: Multiple sources of the same color influence a target stack, creating a **bonus** effect.
- **Decay**: If no influencer is nearby, a villager's shift meter decays after a 3-second grace period.
- **Meters**: Visual bar below each villager shows progress toward shift.

*Mastery*: Cluster your villagers. Group leaders trigger stronger influence. Proximity is power.

---

## Food, Time & Death

Your villagers exist in a web of natural constraints.

### **The Day/Night Cycle**

One game-day = 20 real minutes (by default). The cycle has two phases:

- **Day**: Villagers roam, work, fight. Blues can visit churches. Reds hunt.
- **Night**: Darkness falls. Sheltered villagers lock into houses (safety). Unsheltered reds face night enemies. Colorless wander freely.

At dawn, sheltered villagers emerge. Blue L3s still in church reset their 2-day timer.

### **Red Hunger**

Reds are predators with appetites:

- Each second without food, unfed reds take **starve damage**.
- Economy must supply enough fish to keep them sated.
- **Strategy**: Maximize blue fish delivery. Build fishing huts early. 
- **L3 Danger**: Two reds at L3 consume 4 fish per day—unsustainable without blue scaling.

### **L3 Lifespan**

All L3 villagers have a **2-day timer**, measured in game-time:

- **Red L3**: Eating fish (via hunger system) resets the timer.
- **Blue L3**: Sleeping in a church during night resets the timer.
- **Yellow L3**: No sustain—expires after exactly 2 days.
- **Colorless L3**: Very rare; no sustain mechanism.

When a timer runs out: death animation, EventFeed notification, villager removed.

*Philosophy*: Power has a cost. L3 units are legendary but temporary—brief peaks of strength that must be maintained or they fade.

---

## Territory & Dominion

### **Room Ownership**

The map is divided into rooms (connected buildings, outdoor zones). Each room has an owner based on villager presence:

- Whichever faction has the most villagers in a room **owns** it.
- Ownership changes dynamically as villagers move.
- **Core Room**: Each faction has a designated core room. Lose it → **faction eliminated**.

### **Fog of War**

Each faction sees only its own territory clearly. Enemy-owned rooms are shrouded. Neutral rooms are visible but uncontrolled.

---

## Player Commands

You command villagers directly via mouse and keyboard.

### **Selection**
- **Left-click** villager → select (pulsing white ring).
- **Shift+Left-click** → multi-select (add to selection).
- **Right-click empty ground** → deselect all.
- **Escape** → deselect before quitting.

### **Movement**
- **Right-click target** → selected villagers move there.
- **G + drag** → hold position (toggle); villager stays put.
- **H** → enter/exit nearest house.
- **X** → release commands; return to AI brain.

### **Combat (Multiplayer)**
- **A** (attack) + target click → red villagers attack target villager.
- **S** (stun) + target click → blue villagers stun target villager for 2 seconds.
- Combat persists until target dies, you release the command, or you issue a new one.

### **Building**
- **Build menu** → select house, fishing hut, bank, or church.
- **Click to place** → costs stone (from your faction's treasury).
- Buildings provide shelter, resource deposits, and healing.

---

## Buildings & Economy

Your faction accumulates **stone** (from yellows) and **fish** (from blues). Spend stone to build.

### **House**
- *Cost:* 5 stone
- *Capacity:* 4 villagers
- *Effect:* Shelters villagers at night (protection from enemies, auto-unlock at dawn).

### **Fishing Hut**
- *Cost:* 7 stone
- *Effect:* Blue deposit location. Blues naturally bring fish here.

### **Bank**
- *Cost:* 7 stone
- *Effect:* Yellow deposit location. Yellows bank stone here automatically.

### **Church**
- *Cost:* 10 stone
- *Capacity:* 8 villagers
- *Effect:* Blues heal wounds inside. L3 blues reset lifespan if sheltered here at night.

*Strategy*: Early game = houses + fishing hut. Mid game = add banks for stone scaling. Late game = churches to sustain L3 blues.

---

## Multiplayer: Factions at War

In 2–8 player lobbies:

### **Team Assignment**
Lobby host assigns each player to a faction (1–8 possible). Villagers bear their faction's color ring and symbol.

### **War Declaration**
When a red villager from Faction A attacks a villager from Faction B, the two factions enter a **war state**. This is announced in the event feed.

### **PvP Combat**
- Reds can attack any non-red villager (deal damage directly).
- Blues can stun any non-blue villager.
- Stunned villagers cannot move or act for 2 seconds.
- Damage scales with level: `10 × level` per red shot.

### **Territory Wars**
- Room ownership shifts as villagers move.
- Hold your core room or be eliminated.
- Influence spread can flip neutral villagers and colorless mercenaries to your side.

### **Victory Conditions**
- **Elimination**: Last faction standing wins.
- **Population**: Reach a pop cap first (mid-game variant).
- **Temporal**: Survive a set day count (late-game variant).

---

## Advanced Tactics

### **Influence Cascades**
Cluster yellows near blues. Reds nearby shift yellow → the new yellow spreads to the blue group → blue merge cascade. Exponential growth through proximity.

### **Hunger Economics**
Two fish per red L3 per day = brutal math. Don't over-commit to red. Balance is key: some reds for war, most villagers are yellow/blue for sustainability.

### **Cross-Faction Shifting**
Villagers can change color when influenced by an enemy faction—but they **keep their faction identity**. Use this to infiltrate enemy colors with your influence, turning their workforce against them.

### **Church Bottleneck**
L3 blues are powerful but fragile. Competition for church shelter at night = strategic chokepoint. Control the church, control the meta-game.

### **Door Breaking**
Reds can break doors to expand into new rooms. Use this to:
- Escape a bottleneck.
- Claim neutral territory early.
- Cut off enemy supply lines.

---

## The Event Feed

A scrolling log at the top of the screen announces major events:

- Villager shifts ("Red shifts to Yellow").
- Faction wars declared.
- L3 units expiring.
- Buildings placed.
- Player victories/defeats.

Check it often—it tells the story of your village.

---

## Solo Play

Playing alone? You're the only faction (faction 0, "Player"). The map generates with one core room and neutral/colorless villagers scattered about. Expand, merge, grow, optimize—there's no opponent, only your own ambition.

---

## Tips for New Emperors

1. **Start with a base**: Houses first. One fishing hut nearby. One bank.
2. **Recruit colorless**: Drag them near your orb or reds to shift them to your color/faction.
3. **Leverage blues**: Merging is powerful but slow. Pair them strategically for L3 units.
4. **Watch hunger**: One red L3 eats 2 fish a day. Plan blue fishing scaling accordingly.
5. **Expand in daylight**: Nights are for defense. Days are for door breaks and territorial pushes.
6. **Use the HUD**: Shift bars, level badges, health indicators. They guide your eye.
7. **Influence is passive**: Set up your orbs and colors; influence spreads without micromanagement.

---

## Glossary

- **Faction**: A player's team or faction in multiplayer. Solo play = faction 0.
- **Shift**: When one color converts to another via influence.
- **L1 / L2 / L3**: Villager levels. L3 is the apex—strong but temporary.
- **Merge** (blue): Two villagers touch → become one higher-level villager.
- **Duplicate** (yellow): Two villagers touch → spawn an extra one.
- **Shift Meter**: Bar showing progress toward color conversion.
- **Influence Attractor**: The center point of a group exerting influence on nearby villagers.
- **Core Room**: The faction's home. Losing it = elimination.
- **Colorless**: Unaligned villagers. Shift to whoever influences them.
- **War State**: Two factions in direct combat (red attacking non-red).

---

## Final Words

*Little Village* is a game about **invisible forces**. You do not conquer with armies—you *shift* masses through proximity and ideology. You do not build alone—you leverage the natural hierarchies of merge and duplication. You do not survive without logistics—blues feeding reds, reds defending all.

The village is alive. Watch it grow. Watch it tear itself apart. And remember: every decision cascades.

**Now go forth, shepherd. Build your empire.**

---

*Last Updated: April 2026 | Version: 8.0 (Multiplayer + L3 Lifespan)*
