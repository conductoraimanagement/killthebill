## Overview
`WorldDirector.gd` is the central brain of the simulation. It manages the global economy, procedural Oligarchs, generated regions, and the NetFeed event stream.

## Procedural Oligarchs (`oligarchs: Array[OligarchData]`)
4-6 billionaires are generated per playthrough. Each has intrinsic traits (Ruthlessness, Vanity, etc.) and specific Ambitions (Monopolize Supply, Build a Legacy, etc.). They take autonomous actions each world cycle.

## Procedural Regions (`RegionGenerator`)
The world map is generated at start. The `WorldDirector` tracks the `current_region` and applies local dynamics based on the global economy.

## Signal Bus
| Signal | Payload | Description |
|---|---|---|
| `event_triggered` | action_id, target | Fired when any node reports an action. |
| `world_state_changed` | none | Fired after world evolution. |
| `netfeed_event_generated` | event_data | Fired for NEWS_TICKER events. |
| `oligarch_action_taken` | action | Fired when an oligarch takes an AI-driven step. |

## Butterfly Effect Matrix
When `event_triggered` fires, the WorldDirector resolves systemic ripples:
- **Sabotage Food Supply:** `food_price += 50`, `public_tension += 20`, Food Oligarch `paranoia += 30`
- **Assassinate Oligarch:** Target removed, `security_presence += 40`, all surviving Oligarchs `paranoia += 50`
- **Hack Financial System:** Target Oligarch `wealth -= 200`, `tech_price += 30`
- **Leak Scandal:** Target Oligarch `public_image -= 30`, `controversy_level += 40`
- **Exert Political Pressure:** `senate_alignment` shifts based on player traits and faction support

## NetFeed Integration
- `netfeed_history: Array` — Rolling log of all NEWS_TICKER events.
- `trigger_news_cycle()` — Packages `global_economy` + `oligarchs` into JSON and calls `LLMManager.request_netfeed_events()`.
- `_on_netfeed_stream_received(events)` — Processes each event: NEWS_TICKER events are added to history and signaled; SILENT_RIPPLE events are applied silently to the economy.

## Sector Dynamics
Local sector variables (tension modifiers, security modifiers) are derived from the global economy via `_update_sector_dynamics()`. The Sinks have a +20 baseline tension modifier; The Enclave has a -20.
