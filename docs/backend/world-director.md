# WorldDirector — Technical Reference

## Overview
`WorldDirector.gd` is the central brain of the simulation. It operates as an Autoload Singleton, managing the global economy, Oligarch PR states, the Butterfly Effect matrix, and the NetFeed event stream. It runs independently of the visual scene, simulating the economy even for sectors the player is not in.

**Script:** `src/core/WorldDirector.gd`  
**Type:** Autoload Singleton (Node)

## Global Economy Dictionary (`global_economy`)
| Variable | Type | Default | Description |
|---|---|---|---|
| `food_price` | int | 100 | Base cost of rations. Drives NPC survival needs. |
| `tech_price` | int | 500 | Cost of hacking tools and black market weapons. |
| `public_tension` | int | 50 | How close The Sinks are to riot (0-100). |
| `security_presence` | int | 50 | Enforcer patrol frequency and response time (0-100). |
| `senate_alignment` | int | 0 | Political control: -100 (Reformist) to 100 (Corporate). |

## Oligarchs Dictionary (`oligarchs`)
Each of the 4 Oligarchs (Tech, Food, Security, Media) is tracked with:
| Variable | Type | Description |
|---|---|---|
| `wealth` | int | Current liquid assets. Drives economic decisions. |
| `paranoia` | int | How fearful they are (0-100). Increases security spending. |
| `public_image` | int | How loved/hated by the public (-100 to 100). |
| `controversy_level` | int | How actively discussed (0-100). Multiplies PR event impact. |
| `recent_scandals` | Array[String] | Rolling ledger of recent quotes/actions. |

## Signal Bus
| Signal | Payload | Description |
|---|---|---|
| `event_triggered(action, target)` | String, String | Fired when any node reports an action. |
| `world_state_changed` | none | Fired after the Butterfly Effect resolves. |
| `netfeed_event_generated(event)` | Dictionary | Fired for each NEWS_TICKER event for UI consumption. |

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
