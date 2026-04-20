# Victory and Defeat

> **Status:** Implemented. See [src/core/WorldDirector.gd](../../src/core/WorldDirector.gd) `_check_systemic_collapse()` + `_fire_victory()`, and [src/core/PlayerManager.gd](../../src/core/PlayerManager.gd) `fire_defeat()`.

Four ways to win. Two ways to lose. All checked every world cycle; the first one to fire ends the run. A `_victory_locked` flag ensures only one condition wins per playthrough so you don't get a cascade.

---

## The four victory paths

All live at once. The player rarely commits to one from the start — the world's state at cycle 20 decides which is closest.

| Path | Trigger | Flavor | How you get there |
|---|---|---|---|
| **DIRECT ACTION** | all oligarchs' `alive == false` | *"All oligarchs eliminated. The Enclave falls. A new order writes itself."* | Assassinate them one by one. The rarest path — costs heat every time, oligarchs spike paranoia in reaction. |
| **POLITICAL REVOLUTION** | `public_tension == 100` | *"Tension hits 100. The masses storm The Enclave. The NetFeed goes silent."* | Stack food-price spikes, Enforcer brutality, leaked scandals. Tension snowballs once NPCs start radicalizing. |
| **POLITICAL REFORM** | `senate_alignment == 0` | *"Senate alignment collapses. Corporate charters dissolved by vote."* | Pass populist / reform bills, bribe politicians to vote pro-Sinks, leak scandals on senators until Corporate Bloc fractures. |
| **SYSTEMIC COLLAPSE** | combined living-oligarch wealth `< 100000` | *"Combined oligarch wealth collapses below survival. The Enclave is bankrupt."* | Repeated sabotage, hacks, rival contracts. Each oligarch hemorrhages 10k–15k per hit. Endgame grind. |

Each fires `WorldDirector.victory_achieved(kind, title, flavor)` exactly once; HUD shows the end-of-run modal with `// VICTORY //` accent-orange banner and 4 buttons: SAVE WORLD, LOAD WORLD, RESTART, CONTINUE (sandbox).

---

## The four defeat paths

| Path | Trigger | Flavor |
|---|---|---|
| **ARRESTED** | `PlayerManager.heat == 100` | *"Heat maxed. Compliance AI picked up your scent; Enforcers kicked the safehouse door at dawn."* |
| **SURRENDERED** | SUBMIT on an Enforcer encounter modal | *"You walked up with hands visible. The shackles came out. The Enclave breathes easier tonight."* |
| **DESPAIR_WITHDRAWAL** | `PlayerManager.hope == 0` | *"You stopped leaving the apartment three days ago. The NetFeed moved on. The run ended quietly, the way most of them do."* |
| **TIMEOUT_ABSORBED** | Month 14 reached without a victory | *"Thirteen months passed. No oligarch fell by your hand. No revolution took the streets. No reform passed the chamber. No collapse bent the Enclave's balance sheet. The year ended. The year absorbed you."* |

All four route through `PlayerManager.fire_defeat(kind, title, flavor)` (or for ARRESTED, automatically from `add_heat` at cap) → HUD shows the same end-of-run modal, but with `// DEFEAT //` **hot-red banner** and the title in hot-red too.

---

## Goal-choice modal (run start)

Fresh playthroughs (not loaded from a world config) open with a forced prompt: `// 13 MONTHS — One goal. Pick it, or let the year decide.` Five options:

| Choice | What wins your run |
|---|---|
| `DIRECT_ACTION` | Only direct-action triggers victory |
| `POLITICAL_REVOLUTION` | Only revolution triggers victory |
| `POLITICAL_REFORM` | Only reform triggers victory |
| `SYSTEMIC_COLLAPSE` | Only collapse triggers victory |
| `ANY` (let the year decide) | Any victory path triggers, same as legacy behavior |

Stored in `PlayerManager.chosen_victory_path`. When a non-chosen path *would* fire, `WorldDirector._maybe_fire_victory` notes it in the NetFeed — *"A POLITICAL REVOLUTION condition fired — but that wasn't the path you chose. The run continues."* — and the year rolls on.

Option B from the 13-month design is the default mode: committed to a single narrative.

---

## Ordering and ambiguity

Checks run in this order in `_check_systemic_collapse()`:

```
1. DIRECT_ACTION         (all oligarchs dead)
2. POLITICAL_REVOLUTION  (tension == 100)
3. POLITICAL_REFORM      (senate_alignment == 0)
4. SYSTEMIC_COLLAPSE     (total wealth < 100k)
```

If two would trigger the same cycle (e.g., you assassinate the last oligarch while tension happens to also be 100), **the first in order wins**. DIRECT_ACTION beats revolution beats reform beats collapse. This is a design choice — direct elimination is the loudest, "earned" ending, so it gets first claim.

---

## Rolling credits (no credits)

There is no credits sequence. The end-of-run modal is the ending — title, flavor, buttons. The player's next act is typically **VIEW CHRONICLE** (see the 13-month story laid out in text), then SAVE WORLD (bookmark the seed that produced this outcome), then RESTART or CONTINUE.

### Buttons on the end-of-run modal

| Button | Effect |
|---|---|
| **SAVE WORLD** | Opens the Save modal — capture this run's world config as a JSON file |
| **LOAD WORLD…** | Opens the Load modal — pick a saved config to start a new run |
| **VIEW CHRONICLE** | Opens the Chronicle — 13 monthly recaps laid out as narrative text, exportable to clipboard |
| **RESTART** | Reload current scene — fresh procedural roll |
| **CONTINUE (sandbox)** | Keep world running post-victory; other conditions still fire in the aftermath |

See [Save and Share](../05-systems/save-and-share.md) for how world configs work, and `Chronicle` autoload source for the run artifact.

---

## What's not a victory

Things that *feel* like endings but aren't:
- **An oligarch eliminated** — rival oligarchs redistribute; others get richer. The Enclave is resilient.
- **Your credits hit zero** — PlayerManager doesn't fire defeat on broke. Being poor is the default.
- **A run of bad cycles** — the sim keeps ticking; something will shift.
- **A cameo arc resolves badly** — affects the run but doesn't end it.
- **Eviction** — skipping rent two months in a row flips the `homeless` state (no more apartment, no home computer → can't easily browse gigs, +$8/day food cost, −1 hope/day drift). *Not* a defeat. You survive on the street, and only `hope == 0` (DESPAIR) fires the run-ender.

The only run-enders are the four above.

---

## Cross-references

- [Core Loop](loop.md) — the day rhythm these conditions check against
- [Progression](progression.md) — the heat sources that drive defeat path 1
- [Heat & Enforcement](heat.md) — the Enforcer encounter modal that drives defeat path 2
- [The Senate](../02-world/senate.md) — reform path driver
- [Oligarchs](../03-characters/oligarchs.md) — direct action and collapse path drivers
- [NetFeed](../02-world/netfeed.md) — coverage of the ending state
