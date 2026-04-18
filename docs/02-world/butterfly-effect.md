# Butterfly Effect

> Every player action ripples. Nothing is isolated.

The Butterfly Effect is the rule that makes the game an immersive sim instead of a checklist: a single move mutates the economy, the Oligarchs' paranoia, the NPCs' psychology, and the NetFeed — often in ways the player didn't intend.

Implemented in: [WorldDirector.gd](../../src/core/WorldDirector.gd) (`trigger_event()` and the `_ripple_*` functions).

---

## Matrix

| Action (`event_triggered`) | Direct impact | Ripple impact |
|---|---|---|
| `sabotage_facility` (Food) | `food_price +200` | `public_tension +15`, `security_presence +10`, Food Oligarch: `wealth -50000`, `paranoia +20` |
| `sabotage_facility` (Tech) | `tech_price +100` | Tech Oligarch: `wealth -50000`, `paranoia +20`, `security_presence +5` |
| `assassinate_oligarch` | Target `alive = false` | `public_tension +40`, all survivors: `paranoia +30`, `awareness_of_player +40`; if Media: everyone's `controversy_level = 100` |
| `hack_grid` | `security_presence -20` | Tech Oligarch: `wealth -10000` |
| `exert_political_pressure` (Sinks) | `senate_alignment -10` | `public_tension -5` |
| `exert_political_pressure` (Enclave) | `senate_alignment +10` | `security_presence +5` |
| `leak_scandal` | Target `public_image -30` | Target `controversy_level +50`, scandal added to `recent_scandals` |
| `travel` | `current_region` changes | Region unlocked on arrival if first visit |

---

## How ripples propagate

1. Player triggers action via `WorldDirector.trigger_event(action_id, target)`
2. `_ripple_<action>()` applies direct changes to economy + targeted Oligarch
3. All Oligarchs' surviving `process_world_state()` will see the new state next cycle
4. All NPCs' `process_world_pressure()` will see the new state next cycle
5. `_update_region_dynamics()` re-derives per-region modifiers
6. `_check_systemic_collapse()` evaluates all three [victory paths](../04-player/victory.md)
7. `world_state_changed` emits → UI refreshes

---

## Second-order effects

The direct matrix is the *floor*. The interesting ripples are emergent:

- **Leak a scandal on the Media Oligarch** → Media loses influence → other Oligarchs' scandals stop getting suppressed → every subsequent scandal hits harder.
- **Assassinate the Food Oligarch** → power vacuum → other Oligarchs' greed responses race to capture market share → food prices oscillate → Workers radicalize faster.
- **Sabotage a Transit region** → trade routes break → agricultural regions can't ship → food price spike *without* the player touching agriculture.
- **Kill a paranoid Oligarch with an "Escape" ambition** → their offshore wealth evaporates unused → surviving Oligarchs' paranoia doesn't have an easy "escape" reference point, so they shift to "Crush the resistance" instead.

Most second-order effects are not coded as explicit cases — they fall out of the Oligarchs' autonomous behavior + the NPC Nature/Nurture model. **This is intentional.** Don't script them.

---

## Invisible ripples

The NetFeed also emits `SILENT_RIPPLE` events that mutate the world without the player's knowledge. See [netfeed.md](netfeed.md). These are how the world keeps moving when the player is careful or idle — the system does not wait for the player, per [pillar 5](../01-vision/pillars.md#5-the-world-does-not-wait).

---

## Design notes

- **No ripple is undo-able.** The world state persists across deaths (see [progression.md](../04-player/progression.md)). Mistakes are canon.
- **Ripples should be legible, eventually.** The player doesn't need to predict the chain, but they should be able to *trace* it after the fact. The NetFeed is the explanation device.
- **When adding a new action, add it to the matrix.** If it doesn't deserve an entry here, it probably shouldn't be in the game.
