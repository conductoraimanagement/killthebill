# NPCs

> 40 persistent citizens, generated at playthrough start, evolving every cycle. No spawning, no despawning. If the game says *"She was shot during the riot"*, she's gone for the rest of the run.

Implemented by: [src/entities/NPCData.gd](../../src/entities/NPCData.gd) (Resource) and [src/core/PopulationDirector.gd](../../src/core/PopulationDirector.gd) (Singleton).

---

## The roster

At playthrough start, `PopulationDirector.generate_new_roster()` creates 40 NPCs. Each is a full character — name, class, traits, quirks, memories, starting wealth.

### Class distribution

| Class | Weight | Starting wealth | Role |
|---|---|---|---|
| Oligarch (small fish) | 5% | 800–1,500 cr | Sub-elite, can be played like an Oligarch but no sector |
| Enforcer | 10% | 150–400 cr | Corporate security; often hostile, sometimes turnable |
| Worker | 40% | 30–120 cr | The middle mass — the radicalization battleground |
| Destitute | 45% | 0–30 cr | The Sinks' core; early recruits, fast radicalizers |

---

## Intrinsic traits — Nature (immutable)

Six traits, 0.0–1.0, set at generation. Class biases applied on top:
- Oligarchs: `greed +0.2`, `empathy -0.2`
- Enforcers: `conformity +0.2`, `aggression +0.1`
- Destitute: `resilience +0.1`

| Trait | High | Low |
|---|---|---|
| `resilience` | Stoic, absorbs pressure | Fragile, breaks under stress |
| `aggression` | Radicalizes when pushed | Withdraws from conflict |
| `empathy` | Affected by others' pain | Self-serving, cold |
| `idealism` | Revolutionary believer | Cynical, resigned |
| `greed` | Exploits chaos for gain | Content with little |
| `conformity` | Follows the crowd | Independent thinker |

---

## Dynamic state — Nurture (evolves)

| Variable | Range | Meaning |
|---|---|---|
| `stress_level` | 0–100 | Accumulated psychological pressure |
| `hope` | 0–100 | Belief in a future |
| `radicalization` | 0–100 | How close to action |
| `knowledge_of_player` | 0.0–1.0 | How much they know about the player's activities |
| `opinion_of_player` | −1.0…+1.0 | How they feel |

### World pressure loop

```
stress  += pressure * (1.0 - resilience * 0.7)
hope    -= decay    * (1.0 - idealism  * 0.6)
radical += (aggression * 3.0 - conformity * 2.0)   # only when stressed + hopeless
```

Called each cycle by `PopulationDirector.evolve_all_npcs(global_economy)`.

---

## Behavioral profiles

| Profile | Conditions |
|---|---|
| Radical Agitator | stress >70, aggression >0.7, conformity <0.3 |
| Broken and Submissive | stress >60, resilience <0.3, conformity >0.6 |
| Revolutionary Idealist | idealism >0.7, empathy >0.6, stress >40 |
| Opportunistic Exploiter | greed >0.7, empathy <0.3 |
| Cautiously Stable | stress <30 or resilience >0.7 |
| Anxious Citizen | default |

---

## Quirks

1–3 quirks per NPC, drawn from a shuffled pool of ~56 across five categories:

- **Habits** (12) — "hums when anxious", "collects matchbooks", "never drinks water cold"
- **Speech** (12) — "stutters when nervous", "uses old slang", "speaks only in half-sentences"
- **Physical** (12) — "has a limp from an Enforcer beating", "missing a tooth", "permanent ink stain on left hand"
- **Fears** (10) — "afraid of open water", "won't enter the Enclave", "panics around drones"
- **Backstory** (12) — "used to work for a dead Oligarch", "lost a child in a Sinks collapse", "wrote manifestos in jail"

Quirks are injected into the LLM prompt as *"Quirks you MUST embody: …"*. They compound with traits and profile to produce a voice.

---

## Relationships

Every NPC carries:

| Variable | Type | Meaning |
|---|---|---|
| `relationship_type` | enum 0–5 | None → Acquaintance → Friend → Close Friend → Romantic → Loyal Operative |
| `trust` | 0–100 | Built through aligned actions |
| `is_agent` | bool | Whether they're currently assigned to a mission |
| `current_objective` | String | Active mission |
| `bond_history` | Array[String] | Rolling ledger |

See [relationships.md](relationships.md) for the trust/objective system.

---

## LLM context

`get_llm_context_string()` outputs a token-efficient string: name, class, behavioral profile, stress/hope/radicalization scores, relationship to player, personality adjectives, quirks, recent memories. That string is prepended to every dialogue call.

---

## Design notes

- **Persistence matters.** If the player saves an NPC's life, the NPC remembers. If they don't save them, a friend in the roster does.
- **Death is real and traceable.** NPCs can die from Butterfly Effects (a riot, a purge, starvation). The NetFeed should mention significant NPC deaths. Their absence from the player's life is a story.
- **No generic crowds.** If the player sees a face, it's one of the 40. Background characters are not NPCs — they're visual density ([landscapes](../02-world/landscapes.md)).
- **Cameos are separate.** Pop-culture archetype characters live in [cultural-cameos.md](cultural-cameos.md) and don't pollute the persistent roster. They come and go with their arc.
