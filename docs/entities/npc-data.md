# NPCData Resource — Technical Reference

## Overview
`NPCData.gd` extends `Resource` and defines the complete character sheet for every persistent NPC. It separates **Intrinsic Traits** (immutable nature) from **Dynamic State** (evolving nurture) to ensure no two NPCs react the same way to the same world event.

**Script:** `src/entities/NPCData.gd`  
**Type:** Resource (class_name NPCData)

## Intrinsic Traits (Nature — Immutable)
Set once at roster generation. Act as filters/multipliers on world events.

| Trait | Range | High | Low |
|---|---|---|---|
| `resilience` | 0.0-1.0 | Stoic, absorbs pressure | Fragile, breaks quickly |
| `aggression` | 0.0-1.0 | Radicalizes when pushed | Withdraws from conflict |
| `empathy` | 0.0-1.0 | Affected by others' pain | Self-serving, cold |
| `idealism` | 0.0-1.0 | Revolutionary believer | Cynical, resigned |
| `greed` | 0.0-1.0 | Exploits chaos for gain | Content with little |
| `conformity` | 0.0-1.0 | Follows the crowd | Independent thinker |

## Quirks
Array of 1-3 human details (e.g., "Stutters when nervous", "Has a limp from an Enforcer beating"). Injected into LLM prompt as `"Quirks you MUST embody: ..."`.

## Dynamic State (Nurture — Evolves Each Cycle)
| Variable | Range | Description |
|---|---|---|
| `stress_level` | 0-100 | Accumulated psychological pressure |
| `hope` | 0-100 | Belief in a future. Low = despair or rage |
| `radicalization` | 0-100 | Extremism index |
| `knowledge_of_player` | 0.0-1.0 | How much they know about the player |
| `opinion_of_player` | -1.0 to 1.0 | How they feel about the player |

## Behavioral Profiles (`get_behavioral_profile()`)
Evaluates Nature + Nurture:

| Profile | Conditions |
|---|---|
| Radical Agitator | stress >70, aggression >0.7, conformity <0.3 |
| Broken and Submissive | stress >60, resilience <0.3, conformity >0.6 |
| Revolutionary Idealist | idealism >0.7, empathy >0.6, stress >40 |
| Opportunistic Exploiter | greed >0.7, empathy <0.3 |
| Cautiously Stable | stress <30 or resilience >0.7 |
| Anxious Citizen | Default fallback |

## World Pressure Processing (`process_world_pressure()`)
```
Stress:  stress += pressure * (1.0 - resilience * 0.7)
Hope:    hope -= decay * (1.0 - idealism * 0.6)
Radical: radical_push = aggression * 3.0 - conformity * 2.0  (only when stressed + hopeless)
```

## Relationship System
| Variable | Type | Description |
|---|---|---|
| `relationship_type` | enum (0-5) | None → Acquaintance → Friend → Close Friend → Romantic → Loyal Operative |
| `trust` | 0-100 | Built through interactions, decays through betrayal |
| `is_agent` | bool | Whether currently assigned as a player agent |
| `current_objective` | String | Active mission description |
| `bond_history` | Array[String] | Rolling ledger of relationship events |

## LLM Context Serialization (`get_llm_context_string()`)
Outputs a token-efficient string: name, class, behavioral profile, stress/hope/radicalization scores, relationship context, personality adjectives, quirks, and memories.
