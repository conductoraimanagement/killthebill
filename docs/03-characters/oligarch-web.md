# Oligarch Web

> **Status:** Design spec + stub. See [src/core/OligarchNetwork.gd](../../src/core/OligarchNetwork.gd) and the extensions to [OligarchData.gd](../../src/entities/data/OligarchData.gd).

Today's [billionaire system](oligarchs.md) models each Oligarch as an isolated character. In reality, billionaires don't operate in isolation — they scheme, ally, betray, and prey on each other. The Oligarch Web adds that layer:

1. **Rivalries and alliances** between Oligarchs (a faction graph)
2. **Organic scandals** generated from traits + world state, not just from the player
3. **Adaptation** — billionaires remember the player's tactics and change strategy

This is the difference between "a list of bosses" and "a boardroom at war with itself". The player should be able to *drive wedges* between billionaires, turning two of them against each other without ever taking a shot.

---

## Part 1 — Faction graph

### Relationships between Oligarchs

Every pair of Oligarchs has a `relationship_score` in **−100…+100**:

- +60 to +100 — **Allied** (share intelligence, coordinate PR, co-fund militia)
- +20 to +60 — **Aligned** (won't attack each other, may cooperate opportunistically)
- −20 to +20 — **Neutral** (default)
- −20 to −60 — **Rival** (covertly undermine each other, leak each other's scandals)
- −60 to −100 — **Nemesis** (actively trying to destroy each other; will ally *with the player* in extreme cases)

### Generation

At playthrough start, after Oligarchs are created:
- Initialize all pairs to `randf_range(-20, +20)` — neutral with noise
- Apply **sector-based bias**:
  - Same sector → `-30` (direct competitors, usually)
  - Food ↔ Security → `+10` (mutual interest in order)
  - Media ↔ anyone with high `controversy_level` → `-20`
  - Tech ↔ Pharma → `+15` (shared R&D interests)
- Apply **trait compatibility bias**:
  - Both `ideology > 0.7` → `+20` (true believers recognize each other)
  - Both `greed > 0.7` → `-20` (pure greed doesn't share)
  - `paranoia_base > 0.7` vs `ruthlessness > 0.7` → `-25` (the paranoid fears the ruthless)

### Evolution

Each cycle, `OligarchNetwork.evolve_relationships()` runs:

- Player actions against Oligarch A shift A's view of any rivals +5 (enemy of my enemy)
- A scandal leaked about A shifts A's view of any Media Oligarch −3 unless they're already allied
- Economic success of A while B is struggling → B's view of A −2 per cycle (jealousy)
- Two allied Oligarchs both alive and wealthy → alliance compounds slowly (+1/cycle to mutual score), but large wealth asymmetry starts draining it

### Faction actions

When two Oligarchs reach **Allied**, they unlock joint actions in `OligarchNetwork.process_factions()`:

- **Joint PR defense** — both spend to rehabilitate the other's image
- **Coordinated militia** — double the security_presence impact
- **Shared black book** — `awareness_of_player` for one becomes known to the other
- **Trade concession** — weaker party's wealth drain slowed

When two reach **Nemesis**, they unlock hostile actions:

- **Scandal leak** — one generates an organic scandal about the other (see Part 2)
- **Poached ambition** — one hijacks the other's ambition progress (e.g., buys the media outlet *first*)
- **Assassination contract** — rare, only at `< -80` and `ruthlessness > 0.8`; one hires an NPC agent to kill the other. If it succeeds, the player has one fewer target and one more vindicated billionaire to deal with.

### Player-facing effect

The faction graph is **visible indirectly**:
- Through NetFeed headlines (coverage patterns reveal who protects whom)
- Through dialogue with any NPC agent who's worked for either Oligarch
- Through a dedicated **Web Terminal** UI screen, unlockable mid-game through intel gathering

---

## Part 2 — Organic scandals

Today, scandals only happen when the player triggers `leak_scandal`. That makes the world too quiet. In reality, billionaires generate their own scandals — through trait misfires, ambition overreach, or rival sabotage.

### Scandal seeds

Each cycle, every Oligarch has a chance to **self-generate** a scandal:

```
scandal_pressure =
    (greed * 0.3)
  + (ruthlessness * (ambition_progress["Purge The Sinks"] or 0) * 0.5)
  + (vanity * max(0, -public_image / 100) * 0.3)
  + (controversy_level / 200)
  - (media_ally_protection * 0.5)      # allied Media Oligarch suppresses

if randf() < scandal_pressure * 0.05:  # ~5% at max pressure
    generate organic scandal
```

### Scandal kinds (pool by trait)

| High trait | Scandal archetype |
|---|---|
| `greed` | "Offshore tax evasion scheme uncovered." "Secretly owns three rival brands." |
| `ruthlessness` | "Funded a Sinks eviction squad that killed 12." "Ordered a blacklist of injured workers." |
| `vanity` | "Caught in scripted charity photo-op." "Plagiarized autobiography." |
| `paranoia` | "Built a panic bunker under a public hospital." "Bugged own employees' homes." |
| `ideology` | "Leaked manifesto calls Sinks residents 'inefficient matter'." |
| `intelligence` | "Hired a dead journalist's identity to plant a story." (These are the hardest to trace.) |

LLM-seeded within archetype. Appended to `recent_scandals`. Drops `public_image` and raises `controversy_level` as with player leaks.

### Rival amplification

If Oligarch A's rival (relationship_score < −40) is alive, the scandal's impact is amplified by the rival's **Media reach** if they own Media, or by their willingness to fund anonymous leaks otherwise. This is where the faction graph visibly shapes headlines.

---

## Part 3 — Adaptation (memory + strategy shift)

Today, Oligarchs' only response to the player is `awareness_of_player` + `threat_assessment`. They don't remember *how* the player operates.

### Memory of player tactics

Extend `OligarchData` with:

```gdscript
@export var player_tactics_memory: Dictionary = {
    "sabotage_count": 0,
    "assassination_count": 0,
    "hack_count": 0,
    "scandal_count": 0,
    "political_pressure_count": 0,
    "stealth_preference": 0.5,    # 0 = loud, 1 = stealthy
    "last_observed_region": ""
}
```

Populated each time `WorldDirector._ripple_*` fires on this Oligarch or their sector.

### Strategy shift

Each cycle, `OligarchData.adapt_strategy()`:

- If `assassination_count > 0` and the Oligarch is **next likely target** (high awareness + high threat), they flip to **Escape** ambition if paranoid, or **Crush the resistance** if ruthless. Existing ambitions are not replaced — added.
- If `hack_count > 2`, they spend on cybersecurity — new action `HARDEN_GRID` that reduces future `hack_grid` ripples by 50% for one cycle.
- If `scandal_count > 2`, they spend on a Media alliance (boost relationship_score with any Media Oligarch by +10 via bribe action).
- If `stealth_preference > 0.7`, they switch investigators from street patrols to digital surveillance → future silent player actions become harder (`awareness_of_player` increases per cycle by +2 even from hidden actions).
- If `stealth_preference < 0.3`, they expect loud attacks and over-invest in visible security, which the player can exploit for misdirection.

### Design principle

**The billionaires should not out-think the player; they should out-*remember* the player.** They don't need to be clever. They need to be annoying in the way wealthy institutions are annoying — boring, unresponsive, prepared for last time's attack. The player's job is to keep being surprising.

---

## Code layout

```
src/core/OligarchNetwork.gd        # NEW singleton — faction graph + org scandal gen
src/entities/data/OligarchData.gd       # Extended with tactics memory + adapt_strategy()
```

`OligarchNetwork` is an autoload. It:
- Owns the pairwise relationship matrix
- Runs `evolve_relationships()` and `process_factions()` each cycle, called by `WorldDirector.run_world_cycle()`
- Exposes `get_relationship(a, b)`, `get_allies(oligarch)`, `get_rivals(oligarch)`
- Emits `faction_action_taken(action)` signal (parallel to `oligarch_action_taken`)
- Generates organic scandals via `roll_scandal(oligarch, world_state)`

See the stub in [src/core/OligarchNetwork.gd](../../src/core/OligarchNetwork.gd) for the signatures.

---

## See also
- [Oligarchs](oligarchs.md) — per-billionaire character sheet
- [NetFeed](../02-world/netfeed.md) — how scandals surface to the player
- [Butterfly Effect](../02-world/butterfly-effect.md) — the ripple matrix this layer compounds
