# PopulationDirector — Technical Reference

## Overview
Manages the persistent NPC roster. Generates ~40 unique characters at playthrough start with randomized intrinsic traits and quirks. NPCs persist for the entire run and evolve each cycle.

**Script:** `src/core/PopulationDirector.gd`  
**Type:** Autoload Singleton (Node)

## Roster Generation (`generate_new_roster()`)
Called once per playthrough. Creates `MAX_NPCS` (40) `NPCData` resources.

### Social Class Weights
| Class | Weight | Starting Wealth |
|---|---|---|
| Oligarch | 5% | 800-1500cr |
| Enforcer | 10% | 150-400cr |
| Worker | 40% | 30-120cr |
| Destitute | 45% | 0-30cr |

### Intrinsic Trait Randomization
All 6 traits randomized across 0.0-1.0, then class biases applied:
- **Oligarchs:** `greed += 0.2`, `empathy -= 0.2`
- **Enforcers:** `conformity += 0.2`, `aggression += 0.1`
- **Destitute:** `resilience += 0.1`

### Quirk Assignment
1-3 quirks drawn from a shuffled pool of ~56 across 5 categories: Habits (12), Speech (12), Physical (12), Fears (10), Backstory (12). Injected into LLM prompt as `"Quirks you MUST embody: ..."`.

## Evolution Cycle (`evolve_all_npcs()`)
Called each game cycle by WorldDirector. Passes `tension`, `food_price`, `security_presence` to each NPC's `process_world_pressure()`.

## Query Functions
| Function | Returns | Purpose |
|---|---|---|
| `get_npc_by_id(id)` | NPCData | Lookup by unique ID |
| `get_radicals()` | Array[NPCData] | All "Radical Agitator" profiles |
| `get_broken()` | Array[NPCData] | All "Broken and Submissive" profiles |
| `get_population_summary()` | Dictionary | Profile → count mapping |
