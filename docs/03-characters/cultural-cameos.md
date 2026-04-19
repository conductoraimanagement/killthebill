# Cultural Cameos

> **Status:** Partial implementation — 6 Tier-1 Whisper cameos live. Tier 2–4 arcs are designed below, not yet built. See [src/core/CulturalCameos.gd](../../src/core/CulturalCameos.gd).

## What's implemented today

- `CulturalCameos` autoload evaluates triggers once per news cycle (3× per day).
- **28 cameos live across all four tiers**, with Tier-2+ coverage in 9 of 10 archetype families:

| Tier | Count | Cameos |
|---|---|---|
| **1 (Whisper)** | 10 | `soap_broadcast`, `mask_in_the_crowd`, `compliance_error_7`, `unsigned_manifesto`, `yellow_hymn`, `kindly_coffee`, `last_login_whisper`, `ballad_brick_kid`, `deja_vu_headline`, `indexed_debt_whisper` |
| **2 (Brush)** | 7 | `bread_thief_arc`, `admin_last_login`, `match_man_arc`, `candy_heir_arc`, `project_dust`, `sidewalk_philosopher`, `ledger_leak` |
| **3 (Entanglement)** | 8 | `hermit_substrate_fields`, `yellow_priest_arc`, `fifth_november_arc`, `confectioner_arc`, `pattern_match_arc`, `leak_that_got_her_killed`, `sinks_strike`, `breadline_priest`, `indexed_debt_arc` |
| **4 (Takeover)** | 4 | `soap_man`, `the_revenant`, `the_yellow_king`, `compliance_apotheosis` |

Family-by-family Tier-2+ coverage: chaos_prophet (T2+T4), masked_symbol (T2+T3), lone_manifesto (T2+T3), whistleblower (T2+T3), corporate_priest (T2+T3), cult_of_personality (T3+T4), loop_in_time (T4 only — T2/T3 still open), rogue_ai (T3+T4), folk_hero_from_the_sinks (T2+T3), kindly_stranger (T2+T3).

- Each cameo gates on world state (`public_tension`, `senate_alignment`, `security_presence`) + player profile (`player_chaos_preference`, `player_idealism`, `player_heat`, `player_ruthlessness`, `player_stealth_preference`) + `min_cycle`.
- **Arc lifecycle**: intro NetFeed on trigger → active_arcs tracks TTL + while-active modifiers on each day tick → a matching player action (`sabotage_sector`, `leak_oligarch`, `leak_sector`) completes for the reward → timeout fires a silent-fallout headline.
- **Tier-4 multi-step arcs** (soap_man, the_revenant) use `arc_steps: [...]` with `accept_prompt` → `action_objective` → `binary_decision` steps, surfacing two dedicated HUD modals.
- **At most one Tier-3+ arc concurrent** (MAX_HIGH_TIER_ACTIVE = 1). The world can sustain one hijacking, not three.
- Each cameo fires at most once per run (`fired_ids` tracks; `reset()` clears on new run).
- **HUD**: active arcs render in the JOB BOARD panel (press J) with a `CAMEO T2` / `CAMEO T3` / `CAMEO T4` magenta badge.
- **Unified effect applier** (`_apply_effects`) supports: `credits`, `heat_delta`, `tension_delta`, `senate_alignment_delta`, `security_delta`, `chaos_bump`, `ruthless_bump`, `idealism_bump`, `stealth_bump`. Used by both the legacy single-step reward path and multi-step decision-option effects.

**Tier-4 (Takeover) — 1 arc live**: `soap_man`. Multi-step arc using the new `arc_steps` array:

1. `accept_prompt` — HUD modal pauses the game; player picks TAKE THE SOAP or WALK AWAY. Decline kills the arc with a soft-fallout headline.
2. `action_objective` — waits for the player to sabotage **Finance** (the clearing house / debt ledgers — Fight Club's Project Mayhem literally targeted credit-card companies). NetFeed confirms on match.
3. `binary_decision` — HUD modal with two options (ABSORB / BETRAY) each with flavor text + distinct effects:
   - ABSORB: +2500 cr, tension +15, senate −10, chaos_preference +0.20, headline *"Paper Street's list is yours."*
   - BETRAY: +500 cr, heat +20, tension −5, ruthlessness +0.15, headline *"Your name surfaces in scandal circulation."*

While active: `public_tension +1/day` (the Project hums). Arc-duration 8 cycles. Gates on `public_tension ≥ 50` + `player_chaos_preference ≥ 0.45` + `min_cycle ≥ 6`.

Added `cameo_arc_prompt` and `cameo_arc_decision` signals. HUD owns two new modals — cameo prompt modal (title, body, accept/decline buttons) and cameo decision modal (title, body, N option buttons each with flavor line). Both pause the tree; no ESC out — they're forced choices. CulturalCameos exposes `resolve_prompt(cameo_id, accepted)` and `resolve_decision(cameo_id, option_index)` for HUD to call back.

---

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
