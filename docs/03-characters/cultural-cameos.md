# Cultural Cameos

> **Status:** Design spec + stub. See [src/core/CulturalCameos.gd](../../src/core/CulturalCameos.gd).

Most playthroughs should feel like a grounded, systemic simulation. But sometimes — rarely — the player crosses paths with a figure out of pop-culture myth. A stranger in an alley hands them a soap recipe that turns out to be something else. A lone wolf in a cabin in the Agricultural region keeps sending manifestos to the NetFeed. A man who calls himself only "V" appears on every screen in the Enclave at once.

These moments are the spice that makes a run unforgettable. They're the stories the player tells afterward.

This system is **the machinery for those moments.**

---

## Design goals

1. **Rare, not random.** A cameo should feel earned by the world's state, not rolled out of a hat. The Tyler Durden arc should trigger when a playthrough is *already* ripe for chaos — high tension, beaten-down Workers, a player leaning into direct action.
2. **Tiered intensity.** Most cameos should be small — a NetFeed headline, a one-scene encounter. Some should reshape the run. Very few should end it.
3. **Recognizable, not trademarked.** Use archetypes. "Tyler Durden" in a file becomes *"the Soap Man"* in-game. *Fight Club* → *Project Mayhem* (keep the resonant name; the archetype is what matters). Legal safety is also creative discipline — forcing specificity, not borrowing it.
4. **Systemic consequences.** A cameo arc must feed the same economy/Butterfly Effect as the core game. A chaos cascade isn't narrative — it's `public_tension +5/cycle for 6 cycles` + recruited Workers flipping to Radical Agitator.
5. **Can be refused.** The player should always be able to walk away from a cameo. The interesting ones make walking away feel *expensive*.

---

## Cameo tiers

| Tier | Label | Frequency (per run) | Effect size |
|---|---|---|---|
| 1 — **Whisper** | NetFeed-only easter egg. No encounter. | 2–4 per run | Zero mechanical impact. Flavor only. |
| 2 — **Brush** | One-scene encounter. Short arc (1–2 objectives). | 0–2 per run | Local gift, debuff, or small economy swing |
| 3 — **Entanglement** | Multi-cycle arc. Cameo becomes a temporary operative or adversary. | 0–1 per run | Medium economy swing, possible new victory path |
| 4 — **Takeover** | The cameo hijacks the playthrough. Rare. | ~1 in 10 runs | World-reshaping; can conflict with the player's own goals |

---

## Cameo schema

```gdscript
{
    "id": "soap_man",
    "tier": 4,                                  # Takeover
    "archetype": "chaos_prophet",               # family tag (see below)
    "display_name": "{LLM-generated per run}",  # e.g., "Jack Hollis", "The Man with the Soap"
    "inspired_by_tag": "fight_club",            # internal only, never surfaced
    "trigger": {
        "min_cycle": 4,
        "required_state": {
            "public_tension": ">50",
            "worker_radical_ratio": ">0.25",
            "player_ruthlessness": ">0.5"       # tracked from player actions
        },
        "probability": 0.15                     # rolled each cycle once gated
    },
    "intro_event": {
        "kind": "encounter",                    # or "netfeed_only" for Tier 1
        "location_hint": "URBAN_SLUM/safehouse",
        "netfeed_teaser": "Anonymous broadcast calls for 'space monkeys'. Enforcers investigating."
    },
    "arc": [
        { "objective": "Accept the invitation (find the next house)", "impact": {} },
        { "objective": "Run the first 'homework'", "impact": {"public_tension": 5, "npc_radicalize_hint": "Worker"} },
        { "objective": "Decide: absorb the network, or betray it", "impact_accept": {"public_tension": 15}, "impact_betray": {"scandal_about_player": true} }
    ],
    "world_modifiers_while_active": {
        "public_tension": "+1 per cycle",
        "netfeed_flavor": "project_mayhem_copy"    # headlines style shift
    },
    "exit": {
        "completion_reward": {"cameo_operative": true},
        "betrayal_penalty":  {"heat_tier": 3},
        "timeout_cycles": 8
    },
    "exclusivity": ["chaos_prophet"],           # only one of this archetype per run
    "rarity_weight": 1.0
}
```

---

