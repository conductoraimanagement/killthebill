# RegionGenerator — Technical Reference

## Overview
Procedural world map builder. Generates 6-10 unique regions at playthrough start with random names, properties, and visual biomes. Replaces all hardcoded sector names.

**Script:** `src/core/RegionGenerator.gd`  
**Type:** Node (class_name RegionGenerator, Autoload Singleton)  
**Called by:** `WorldDirector.initialize_playthrough()`

## Region Types
| Type | Count | Security | Tension | Population |
|---|---|---|---|---|
| URBAN_SLUM | 2-3 | -30 to -10 | +10 to +30 | 0.7-1.0 |
| URBAN_ELITE | 1-2 | +30 to +60 | -30 to -10 | 0.1-0.3 |
| INDUSTRIAL | 1-2 | -5 to +15 | 0 to +15 | 0.2-0.4 |
| AGRICULTURAL | 1-2 | -10 to +5 | -5 to +10 | 0.1-0.25 |
| ISLAND_RETREAT | 0-1 | +50 to +80 | -40 to -20 | 0.01-0.05 |
| TRANSIT | 1-2 | +10 to +30 | +5 to +15 | 0.3-0.6 |

## Name Generation
Each type has pools of 10 prefixes and 10 suffixes:
- **Slum:** "Rust", "Ash", "Gray"... + "Hollow", "Row", "Depths"...
- **Elite:** "Crystal", "Silver", "Solar"... + "Heights", "Spire", "Plaza"...
- **Industrial:** "Foundry", "Slag", "Iron"... + "Basin", "Works", "Yard"...
- **Farm:** "Substrate", "Root", "Loam"... + "Fields", "Beds", "Vaults"...
- **Island:** "Haven", "Obsidian", "Coral"... + "Cay", "Atoll", "Isle"...
- **Transit:** "Checkpoint", "Border", "Passage"... + "Nexus", "Point", "Lock"...

## Region Properties
| Property | Type | Description |
|---|---|---|
| `security_modifier` | int | Added to global security for local checks |
| `tension_modifier` | int | Added to global tension for local NPC behavior |
| `population_density` | float | 0-1, affects NPC encounter frequency |
| `infrastructure_targets` | Array | 2-3 sabotage-able facilities |
| `visual_biome` | String | Environment theme for level generator |
| `connected_oligarch` | String | Oligarch who controls this region |
| `unlocked` | bool | Whether player can travel here |

## Query Functions
| Function | Returns | Purpose |
|---|---|---|
| `get_region_by_name(name)` | Dictionary | Lookup by name |
| `get_regions_by_type(type)` | Array | All regions of a type |
| `get_unlocked_regions()` | Array | Currently accessible regions |
| `get_world_summary()` | Dictionary | Type → count mapping |
