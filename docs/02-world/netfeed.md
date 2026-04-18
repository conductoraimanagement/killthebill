# NetFeed

> The living narrative engine. A scrolling ticker the player sees, and a silent backchannel the world uses to move without them.

Implemented across: [WorldDirector.gd](../../src/core/WorldDirector.gd) (cycle trigger, event handling) · [LLMManager.gd](../../src/core/LLMManager.gd) (generation).

---

## What it is

The NetFeed is the world's media layer **and** the game's narrator. Every cycle, `WorldDirector.trigger_news_cycle()` packages the economy, the Oligarch states, and recent events into a prompt. The LLM returns a stream of events. Some the player sees. Some shift the world invisibly.

---

## Event types

| Type | Visible to player? | Purpose | Example |
|---|---|---|---|
| `NEWS_TICKER` | **Yes** (scrolling bar + log) | Narrative, flavor, signal what the world noticed | *"Food riots spread to three new sectors"* |
| `SILENT_RIPPLE` | **No** | Systemic drift the world does on its own | *"Enforcers quietly double patrols in the Foundry."* |

Both modify the economy and Oligarch state. The difference is whether the player knows.

---

## Event JSON schema

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

The LLM is instructed:
- event count is **uncapped** — the world generates as many events as the gravity of the state warrants
- quiet periods are valid — it's fine to return `{"events": []}`
- black swans are allowed but should be rare
- events must reference current world variables, not hallucinated ones

---

## Flow

```
WorldDirector.trigger_news_cycle()
  → build context: global_economy + oligarch_summaries + netfeed_history (recent)
  → LLMManager.request_netfeed_events(context)
    → LLM returns {"events": [...]}
  → WorldDirector._on_netfeed_stream_received(events)
    → for each event:
        if NEWS_TICKER:
          netfeed_history.append(event)
          emit netfeed_event_generated → UI ticker
        if SILENT_RIPPLE:
          apply systemic_impact to global_economy / Oligarchs
          (nothing emitted to UI)
```

---

## What the NetFeed does well today

- Hooks exist for both event types.
- Silent ripples already flow into the economy without player awareness.
- LLM prompting is provider-agnostic through [LLMManager](../05-systems/llm.md).

## What's still thin

- No cultural cameo integration yet. See [cultural-cameos.md](../03-characters/cultural-cameos.md) — cameos trigger dedicated NetFeed events with recognizable flavor.
- No cross-cycle narrative threading. Events are episodic. Adding a "running story" field that chains events (a scandal that unfolds over 3 cycles) is a [roadmap](../06-roadmap/phases.md) item.
- No player-addressable feed yet. Eventually the player should be able to search the feed, subscribe to keywords, etc.
- The LLM is not told who's a cameo target — that layer happens in [CulturalCameos](../03-characters/cultural-cameos.md).

---

## Design notes

- **The NetFeed is biased.** The Media Oligarch shapes what the feed says. A strong Media billionaire can suppress scandals; a dead one can't. The feed lies by omission.
- **The feed is not omniscient.** If the player is careful, actions can happen without becoming a headline. Silent ripples affect the world; silent player actions might not.
- **The feed has tone.** It should read like satire — Network-meets-Onion — especially when reporting on billionaires. Gravity comes from contrast with the misery the numbers encode.