## Archetype families

Archetypes are **thematic buckets**. Only one cameo per family per run. Families balance themselves — the pool should cover dystopian fiction's main "intrusions".

| Family | What it represents | Examples (internal names → in-game archetype) |
|---|---|---|
| `chaos_prophet` | Anti-consumerist chaos agents | *Fight Club* → Soap Man / Project Mayhem |
| `masked_symbol` | Iconic revolutionary | *V for Vendetta* → Mask of Empty, / Fifth November |
| `lone_manifesto` | The isolated ideologue with a cabin | Unabomber archetype → The Hermit / The Manifesto |
| `whistleblower` | Insider who flips | *Mr. Robot* / Snowden-ish → The Disgruntled Admin |
| `corporate_priest` | Charismatic Oligarch-in-waiting | *Wolf of Wall Street* / Wonka gone dark → The Confectioner |
| `cult_of_personality` | A preacher with a flock in The Sinks | *Jonestown* / *True Detective* Carcosa-lite → The Yellow Priest |
| `loop_in_time` | A person from "another run" (meta) | *12 Monkeys* / Dark → The Revenant |
| `rogue_ai` | Broken system that noticed you | *Shodan* / Terminator → Compliance Error 7 |
| `folk_hero_from_the_sinks` | An NPC the NetFeed has canonized | *Robin Hood* archetype → The Bread Thief |
| `kindly_stranger` | A small, benevolent intrusion | *Bagger Vance* / *Forrest Gump* — a Tier 1 or 2, pure warmth |

Start with 10 archetypes × 2 cameos each = 20 cameo definitions. Grow organically.

---

## Triggering

Each cycle, `CulturalCameos.evaluate_triggers(world_state, player_profile)`:

1. Roll **all Tier 1 (Whisper)** cameos — NetFeed flavor only, lightweight
2. For Tier 2–4 cameos whose `min_cycle` is reached and whose `required_state` is satisfied:
   - Roll against `probability * rarity_weight`
   - If it hits and no cameo of the same `archetype` family is active → trigger
3. Emit `cameo_triggered(cameo_id)` → WorldDirector queues the intro event

Triggers are **gated by world state**, not player choice. The player doesn't opt in. The world *produces* the encounter because it was ready.

### Player profile tracking

`CulturalCameos` needs a lightweight profile of the player's playstyle to gate appropriately. Tracked in `PlayerManager`:

- `player_ruthlessness` — increases on loud combat, scandals, betrayals
- `player_idealism` — increases on political pressure, saved NPCs
- `player_stealth_preference` — increases on silent kills, hacks
- `player_chaos_preference` — increases on sabotage + assassinations

A `chaos_prophet` cameo gates on high `chaos_preference`. A `kindly_stranger` gates on low `ruthlessness`. A `rogue_ai` gates on lots of hacks. The system *rewards your style with the right mythology*.

---

## Arc execution

A Tier 2+ cameo enters an **active** state:

```
active_cameos: Array[ActiveCameo]

ActiveCameo {
    definition: CameoDefinition
    current_step: int
    cycles_remaining: int
    operative_slot_used: bool       # tier 3-4 may occupy an agent slot
    modifiers_applied: Array
}
```

Each cycle:
- Apply `world_modifiers_while_active` (tension drift, NetFeed flavor, etc.)
- If current step's objective is completable in world state, surface a prompt to the player
- If `cycles_remaining == 0` without completion → timeout, apply timeout exit
- On completion or betrayal → apply exit effects, remove from `active_cameos`

**NetFeed flavor while active:** when a cameo is running, the `CulturalCameos` system injects a flavor tag into `trigger_news_cycle()` context. The LLM is told *"A chaos-prophet arc is active. Lean into anti-consumerist, rally-cry copy."* NetFeed headlines shift register for the duration. This is the cheapest way to make a cameo *feel* like it's taking over the world.

---

## Example: the Soap Man arc

