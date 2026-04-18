# NetFeed Event Stream — Technical Reference

## Overview
The NetFeed is the game's living narrative engine. It uses the LLM to evaluate the "complex conjecture" — the intersection of all world variables — and generate an organic stream of events that shape the world in real time.

## Event Types
| Type | Visible to Player? | Example |
|---|---|---|
| `NEWS_TICKER` | Yes (scrolling ticker UI) | "Food riots erupt in Sector 7" |
| `SILENT_RIPPLE` | No (invisible systemic shift) | "Enforcers quietly double patrols" |

## Data Flow
1. `WorldDirector.trigger_news_cycle()` is called
2. WorldDirector calls `LLMManager.request_netfeed_events(global_economy, oligarchs)`
3. LLM evaluates the conjecture and returns `{"events": [...]}`
4. `WorldDirector._on_netfeed_stream_received()` processes each event:
   - **NEWS_TICKER:** Appended to `netfeed_history`, emits `netfeed_event_generated` for UI
   - **SILENT_RIPPLE:** Systemic impact applied silently to economy variables

## Event JSON Schema
```json
{
  "events": [
    {
      "type": "NEWS_TICKER",
      "headline": "Food riots spread to three new sectors",
      "systemic_impact": "public_tension +15, food_price +20"
    },
    {
      "type": "SILENT_RIPPLE",
      "headline": "",
      "systemic_impact": "Security Oligarch quietly funds militia"
    }
  ]
}
```

## Design Notes
- Event count is **uncapped** — the LLM decides how many events are warranted based on the gravity of the world state.
- Not every cycle generates events. Quiet periods are valid.
- Black swan events (rare, high-impact) are possible but should be infrequent.
- Events can be consequences of player actions, Oligarch decisions, or completely random.
