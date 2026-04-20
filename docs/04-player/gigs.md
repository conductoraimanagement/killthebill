# Gigs, Rent & Employment

> **Status:** Implemented. See [src/core/GigBoard.gd](../../src/core/GigBoard.gd), [src/core/PlayerManager.gd](../../src/core/PlayerManager.gd), and the HUD modals in [src/scenes/HUD.gd](../../src/scenes/HUD.gd).

The compliance path. The player's personal economy sits next to the resistance layer — and the game is deliberately built so neither path alone gets you to month 13 clean.

---

## Starting wallet

Rolled once at run-start based on class seed. See `PlayerManager.initialize_run()`.

| Class | Credits | Interpretation |
|---|---|---|
| White Collar | 50,000 cr | Severance + liquidated 401(k). A year's frayed cushion if you're careful. |
| Blue Collar | 29,000 cr | Union payout + cashed-out savings. Covers the year if nothing goes wrong. Something always goes wrong. |

Hope starts at 55 (WC) or 45 (BC). Severance period is months 1–2 — hope decay is paused. At month 3, a one-shot NetFeed note fires: *"Your severance ran out this morning."*

---

## Monthly rent — the decision

Rent is rolled **once at run-start** in `[700, 2000] cr`. A Sinks studio rolls cheap; an Enclave-adjacent 1BR rolls expensive. Fixed for the playthrough. See `PlayerManager.monthly_rent`.

**On the 1st of every in-game month** (`TimeSystem.rent_due` fires on month rollover), `PlayerManager.handle_rent_due()` emits the `rent_due_prompt` signal. The HUD catches it and opens a **forced modal** that pauses the game:

> **// RENT DUE**
>
> The landlord wants his check. This month's rent: **X cr**.
>
> Pay now, or skip and eat the ding on your record.
>
> `[PAY  X cr]`   `[SKIP]`

### Paying

`PlayerManager.pay_rent()` drains `monthly_rent × (arrears_months + 1)` from credits. **Credits can go negative** — you chose the hole. +2 hope, arrears cleared, modal closes. The landlord's receipt hits the mail slot by noon.

### Skipping

`PlayerManager.skip_rent()` increments `rent_arrears_months`. −4 hope, NetFeed notes the first notice. Modal re-fires on the next month rollover.

### Eviction — state, not defeat

If `rent_arrears_months` reaches **2** on a rent-due tick, the eviction squad comes. `PlayerManager._evict()` flips `homeless = true`, −10 hope. It is **not a run-ender.** Homeless consequences:
- No home computer → GIG BOARD is inaccessible (public terminals will land in a later feature).
- +8 cr/day food cost (exposure tax).
- −1 hope/day extra drift.
- Only `hope == 0` fires the DESPAIR defeat. See [victory.md](victory.md).

Re-housing via the black-market shop costs one month's rent as deposit (`PlayerManager.secure_housing()`).

---

## Gig Board

Press **`G`** to open the panel when you have a home computer (not homeless). The panel shows two sections:

### 1. Gig Work (region-filtered)

6 gig kinds defined in `GigBoard.GIG_CATALOG`. Listings are region-gated — a waiter only works URBAN_ELITE, a trash hauler only INDUSTRIAL, dishwasher/street-sweep anywhere.

| Gig | Regions | Hours | Pay | Notes |
|---|---|---|---|---|
| Dishwasher | any | 3h | 36–48 cr | |
| Street sweep | any | 3h | 42–54 cr | |
| Trash hauler | INDUSTRIAL | 4h | 54–72 cr | |
| Delivery runner | URBAN_SLUM, TRANSIT | 3h | 30–54 cr + tip 0–22 cr | |
| Waiter | URBAN_ELITE | 3h | 30–45 cr + tip 0–60 cr | Highest ceiling, worst humiliation |
| Day-labor construction | INDUSTRIAL | 4h | 60–84 cr | |

**Apply with number keys `1`–`6`.** `GigBoard.apply_for_shift(kind)` runs the roll:

- **40% silent denial** — no reason given, 30 game-mins wasted. NetFeed surfaces one of *"Position filled."* / *"Not a fit at this time."* / *"Thank you for your interest."* etc.
- **60% accepted** — `TimeSystem.skip_hours(hours)` advances game time, wages accrue to `PlayerManager.pending_wages`, a humiliation dialogue line fires (offline pool per gig), 1–3 hope drained, −0.02 idealism drift per shift.

The humiliation lines are offline-pool today (LLM-seeded generation slated for a later pass). Examples baked into the catalog:

- *"A party of six leaves without tipping and one of them looked exactly like your old boss's nephew."*
- *"The app deducted 4 cr for 'late delivery'. The route the app gave you had a closed bridge."*
- *"A former colleague from your old firm sits at table six and pretends not to recognize you."*

### 2. White-Collar Listings

**Always present.** 4 listings refresh every 7 in-game days (`WC_LISTINGS_PER_REFRESH` / `WC_REFRESH_EVERY_DAYS`). Titles and company names come from `_WC_TITLES` / `_WC_COMPANIES` — a rotating pool that can be swapped out via LLM generation in a later pass.

Posted monthly salaries: **2,000–4,000 cr/month**. Genuinely better than gigs. Almost entirely decorative.