```
Trigger conditions:
  min_cycle: 4
  public_tension > 50
  worker_radical_ratio > 0.25
  player_chaos_preference > 0.5

Intro (cycle 5):
  NetFeed: "Enforcers investigating underground soap distribution. Product contains suspicious alkaline burns."
  Encounter: in a Slum safehouse, a man offers the player a bar of soap and an address.

Arc:
  Step 1 (cycle 6): "Visit the house on Paper Street."
    → Player visits, meets the Project. 6 Workers from the roster flip to Radical Agitator permanently.
  Step 2 (cycle 7-8): "Run the first homework." (destroy a corporate billboard)
    → public_tension +10 on success. If loud: +Heat.
  Step 3 (cycle 9): "Decide — absorb or betray."
    → Absorb: gain a cameo operative (The Soap Man as Loyal Operative tier 5).
       Project Mayhem becomes permanent: +1 tension/cycle, NetFeed stays in chaos-prophet register.
       A new victory sub-path opens: "Let the Project finish what you started" — automatic
       tension escalation toward revolution while the player is free to do anything else.
    → Betray: the Soap Man vanishes. A scandal about the player hits the NetFeed. Six
       Workers you radicalized remember you as the traitor. Loyal Operative slot is burned.

Timeout (cycle 13): the Project dissolves quietly. Tension drops back to pre-arc level over 3 cycles.
```

The player can also **refuse at the intro**. The Soap Man never appears again in that run, but a Tier 1 Whisper occasionally mentions "soap-related vandalism" in the feed — a reminder of the road not taken.

---

## Balancing

- **Cap active cameos at 1 Tier 3+ at a time.** The world can sustain one hijacking, not three.
- **Inject "flavor tax" into NetFeed prompt when cameos are active** so the LLM doesn't drown the cameo in unrelated headlines.
- **Rarity drift:** a cameo that fires in one run has its `rarity_weight` halved for the next seven runs (persistent across deaths/runs via save file). Prevents the same mythology dominating a player's experience.
- **One Takeover per run maximum.** Period.

---

## What this **must not** do

- Don't break the tone. Cameos should feel like the game's world is *dreaming*, not like a crossover episode. The NetFeed stays deadpan; the cameo earns its presence by fitting.
- Don't over-explain. If the player misses the reference, the arc still has to work on its own mechanical merits.
- Don't overwrite the persistent roster. Cameos are their own roster. NPCs are NPCs.
- Don't let a cameo's modifiers persist after the arc ends (except where the arc explicitly opened a new path, like Project Mayhem).

---

## Code layout

```
src/core/CulturalCameos.gd    # NEW singleton — trigger engine, arc execution
res://data/cameos/*.tres      # one resource per cameo definition (later)
```

See the stub at [src/core/CulturalCameos.gd](../../src/core/CulturalCameos.gd) for signatures. Definitions start in-code; will move to Godot resources once the pool grows past ~20.

---

## Seed archetype list (first 10)

To ship the system with content, start with two cameos each from:

1. `chaos_prophet` — Soap Man (T4), The Broadcast (T2 whisper-based)
2. `masked_symbol` — Fifth November (T3), The Mask in the Crowd (T1)
3. `lone_manifesto` — The Hermit of Substrate Fields (T3), Unsigned Papers (T1)
4. `whistleblower` — The Admin Who Got Fired (T2), Last Login: 03:12 (T1)
5. `corporate_priest` — The Confectioner (T3 — offers a bitter gift), Candy Heir (T2)
6. `cult_of_personality` — The Yellow Priest (T3), Hymns from the Undercity (T1)
7. `loop_in_time` — The Revenant (T4 — claims to remember the player from a "previous cycle"), Déjà-Vu Headline (T1)
8. `rogue_ai` — Compliance Error 7 (T3 — friendly), Pattern Match Exceeded (T1)
9. `folk_hero_from_the_sinks` — The Bread Thief (T2), Ballad of the Brick Kid (T1)
10. `kindly_stranger` — The Man with the Match (T2 — pure warmth, restores hope), A Coffee on the House (T1)

Twenty cameos is enough to feel varied for the first dozen runs. The system is the value; the pool grows.

---

## See also
- [Pillars](../01-vision/pillars.md) — cameos reinforce "emergent storytelling" and "people, not pawns"
- [NetFeed](../02-world/netfeed.md) — delivery layer
- [Relationships](relationships.md) — cameo operatives slot into the agent system
- [Progression](../04-player/progression.md) — player profile tracking that gates cameos
