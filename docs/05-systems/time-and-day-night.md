# Time, Day/Night, and the 13-Month Cycle

> **Status:** Implemented. See [src/core/TimeSystem.gd](../../src/core/TimeSystem.gd).

The clock is the game's pulse. A playthrough is a **13-month year** with an absolute deadline — month 14 fires `TIMEOUT_ABSORBED` defeat. Time is partitioned so you can see the world shift around you without the sim getting twitchy, and scaled so long runs stay reasonable at fast-forward.

---

## The units

| Concept | Length | What happens at the boundary |
|---|---|---|
| **Day** | 10 real minutes (600s) | `WorldDirector.run_world_cycle()` — oligarchs act, Senate resolves, jobs expire, NPCs evolve, heat decays, daily food cost drains, NPC deaths + social graph tick |
| **Phase** | ~3:20 real minutes (200s) | `WorldDirector.trigger_news_cycle()` — NetFeed refresh + job board post rolls + cameo trigger evaluation |
| **Week** | 7 days (70 real minutes at 1×) | `TimeSystem.payday` — `PlayerManager.apply_weekly_payday()` runs the WC firing roll, accrues the weekly salary slice if employed, deposits `pending_wages` into `credits` |
| **Month** | 30 days (300 real minutes / 5 real hours at 1×) | `TimeSystem.month_advanced` — Chronicle snapshots last month's recap. **Also fires `TimeSystem.rent_due`** → `PlayerManager.handle_rent_due()` → HUD rent modal `[PAY]/[SKIP]` |
| **Year** | 13 months (390 days / ~65 real hours at 1×) | `TimeSystem.year_ended` — if no victory path fired, `TIMEOUT_ABSORBED` defeat |
| **Frame** | every render frame | `TimeSystem.time_of_day_updated` — lighting, HUD clock, sun position |

Three phases per day: **Morning** → **Afternoon** → **Night**, each exactly 1/3 of a day (200s).

Clock mapping: `tod=0.0` → **06:00**, `tod=0.5` → **18:00**, `tod=1.0` → **06:00 next day**.

- Morning: 06:00 – 14:00
- Afternoon: 14:00 – 22:00
- Night: 22:00 – 06:00

---

## The 13-month narrative arc

Every month belongs to a **pacing band** that multiplies world intensity. Layered on top of reactive mechanics — the world still responds to you, but it also *ages*.

| Months | Band | Cameo prob ×  | Patrol count × | Tension drift/day | Heat decay × | Notes |
|---|---|---|---|---|---|---|
| 1–2 | **Settling** | 0.75 | 0.9 | 0 | 1.0 | Hope decay also paused (severance period) |
| 3–5 | **Pressure** | 1.0 | 1.0 | 0 | 1.0 | Hope decay kicks in at dawn of month 3 |
| 6–9 | **Escalation** | 1.25 | 1.15 | +1 | 1.0 | Passive tension climb begins |
| 10–12 | **Climactic** | 1.4 | 1.3 | +2 | 0.5 | Heat cools half-speed; the world remembers |
| 13 | **Year's End** | 1.6 | 1.5 | +3 | 0.25 | Victory thresholds soften by 10 — the world bends toward resolution |

Month 14 (would-be start) fires `TIMEOUT_ABSORBED`. The year ends. You lost, not by any specific event, but by running out of time.

---

## Day/night visual blend

[LandscapeGenerator](../02-world/landscapes.md) subscribes to `time_of_day_updated` and interpolates sun + ambient + fog between the biome's "day" config and a shared night target along a cosine curve:

```
brightness = (cos( (tod - 0.25) * 2π ) + 1) / 2
# peaks 1.0 at noon (tod=0.25), troughs 0.0 at midnight (tod=0.75)
```

At night:
- Sun drops below horizon, color shifts to pale cobalt, energy cut to ~0.15
- Ambient light shifts to dark blue, energy cut to ~0.18
- Fog color goes near-black, density +40%
- Background color near-black

---

## NPCs and active phases

Every NPC has an `active_phase` field, set at roster generation:

| Social class | Bias | Distribution |
|---|---|---|
| Enforcer | night-biased (patrols) | 35% night, 15% day, 50% both |
| Destitute | day-biased (the night is dangerous) | 30% day, 10% night, 60% both |
| Worker (default) | balanced | 70% both, 15% day, 15% night |

An NPC only appears in the crowd, posts fixer jobs, or participates in the social graph during a phase they're active in. The same fixed 40-person roster breathes differently morning vs. afternoon vs. night.

---

## Fast-forward

| Input | Effect |
|---|---|
| `Space` | Toggle 6× (regular fast-forward) |
| `Shift+Space` | Toggle 24× (super-FF — essential for 13-month runs) |

At 1× the full run is ~65 hours. At 6× it's ~11 hours. At 24× it's ~2.7 hours. Super-FF is how you coast through quiet months waiting for the next beat.

Fast-forward is global. Automatically stops when any modal opens (tree pause propagates through `PROCESS_MODE_INHERIT`). Dialogue, bribe, save, load, cameo prompts, encounter modals — all freeze time while you're looking at them.

---

## Travel costs time

Within a region, the clock keeps ticking while you walk — crossing a 150m map at 5 m/s costs ~1–2 in-game hours naturally.

**Inter-region travel** via the transit pillar explicitly calls `TimeSystem.skip_hours(6)` before regenerating the new landscape. Six game hours pass per jump. The `skip_hours(h)` method properly fires `day_advanced` / `phase_changed` / `month_advanced` / `year_ended` if the jump crosses those boundaries — the simulation catches up mid-travel.

---

## Knobs

| Constant | File | Effect |
|---|---|---|
| `DAY_REAL_SECONDS` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | Whole-run pacing. **600s = 10 min/day.** |
| `DAYS_PER_MONTH` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | 30 today. |
| `MONTHS_PER_YEAR` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | 13 today. |
| `FAST_SPEED` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | 6×. |
| `SUPER_FAST_SPEED` | [TimeSystem.gd](../../src/core/TimeSystem.gd) | 24×. |
| Pacing band multipliers | `pacing_band()`, `cameo_probability_multiplier()`, `patrol_count_multiplier()`, `tension_drift_per_cycle()`, `heat_decay_multiplier()`, `year_end_softness()` | All live in TimeSystem. |

---

## Cross-references

- [Core Loop — second-by-second](../04-player/loop.md) — what the player actually experiences through a 13-month run
- [Progression, Credits & Heat](../04-player/progression.md) — severance period and survival loop
- [Victory & Defeat](../04-player/victory.md) — year-end timeout path
- [Landscape Generator](../02-world/landscapes.md) — where the day/night blend runs
- [NetFeed](../02-world/netfeed.md) — refreshed 3× per day on phase transitions
- [Save and Share](save-and-share.md) — `active_phase` persists in world configs
