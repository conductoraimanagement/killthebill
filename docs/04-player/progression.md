# Progression, Credits, and Heat

> **Status:** Implemented. See [src/core/PlayerManager.gd](../../src/core/PlayerManager.gd), [src/core/GigBoard.gd](../../src/core/GigBoard.gd).

The player's personal economy is where the design gets honest. You were laid off. Savings carry you, for a while. Every move costs something — credits, hope, idealism, time. The only way to keep acting is to do things that compromise the cause a little, or make you more wanted.

One law: **nothing is free.**

> This page is the condensed reference for the player-facing economy. The **[Gigs, Rent & Employment](gigs.md)** page has the narrative walkthrough; this one is the numbers.

---

## The four resources

| Resource | Range | Where it lives | Meaning |
|---|---|---|---|
| `credits` | −∞..∞ | [PlayerManager](../../src/core/PlayerManager.gd) | The wallet, in credits (cr). Can go negative. |
| `heat` | 0..100 | [PlayerManager](../../src/core/PlayerManager.gd) | Enforcer attention. At 100 → `ARRESTED` defeat. |
| `hope` | 0..100 | [PlayerManager](../../src/core/PlayerManager.gd) | Psychological reserve. At 0 → `DESPAIR` defeat. |
| `homeless` | bool | [PlayerManager](../../src/core/PlayerManager.gd) | Lost the apartment. Extra hope drift, no home computer → no Gig Board. **Not a defeat.** |

Plus two accumulators that feed payday deposits:

| Field | Meaning |
|---|---|
| `pending_wages` | Gig + WC-salary wages that accrue between Mondays. Deposited weekly via `TimeSystem.payday`. |
| `pending_wages_breakdown` | `source → cr subtotal` for the HUD toast breakdown. |

---

## Starting class seeds

See [`PlayerManager.initialize_run`](../../src/core/PlayerManager.gd).

| Seed | credits | intel | social | hope | Framing |
|---|---|---|---|---|---|
| **WHITE_COLLAR** | 50,000 cr | 100 | −50 | 55 | Laid off last month. Severance + liquidated 401(k). A year's frayed cushion if you're careful. Hope is fragile because you had more to lose. |
| **BLUE_COLLAR** | 29,000 cr | 10 | 80 | 45 | Union layoff. Severance + cashed-out savings. Covers the year if nothing goes wrong — and something always goes wrong. Social capital is your edge. |

Also rolled at run-start, once per run, fixed for the playthrough:

- **`monthly_rent`** — `randi_range(700, 2000)` cr. A lucky Sinks studio rolls cheap; an Enclave-adjacent 1BR rolls expensive.

No future "syndicate / journalist / veteran" seeds yet — the two core seeds lock in the class-anxiety premise.

---

## Severance period (months 1–2)

The year doesn't start at full intensity. Months 1 and 2 are the **severance period**:

- Rent is still due on the 1st of each month (the landlord doesn't wait).
- Daily food + utilities still drain.
- **Hope decay is suspended.** No passive drift.
- All other mechanics (heat, cameos, Senate, NPC social graph) proceed.

At the start of month 3, severance ends. A NetFeed note fires:
*"Your severance ran out this morning. The weight finds you now. Hope starts to drift."* From that moment, the decay curve below kicks in.

Design intent: two months of breathing room to meet people, read the world, pick a path. Past that, the clock presses.

---

## Daily survival tick

`WorldDirector.run_world_cycle` (once per day) calls `PlayerManager.apply_daily_tick(economy)`:

```
# Food & utilities — scales with food_price. Homeless: exposure tax.
daily_cost = 25 + max(0, (food_price - 100) / 3)
if homeless:
    daily_cost += 8                                   # exposure tax
daily_cost *= rent_drain_multiplier                    # ×1.15 during Finance shock
credits -= daily_cost

# Hope decay — outside severance only.
hope_delta = -1                                        # baseline drift
           - 1 if credits < 0
           - 1 if heat > 60
           - 1 if homeless
           - 0.5 if rent_arrears_months >= 1          # envelope says FINAL NOTICE
           - 1 if month >= 10                          # endgame weighs
hope += hope_delta

if hope <= 0 → fire_defeat("DESPAIR_WITHDRAWAL", ...)
```

**Rent is NOT in the daily tick.** Rent is a monthly decision — see below.

---

## Monthly rent — the decision

On the 1st of each in-game month, `TimeSystem.rent_due` fires. `PlayerManager.handle_rent_due()` emits the `rent_due_prompt` signal and the HUD opens a forced modal that pauses the game:

> **// RENT DUE** — landlord wants his check. This month's rent: **X cr**. `[PAY]` / `[SKIP]`

- **Pay** → `PlayerManager.pay_rent()` drains `monthly_rent × (arrears_months + 1)` from credits. Can go negative. +2 hope, arrears cleared.
- **Skip** → `PlayerManager.skip_rent()` increments `rent_arrears_months`. −4 hope. NetFeed note.

If `rent_arrears_months` hits **2** at a rent-due tick, eviction fires: `homeless = true`, −10 hope. **Not a run-ender** — it's a state. Re-housing via the Shop costs one month's rent as deposit.

The Finance oligarch, if one rolled at run-start, is attributed as the holder of your rent debt via `debt_held_by_oligarch_id`. Killing that oligarch or triggering an Indexed-Debt-style jubilee wipes the attribution.

---

## Weekly payday

`TimeSystem.payday` fires every 7th day (`day % 7 == 0`). `PlayerManager.apply_weekly_payday()`:

1. **Firing roll (if WC-employed)** — 10% chance per week fires `_fire_from_wc_role()`. −5 hope, NetFeed toast, employment ends. Any wages already accrued for that week still deposit.
2. **Weekly salary slice** — if still employed, `monthly_salary / 4` accrues as a `wc_salary:[Company]` source.
3. **Deposit** — all `pending_wages` dump into `credits`. `payday_deposited(amount, breakdown)` fires for the HUD toast.

NetFeed toast example:
*"PAYDAY: 1,245 cr deposited. (waiter 420 cr, dishwasher 180 cr, wc_salary:Paperclip & Thorne, LLP 645 cr)"*

---

## Income sources

### 1. Gig shifts — the compliance floor ✓ *(implemented)*

Open GIG BOARD with **`G`** (home computer required — fails when homeless). Gigs are region-gated and apply via number keys `1`–`6`:

| Gig | Regions | Hours | Pay | Notes |
|---|---|---|---|---|
| Dishwasher | any | 3h | 36–48 cr | |
| Street sweep | any | 3h | 42–54 cr | |
| Trash hauler | INDUSTRIAL | 4h | 54–72 cr | |
| Delivery runner | URBAN_SLUM, TRANSIT | 3h | 30–54 + tip 0–22 | |
| Waiter | URBAN_ELITE | 3h | 30–45 + tip 0–60 | Highest ceiling, worst humiliation |
| Day-labor | INDUSTRIAL | 4h | 60–84 cr | |

**40% silent denial** on apply (30 game-min wasted). On accept: game time skips `hours`, wages accrue to `pending_wages`, a humiliation dialogue line fires, 1–3 hope drained, −0.02 idealism drift.

See [gigs.md](gigs.md) for the full gig catalog + humiliation pool.

### 2. White-collar salaried role ✓ *(implemented)*

Listings appear below gigs, **always present**, refresh weekly. Apply with **`Shift+1`–`Shift+4`**. Triggers a 3-question absurdist interview gauntlet (LLM-generated per interview when an API key is configured; offline-pool fallback otherwise). Posted monthly salaries 2,000–4,000 cr.

**95% rejection** — letter compiled from the specific answers picked. 2 game-hours + 3–5 hope cost. **5% acceptance** — +15 hope, monthly salary paid in 4 weekly slices, 10% weekly firing roll. See [gigs.md](gigs.md).

### 3. Loot from sabotage ✓ *(implemented)*

Sabotaging a facility drops credits in addition to the economy ripple. Payout scales with sector.

| Sector | Base payout | Heat | Why |
|---|---|---|---|
| Food | 300–600 cr | +3 | Warehouses, pallets of rations |
| Tech | 500–900 cr | +4 | Server racks worth black-market gold |
| Pharma | 600–1000 cr | +4 | Every capsule is cash |
| Energy | 400–700 cr | +3 | Copper, rare earths |
| Security | 200–400 cr | +5 | Gear + arrest risk |
| Media | 200–500 cr | +2 | PR assets, less tangible haul |
| **Finance** | **800–1,400 cr** | **+6** | A clearing-house hit is a vault hit. Also fires `apply_finance_shock()`: rent drain ×1.15 for 10 days + food/tech +30 + tension +20 |

**Tradeoff**: every sabotage raises public tension, attracts Enforcers, and identifies you as a threat.

### 4. Sell scandal to Media oligarch ✓ *(implemented)*

You've surfaced dirt on an oligarch. Two paths:

- **LEAK** (free, existing): NetFeed picks it up. `public_image` of target tanks, `public_tension` up, `senate_alignment` drifts populist.
- **SELL** (money, corrupt): Media Oligarch buys the scoop to shelve it. You get paid; scandal never surfaces. Target's `controversy_level` drops, `senate_alignment` shifts corporate.

```
payout ≈ 500 + target.controversy_level × 30 + 1000 if Media oligarch alive
```

**Tradeoff**: money now, strengthened Enclave later. Bumps `player_ruthlessness`.

### 5. Resistance cell contract ✓ *(implemented)*

Each news cycle, the game rolls ~65% odds of posting an underground cell contract targeting the sector of an oligarch the resistance hates most (weighted by `awareness_of_player` + `paranoia` + aggressive ambitions). NetFeed: *"Underground broadcast on a pirate frequency — The Red Circle wants X's operations damaged."*

Any sabotage of the target sector within 3 cycles pays the full bounty (**500–2,500 cr**) out of **black-market funds**. No oligarch transacts with the player.

On completion: `+bounty` credits, `+4` hope, NetFeed thank-you.

Cell pool: The Red Circle, Paper Street Crew, The Ash Underground, The Sinks Collective, The Unlicensed Dispatch, The Thirteenth Hour, The Rust Coalition, The Night Shift, The Gutter Press, The Unindexed.

### 6. Fixer jobs from NPCs ✓ *(implemented)*

NPCs with `trust >= 30` can post a fixer job via NetFeed: *"Fixer signal in the Sinks — Jon Holt wants the Food sector disrupted. They say it's personal."*

Two flavors:

- **Disrupt sector**: sabotage a random sector. Pays **200–400 cr**.
- **Leak on oligarch**: leak on a specified oligarch. Pays **150–350 cr**.

On completion: `+bounty` credits, `+5` hope, fixer NPC's `trust +15`.

### 7. Pickpocket ✓ *(implemented)*

Walk within ~2.6m of a crowd NPC → `[E] Pickpocket {name}`.

```
chance = clamp(0.50 + player_stealth_preference × 0.40 - target.conformity × 0.10, 0.15, 0.90)
```

| Outcome | Effect |
|---|---|
| Success | +20–80 cr, +1 heat, target's `opinion_of_player −0.05`, silent NetFeed ripple |
| Failure | +3 heat, target `knowledge_of_player +0.30`, `opinion −0.15`, NetFeed alert, target bolts |

**Tradeoff**: reliable trickle but heat compounds. One failed roll at heat 80+ cascades into arrest.

### 8. Hack the grid ✓ *(implemented)*

Datashard Terminal menu → `HACK THE GRID`. Flows through the Tech oligarch by default. Retargets to the Finance oligarch first if one exists.

- `+1500–3000 cr` (biggest single payout)
- `+8 heat`
- Target oligarch: `wealth −15000`, `paranoia +30`, `awareness_of_player +25`
- `security_presence −20` (grid blinded temporarily)
- `player_chaos_preference +0.06`, `player_stealth_preference +0.15`

**Tradeoff**: top income mechanism, but the victim oligarch hunts harder each repeat.

---

## Spending sinks

### Shop at the Datashard Terminal ✓ *(implemented)*

| Item | Cost | Effect |
|---|---|---|
| Forged IDs | 500 cr | `heat −25` instantly |
| Burner Datashard | 1,500 cr | Reveals the current bill's `honest_rationale` + `scandal_hooks` in the Senate panel while the bill is in debate |
| Secure Housing (if homeless) | one month's rent (700–2,000 cr) | `homeless = false`, +8 hope — deposit scales with the run's rolled `monthly_rent` |

### Bribes ✓ *(implemented)*

**Politician (Datashard Terminal → LOBBY POLITICIAN):**
```
cost = 2000 × (1 − scandal_level/100) × (1 − corruption)     # clamp ≥ 100
```
A scandal-riddled, corrupt senator runs ~100 cr; a clean one, up to 2,000 cr. +2 heat per bribe. One vote only.

**Enforcer (encounter modal, heat ≤ 80):** base 200 cr + 200 cr per 20 heat.

### Sabotage / leak-scandal ✓

No credit cost, but heat cost and world-state cost.

### Designed, not yet implemented

| Action | Cost range | What it unlocks |
|---|---|---|
| Buy intel from a fixer | 200–800 cr | Reveals a random oligarch's current ambition |
| Safehouse bribe | 200/cycle | Passive heat decay while paid up |
| Black-market weapon | 800–2500 cr | Unlocks the combat lever (future) |
| Recruit cameo operative | 3000+ cr | When a cameo arc resolves with recruitment |

---

## Hope restoration — what makes you keep going

| Action | Hope Δ |
|---|---|
| Sabotage a facility | +3 — you hit back |
| Hack the grid | +4 — biggest hit |
| Leak scandal publicly | +2 |
| Fixer job completion (NPC who trusts you) | +5 |
| Resistance-cell contract completion | +4 |
| Cameo arc resolved | +3 baseline (can be overridden per-arc) |
| **Hired at a WC role** | +15 — the hook sinks in |
| **Rent paid on time** | +2 |
| **Securing housing after homelessness** | +8 |
| Sell scandal to Media (corrupt) | −2 |
| Pickpocket a neighbor (success) | −1 |
| Bribe a senator | −1 |
| **Gig shift completed** | −1 to −3 (humiliation dialogue line) |
| **WC interview rejected** | −3 to −5 |
| **Partner death** | −40 / −20 / −15 / −10 (scales inversely with partner count) |
| **Rent skipped** | −4 |
| **Evicted** | −10 |
| **Fired from WC role** | −5 |

Rhythm: a player actively doing resistance work gains ~+10 hope per good day; a pure-compliance grinder bleeds ~−4 hope per day from gig humiliation alone.

---

## Playstyle trackers

`PlayerManager.bump_playstyle(chaos, ruthlessness, idealism, stealth)` nudges four cumulative floats in `[0, 1]`. Read by `CulturalCameos` to gate archetype eligibility:

| Tracker | Nudged up by | Used by |
|---|---|---|
| `player_chaos_preference` | Sabotage, hack | `chaos_prophet` arcs (Soap Man, Project Dust) |
| `player_ruthlessness` | Sell-scandal, assassinate, betray | `kindly_stranger` gates OFF at high values |
| `player_idealism` | Leak publicly, cell jobs, Bread Thief | `folk_hero_from_the_sinks`, `whistleblower` arcs |
| `player_stealth_preference` | Pickpocket, hack | `rogue_ai` arcs, low-profile cameos |

Gigs and WC interviews both drift `player_idealism` downward — the compliance path costs you your capacity to see cameos that reward conviction.

---

## Heat system

`heat` is 0–100, capped. Raises on illegal acts:

| Event | Heat delta |
|---|---|
| Sabotage a facility | +2 to +6 (see sector table) |
| Sell scandal to Media | +2 |
| Bribe a politician | +2 |
| Pickpocket / mug | +1 to +3 |
| Hack financial grid | +8 |
| Assassinate oligarch | sets heat to max |
| Cycle tick (passive) | −1 × `TimeSystem.heat_decay_multiplier()` (halved in Climactic band, quartered in Year's End) |

Threshold effects:

| Threshold | Effect |
|---|---|
| `heat ≥ 30` | NetFeed warning: *"Enforcer patrols thicken near the Sinks."* |
| `heat ≥ 60` | NetFeed warning: *"Compliance AI flags a person of interest."* |
| `heat ≥ 80` | Bribe costs **doubled**; NetFeed: *"Arrest warrants issued…"* |
| `heat == 100` | `ARRESTED` defeat. |

Cooling mechanisms:
- Passive decay (−1/day × pacing multiplier)
- **Forged IDs** at the Shop: 500 cr for −25 heat

See [heat.md](heat.md) for Enforcer encounter mechanics.

---

## UI

The HUD state panel (top-left) shows:

```
credits            29000  cr        (color cyan if ≥ 1000, fg > 200, dim ≤ 200)
pending wages      +420   cr        (only shown if > 0)
rent                1200  cr/mo
arrears             1 month(s) unpaid   (only shown if > 0)
heat                  34  / 100     (hot red > 60, warn yellow > 30, fg otherwise)
hope        ▓▓▓▓░░░░░░  42
housing             HOMELESS              (only shown when homeless)
```

Updates flow via signals (`credits_changed`, `heat_changed`, `hope_changed`, `housing_status_changed`, `pending_wages_changed`) — the HUD never polls.

---

## What the player can't do (by design)

- **Farm endless credits without consequences.** Every income source raises heat, erodes hope, or drifts idealism.
- **Buy victory.** Credits can't directly move global economy variables. They can only pay for *actions* that move them.
- **Grind only the compliance path to safety.** Gigs cover rent, but the hope bleed + idealism drift makes DESPAIR likely before month 13.
- **Grind only the resistance path to safety.** Sabotage covers rent, but heat caps trigger ARRESTED before month 13.

The year is survivable. Not cleanly.

---

## Cross-references

- [Gigs, Rent & Employment](gigs.md) — the narrative walkthrough for the compliance layer
- [PlayerManager](../../src/core/PlayerManager.gd) — source of truth for `credits`, `heat`, `hope`, `homeless`, rent, employment
- [GigBoard](../../src/core/GigBoard.gd) — gig catalog + WC listings + interview gauntlet
- [TimeSystem](../../src/core/TimeSystem.gd) — `day_advanced`, `payday`, `rent_due`, `month_advanced` signals
- [WorldDirector](../../src/core/WorldDirector.gd) — ripples call `PlayerManager.add_credits`/`add_heat`/`add_hope`
- [Politicians](../03-characters/politicians.md) — bribe mechanics
- [Oligarchs](../03-characters/oligarchs.md) — sell-scandal, Finance debt attribution
- [The Senate](../02-world/senate.md) — bribes resolve when `_tally_and_resolve` runs
- [Cultural Cameos](../03-characters/cultural-cameos.md) — cameos gate on `player_*_preference` trackers; rewards are world-shift + narrative payoffs, never cash