**Apply with `Shift+1`–`Shift+4`.** The HUD opens the interview modal in a loading state while `GigBoard.request_interview_gauntlet` runs:
- **Online path** (LLMManager has an API key): the LLM generates a tailored 3-question gauntlet referencing the title/company/description. Questions feel custom per run. Rejection fragments are LLM-authored HR-speak.
- **Offline path**: 3 questions drawn from `_WC_INTERVIEW_QUESTIONS` (6-question static pool), options shuffled, each with a pre-written rejection fragment.

Each question has **4 multiple-choice options**. Every option is wrong.

Sample (offline pool):

> **Q:** *"Estimate the number of pigeons currently residing within The Enclave. Show your reasoning."*
>
> 1. ~5,000. Back-of-envelope: 1 per 4 residents, minus nets.
> 2. Uncountable — we'd need a stratified sampling method first.
> 3. Zero. Pigeons are prohibited by ordinance 41-C.
> 4. Why is this relevant to the role?

After all 3 rounds, `GigBoard.submit_interview_answers` rolls `WC_ACCEPTANCE_RATE = 0.05`. The interview costs 2 game-hours regardless of outcome.

### Rejection letter

On the 95% branch, the game compiles a letter from the **specific answers** the player picked. Each option's `rejection_fragment` is stitched into a preamble + closing:

> *After careful consideration from the full hiring panel, we regret to inform you that we've decided to move forward with other candidates. Specifically, your response at (1) revealed a preference for boundary-setting that does not align with the adjacency model we're building toward; the 5,000 figure at (2) reveals insufficient top-down calibration — a senior hire would have started with airspace volume, not resident density; on (3) you could not name a specific initiative beyond generalities, which broke the spell. We encourage you to re-apply in 12 months once you've had more time to grow in your current role.*

Cost: 3–5 hope, −0.03 idealism drift. Listing is consumed either way — one shot per posting.

### Hired

On the 5% branch, `PlayerManager.accept_wc_role(title, company, salary)` flips `wc_employed = true`, +15 hope, −0.05 idealism drift (the system got a hook in you). The gig panel header now shows **EMPLOYED: Title @ Company (X cr/mo)**.

Every weekly payday (`TimeSystem.payday` on `day % 7 == 0`):

1. **Firing roll first.** `WC_WEEKLY_FIRING_ROLL = 0.10` — if it fires, `_fire_from_wc_role()` runs, −5 hope, NetFeed toasts *"You were let go from [Company]. HR's email used 'unfortunately' seven times."* Already-accrued wages for that week still deposit (you earned them before the term ended).
2. **Wage accrual.** If still employed, `monthly_salary / 4` accrues as `wc_salary:[Company]` source.
3. **Deposit.** All pending wages (gig + WC) dump into `credits` with a source breakdown for the HUD toast.

Mean WC tenure at 10% weekly firing ≈ 10 weeks. Getting hired and fired in the same season is normal.

---

## Weekly payday

All wages accrue between Mondays. `TimeSystem.payday` fires on every 7th day rollover (`day % 7 == 0`). `PlayerManager.apply_weekly_payday()` runs the WC firing roll, accrues the week's salary slice, then deposits `pending_wages` into `credits` and clears the accumulator.

The HUD shows pending wages in the top-left state panel (`+N cr (next payday)`) and in the gig panel title (`pending X cr · next payday in Y days`).

On deposit, a NetFeed toast fires with the source breakdown:

> *PAYDAY: 1,245 cr deposited. (waiter 420 cr, dishwasher 180 cr, wc_salary:Paperclip & Thorne, LLP 645 cr)*

---

## Daily tick

Even while you sleep, you still eat. `PlayerManager.apply_daily_tick(economy)` runs on every `TimeSystem.day_advanced`:

- **Food & utilities** — 25 cr + `(food_price − 100) / 3`. Homeless: +8 cr/day (exposure tax). Multiplied by `rent_drain_multiplier` during a Finance shock window (×1.15 for 10 days).
- **Hope decay** — outside severance: baseline −1, −1 more if broke, −1 if heat > 60, −1 if homeless, −0.5 per month of arrears, −1 if month ≥ 10. Despair defeat at hope = 0.

Rent is NOT in the daily tick. That's a monthly decision, surfaced via its own modal.

---

## How the two paths trade off

| | Resistance path | Compliance path |
|---|---|---|
| **Income** | Spiky: 500–2,500 cr per cell job | Steady: 200–500 cr/week gigs, 500–1000 cr/week WC |
| **Hope** | +3 per successful sabotage | −1 to −3 per shift, −3 to −5 per WC rejection |
| **Heat** | +heat per op | No heat at all |
| **Idealism** | +idealism | −idealism (participating in the system) |
| **Time cost** | Minutes per op | Hours per shift; weekday lock if WC-employed |

A pure-gig player earns enough to survive the year but bleeds hope and idealism; the run ends in DESPAIR around month 10–11. A pure-sabotage player pays rent easily but heat caps them at month 6–8. The year needs both.

---

## Cross-references

- [Core Loop](loop.md) — the day rhythm these systems tick against
- [Economy](../02-world/economy.md) — the world-level prices these sources react to
- [Victory & Defeat](victory.md) — eviction ≠ defeat, hope = 0 ends the run
- [Heat & Enforcement](heat.md) — what the resistance path costs you
- [NetFeed](../02-world/netfeed.md) — where payday toasts, denials, and firings surface
