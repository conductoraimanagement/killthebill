# Time, Day/Night, and Fast-Forward

> **Status:** Implemented. See [src/core/TimeSystem.gd](../../src/core/TimeSystem.gd).

The clock is the game's pulse. One real minute ≠ one in-game minute; one real minute feels like a long afternoon. Time is partitioned so you can see the world shift around you without the sim getting twitchy.

---

## The units

| Concept | Length | What happens at the boundary |
|---|---|---|
| **Day** | 5 real minutes (300s) | `WorldDirector.run_world_cycle()` — oligarchs act, Senate resolves, jobs expire, NPCs evolve, heat decays |
| **Phase** | ~1:40 real minutes (100s) | `WorldDirector.trigger_news_cycle()` — NetFeed refresh + job board post rolls |
| **Frame** | every render frame | `TimeSystem.time_of_day_updated` — lighting, HUD clock, sun position |

Three phases per day: **Morning** → **Afternoon** → **Night**, each exactly 1/3 of a day (100s).

Clock mapping: `tod=0.0` → **06:00**, `tod=0.5` → **18:00**, `tod=1.0` → **06:00 next day**.

- Morning: 06:00 – 14:00
- Afternoon: 14:00 – 22:00
- Night: 22:00 – 06:00

---

## Day/night visual blend

[LandscapeGenerator](landscape-generator.md) subscribes to `time_of_day_updated` and interpolates sun + ambient + fog between the biome's "day" config and a shared night target along a cosine curve:

```
brightness = (cos( (tod - 0.25) * 2π ) + 1) / 2
# peaks 1.0 at noon (tod=0.25), troughs 0.0 at midnight (tod=0.75)
```

At night:
- Sun drops below horizon, color shifts to pale cobalt `(0.30, 0.38, 0.62)`, energy cut to ~0.15
- Ambient light color shifts to dark blue `(0.12, 0.14, 0.22)`, energy cut to ~0.18
- Fog color goes near-black, density +40%
- Background color near-black
- Shadows become moonlight-soft

At dawn/dusk (`tod ≈ 0.0` or `0.5`), brightness = 0.5 — a warm orange blend. The biome's `sun_color` (e.g. rust-orange for URBAN_SLUM, pale gold for URBAN_ELITE) gives each region its own sunset mood.

---

## NPCs and active phases

Every NPC has an `active_phase` field, set at roster generation:

| Social class | Bias | Distribution |
|---|---|---|
| Enforcer | night-biased (patrols) | 35% night, 15% day, 50% both |
| Destitute | day-biased (the night is dangerous) | 30% day, 10% night, 60% both |
| Worker (default) | balanced | 70% both, 15% day, 15% night |

An NPC only posts fixer jobs during a phase they're active in. A night-only fence won't appear on the job board at 10:00 in the morning. This is the cheapest way to make a fixed roster *feel alive* — the same NPCs are always there, but *when* matters.

`active_phase` is serialized in [world configs](save-and-share.md), so a shared world reproduces the same nocturnal fences and early-rising agitators for every player.

---

## Fast-forward

Press `Space` (when no modal is open) → toggle 6× time scale. Lighting, simulation, NetFeed, and Senate all speed up proportionally — it's a direct `time_scale` multiplier on `_process(delta)`. Press `Space` again to resume 1×.

The HUD's "day" row shows `▶▶ 6×` in accent color when fast-forward is on.

Fast-forward is global, pure speed-up, and pauses automatically when any modal opens (tree pause propagates through `PROCESS_MODE_INHERIT`). This is the "activity automation" surface — when you accept a job and have nothing to do but wait for the next cycle, hold Space.

Planned: a **"skip to next event"** control (next bill proposed / next job posted / resolution of active bill) that fast-forwards then snaps back to 1× on the triggering event.

---

## Why one-cycle-per-day (not per phase)?

A full world cycle is expensive — oligarchs evaluate ambitions, the Senate tallies a bill, NPCs evolve 40× through their `process_world_pressure`, the job board clears expired items, heat decays. Doing that every ~100s feels right (one bill per day, one oligarch move per day). Doing it per phase (~33s) would drown the player in notifications and remove any feeling of *waiting for the next day*.

NetFeed and job board, by contrast, refresh 3× per day — fast enough to feel reactive, slow enough that each headline has weight.

---

## Knobs

| Constant | File | Effect |
|---|---|---|
| `DAY_REAL_SECONDS` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | Whole-run pacing. 300s = 5 min/day. |
| `PHASES_PER_DAY` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | 3 today. Increasing it adds NetFeed density. |
| `FAST_SPEED` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | How fast Space makes time. 6× today. |
| `_NIGHT_*` colors | [LandscapeGenerator.gd](../../src/core/LandscapeGenerator.gd) | The night palette all biomes blend toward. |
| `active_phase` distribution | [PopulationDirector.gd](../../src/core/PopulationDirector.gd) | How many NPCs are reachable at any phase. |

---

## Cross-references

- [Core Loop — second-by-second](../04-player/loop.md) — what the player actually experiences during those 5 minutes
- [Landscape Generator](landscape-generator.md) — where the day/night blend runs
- [NetFeed](../02-world/netfeed.md) — refreshed 3× per day on phase transitions
- [Job Board](../04-player/progression.md#income-mechanisms) — posts align to the news cycle
- [Save and Share](save-and-share.md) — `active_phase` persists in world configs
