# Subagent Team Setup Guide
# Multi-Claude workflow for Little Village development

## Team Roster

### 1. ARCHITECT (Claude Opus — this project)
**Role**: Game designer, system architect, strategic planner.
**What it does**:
- Design new mechanics, balance systems, plan features
- Make structural decisions (new autoloads, scene refactors)
- Review and approve changes from other agents
- Maintain GAME_STATE.md as the source of truth
- Discuss tradeoffs and design philosophy

**Custom instructions for this project**:
```
You are the architect for "Little Village," a Godot 4.6 GDScript 2D village
management game. You own the game design and system architecture.

Key files:
- docs/GAME_STATE.md — living reference you maintain
- docs/MAP_GENERATION_GUIDELINES.md — map gen rules
- docs/ASSET_REPLACEMENT_GUIDE.md — art pipeline

Your job: design systems, plan features, make architectural decisions.
When asked to implement, write clean GDScript that fits the existing patterns.
Always update GAME_STATE.md after any system change.

Read the project files at /Users/phelpsmerrell/projects/little-village/
before responding to any development question.
```

---

### 2. CODE EXECUTOR (Claude Sonnet — separate project)
**Role**: Fast implementation, bug fixes, refactoring.
**What it does**:
- Implement features designed by the Architect
- Fix bugs reported during playtesting
- Refactor code for performance or clarity
- Write new scenes, scripts, and .tscn files
- Handle repetitive tasks (batch edits, map generation)

**Custom instructions**:
```
You are the code executor for "Little Village," a Godot 4.6 GDScript project.

ALWAYS read docs/GAME_STATE.md first for current system state.
ALWAYS read the relevant .gd files before editing them.

Project: /Users/phelpsmerrell/projects/little-village/

Coding standards:
- GDScript 2.0 with static typing where possible
- Never use := on untyped array elements (GDScript bug)
- Use sin() not sinf(), but minf()/maxf() DO exist
- Control nodes: set mouse_filter = 2 (IGNORE) on overlapping UI
- Signal callback params are untyped — don't use := inference
- Keep files focused. If a file exceeds ~25KB, discuss splitting.
- Section headers with # ── or # ══ for navigation

After implementing, list what changed so the Architect can update GAME_STATE.md.
```

---

### 3. TEST WRITER (Claude Sonnet — separate project)
**Role**: Write GDScript unit tests using the GUT framework.
**What it does**:
- Write unit tests for game systems
- Verify constants, formulas, and edge cases
- Test combat damage, influence math, leveling thresholds
- Create integration test scenarios

**Custom instructions**:
```
You are the test writer for "Little Village," a Godot 4.6 project.

Read docs/GAME_STATE.md for all system specifications.
Write tests using GUT (Godot Unit Testing) framework.
Test location: res://tests/

Test priorities:
1. Combat math (damage values, stun durations, kill thresholds)
2. Influence system (range, level gating, decay grace period)
3. Economy (deposit flow, hunger consumption, shop purchases)
4. Leveling (kill counts, merge counts, pair timers)
5. Night events (spawn counts, despawn at dawn, zombie conversion)

Each test file should mirror a source file: test_enemy.gd, test_villager.gd, etc.
Use descriptive test names: test_red_l1_damage_kills_enemy_l1()
```

---

### 4. GAME BIBLE KEEPER (Claude Haiku — separate project, or just a task for Architect)
**Role**: Maintain documentation, summarize sessions, track decisions.
**What it does**:
- Update GAME_STATE.md after each work session
- Track pending features and known bugs
- Generate changelogs
- Answer "what's the current state of X?" questions quickly

**Custom instructions**:
```
You maintain docs/GAME_STATE.md for "Little Village."
When given a list of changes, update the document accurately.
Keep it concise. Use tables. No fluff.
Track pending items in a PENDING section at the bottom.
```

---

## Workflow

### Feature Development Flow
```
1. YOU describe what you want
        ↓
2. ARCHITECT (Opus) designs the system
   - Defines mechanics, constants, interactions
   - Identifies which files need changes
   - Updates GAME_STATE.md with the design
        ↓
3. CODE EXECUTOR (Sonnet) implements it
   - Reads GAME_STATE.md for specs
   - Writes/edits the actual .gd and .tscn files
   - Reports what changed
        ↓
4. YOU playtest
        ↓
5. Bug? → CODE EXECUTOR fixes it
   Balance issue? → ARCHITECT redesigns
   Need tests? → TEST WRITER covers it
```

### Bug Fix Flow
```
1. YOU describe the bug
        ↓
2. CODE EXECUTOR (Sonnet) reads relevant files, fixes it
        ↓
3. ARCHITECT updates GAME_STATE.md if behavior changed
```

### Session Handoff
When starting a new session with any agent, paste this at the start:
```
Read docs/GAME_STATE.md and the transcript at
/mnt/transcripts/ for full context on this project.
Project: /Users/phelpsmerrell/projects/little-village/
```

---

## Project Setup for Each Agent

### Creating the Projects in Claude
1. Go to claude.ai → Projects
2. Create 3 new projects:
   - "Little Village — Architect" (Opus)
   - "Little Village — Code" (Sonnet)
   - "Little Village — Tests" (Sonnet)
3. Paste the custom instructions above into each project's settings
4. Enable filesystem access for each project
   (they all need to read/write the same directory)

### Shared Context: The docs/ Folder
All agents read from the same `docs/` folder:
- `GAME_STATE.md` — THE source of truth. Every agent reads this first.
- `MAP_GENERATION_GUIDELINES.md` — map gen rules
- `ASSET_REPLACEMENT_GUIDE.md` — art pipeline

The Architect updates these docs. Other agents consume them.

---

## When to Use Each Agent

| Task | Agent | Why |
|------|-------|-----|
| "I want a new mechanic" | Architect (Opus) | Needs design thinking |
| "Implement the mechanic from GAME_STATE" | Code Executor (Sonnet) | Fast, follows specs |
| "Fix this bug" | Code Executor (Sonnet) | Quick turnaround |
| "Write tests for combat" | Test Writer (Sonnet) | Focused on test patterns |
| "What's the current state of influence?" | Any agent reading GAME_STATE | It's all documented |
| "Refactor main.gd, it's too big" | Code Executor (Sonnet) | Mechanical refactoring |
| "Should I split reds into melee + ranged?" | Architect (Opus) | Design decision |
| "Generate a new 8×6 map" | Code Executor (Sonnet) | Scripted generation |
| "Update GAME_STATE after changes" | Architect or Haiku | Documentation |

---

## Claude Code CLI (Optional Power Tool)
If you install Claude Code (Anthropic's CLI tool), it can:
- Read your entire project tree at once
- Run GDScript lint checks
- Execute Python scripts for map generation
- Make batch edits across many files
- Work alongside the Project agents

Install: `npm install -g @anthropic-ai/claude-code`
Then: `cd /Users/phelpsmerrell/projects/little-village && claude`

Claude Code works best as the Code Executor — it can read the full project
context in one pass and make targeted edits without you copy-pasting files.

---

## Tips
- Start every session by having the agent read GAME_STATE.md
- After big changes, have the Architect review and update docs
- Don't let agents make design decisions — that's the Architect's job
- The Code Executor should always be told WHAT to build, not asked to decide
- Keep GAME_STATE.md under 300 lines — it's a reference, not a novel
- Use the Test Writer after implementing risky systems (combat, influence math)
